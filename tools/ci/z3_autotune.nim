import core/trusted/layer_declaration
axiomLayer "tools"
import std/[algorithm, json, math, os, strutils, times]

const
  TelemetryPath = "logs/z3_telemetry.jsonl"
  ConstantsPath = "src/core/config/constants.nim"
  EmaAlpha = 2.0 / 8.0  ## 7-day EMA smoothing factor: 2/(N+1)

type
  TelemetryRecord = object
    ts: DateTime
    queryType: string
    rlimit: float
    result: string

proc parseIsoTs(s: string): DateTime =
  try:
    parse(s, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
  except CatchableError:
    utc(now())

proc loadTelemetryRecords(path: string; cutoff: DateTime): seq[TelemetryRecord] =
  result = @[]
  if not fileExists(path):
    return
  for line in lines(path):
    if line.strip().len == 0:
      continue
    try:
      let j = parseJson(line)
      let tsStr = j{"ts"}.getStr("")
      let ts = parseIsoTs(tsStr)
      if ts < cutoff:
        continue
      result.add(TelemetryRecord(
        ts: ts,
        queryType: j{"query_type"}.getStr("unknown"),
        rlimit: j{"rlimit"}.getFloat(0.0),
        result: j{"result"}.getStr("unknown")
      ))
    except CatchableError:
      discard  # axiom:best-effort(malformed telemetry record — skip silently)

proc percentile(sortedValues: seq[float]; p: float): float =
  if sortedValues.len == 0:
    return 0.0
  let idx = float(sortedValues.len - 1) * p
  let lowerIdx = int(floor(idx))
  let upperIdx = int(ceil(idx))
  if lowerIdx == upperIdx:
    return sortedValues[lowerIdx]
  let frac = idx - float(lowerIdx)
  result = sortedValues[lowerIdx] * (1.0 - frac) + sortedValues[upperIdx] * frac

proc filterIqr(values: seq[float]): seq[float] =
  if values.len < 4:
    return values
  var sorted = values
  sort(sorted)
  let q1 = percentile(sorted, 0.25)
  let q3 = percentile(sorted, 0.75)
  let iqr = q3 - q1
  let lower = q1 - 1.5 * iqr
  let upper = q3 + 1.5 * iqr
  result = @[]
  for v in sorted:
    if v >= lower and v <= upper:
      result.add(v)

proc computeEma(values: seq[float]): float =
  if values.len == 0:
    return 0.0
  result = values[0]
  for i in 1 ..< values.len:
    result = EmaAlpha * values[i] + (1.0 - EmaAlpha) * result

proc main() =
  let dryRun = paramCount() >= 1 and paramStr(1) == "--dry-run"

  let cutoff = now().utc - initDuration(days = 7)
  let records = loadTelemetryRecords(TelemetryPath, cutoff)

  if records.len == 0:
    echo "No telemetry records found in the last 7 days."
    echo "Recommended z3RlimitMultiplier: 1000 (no change)"
    return

  ## Group by query_type
  var queryTypes: seq[string] = @[]
  for r in records:
    if r.queryType notin queryTypes:
      queryTypes.add(r.queryType)

  var byQueryType: seq[tuple[queryType: string, p95: float]] = @[]
  for qt in queryTypes:
    var values: seq[float] = @[]
    for r in records:
      if r.queryType == qt:
        values.add(r.rlimit)
    let filtered = filterIqr(values)
    let p95 = percentile(filtered, 0.95)
    byQueryType.add((queryType: qt, p95: p95))

  ## Sort alphabetically for deterministic EMA ordering
  byQueryType.sort(proc(a, b: auto): int = cmp(a.queryType, b.queryType))

  var p95Seq: seq[float] = @[]
  for item in byQueryType:
    p95Seq.add(item.p95)

  let ema = computeEma(p95Seq)
  let newMultiplier = max(500.0, min(5000.0, ema * 1.2)).int

  echo "Z3 Autotune Report"
  echo "=================="
  echo "Records analyzed: ", records.len
  echo "Query types:      ", byQueryType.len
  for item in byQueryType:
    echo "  ", item.queryType, " P95 rlimit: ", item.p95.formatFloat(ffDecimal, 2)
  echo "EMA(P95):         ", ema.formatFloat(ffDecimal, 2)
  echo "Recommended z3RlimitMultiplier: ", newMultiplier

  if not dryRun:
    if not fileExists(ConstantsPath):
      echo "Warning: constants file not found, skipping update."
      return
    try:
      let content = readFile(ConstantsPath)
      ## Match the exact assignment pattern in constants.nim
      let oldPattern = "z3RlimitMultiplier* ="
      var updated = ""
      var found = false
      for line in content.splitLines():
        if not found and line.strip().startsWith(oldPattern):
          let indent = line[0 ..< line.find(oldPattern) + oldPattern.len]
          updated.add(indent & " " & $newMultiplier & "\n")
          found = true
        else:
          updated.add(line & "\n")
      if found:
        writeFile(ConstantsPath, updated)
        echo "Updated ", ConstantsPath
      else:
        echo "Warning: could not find 'z3RlimitMultiplier' in constants file."
    except CatchableError as e:
      echo "Error updating constants file: ", e.msg

when isMainModule:
  main()
