import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import core/axiom_pragmas
import gate/gate_contract
import gate/gate_registry
import std/json
import std/os
import std/strutils
import std/tables
import std/times
import infrastructure/logging_facade
# ─── Types & Constants ───────────────────────────────────────────────────────
const
  HistoryPath = ".axiom/gate_history.jsonl"
  SlaPath = "tools/config/gate_sla.json"
  GateOutputDir = ".axiom/cache/gate_output/"
  RunningThresholdMinutes = 5
type
  GateClass* = enum
    gcPass, gcFail, gcWarn, gcRunning, gcSkip, gcDeferred

  GateRecord* = object
    gateId: string
    result: string
    durationNs: int64
    ts: string
    stage: string
    commit: string
    branch: string
    tier: int
    cached: bool
    outputFile: string
    skipReason: string

  PipelineRun* = object
    ts: string
    stage: string
    commit: string
    branch: string
    records: seq[GateRecord]

func groupByTimestamp(history: seq[GateRecord]): seq[PipelineRun] =
  ## Group consecutive records sharing the same timestamp into pipeline runs.
  result = @[]
  if history.len == 0:
    return

  var current = PipelineRun(
    ts: history[0].ts,
    stage: history[0].stage,
    commit: history[0].commit,
    branch: history[0].branch,
    records: @[]
  )

  for rec in history:
    if rec.ts == current.ts and rec.stage == current.stage:
      current.records.add(rec)
    else:
      if current.records.len > 0:
        result.add(current)
      current = PipelineRun(
        ts: rec.ts,
        stage: rec.stage,
        commit: rec.commit,
        branch: rec.branch,
        records: @[rec]
      )

  if current.records.len > 0:
    result.add(current)
func severityStr(sev: GateSeverity): string =
  case sev
  of gsWarn: "warn"
  of gsError: "error"
func classStr(cls: GateClass): string =
  case cls
  of gcPass: "pass"
  of gcFail: "fail"
  of gcWarn: "warn"
  of gcRunning: "running"
  of gcSkip: "skip"
  of gcDeferred: "deferred"
func durationNsToDisplay(ns: int64): string =
  let ms = ns div 1_000_000
  if ms < 1000:
    result = $ms & "ms"
  else:
    let secs = ms.float / 1000.0
    result = formatFloat(secs, ffDecimal, 1) & "s"
proc parseTimestamp(ts: string): DateTime {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse ISO-8601-ish timestamp from history.
  try:
    result = parse(ts, "yyyy-MM-dd'T'HH:mm:sszzz")
  except CatchableError:
    try:
      result = parse(ts, "yyyy-MM-dd'T'HH:mm:ss")
    except CatchableError:
      result = now()
proc loadSeverityMap(): Table[string, GateSeverity] =
  result = initTable[string, GateSeverity]()
  for g in allGates():
    result[g.id] = g.severity
proc loadSlaMap(): Table[string, int] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = initTable[string, int]()
  if not fileExists(SlaPath):
    return
  try:
    let sla = parseJson(readFile(SlaPath))
    let defaultTimeout = sla["default_timeout_sec"].getInt(120)
    for gateId, val in sla["gates"]:
      result[gateId] = val["timeout_sec"].getInt(defaultTimeout)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
proc loadHistory(): seq[GateRecord] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  if not fileExists(HistoryPath):
    return
  try:
    for line in lines(HistoryPath):
      let trimmed = line.strip()
      if trimmed.len == 0 or trimmed[0] != '{':
        continue
      let obj = parseJson(trimmed)
      var rec: GateRecord
      rec.gateId = obj["gateId"].getStr()
      rec.result = obj["result"].getStr()
      rec.durationNs = obj["durationNs"].getInt(0)
      rec.ts = obj["ts"].getStr()
      rec.stage = obj["stage"].getStr()
      rec.commit = obj["commit"].getStr()
      rec.branch = obj["branch"].getStr("main")
      rec.tier = obj["tier"].getInt(0)
      rec.cached = obj["cached"].getBool(false)
      if obj.hasKey("outputFile"):
        rec.outputFile = obj["outputFile"].getStr()
      if obj.hasKey("skipReason"):
        rec.skipReason = obj["skipReason"].getStr()
      result.add(rec)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
func classifyGate(rec: GateRecord; severity: GateSeverity): GateClass =
  case rec.result
  of "pass", "cached":
    gcPass
  of "fail":
    if severity == gsWarn: gcWarn else: gcFail
  of "skip":
    gcSkip
  else:
    gcPass
proc isRecentlyModified(path: string; withinMinutes: int): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if file was modified within the last N minutes.
  if not fileExists(path):
    return false
  try:
    let info = getFileInfo(path)
    let fileDt = info.lastWriteTime.utc
    let nowDt = now().utc
    let elapsed = nowDt - fileDt
    result = elapsed.inMinutes < withinMinutes
  except CatchableError:
    result = false
proc extractLogSnippet(path: string; maxLen: int = 80): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read first non-empty meaningful line from a gate log file.
  result = ""
  if not fileExists(path):
    return
  try:
    for line in lines(path):
      let trimmed = line.strip()
      if trimmed.len > 0 and not trimmed.startsWith("---") and
         not trimmed.startsWith("==="):
        result = trimmed
        if result.len > maxLen:
          result = result[0 ..< maxLen] & "..."
        break
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
proc renderFormatted(run: PipelineRun; severityMap: Table[string, GateSeverity];
                     slaMap: Table[string, int]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let totalNs = block:
    var s: int64 = 0
    for r in run.records:
      s += r.durationNs
    s

  # Parse timestamp for display
  let tsTime = parseTimestamp(run.ts)
  let tsDisplay = tsTime.format("yyyy-MM-dd HH:mm")

  # Classify all gates
  var passCount, warnCount, failCount, runningCount, skipCount: int
  var warns: seq[(string, string, string)]  # (gateId, duration, snippet)
  var fails: seq[(string, string, string)]
  var runnings: seq[(string, int, string)]   # (gateId, sla, snippet)

  for rec in run.records:
    let sev = severityMap.getOrDefault(rec.gateId, gsWarn)
    var cls = classifyGate(rec, sev)

    # Check RUNNING: log file exists and was recently modified
    if cls == gcPass and rec.result == "pass" and not rec.cached:
      let logPath = GateOutputDir & rec.gateId & ".log"
      if isRecentlyModified(logPath, RunningThresholdMinutes):
        cls = gcRunning

    case cls
    of gcPass: inc passCount
    of gcWarn:
      inc warnCount
      let snippet = extractLogSnippet(GateOutputDir & rec.gateId & ".log")
      warns.add((rec.gateId, durationNsToDisplay(rec.durationNs),
                 if snippet.len > 0: snippet else: "see log"))
    of gcFail:
      inc failCount
      let snippet = extractLogSnippet(GateOutputDir & rec.gateId & ".log")
      fails.add((rec.gateId, durationNsToDisplay(rec.durationNs),
                 if snippet.len > 0: snippet else: "see log"))
    of gcRunning:
      inc runningCount
      let sla = slaMap.getOrDefault(rec.gateId, 120)
      let snippet = extractLogSnippet(GateOutputDir & rec.gateId & ".log")
      runnings.add((rec.gateId, sla,
                    if snippet.len > 0: snippet else: ""))
    of gcSkip, gcDeferred: inc skipCount

  # ── Render ────────────────────────────────────────────────────────────────
  let shortCommit = if run.commit.len > 6: run.commit[0 ..< 6] else: run.commit
  let totalDisplay = durationNsToDisplay(totalNs)

  stdout.write "\n"
  stdout.write "━━━ Axiom Gate Status ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  stdout.write "  Pipeline:  " & run.stage & " (" & shortCommit & ", " & tsDisplay & ")\n"
  stdout.write "  Branch:    " & run.branch & "\n"
  stdout.write "  Duration:  " & totalDisplay & " total\n"
  stdout.write "\n"

  # Summary bar
  stdout.write "  "
  if passCount > 0:
    stdout.write "\e[32m✅ PASS (" & $passCount & ")\e[0m   "
  if warnCount > 0:
    stdout.write "\e[33m[WARN]  WARN (" & $warnCount & ")\e[0m   "
  if failCount > 0:
    stdout.write "\e[31m[FAIL] FAIL (" & $failCount & ")\e[0m   "
  if runningCount > 0:
    stdout.write "\e[36m⏳ RUNNING (" & $runningCount & ")\e[0m   "
  if skipCount > 0:
    stdout.write "\e[90m⏭  CACHED (" & $skipCount & ")\e[0m   "
  stdout.write "\n"

  # Warnings section
  if warns.len > 0:
    stdout.write "\n\e[33m[WARN]  Warnings:\e[0m\n"
    for (gateId, dur, snippet) in warns:
      stdout.write "    " & gateId & "  " & dur & "  " & snippet & "\n"

  # Failures section
  if fails.len > 0:
    stdout.write "\n\e[31m[FAIL] Failures:\e[0m\n"
    for (gateId, dur, snippet) in fails:
      stdout.write "    " & gateId & "  " & dur & "  " & snippet & "\n"

  # Running section
  if runnings.len > 0:
    stdout.write "\n\e[36m⏳ Background:\e[0m\n"
    for (gateId, sla, snippet) in runnings:
      stdout.write "    " & gateId & "  running (SLA=" & $sla & "s)"
      if snippet.len > 0:
        stdout.write "  " & snippet
      stdout.write "\n"

  stdout.write "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  stdout.write "\n"
proc renderJson(run: PipelineRun; severityMap: Table[string, GateSeverity];
                slaMap: Table[string, int]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let root = newJObject()
  let runObj = newJObject()
  runObj["ts"] = newJString(run.ts)
  runObj["stage"] = newJString(run.stage)
  runObj["commit"] = newJString(run.commit)
  runObj["branch"] = newJString(run.branch)

  let gatesArr = newJArray()
  var totalNs: int64 = 0

  for rec in run.records:
    let sev = severityMap.getOrDefault(rec.gateId, gsWarn)
    var cls = classifyGate(rec, sev)

    let logPath = GateOutputDir & rec.gateId & ".log"
    if cls == gcPass and rec.result == "pass" and not rec.cached:
      if isRecentlyModified(logPath, RunningThresholdMinutes):
        cls = gcRunning

    let gateObj = newJObject()
    gateObj["gateId"] = newJString(rec.gateId)
    gateObj["result"] = newJString(rec.result)
    gateObj["class"] = newJString(classStr(cls))
    gateObj["durationNs"] = newJInt(rec.durationNs)
    gateObj["severity"] = newJString(severityStr(sev))
    gateObj["tier"] = newJInt(rec.tier)
    gateObj["cached"] = newJBool(rec.cached)

    if cls == gcRunning:
      gateObj["slaSec"] = newJInt(slaMap.getOrDefault(rec.gateId, 120))

    let snippet = extractLogSnippet(logPath)
    if snippet.len > 0:
      gateObj["logSnippet"] = newJString(snippet)

    gatesArr.add(gateObj)
    totalNs += rec.durationNs

  runObj["gates"] = gatesArr
  runObj["totalDurationNs"] = newJInt(totalNs)
  root["run"] = runObj
  stdout.write $root & "\n"
proc renderHistory(runs: seq[PipelineRun]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let maxRuns = min(runs.len, 10)
  if maxRuns == 0:
    echo "No pipeline runs found in history."
    return

  stdout.write "\n"
  stdout.write "━━━ Axiom Gate History (last " & $maxRuns & " runs) ━━━━━━━━━━━━━━━━\n"
  stdout.write "  " & alignLeft("Stage", 12) & alignLeft("Commit", 8) &
    alignLeft("Date", 17) & align("Pass", 5) & align("Warn", 5) &
    align("Fail", 5) & align("Dur", 8)
  stdout.write "\n"
  stdout.write "  " & "-".repeat(66) & "\n"

  for i in 0 ..< maxRuns:
    let run = runs[runs.len - 1 - i]  # most recent first
    var passC, warnC, failC: int
    let severityMap = loadSeverityMap()
    for rec in run.records:
      let sev = severityMap.getOrDefault(rec.gateId, gsWarn)
      let cls = classifyGate(rec, sev)
      case cls
      of gcPass: inc passC
      of gcWarn: inc warnC
      of gcFail: inc failC
      else: discard

    var totalNs: int64 = 0
    for rec in run.records:
      totalNs += rec.durationNs

    let tsTime = parseTimestamp(run.ts)
    let dateStr = tsTime.format("MM-dd HH:mm")
    let shortCommit = if run.commit.len > 6: run.commit[0 ..< 6] else: run.commit
    let durStr = durationNsToDisplay(totalNs)

    stdout.write "  " &
      alignLeft(run.stage, 12) &
      alignLeft(shortCommit, 8) &
      alignLeft(dateStr, 17) &
      align($passC, 5) &
      align($warnC, 5) &
      align($failC, 5) &
      align(durStr, 8) & "\n"

  stdout.write "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
proc renderGateDetail(gateId: string; history: seq[GateRecord];
                      severityMap: Table[string, GateSeverity];
                      slaMap: Table[string, int]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let sev = severityMap.getOrDefault(gateId, gsWarn)
  let sla = slaMap.getOrDefault(gateId, 120)

  # Collect all records for this gate
  var matches: seq[GateRecord]
  for rec in history:
    if rec.gateId == gateId:
      matches.add(rec)

  if matches.len == 0:
    echo "No history found for gate: " & gateId
    return

  stdout.write "\n"
  stdout.write "━━━ Gate Detail: " & gateId & " ━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  stdout.write "  Severity:  " & severityStr(sev) & "\n"
  stdout.write "  SLA:       " & $sla & "s\n"
  stdout.write "  Records:   " & $matches.len & " total\n"

  # Count results
  var resultCounts: Table[string, int]
  for rec in matches:
    if not resultCounts.hasKey(rec.result):
      resultCounts[rec.result] = 0
    inc resultCounts[rec.result]

  stdout.write "  Results:   "
  for result, count in resultCounts:
    stdout.write result & "=" & $count & "  "
  stdout.write "\n"

  # Last 5 runs
  let maxShow = min(matches.len, 5)
  stdout.write "\n  Last " & $maxShow & " runs:\n"
  for i in 0 ..< maxShow:
    let rec = matches[matches.len - 1 - i]
    let tsTime = parseTimestamp(rec.ts)
    let durStr = durationNsToDisplay(rec.durationNs)
    let cls = classifyGate(rec, sev)
    let marker = case cls
      of gcPass: "✅"
      of gcWarn: "[WARN] "
      of gcFail: "[FAIL]"
      of gcSkip: "⏭ "
      of gcRunning: "⏳"
      of gcDeferred: ".defer"

    stdout.write "    " & marker & " " &
      tsTime.format("MM-dd HH:mm") & "  " &
      durStr & "  " &
      rec.stage & "  " &
      rec.result & "\n"

  # Current state
  let latest = matches[matches.len - 1]
  let logPath = GateOutputDir & gateId & ".log"
  if isRecentlyModified(logPath, RunningThresholdMinutes):
    let snippet = extractLogSnippet(logPath)
    stdout.write "\n  🔴 CURRENTLY RUNNING"
    if snippet.len > 0:
      stdout.write ": " & snippet
    stdout.write "\n"

  stdout.write "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
proc runStatusCli*(args: seq[string]): int {.axiomEffect: IOEffect, raises: [CatchableError].} =
  var
    jsonMode = false
    historyMode = false
    gateFilter = ""

  # Parse flags
  var i = 0
  while i < args.len:
    case args[i]
    of "--json":
      jsonMode = true
    of "--history":
      historyMode = true
    of "--gate":
      if i + 1 < args.len:
        inc i
        gateFilter = args[i]
      else:
        logInfo("axiom_status", "Usage: ax status --gate <gate-id>")
        return 1
    of "--help", "-h":
      echo "ax status — Product State + gate pipeline observability dashboard"
      echo ""
      echo "Usage:"
      echo "  ax status              Show Product State summary and latest gate dashboard"
      echo "  ax status --json       Machine-parseable JSON output"
      echo "  ax status --history    Last 10 pipeline runs trend table"
      echo "  ax status --gate <id>  Detailed info for a specific gate"
      echo "  ax status --help       Show this help message"
      return 0
    else:
      logInfo("axiom_status", "Unknown flag: " & args[i])
      return 1
    inc i

  # Load data
  let severityMap = loadSeverityMap()
  let slaMap = loadSlaMap()
  let history = loadHistory()

  if history.len == 0:
    let noHistMsg = "No gate history found. Run a pipeline first."
    let noHistDetail = "  (Expected file: " & HistoryPath & ")"
    if jsonMode:
      stderr.writeLine noHistMsg
      stderr.writeLine noHistDetail
    else:
      echo noHistMsg
      echo noHistDetail
    return 0

  let runs = groupByTimestamp(history)

  # Gate detail mode
  if gateFilter.len > 0:
    if jsonMode:
      var gateJson = newJObject()
      let sev = severityMap.getOrDefault(gateFilter, gsWarn)
      let sla = slaMap.getOrDefault(gateFilter, 120)
      gateJson["gateId"] = newJString(gateFilter)
      gateJson["severity"] = newJString($sev)
      gateJson["slaSec"] = newJInt(sla)
      var matches: seq[GateRecord]
      for rec in history:
        if rec.gateId == gateFilter:
          matches.add(rec)
      gateJson["recordCount"] = newJInt(matches.len)
      if matches.len > 0:
        gateJson["lastResult"] = newJString(matches[matches.len - 1].result)
        gateJson["lastTs"] = newJString(matches[matches.len - 1].ts)
        gateJson["lastDurationNs"] = newJInt(matches[matches.len - 1].durationNs)
      stdout.write $gateJson & "\n"
    else:
      renderGateDetail(gateFilter, history, severityMap, slaMap)
    return 0

  # History mode
  if historyMode:
    if jsonMode:
      var arr = newJArray()
      for run in runs:
        var runObj = newJObject()
        runObj["ts"] = newJString(run.ts)
        runObj["stage"] = newJString(run.stage)
        runObj["commit"] = newJString(run.commit)
        runObj["gateCount"] = newJInt(run.records.len)
        var totalNs: int64 = 0
        for rec in run.records:
          totalNs += rec.durationNs
        runObj["totalDurationNs"] = newJInt(totalNs)
        arr.add(runObj)
      stdout.write $arr & "\n"
    else:
      renderHistory(runs)
    return 0

  # Default: show latest run
  # ── Product State (canonical claim/artifact summary) ──
  let proofStatePath = "logs/ax_proof_state.json"
  if fileExists(proofStatePath):
    let psRaw = readFile(proofStatePath)
    let psJson = parseJson(psRaw)
    let psSummary = psJson["summary"]
    let productStateOutput = "━━━ Product State ━━━\n" &
      "  verified: " & $psSummary["verified"] & "\n" &
      "  totalSymbols: " & $psSummary["symbolCount"] & "\n" &
      "  verifiedRatio: " & $psSummary["verifiedRatio"] & "\n" &
      "  verificationSuccessRate: " & $psSummary["verificationSuccessRate"] & "\n" &
      "\n"
    if jsonMode:
      stderr.writeLine productStateOutput
    else:
      stdout.write productStateOutput

  let latestRun = runs[runs.len - 1]
  if jsonMode:
    renderJson(latestRun, severityMap, slaMap)
  else:
    renderFormatted(latestRun, severityMap, slaMap)

  return 0

when isMainModule:
  let args = commandLineParams()
  let exitCode = runStatusCli(args)
  quit(exitCode)

{.pop.}
