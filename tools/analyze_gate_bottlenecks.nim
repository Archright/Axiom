## tools/analyze_gate_bottlenecks.nim
## Bottleneck analysis CLI for gate telemetry data.
## Reads .axiom/cache/gate_history.jsonl and produces:
##   - Top-N slowest gates (sorted by mean duration)
##   - Cache hit rate per gate
##   - Timeout/fail statistics
##   - Stage comparison (pre-commit vs pre-push vs CI)
##
## Usage:
##   nim c -o:bin/analyze_gate_bottlenecks tools/analyze_gate_bottlenecks.nim
##   bin/analyze_gate_bottlenecks [--top=10] [--days=7] [--stage=pre-commit]

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, strformat, json, times, algorithm, tables]

const
  HistoryPath = ".axiom/gate_history.jsonl"
  SummaryDir = ".axiom/gate_runs"

type
  GateStats = object
    gateId: string
    count: int
    totalNs: int64
    minNs: int64
    maxNs: int64
    passCount: int
    failCount: int
    timeoutCount: int
    cachedCount: int
    skipCount: int
    tier: string

  StageFilter = enum
    sfAll = "all"
    sfPreCommit = "pre-commit"
    sfPrePush = "pre-push"
    sfCI = "ci"

proc parseArgs(): tuple[topN: int, days: int, stage: StageFilter, json: bool] =
  result = (10, 7, sfAll, false)
  for i in 1..paramCount():
    let p = paramStr(i)
    if p.startsWith("--top="):
      result.topN = parseInt(p[6..^1])
    elif p.startsWith("--days="):
      result.days = parseInt(p[7..^1])
    elif p.startsWith("--stage="):
      let s = p[8..^1]
      case s
      of "all": result.stage = sfAll
      of "pre-commit": result.stage = sfPreCommit
      of "pre-push": result.stage = sfPrePush
      of "ci": result.stage = sfCI
      else: discard
    elif p == "--json":
      result.json = true
    elif p == "--help" or p == "-h":
      echo "Usage: analyze_gate_bottlenecks [--top=N] [--days=N] [--stage=all|pre-commit|pre-push|ci] [--json]"
      quit(0)

proc loadHistory(path: string, maxAge: int, stage: StageFilter): seq[JsonNode] =
  ## Load history records within maxAge days, optionally filtered by stage.
  if not fileExists(path):
    return @[]
  let cutoff = now() - initDuration(days = maxAge)
  for line in lines(path):
    if line.len == 0: continue
    try:
      let j = parseJson(line)
      # Filter by time — try multiple formats
      let ts = j{"ts"}.getStr("")
      if ts.len > 0:
        var recordTime: DateTime
        var parsed = false
        for fmt in ["yyyy-MM-dd'T'HH:mm:sszzz", "yyyy-MM-dd'T'HH:mm:ss'.'fffzzz", "yyyy-MM-dd'T'HH:mm:ss"]:
          try:
            recordTime = parse(ts, fmt)
            parsed = true
            break
          except CatchableError: discard  # axiom:best-effort(timestamp parse fallback)
        if parsed and recordTime < cutoff: continue
      # Filter by stage
      if stage != sfAll:
        let stageName = j{"ctx"}{"stage"}.getStr("")
        case stage
        of sfPreCommit:
          if stageName != "pre-commit": continue
        of sfPrePush:
          if stageName != "pre-push": continue
        of sfCI:
          if stageName != "ci": continue
        else: discard
      result.add(j)
    except CatchableError: discard  # axiom:best-effort(history load failure)

proc aggregateStats(records: seq[JsonNode]): Table[string, GateStats] =
  ## Aggregate gate statistics from history records.
  result = initTable[string, GateStats]()
  for j in records:
    let gateId = j{"gateId"}.getStr("")
    if gateId.len == 0: continue
    let durationNs = j{"durationNs"}.getInt(0)
    let res = j{"result"}.getStr("")
    let cached = j{"cached"}.getBool(false)
    let tier = j{"tier"}.getStr("L2")

    if gateId notin result:
      result[gateId] = GateStats(
        gateId: gateId,
        count: 0,
        totalNs: 0,
        minNs: high(int64),
        maxNs: 0,
        tier: tier
      )
    var s = result[gateId]
    inc s.count
    s.totalNs += durationNs
    if durationNs < s.minNs: s.minNs = durationNs
    if durationNs > s.maxNs: s.maxNs = durationNs
    case res
    of "pass": inc s.passCount
    of "fail": inc s.failCount
    of "timeout": inc s.timeoutCount
    of "skip": inc s.skipCount
    else: discard
    if cached: inc s.cachedCount
    result[gateId] = s

proc formatDuration(ns: int64): string =
  if ns >= 1_000_000_000:
    &"{ns.float / 1_000_000_000:.2f}s"
  elif ns >= 1_000_000:
    &"{ns.float / 1_000_000:.1f}ms"
  elif ns >= 1_000:
    &"{ns.float / 1_000:.1f}µs"
  else:
    &"{ns}ns"

proc printTable(stats: Table[string, GateStats], topN: int) =
  ## Print top-N slowest gates by mean duration.
  var sorted: seq[GateStats]
  for _, s in stats:
    if s.count > 0:
      sorted.add(s)
  # Sort by mean duration (totalNs / count)
  sorted.sort(proc(a, b: GateStats): int =
    let aMean = a.totalNs div a.count.int64
    let bMean = b.totalNs div b.count.int64
    result = cmp(aMean, bMean)
  )

  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════════════╗"
  echo "║                    GATE BOTTLENECK ANALYSIS                                ║"
  echo "╠══════════════════════════════════════════════════════════════════════════════╣"
  echo ""
  echo &"  Top {min(topN, sorted.len)} slowest gates (by mean duration):"
  echo ""
  echo "  ┌─" & "─".repeat(72) & "┐"
  echo "  │ " & alignLeft("Gate ID", 30) & " │ " & align("Mean", 10) & " │ " & align("Min", 10) & " │ " & align("Max", 10) & " │ " & align("Runs", 5) & " │ " & align("Pass%", 6) & " │"
  echo "  ├─" & "─".repeat(72) & "┤"

  for i in 0..<min(topN, sorted.len):
    let s = sorted[i]
    let meanNs = s.totalNs div s.count.int64
    let passRate = if s.count > 0: (s.passCount * 100) div s.count else: 0
    let gateIdTrunc = if s.gateId.len > 30: s.gateId[0..26] & "..." else: s.gateId
    echo "  │ " & alignLeft(gateIdTrunc, 30) & " │ " & align(formatDuration(meanNs), 10) & " │ " & align(formatDuration(s.minNs), 10) & " │ " & align(formatDuration(s.maxNs), 10) & " │ " & align($s.count, 5) & " │ " & align($passRate & "%", 6) & " │"

  echo "  └─" & "─".repeat(72) & "┘"

  # Summary statistics
  echo ""
  echo "  ── Summary ──────────────────────────────────────────────────────────────"
  var totalRuns = 0
  var totalPass = 0
  var totalFail = 0
  var totalTimeout = 0
  var totalCached = 0
  var totalSkip = 0
  for _, s in stats:
    totalRuns += s.count
    totalPass += s.passCount
    totalFail += s.failCount
    totalTimeout += s.timeoutCount
    totalCached += s.cachedCount
    totalSkip += s.skipCount

  echo &"  Total runs analyzed:   {totalRuns}"
  let passRate = if totalRuns > 0: (totalPass * 100) div totalRuns else: 0
  echo &"  Pass:                  {totalPass} ({passRate}%)"
  echo &"  Fail:                  {totalFail}"
  echo &"  Timeout:               {totalTimeout}"
  echo &"  Cached (skip):         {totalCached}"
  echo &"  Dependency skip:       {totalSkip}"
  if totalRuns > 0:
    let cacheRate = (totalCached * 100) div totalRuns
    echo &"  Cache hit rate:        {cacheRate}%"
  echo ""

proc printJson(stats: Table[string, GateStats]) =
  ## Output stats as JSON for programmatic consumption.
  var arr = newJArray()
  for _, s in stats:
    if s.count == 0: continue
    var obj = newJObject()
    obj["gateId"] = %s.gateId
    obj["count"] = %s.count
    obj["meanNs"] = %(s.totalNs div s.count.int64)
    obj["minNs"] = %s.minNs
    obj["maxNs"] = %s.maxNs
    obj["passCount"] = %s.passCount
    obj["failCount"] = %s.failCount
    obj["timeoutCount"] = %s.timeoutCount
    obj["cachedCount"] = %s.cachedCount
    obj["skipCount"] = %s.skipCount
    obj["tier"] = %s.tier
    arr.add(obj)
  echo arr.pretty()

proc main() =
  let (topN, days, stage, jsonOutput) = parseArgs()

  # Load from history.jsonl (primary source)
  let historyPath = HistoryPath
  let records = loadHistory(historyPath, days, stage)

  if records.len == 0:
    echo &"No telemetry data found in {historyPath} (last {days} days, stage={stage})."
    echo "Run a gate cycle first: git commit --allow-empty -m 'test'"
    quit(1)

  let stats = aggregateStats(records)

  if jsonOutput:
    printJson(stats)
  else:
    printTable(stats, topN)

when isMainModule:
  main()
