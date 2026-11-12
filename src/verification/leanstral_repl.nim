import core/trusted/layer_declaration
axiomLayer "infrastructure"
# Leanstral REPL Engine — Interactive Proof Feedback Loop
# Phase 1: One-shot 생성을 REPL 상호작용 루프로 전환
# Context7 공식 프로토콜 기반 (leanprover-community/repl)
# Z3 Persistent Pool 패턴 차용 (src/verification/solver/z3_pool.nim)
{.push raises: [].}

import std/[json, osproc, streams, strutils, locks]
import std/exitprocs

import core/utils/constants
import core/trusted/axiom_pragmas
import core/results
# axiomIoBoundary

# ── 타입 ──────────────────────────────────────────────────────────

type
  TacticModeEntry* = object
    proofState*: int
    env*: int
    goals*: seq[string]

  ReplFeedback* = object
    ## Lean REPL 피드백 한 덩어리
    proofState*: int           ## 현재 증명 상태 ID
    goals*: seq[string]        ## 현재 남은 목표
    proofStatus*: string       ## "Goals accomplished" / "Incomplete"
    error*: string             ## 오류 메시지
    diagnostics*: seq[string]  ## warning/info

  LeanstralReplResult* = object
    ## REPL 루프 최종 결과
    success*: bool
    theoremSource*: string     ## 증명된 최종 Lean 소스
    tacticTrace*: seq[string]  ## 적용된 타틱 이력
    rounds*: int               ## 총 라운드 수
    diagnostics*: string       ## 최종 진단
    rawOutput*: string         ## LLM 원본 출력

  ReplWorker = object
    process: Process
    input: Stream
    output: Stream
    alive: bool
    gate: Lock

  ReplWorkerManager = object
    worker: ReplWorker
    ready: bool
    bootstrapGate: Lock
    bootstrapGateReady: bool

# ── 프로세스 관리 (Z3 Pool 패턴) ──────────────────────────────────

var replManagerPrivate: ptr ReplWorkerManager

proc replManager(): ptr ReplWorkerManager {.gcsafe, axiomNoEscape, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if replManagerPrivate.isNil:
    replManagerPrivate = create(ReplWorkerManager)
  replManagerPrivate

proc startReplWorker(worker: var ReplWorker): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    worker.process = startProcess(
      command = "lake",
      args = @["env", "repl"],
      options = {poUsePath, poStdErrToStdOut}
    )
    if worker.process.isNil:
      return err("startProcess returned nil for Lean REPL")
    worker.input = inputStream(worker.process)
    worker.output = outputStream(worker.process)
    if worker.input.isNil or worker.output.isNil:
      return err("Lean REPL streams not available")
    worker.alive = true
    ok(true)
  except CatchableError as e:
    err("startReplWorker: " & e.msg)

proc stopReplWorker(worker: var ReplWorker) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not worker.process.isNil:
    try:
      worker.input.writeLine("")
      worker.input.flush()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    try:
      close(worker.process)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    worker.alive = false

proc ensureReplReady(): Result[ptr ReplWorkerManager, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let mgr = replManager()
  if not mgr.ready:
    initLock(mgr.bootstrapGate)
    mgr.bootstrapGateReady = true
    acquire(mgr.bootstrapGate)
    if not mgr.ready:
      let res = startReplWorker(mgr.worker)
      if res.isErr:
        release(mgr.bootstrapGate)
        return err("Lean REPL startup failed: " & res.error)
      mgr.ready = true
    release(mgr.bootstrapGate)
  if not mgr.worker.alive:
    return err("Lean REPL worker is not alive")
  ok(mgr)

proc deinitReplPool() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not replManagerPrivate.isNil:
    if replManagerPrivate[].bootstrapGateReady:
      deinitLock(replManagerPrivate[].bootstrapGate)
    if replManagerPrivate[].ready:
      stopReplWorker(replManagerPrivate[].worker)
    dealloc(replManagerPrivate)
    replManagerPrivate = nil

addExitProc(deinitReplPool)

# ── JSON 프로토콜 통신 ────────────────────────────────────────────
# 공식 문서: "commands separated by blank lines"
# 오류: {"message": "..."} ← NOT {"error": "..."}

proc sendReplJson(worker: ReplWorker, payload: JsonNode): Result[JsonNode, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    worker.input.writeLine($payload)
    worker.input.writeLine("")  # ← 공식 프로토콜: blank line 구분자
    worker.input.flush()
    let raw = worker.output.readLine()
    if raw.len == 0:
      return err("Empty response from Lean REPL")
    ok(parseJson(raw))
  except CatchableError as e:
    err("Lean REPL communication: " & e.msg)

# ── 타틱 모드 API ─────────────────────────────────────────────────

proc enterTacticMode(worker: ReplWorker, theoremCmd: string, env: int = -1): Result[TacticModeEntry, string] =
  ## sorry 포함 명령으로 타틱 모드 진입
  var payload = %* {"cmd": theoremCmd}
  if env >= 0:
    payload["env"] = %env
  let jRes = sendReplJson(worker, payload)
  if jRes.isErr:
    return err(jRes.err)
  let j = jRes.value
  var msg = ""
  try:
    if j.hasKey("message"):
      msg = j["message"].getStr()
      return err(msg)
  except KeyError:
    return err("JSON key error")
  var proofState = -1
  var retEnv = -1
  var goals: seq[string]
  try:
    if j.hasKey("sorries"):
      for s in j["sorries"]:
        if s.hasKey("proofState"):
          proofState = s["proofState"].getInt()
        if s.hasKey("goal"):
          goals.add(s["goal"].getStr())
    if j.hasKey("env"):
      retEnv = j["env"].getInt()
  except KeyError:
    discard
  if proofState < 0:
    return err("No proofState in tactic mode response")
  ok(TacticModeEntry(proofState: proofState, env: retEnv, goals: goals))

proc applyTacticStep(worker: ReplWorker, tactic: string, proofStateId: int): ReplFeedback =
  ## 타틱 한 줄 적용 + 피드백 파싱
  let payload = %* {"tactic": tactic, "proofState": proofStateId}
  let jRes = sendReplJson(worker, payload)
  if jRes.isErr:
    return ReplFeedback(error: jRes.err)
  let j = jRes.value
  # 공식 문서: 오류는 "message" 필드
  if j.hasKey("message"):
    var errMsg = "unknown error"
    try:
      errMsg = j["message"].getStr()
    except KeyError:
      discard
    return ReplFeedback(error: errMsg)
  if j.hasKey("proofStatus"):
    try:
      if j.hasKey("proofStatus"): result.proofStatus = j["proofStatus"].getStr()
      if j.hasKey("proofState"): result.proofState = j["proofState"].getInt()
    except KeyError: discard
  try:
    if j.hasKey("goals"):
      for g in j["goals"]:
        result.goals.add(g.getStr())
    if j.hasKey("messages"):
      for m in j["messages"]:
        if m.hasKey("data"):
          result.diagnostics.add(m["data"].getStr())
  except KeyError:
    discard

proc isGoalsAccomplished(fb: ReplFeedback): bool =
  fb.proofStatus == "Goals accomplished"

# ── REPL 기반 증명 종합 ───────────────────────────────────────────

proc buildReplPromptFromFeedback*(
  basePrompt: string,
  goals: seq[string],
  prevError: string,
  round: int
): string =
  ## REPL 피드백을 LLM 프롬프트에 주입
  ## 목표 + 이전 오류 → 다음 타틱 요청
  result = basePrompt
  result.add("\n\n--- Lean REPL Feedback (Round " & $round & ") ---\n")
  if goals.len > 0:
    result.add("Current goals:\n")
    for g in goals:
      result.add("  " & g & "\n")
  if prevError.len > 0:
    result.add("Previous error:\n  " & prevError & "\n")
  result.add("\nProvide the next tactic to apply. Output ONLY the tactic, nothing else.\n")

proc buildHealingPrompt*(
  basePrompt: string,
  goals: seq[string],
  compilerError: string,
  attempt: int
): string =
  ## Local Healing 프롬프트: 컴파일러 에러 컨텍스트를 역주입
  ## 동일 proofState 기점에서 단일 타틱만 재시도
  result = basePrompt
  result.add("\n\n--- Local Healing (Attempt " & $attempt & "/3) ---\n")
  if goals.len > 0:
    result.add("Current goals:\n")
    for g in goals:
      result.add("  " & g & "\n")
  result.add("The previous tactic failed with this compiler error:\n")
  result.add("  " & compilerError & "\n")
  result.add("\nProvide a corrected single tactic. Output ONLY the tactic, nothing else.\n")

import verification/leanstral_gateway

proc tryLeanstralReplSynthesis*(
  prompt: string,
  theoremSource: string,
  timeoutMs: int = proofAttemptHardTimeoutMs,
  maxRounds: int = 10
): LeanstralReplResult {.raises: [].} =
  ## REPL 기반 증명 종합: LLM ↔ Lean REPL 대화형 루프
  ## 기존 tryLeanstralSynthesis의 one-shot 패턴을 대체
  ##
  ## 턴제 루프 구조:
  ##   1. enterTacticMode (sorry) → proofState 획득
  ##   2. LLM에게 goals+error → 타틱 1줄 생성
  ##   3. applyTacticStep → REPL 피드백
  ##   4a. "Goals accomplished" → 수렴
  ##   4b. "Incomplete" → 상태 갱신, 다음 턴
  ##   4c. "message" 오류 → Local Healing (same proofState, roundsCap: 3)

  const localHealingRoundsCap = 3

  let mgrRes = ensureReplReady()
  if mgrRes.isErr:
    result.diagnostics = "Lean REPL not available: " & mgrRes.err
    return

  var worker = mgrRes.value.worker
  acquire(worker.gate)
  defer: release(worker.gate)

  # 1단계: 타틱 모드 진입 (sorry 포함 theorem 명령)
  let theoremCmd = theoremSource.replace(":=", ":= by sorry")
  if ":= by sorry" notin theoremCmd:
    result.diagnostics = "Cannot enter tactic mode: theorem source lacks ':='"
    return

  let enterRes = enterTacticMode(worker, theoremCmd)
  if not enterRes.isOk:
    result.diagnostics = "Tactic mode entry failed: " & enterRes.err
    return

  var currentProofState = enterRes.value.proofState
  var prevError = ""
  var currentGoals = enterRes.value.goals
  result.tacticTrace = @[]

  for round in 1 .. maxRounds:
    result.rounds = round

    # LLM에게 현재 목표 + 이전 오류를 보여주고 다음 타틱 요청
    let replPrompt = buildReplPromptFromFeedback(prompt, currentGoals, prevError, round)
    let llmRes = callLeanstral(replPrompt, timeoutMs = timeoutMs)

    if not llmRes.success or llmRes.theoremSource.len == 0:
      prevError = "LLM failed: " & llmRes.diagnostics
      continue

    # LLM 응답에서 타틱 추출 (공백/개행 정리)
    let tactic = llmRes.theoremSource.strip()
    if tactic.len == 0:
      prevError = "LLM returned empty tactic"
      continue

    # 타틱 적용
    var fb = applyTacticStep(worker, tactic, currentProofState)
    result.tacticTrace.add(tactic)

    # ── Local Healing: 동일 proofState 내에서 최대 3회 재시도 ──
    var healingAttempts = 0
    while fb.error.len > 0 and healingAttempts < localHealingRoundsCap:
      healingAttempts += 1
      let healingPrompt = buildHealingPrompt(
        prompt, currentGoals, fb.error, healingAttempts
      )
      let healedRes = callLeanstral(healingPrompt, timeoutMs = timeoutMs)
      if healedRes.success and healedRes.theoremSource.len > 0:
        let healedTactic = healedRes.theoremSource.strip()
        if healedTactic.len > 0:
          fb = applyTacticStep(worker, healedTactic, currentProofState)
          result.tacticTrace.add("[heal]" & healedTactic)
          if fb.error.len == 0:
            break  # Local Healing 성공

    # 오류 처리 (Local Healing 실패 시)
    if fb.error.len > 0:
      prevError = fb.error & " (healing " & $healingAttempts & "/" & $localHealingRoundsCap & " failed)"
      continue

    # 증명 완료 확인
    if fb.isGoalsAccomplished():
      result.success = true
      result.theoremSource = theoremSource
      result.diagnostics = "Proof accomplished via REPL in " & $round & " rounds (healing: " & $healingAttempts & ")"
      return

    # 미완료 → 상태 갱신 후 다음 라운드
    if fb.proofStatus.startsWith("Incomplete"):
      currentProofState = fb.proofState
      currentGoals = fb.goals
      prevError = ""
      continue

    # 알 수 없는 상태
    prevError = "Unexpected proofStatus: " & fb.proofStatus

  result.diagnostics = "REPL loop exhausted after " & $maxRounds & " rounds"
{.pop.}

