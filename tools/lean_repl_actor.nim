import core/trusted/layer_declaration
axiomLayer "tools"
# Lean REPL Actor — Interactive Proof Feedback Loop
# Phase 1: Lean REPL 엔진 장착
# Context7 공식 프로토콜 기반 (leanprover-community/repl)
{.push raises: [].}

import std/[json, osproc, streams, strutils]
import shared_types/shared_types

type
  ReplMode* = enum
    rmCommand,    ## 명령 모드: def/theorem declaration
    rmTactic,     ## 타틱 모드: 단계별 증명
    rmFile        ## 파일 모드: .lean 전체 처리

  ReplResponse* = object
    proofState*: int           ## 증명 상태 스냅샷 ID
    goals*: seq[string]        ## 현재 남은 목표
    proofStatus*: string       ## "Goals accomplished" 또는 "Incomplete"
    env*: int                  ## 환경 스냅샷 ID
    error*: string             ## 오류 메시지 (message 필드에서 파싱)
    diagnostics*: seq[string]  ## warning/info 메시지
    rawJson*: JsonNode         ## 원본 JSON 응답

  LeanReplActor* = object
    process*: Process
    input*: Stream
    output*: Stream
    currentEnv*: int           ## 현재 환경 스냅샷
    activeProofStates*: seq[int] ## 활성 증명 상태
    alive*: bool

# ── 프로세스 생명주기 ──────────────────────────────────────────────

# Forward declaration: safeCloseProcess
proc safeCloseProcess(p: Process): Result[bool, string] =
  try:
    close(p)
    ok(true)
  except CatchableError:
    ok(true)

proc startLeanRepl*(leanExe: string = "lake"): Result[LeanReplActor, string] =
  ## Lean REPL 프로세스 시작
  ## 공식 문서: "The REPL communicates via JSON on stdin and stdout"
  try:
    let args = if leanExe == "lake": @["env", "repl"] else: @["--repl"]
    let p = startProcess(
      command = leanExe,
      args = args,
      options = {poUsePath, poStdErrToStdOut}
    )
    if p.isNil:
      return err("startProcess returned nil for Lean REPL")
    let inp = inputStream(p)
    let outp = outputStream(p)
    if inp.isNil or outp.isNil:
      discard safeCloseProcess(p)
      return err("Lean REPL streams not available")
    ok(LeanReplActor(
      process: p,
      input: inp,
      output: outp,
      currentEnv: -1,
      activeProofStates: @[],
      alive: true
    ))
  except CatchableError as e:
    err("startLeanRepl: " & e.msg)

proc stopRepl*(actor: var LeanReplActor) =
  ## REPL 프로세스 종료
  if not actor.process.isNil:
    try:
      actor.input.writeLine("")  # 빈 명령으로 종료 유도
      actor.input.flush()
    except CatchableError:
      discard  # axiom:best-effort(repl-input-flush-failure: pipe may be closed, termination still proceeds)
    discard safeCloseProcess(actor.process)
    actor.alive = false

# ── JSON 프로토콜 통신 ────────────────────────────────────────────
# 공식 문서: "commands separated by blank lines"
# 오류 필드: "message" (NOT "error")

proc sendRaw(p: Process, payload: JsonNode): Result[string, string] =
  ## JSON 명령 전송 + 응답 수신
  ## 공식 프로토콜: 명령 간 blank line 구분자 필수
  try:
    let inp = inputStream(p)
    let outp = outputStream(p)
    inp.writeLine($payload)
    inp.writeLine("")  # ← 공식 프로토콜: blank line 구분자
    inp.flush()
    let raw = outp.readLine()
    if raw.len == 0:
      return err("Empty response from Lean REPL")
    ok(raw)
  except CatchableError as e:
    err("Lean REPL communication error: " & e.msg)

proc parseReplResponse*(raw: string): ReplResponse =
  ## 공식 JSON 응답 파싱
  ## 오류: {"message": "..."} ← NOT {"error": "..."}
  try:
    result.rawJson = parseJson(raw)
  except JsonParsingError:
    return ReplResponse(error: "JSON parse error: " & raw)
  except CatchableError:
    return ReplResponse(error: "Unexpected parse error: " & raw)

  let j = result.rawJson

  try:
    # 공식 문서: "The REPL returns JSON objects with a 'message' field for errors"
    if j.hasKey("message"):
      result.error = j["message"].getStr()
      return

    # 성공 응답 파싱
    if j.hasKey("proofState"):
      result.proofState = j["proofState"].getInt()

    if j.hasKey("env"):
      result.env = j["env"].getInt()

    if j.hasKey("proofStatus"):
      result.proofStatus = j["proofStatus"].getStr()

    if j.hasKey("goals"):
      for goal in j["goals"]:
        result.goals.add(goal.getStr())

    # sorries 응답 (tactic mode 진입 시)
    if j.hasKey("sorries"):
      for sorry in j["sorries"]:
        if sorry.hasKey("proofState"):
          result.proofState = sorry["proofState"].getInt()
        if sorry.hasKey("goal"):
          result.goals.add(sorry["goal"].getStr())

    # messages (warnings, info)
    if j.hasKey("messages"):
      for msg in j["messages"]:
        if msg.hasKey("data"):
          result.diagnostics.add(msg["data"].getStr())
  except KeyError:
    result.error = "JSON key access error in REPL response"

# ── 명령 모드 API ─────────────────────────────────────────────────

proc sendCommand*(actor: var LeanReplActor, cmd: string, env: int = -1): ReplResponse =
  ## 명령 모드: def/theorem declaration 전송
  var payload = %* {"cmd": cmd}
  if env >= 0:
    payload["env"] = %env
  let rawRes = sendRaw(actor.process, payload)
  if rawRes.isErr:
    return ReplResponse(error: rawRes.err)
  result = parseReplResponse(rawRes.value)
  if result.error.len == 0 and result.env >= 0:
    actor.currentEnv = result.env

proc enterTacticMode*(actor: var LeanReplActor, theoremCmd: string, env: int = -1): ReplResponse =
  ## 타틱 모드 진입: sorry 포함 명령으로 proofState 획득
  ## 공식 문서: "Initiate tactic mode by sending a command containing 'sorry'"
  result = actor.sendCommand(theoremCmd, env)
  if result.error.len == 0 and result.proofState >= 0:
    actor.activeProofStates.add(result.proofState)

# ── 타틱 모드 API ─────────────────────────────────────────────────

proc applyTactic*(actor: var LeanReplActor, tactic: string, proofStateId: int): ReplResponse =
  ## 타틱 한 줄 적용
  ## 공식 문서: {"tactic": "...", "proofState": N}
  let payload = %* {"tactic": tactic, "proofState": proofStateId}
  let rawRes = sendRaw(actor.process, payload)
  if rawRes.isErr:
    return ReplResponse(error: rawRes.err)
  result = parseReplResponse(rawRes.value)

proc isGoalsAccomplished*(resp: ReplResponse): bool =
  ## 증명 완료 확인
  ## 공식 문서: proofStatus = "Goals accomplished"
  resp.proofStatus == "Goals accomplished"

proc isGoalIncomplete*(resp: ReplResponse): bool =
  ## 증명 미완료 확인
  resp.proofStatus.startsWith("Incomplete")

# ── 파일 모드 API ─────────────────────────────────────────────────

proc processFile*(actor: var LeanReplActor, filePath: string, allTactics: bool = true): ReplResponse =
  ## 파일 모드: .lean 파일 전체 처리
  ## 공식 문서: {"path": "file.lean", "allTactics": true}
  var payload = %* {"path": filePath}
  if allTactics:
    payload["allTactics"] = %true
  let rawRes = sendRaw(actor.process, payload)
  if rawRes.isErr:
    return ReplResponse(error: rawRes.err)
  result = parseReplResponse(rawRes.value)

# ── 대화형 증명 루프 ──────────────────────────────────────────────

type
  ProofLoopResult* = object
    success*: bool
    finalProofState*: int
    tacticTrace*: seq[string]    ## 적용된 타틱 이력
    goalHistory*: seq[seq[string]] ## 라운드별 목표 스냅샷
    errorHistory*: seq[string]   ## 라운드별 오류
    rounds*: int

proc interactiveProofLoop*(
  actor: var LeanReplActor,
  theoremCmd: string,
  tacticGenerator: proc(goals: seq[string], prevError: string): string {.noSideEffect, raises: [].},
  maxRounds: int = 20,
  env: int = -1
): ProofLoopResult =
  ## 대화형 증명 루프: LLM이 타틱을 방출하면 REPL이 피드백을 반환하는 구조

  # 1단계: 타틱 모드 진입 (sorry 포함 명령)
  let enterResp = actor.enterTacticMode(theoremCmd, env)
  if enterResp.error.len > 0:
    result.errorHistory.add("Tactic mode entry failed: " & enterResp.error)
    return

  var currentProofState = enterResp.proofState
  var prevError = ""
  result.goalHistory.add(enterResp.goals)

  for round in 1 .. maxRounds:
    result.rounds = round

    # 현재 목표를 기반으로 타틱 생성
    let tactic = tacticGenerator(enterResp.goals, prevError)
    if tactic.len == 0:
      result.errorHistory.add("Round " & $round & ": tacticGenerator returned empty tactic")
      break

    # 타틱 적용
    let resp = actor.applyTactic(tactic, currentProofState)
    result.tacticTrace.add(tactic)

    # 오류 응답 처리
    if resp.error.len > 0:
      prevError = resp.error
      result.errorHistory.add("Round " & $round & ": " & resp.error)
      continue

    # 목표 업데이트
    result.goalHistory.add(resp.goals)

    # 증명 완료 확인
    if resp.isGoalsAccomplished():
      result.success = true
      result.finalProofState = resp.proofState
      return

    # 증명 미완료 → 다음 라운드
    if resp.isGoalIncomplete():
      currentProofState = resp.proofState
      prevError = ""
      continue

    # 알 수 없는 상태
    result.errorHistory.add("Round " & $round & ": unexpected proofStatus: " & resp.proofStatus)
    break

when isMainModule:
  ## 독립 실행 테스트
  echo "Lean REPL Actor — Phase 1 Test"
  echo "==============================="

  let actorRes = startLeanRepl("lake")
  if actorRes.isErr:
    echo "ERROR: Cannot start Lean REPL: ", actorRes.err
    echo "  -> Ensure 'lake' is in PATH and leanprover-community/repl is available"
    quit(1)

  var a = actorRes.value
  echo "Lean REPL started successfully"

  # 간단한 명령 테스트
  let resp = a.sendCommand("def f : Nat := 37")
  if resp.error.len > 0:
    echo "Command error: ", resp.error
  else:
    echo "Command OK, env=", resp.env

  # 타틱 모드 테스트
  let proofResp = a.enterTacticMode("theorem test : 1 + 1 = 2 := by sorry")
  if proofResp.error.len > 0:
    echo "Tactic mode error: ", proofResp.error
  else:
    echo "Proof state: ", proofResp.proofState
    echo "Goals: ", proofResp.goals

    let applyResp = a.applyTactic("exact rfl", proofResp.proofState)
    if applyResp.isGoalsAccomplished():
      echo "Proof accomplished!"
    else:
      echo "Status: ", applyResp.proofStatus
      echo "Goals: ", applyResp.goals

  a.stopRepl()
  echo "Lean REPL stopped."
