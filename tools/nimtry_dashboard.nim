## nimtry_dashboard.nim — Trend report for nimtry violation snapshots.
##
## Reads all logs/nimtry_history/*.json snapshots and data/nimtry_baseline.json,
## then outputs a console/markdown trend report or an HTML page.
##
## Usage:
##   nim c -r src/gate/runners/nimtry_dashboard.nim                 # console markdown
##   nim c -r src/gate/runners/nimtry_dashboard.nim --html          # HTML page
##   nim c -r src/gate/runners/nimtry_dashboard.nim --budget        # weekly 5% reduction check
##   nim c -r src/gate/runners/nimtry_dashboard.nim --html --budget # both

import core/trusted/layer_declaration
axiomLayer "tools"
import shared_types/shared_types
import std/json
import std/options
import std/os
import std/strutils
import std/times
import std/algorithm

axiomIoBoundary()

const
  GateTag = "[nimtry-dashboard]"
  HistoryRelDir = "logs/nimtry_history"
  BaselineRelPath = "data/nimtry_baseline.json"

type
  SnapshotEntry = object
    timestamp: string
    commit: string
    total: int
    errors: int
    warnings: int
    byRule: JsonNode
    isBaseline: bool
    delta: int

proc trendArrow(delta: int): string =
  if delta < 0:
    "📉 " & $delta
  elif delta > 0:
    "📈 +" & $delta
  else:
    "➡️  " & $delta

proc loadSnapshots(repoRoot: string): seq[SnapshotEntry] {.axiomEffect: IoEffect.} =
  let baselinePath = repoRoot / BaselineRelPath
  if fileExists(baselinePath):
    try:
      let data = parseJson(readFile(baselinePath))
      let sev = data.getOrDefault("by_severity")
      result.add(SnapshotEntry(
        timestamp: "baseline",
        commit: "baseline",
        total: data.getOrDefault("total_violations").getInt(0),
        errors: if sev.isNil: 0 else: sev.getOrDefault("error").getInt(0),
        warnings: if sev.isNil: 0 else: sev.getOrDefault("warning").getInt(0),
        byRule: data.getOrDefault("by_rule"),
        isBaseline: true,
        delta: 0
      ))
    except CatchableError as e:
      stderr.writeLine(GateTag, " WARNING: could not parse baseline: ", e.msg)

  let historyDir = repoRoot / HistoryRelDir
  if dirExists(historyDir):
    var files: seq[string] = @[]
    for kind, path in walkDir(historyDir):
      if kind == pcFile and path.endsWith(".json"):
        files.add(path)
    files.sort()

    for path in files:
      try:
        let data = parseJson(readFile(path))
        let (_, _, name) = splitFile(path)
        result.add(SnapshotEntry(
          timestamp: data.getOrDefault("timestamp").getStr("unknown"),
          commit: data.getOrDefault("commit").getStr("?"),
          total: data.getOrDefault("total").getInt(0),
          errors: data.getOrDefault("errors").getInt(0),
          warnings: data.getOrDefault("warnings").getInt(0),
          byRule: data.getOrDefault("by_rule"),
          isBaseline: false,
          delta: 0
        ))
      except CatchableError as e:
        stderr.writeLine(GateTag, " ⚠️  Skipping ", extractFilename(path), ": ", e.msg)

proc computeDeltas(entries: var seq[SnapshotEntry]) =
  for i in 0 ..< entries.len:
    if i == 0:
      entries[i].delta = 0
    else:
      entries[i].delta = entries[i].total - entries[i - 1].total

proc shortenTs(ts: string): string =
  if ts.len > 10 and "T" in ts:
    ts[0 ..< 10]
  else:
    ts

proc formatConsole(entries: seq[SnapshotEntry]): string =
  if entries.len == 0:
    return "No nimtry snapshots found."

  var lines: seq[string] = @[]
  lines.add("# nimtry Violation Trend Report")
  lines.add("")
  lines.add("Generated: " & now().format("yyyy-MM-dd HH:mm:ss"))
  lines.add("Snapshots: " & $entries.len)
  lines.add("")
  lines.add("| Date | Commit | Total | Errors | Warnings | Δ |")
  lines.add("|------|--------|-------|--------|----------|---|")

  for e in entries:
    let ts = shortenTs(e.timestamp)
    let commit = if e.commit.len > 8: e.commit[0 ..< 8] else: e.commit
    lines.add("| " & ts & " | " & commit & " | " & $e.total &
      " | " & $e.errors & " | " & $e.warnings & " | " & trendArrow(e.delta) & " |")

  if entries.len >= 2:
    let first = entries[0]
    let last = entries[^1]
    let totalChange = last.total - first.total
    lines.add("")
    lines.add("**Net change**: " & $totalChange & " violations (" &
      $first.total & " → " & $last.total & ")")

  # Top rules breakdown from latest snapshot
  let latest = entries[^1]
  if not latest.byRule.isNil and latest.byRule.kind == JObject:
    var rulePairs: seq[(string, int)] = @[]
    for k, v in latest.byRule:
      rulePairs.add((k, v.getInt()))
    rulePairs.sort(proc (a, b: (string, int)): int = cmp(b[1], a[1]))
    if rulePairs.len > 0:
      lines.add("")
      lines.add("## Top Violation Rules (latest snapshot)")
      lines.add("")
      lines.add("| Rule | Count |")
      lines.add("|------|-------|")
      let limit = min(15, rulePairs.len)
      for i in 0 ..< limit:
        lines.add("| " & rulePairs[i][0] & " | " & $rulePairs[i][1] & " |")

  lines.join("\n")

proc computeBudget(entries: seq[SnapshotEntry]): string =
  if entries.len < 2:
    return "\n📊 Budget: Not enough snapshots for weekly analysis."

  var lines: seq[string] = @[]
  lines.add("\n## Weekly Budget Tracking (5% reduction target)")
  lines.add("")

  # Group by week
  var weeks: seq[(string, seq[SnapshotEntry])] = @[]
  for e in entries:
    let ts = e.timestamp
    var weekKey = ""
    if ts == "baseline" or ts.len < 10:
      weekKey = "baseline"
    else:
      try:
        let s = ts.replace("Z", "+00:00")
        for fmt in ["yyyy-MM-dd'T'HH:mm:sszzz", "yyyy-MM-dd'T'HH:mm:ss'.'fffzzz",
                     "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]:
          try:
            let dt = parse(s, fmt)
            # ISO 8601 week number: Jan 4 is always in week 1
            let year = dt.year
            let jan4 = dateTime(4, mJan, year, 0, 0, 0, 0, utc())
            let jan4Weekday = jan4.weekDay.ord  # 0=Mon
            let dayOfYear = dt.yearday
            let weekStart = dayOfYear - ((jan4Weekday + dayOfYear - jan4.yearday) %% 7)
            let weekNum = (weekStart div 7) + 1
            weekKey = $year & "-W" & $weekNum
            break
          except ValueError:
            discard
        if weekKey.len == 0:
          weekKey = "unknown"
      except CatchableError:
        weekKey = "unknown"

    var found = false
    for i, (wk, _) in weeks:
      if wk == weekKey:
        weeks[i][1].add(e)
        found = true
        break
    if not found:
      weeks.add((weekKey, @[e]))

  var prevTotal: Option[int]
  for (wk, entriesInWeek) in weeks:
    let latestInWeek = entriesInWeek[^1]
    let total = latestInWeek.total

    if prevTotal.isSome and prevTotal.get() > 0:
      let pt = prevTotal.get()
      let changePct = ((total - pt).float / pt.float) * 100.0
      let target = (pt.float * 0.95).int
      let onBudget = total <= target
      let status = if onBudget: "✅ ON BUDGET" else: "❌ OVER BUDGET"
      lines.add("  " & wk & ": " & $pt & " → " & $total &
        " (" & formatFloat(changePct, ffDecimal, 1) & "%) " &
        "[target ≤ " & $target & "] " & status)
    else:
      lines.add("  " & wk & ": " & $total & " (baseline)")

    prevTotal = some(total)

  lines.join("\n")

proc formatHtml(entries: seq[SnapshotEntry], includeBudget: bool): string =
  if entries.len == 0:
    return "<html><body><p>No snapshots found.</p></body></html>"

  let latest = entries[^1]

  var tableRows = ""
  for e in entries:
    let ts = shortenTs(e.timestamp)
    let commit = if e.commit.len > 8: e.commit[0 ..< 8] else: e.commit
    let deltaClass = if e.delta < 0: "good" elif e.delta > 0: "bad" else: "neutral"
    let deltaStr = if e.delta > 0: "+" & $e.delta else: $e.delta
    tableRows.add("<tr><td>" & ts & "</td><td><code>" & commit & "</code></td>" &
      "<td>" & $e.total & "</td><td>" & $e.errors & "</td><td>" & $e.warnings & "</td>" &
      "<td class=\"" & deltaClass & "\">" & deltaStr & "</td></tr>\n")

  var ruleRows = ""
  if not latest.byRule.isNil and latest.byRule.kind == JObject:
    var rulePairs: seq[(string, int)] = @[]
    for k, v in latest.byRule:
      rulePairs.add((k, v.getInt()))
    rulePairs.sort(proc (a, b: (string, int)): int = cmp(b[1], a[1]))
    let limit = min(15, rulePairs.len)
    for i in 0 ..< limit:
      ruleRows.add("<tr><td>" & rulePairs[i][0] & "</td><td>" & $rulePairs[i][1] & "</td></tr>\n")

  var budgetHtml = ""
  if includeBudget and entries.len >= 2:
    let firstTotal = entries[0].total
    let lastTotal = entries[^1].total
    let change = lastTotal - firstTotal
    budgetHtml = "\n<h2>Weekly Budget (5% reduction target)</h2>\n" &
      "<p>Baseline: " & $firstTotal & " → Current: " & $lastTotal &
      " (net change: " & $change & ")</p>\n"

  "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"UTF-8\">\n" &
  "<title>nimtry Dashboard</title>\n<style>\n" &
  "  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;\n" &
  "         max-width: 900px; margin: 2rem auto; padding: 0 1rem; color: #222; }\n" &
  "  h1 { color: #1a1a2e; border-bottom: 2px solid #e94560; padding-bottom: 0.3rem; }\n" &
  "  h2 { color: #16213e; margin-top: 2rem; }\n" &
  "  table { border-collapse: collapse; width: 100%; margin: 1rem 0; }\n" &
  "  th, td { border: 1px solid #ddd; padding: 0.5rem; text-align: left; }\n" &
  "  th { background: #16213e; color: white; }\n" &
  "  tr:nth-child(even) { background: #f8f8f8; }\n" &
  "  .good { color: #2ecc71; font-weight: bold; }\n" &
  "  .bad { color: #e74c3c; font-weight: bold; }\n" &
  "  .neutral { color: #95a5a6; }\n" &
  "  code { background: #f4f4f4; padding: 0.15rem 0.4rem; border-radius: 3px; }\n" &
  "  .meta { color: #666; font-size: 0.9rem; }\n" &
  "</style>\n</head>\n<body>\n" &
  "<h1>🔍 nimtry Violation Dashboard</h1>\n" &
  "<p class=\"meta\">Generated: " & now().format("yyyy-MM-dd HH:mm:ss") &
  " | Snapshots: " & $entries.len & "</p>\n" &
  "<h2>Trend</h2>\n<table>\n" &
  "<tr><th>Date</th><th>Commit</th><th>Total</th><th>Errors</th><th>Warnings</th><th>Δ</th></tr>\n" &
  tableRows & "</table>\n" &
  "<h2>Top Violation Rules (latest)</h2>\n<table>\n" &
  "<tr><th>Rule</th><th>Count</th></tr>\n" &
  ruleRows & "</table>\n" & budgetHtml & "</body>\n</html>"

proc main() {.axiomEffect: IoEffect.} =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)

  var htmlMode = false
  var budgetMode = false
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg == "--html":
      htmlMode = true
    elif arg == "--budget":
      budgetMode = true

  var entries = loadSnapshots(repoRoot)
  computeDeltas(entries)

  if htmlMode:
    echo formatHtml(entries, budgetMode)
  else:
    echo formatConsole(entries)
    if budgetMode:
      echo computeBudget(entries)

when isMainModule:
  main()
