## tools/ci/observe_fault_streak.nim — 관측 증거 집계기 (GET-only, 단일 패스).
##
## Output is ADVISORY EVIDENCE — this tool is not an authority. 어떤 merge도 막지
## 않으며, 계수 경보의 책임은 이 명령을 실행·기록하는 자에게 있다 (ADR-0033
## §관측기 생존 표시 개정, 결정 #20(d)). 승격 판단 시 Owner가 필수로 실행하고,
## 그 외 시점의 재실행은 누구나 임의로 가능하다 (landing_observe.sh 재관측 선례).
##
## 산출 (stdout):
##   1. JSON 라운드 표 1개 — merge_group 라운드별 payload 판정·원인 분류
##   2. 고정 마커 라인 (승격 증거가 인용하는 값):
##        PRESENCE ratio=<분자>/<분모> (<pct>%)
##        FAULT streak=<N> owner-display=<required|clear>
##        UNCAUSED count=<N>   ← 원인 불명. 0이어야 승격 가능(결정 #20(d))
##        COLD-STATS p95=<s>s runs=<n>
##
## 계약:
##   - 2계층 원인 분류(결정 #20(d)):
##     계층1 payload.fault_cause: timeout | gate | toolchain
##     계층2 run-level (payload 부재): 런 부재=platform / jobs==0=platform
##       (conclusion 무관 — startup_failure·failure 혼재 실측) / cancelled=platform
##       / 부재 ∧ 경과 ≥ timeoutBudget=timeout / 그 외=platform
##   - `conclusion==timed_out`에 의존하지 않는다 (8,389런 실측 0건).
##   - 집계 창 ≤ 아티팩트 retention(30일) — 그 밖은 집계 불가(원인 불명 아님).
##   - 집계기 자신의 REST 장애는 메타 OBSERVER-FAULT로 stderr에 기록한다.
##   - E-A 계수 대상 = verdict==PASS ∧ identityOk==true.
##
## Purity: read-only — gh api GET만. mutation·rerun 경로 없음. 재관측 = 재실행.

import std/[os, osproc, strutils, sequtils, json, algorithm, math, parseopt, times]

const
  DefaultRepo = "Archright/Axiom"
  DefaultWindow = 20
  DefaultTimeoutBudget = 600

type
  Round = object
    g: string
    runId: string
    verdict: string
    cause: string
    started: string
    elapsed: int
    payloadPresent: bool
    identityOk: bool

  AggError = object of CatchableError

proc ghGet(args: string): string =
  ## 단일 GET — gh api (read-only). URL은 셸 인용한다(`&`가 셸 연산자로 해석되어
  ## 출력이 오염된다 — 실측 JsonParsingError 원인). stderr는 폐기한다(execCmdEx는
  ## stdout+stderr를 합쳐 받는다). 실패 시 AggError (메타 OBSERVER-FAULT 경로).
  let (output, code) = execCmdEx("gh api '" & args & "' 2>/dev/null")
  if code != 0:
    raise newException(AggError, "gh api " & args & " failed: " & output)
  output

proc classifyMissing(conclusion, jobsTotal: string; elapsed, timeoutBudget: int): string =
  ## 계층2 — payload 부재의 원인 분류 (결정 #20(d)). 순수 함수.
  if jobsTotal == "0": "platform"
  elif conclusion == "cancelled": "platform"
  elif elapsed >= timeoutBudget: "timeout"
  else: "platform"

proc classifyCause(payloadPresent: bool; payloadCause, verdict, conclusion,
                   jobsTotal: string; elapsed, timeoutBudget: int): string =
  if not payloadPresent:
    classifyMissing(conclusion, jobsTotal, elapsed, timeoutBudget)
  elif verdict == "OBSERVER-FAULT" and payloadCause.len == 0:
    "gate"
  elif payloadCause.len == 0:
    "none"
  else:
    payloadCause

proc isUnknownCause(c: string): bool =
  c notin ["none", "timeout", "gate", "toolchain", "platform"]

proc main() =
  # M7 no-fallback credential guard (docs/spec/diagnostic_execution_delegation.md
  # §4) — identical mechanism to merge_ruleset_drift_monitor.nim: AXIOM_DIAG_TOKEN
  # (explicitly provisioned) is injected as GH_TOKEN and used for every `gh api`
  # GET below; AXIOM_DIAG_STRICT=1 refuses the `gh auth` fallback (operator PAT)
  # — fail closed. The credential source is ALWAYS printed (never silent).
  block:
    let explicit = getEnv("AXIOM_DIAG_TOKEN").strip()
    if explicit.len > 0:
      stderr.writeLine "observe_fault_streak: credential-source=AXIOM_DIAG_TOKEN"
      putEnv("GH_TOKEN", explicit)
    elif getEnv("AXIOM_DIAG_STRICT") == "1":
      stderr.writeLine "observe_fault_streak: FAIL — AXIOM_DIAG_TOKEN absent and AXIOM_DIAG_STRICT=1: `gh auth` credentials (operator PAT) are refused for diagnostic execution (M7 no-fallback — docs/spec/diagnostic_execution_delegation.md §4)"
      quit 1
    else:
      stderr.writeLine "observe_fault_streak: credential-source=gh-auth (fallback — AXIOM_DIAG_STRICT not set; not a diagnostic credential)"

  var
    repo = DefaultRepo
    window = DefaultWindow
    timeoutBudget = DefaultTimeoutBudget

  var pending = ""
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      if val.len > 0:
        case key
        of "repo": repo = val
        of "window": window = parseInt(val)
        of "timeout-budget": timeoutBudget = parseInt(val)
        else: discard
        pending = ""
      else:
        pending = key
    of cmdArgument:
      case pending
      of "repo": repo = key
      of "window": window = parseInt(key)
      of "timeout-budget": timeoutBudget = parseInt(key)
      else: discard
      pending = ""
    else: discard

  var rounds: seq[Round]
  try:
    # 1. merge_group 런 수집 (GET)
    let runsJson = parseJson(ghGet(
      "repos/" & repo & "/actions/runs?event=merge_group&per_page=100"))
    var rows: seq[JsonNode]
    for r in runsJson["workflow_runs"].getElems: rows.add r
    rows.sort(proc (a, b: JsonNode): int =
      cmp(a{"run_started_at"}.getStr, b{"run_started_at"}.getStr))

    # 2. 라운드별 판정·분류 (run-scoped artifacts, GET)
    #    라운드 = 관측 워크플로의 런만(probe/landing-integrity 등 타 워크플로의
    #    merge_group 런은 관측 대상이 아니므로 제외 — 실측 부풀림 교정).
    for r in rows:
      let
        wfName = r{"name"}.getStr
        wfPath = r{"path"}.getStr
      if wfName != "observer-manifest-consistency" and
         not wfPath.endsWith("observation.yml"):
        continue
      let
        runId = r{"id"}.getBiggestInt
        g = r{"head_sha"}.getStr
        conclusion = r{"conclusion"}.getStr
        started = r{"run_started_at"}.getStr
        updated = r{"updated_at"}.getStr
      var elapsed = 0
      try:
        let
          t0 = parseTime(started, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
          t1 = parseTime(updated, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
        elapsed = int((t1 - t0).inSeconds)
      except CatchableError:
        elapsed = 0

      var
        payloadPresent = false
        verdict = "MISSING"
        payloadCause = ""
        identityOk = false

      let artsRaw = ghGet("repos/" & repo & "/actions/runs/" & $runId & "/artifacts")
      var lastId = 0
      for a in artsRaw.parseJson{"artifacts"}.getElems:
        if a{"name"}.getStr.startsWith("observer-payload-") and
           a{"expired"}.getBool == false:
          lastId = a{"id"}.getBiggestInt.int
      if lastId > 0:
        payloadPresent = true
        # payload 판독: zip을 임시 파일로 받아 unzip -p로 payload.json을 추출
        # (execCmdEx는 바이너리 스트림을 다루지 못한다 — 셸 파이프로 텍스트만 취한다).
        let tmp = getTempDir() / "obs_payload_" & $runId & ".zip"
        let dl = execCmdEx("gh api repos/" & repo & "/actions/artifacts/" &
          $lastId & "/zip > " & tmp & " 2>/dev/null")
        if dl.exitCode == 0:
          let (pJson, pCode) = execCmdEx("unzip -p " & tmp & " payload.json 2>/dev/null")
          if pCode == 0 and pJson.len > 0:
            try:
              let p = parseJson(pJson)
              verdict = p{"verdict"}.getStr
              payloadCause = p{"fault_cause"}.getStr
              identityOk = p{"identityOk"}.getBool
            except CatchableError:
              verdict = "OBSERVER-FAULT"
              payloadCause = "gate"
        removeFile(tmp)

      var jobsTotal = "-1"
      try:
        let jobsRaw = ghGet("repos/" & repo & "/actions/runs/" & $runId & "/jobs")
        jobsTotal = $jobsRaw.parseJson{"total_count"}.getBiggestInt
      except CatchableError:
        jobsTotal = "-1"

      let cause = classifyCause(payloadPresent, payloadCause, verdict,
        conclusion, jobsTotal, elapsed, timeoutBudget)
      rounds.add Round(g: g, runId: $runId, verdict: verdict, cause: cause,
        started: started, elapsed: elapsed, payloadPresent: payloadPresent,
        identityOk: identityOk)

    # 3. 존재율: 효력 개시(관측 첫 런) 이후의 큐 착지 대비 payload 보유 (GET)
    #    효력 개시 이전 랜딩은 계수하지 않는다(결정 #20(e): β2 착지 후 첫 머지부터).
    var effectiveStart = ""
    for r in rounds:
      if effectiveStart.len == 0 or r.started < effectiveStart:
        effectiveStart = r.started
    var presNum, presDen = 0
    let commitsRaw = ghGet("repos/" & repo & "/commits?sha=main&per_page=40")
    for c in commitsRaw.parseJson.getElems:
      if c{"parents"}.getElems.len != 2: continue
      let cdate = c{"commit"}{"committer"}{"date"}.getStr
      if effectiveStart.len > 0 and cdate < effectiveStart: continue
      inc presDen
      let
        m = c{"sha"}.getStr
        g = c{"parents"}[1]{"sha"}.getStr
      if rounds.anyIt((it.g == g or it.g == m) and it.payloadPresent):
        inc presNum

    # 4. 트레일링 FAULT streak (트레일링 연속 — 승격 증거와 동일 라운드 표에서)
    var streak = 0
    for i in countdown(rounds.high, 0):
      if rounds[i].verdict in ["OBSERVER-FAULT", "MISSING"]: inc streak
      else: break

    let uncaused = rounds.filterIt(isUnknownCause(it.cause)).len
    var elapsedSeq = rounds.mapIt(it.elapsed)
    elapsedSeq.sort
    let p95 = if elapsedSeq.len > 0: elapsedSeq[elapsedSeq.len * 95 div 100]
              else: 0

    # 출력
    var table = newJArray()
    for r in rounds:
      table.add %*{"G": r.g, "run": r.runId, "verdict": r.verdict,
        "cause": r.cause, "started": r.started, "elapsed_s": r.elapsed,
        "payload_present": r.payloadPresent, "identity_ok": r.identityOk}
    echo $(%*{"rounds": table, "round_count": rounds.len})

    let pct = if presDen > 0: presNum * 100 div presDen else: 0
    echo "PRESENCE ratio=" & $presNum & "/" & $presDen & " (" & $pct & "%)"
    if streak >= 3:
      echo "FAULT streak=" & $streak & " owner-display=required"
    else:
      echo "FAULT streak=" & $streak & " owner-display=clear"
    echo "UNCAUSED count=" & $uncaused
    echo "COLD-STATS p95=" & $p95 & "s runs=" & $rounds.len

  except AggError as e:
    stderr.writeLine "META OBSERVER-FAULT (platform) — " & e.msg
    quit 2

main()
