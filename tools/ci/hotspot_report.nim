## Hotspot Report Generator
## Generates markdown burn-down report from git history.
## Usage: nim c -r tools/ci/hotspot_report.nim --since=30 --top=20 --format=markdown

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, sequtils, tables, algorithm, parseopt]
import shared_types/audit_bridge

{.push raises: [OSError, IOError].}

type
  ReportFormat* = enum
    rfMarkdown, rfJson, rfTTY

func tierEmoji*(tier: HotspotTier): string =
  case tier
  of htCritical: "🔴"
  of htHigh: "🟠"
  of htMedium: "🟡"
  of htLow: "🟢"

func tierLabel*(tier: HotspotTier): string =
  case tier
  of htCritical: "Critical (no test)"
  of htHigh: "High (SAD<5%)"
  of htMedium: "Medium (SAD<15%)"
  of htLow: "Low (SAD≥15%)"

proc renderMarkdown*(queue: seq[HotspotEntry]; sinceDays: int): string =
  ## Render priority queue as markdown table.
  result = "# Hotspot Burn-down Queue\n\n"
  result &= "**Auto-generated report** — do not edit manually.\n\n"
  result &= "- Analysis period: last " & $sinceDays & " days\n"
  result &= "- Total hotspots tracked: " & $queue.len & "\n"
  result &= "- Scoring: priority = edits × risk_multiplier\n"
  result &= "  - No test: ×3.0, SAD<5%: ×2.0, SAD<15%: ×1.5, SAD≥15%: ×1.0\n\n"

  result &= "| Rank | Module | Path | Edits | Test? | SAD | Priority | Tier |\n"
  result &= "|------|--------|------|-------|-------|-----|----------|------|\n"

  for i, e in queue:
    let rank = $(i + 1)
    let testMark = if e.hasTest: "✓" else: "✗"
    let sadStr = if e.hasTest: $(e.sadScore * 100) & "%" else: "—"
    result &= "| " & rank & " | " & e.moduleName & " | " & e.filePath &
              " | " & $e.editCount & " | " & testMark & " | " & sadStr &
              " | " & $e.priorityScore & " | " & tierEmoji(e.tier) & " " & tierLabel(e.tier) & " |\n"

proc renderJson*(queue: seq[HotspotEntry]; sinceDays: int): string =
  ## Render priority queue as compact JSON.
  var lines: seq[string] = @[]
  lines.add("{\"period_days\": " & $sinceDays & ", \"hotspots\": [")
  for i, e in queue:
    let comma = if i < queue.len - 1: "," else: ""
    let testPath = if e.testPath.len > 0: "\"" & e.testPath & "\"" else: "null"
    lines.add("  {\"rank\": " & $(i + 1) & ", \"module\": \"" & e.moduleName &
              "\", \"path\": \"" & e.filePath & "\", \"edits\": " & $e.editCount &
              ", \"has_test\": " & $e.hasTest & ", \"test_path\": " & testPath &
              ", \"sad\": " & $e.sadScore & ", \"priority\": " & $e.priorityScore &
              ", \"tier\": \"" & $e.tier & "\"}" & comma)
  lines.add("]}")
  result = lines.join("\n")

proc renderTTY*(queue: seq[HotspotEntry]; sinceDays: int): string =
  ## Render priority queue as colored terminal output.
  result = "Hotspot Burn-down Queue (last " & $sinceDays & " days)\n"
  result &= repeat("=", 80) & "\n"
  result &= align("Rank", 5) & " " & align("Module", 30) & " " &
            align("Edits", 6) & " " & align("Test?", 5) & " " &
            align("SAD", 6) & " " & align("Priority", 10) & " " & "Tier\n"
  result &= repeat("-", 80) & "\n"
  for i, e in queue:
    let testMark = if e.hasTest: "✓" else: "✗"
    let sadStr = if e.hasTest: $(e.sadScore * 100).formatFloat(ffDecimal, 1) & "%" else: "—"
    result &= align($(i + 1), 5) & " " & alignLeft(e.moduleName, 30) & " " &
              align($e.editCount, 6) & " " & align(testMark, 5) & " " &
              align(sadStr, 6) & " " & align($e.priorityScore, 10) & " " &
              tierLabel(e.tier) & "\n"

when isMainModule:
  var sinceDays = 30
  var topN = 20
  var fmt = rfTTY

  var p = initOptParser(commandLineParams())
  for kind, key, val in p.getopt():
    case kind
    of cmdShortOption, cmdLongOption:
      case key
      of "since", "s": sinceDays = parseInt(val)
      of "top", "t": topN = parseInt(val)
      of "format", "f":
        case val.toLowerAscii()
        of "markdown", "md": fmt = rfMarkdown
        of "json": fmt = rfJson
        of "tty", "terminal": fmt = rfTTY
        else: stderr.writeLine("Unknown format: " & val); quit(1)
      else: discard
    of cmdArgument: discard
    of cmdEnd: break

  let churn = computeChurnScores(sinceDays)
  let queue = buildPriorityQueue(churn, topN)

  case fmt
  of rfMarkdown: echo renderMarkdown(queue, sinceDays)
  of rfJson: echo renderJson(queue, sinceDays)
  of rfTTY: echo renderTTY(queue, sinceDays)
