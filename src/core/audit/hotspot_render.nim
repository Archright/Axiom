## Hotspot Render
## Presentation layer for hotspot priority queue.
## Renders queue entries as TTY, Markdown, or JSON.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/strutils
import burn_down_queue

{.push raises: [].}
# axiomIoBoundary

type
  ReportFormat* = enum
    rfTTY, rfMarkdown, rfJson

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

func renderMarkdown*(queue: seq[HotspotEntry]; sinceDays: int): string =
  result = "# Hotspot Burn-down Queue\n\n"
  result &= "**Auto-generated report** — do not edit manually.\n\n"
  result &= "- Analysis period: last " & $sinceDays & " days\n"
  result &= "- Total hotspots tracked: " & $queue.len & "\n"
  result &= "- Scoring: priority = edits × risk_multiplier\n"
  result &= "  - No test: ×3.0, SAD<5%: ×2.0, SAD<15%: ×1.5, SAD≥15%: ×1.0\n\n"
  result &= "| Rank | Module | Path | Edits | Test? | SAD | Priority | Tier |\n"
  result &= "|------|--------|------|-------|-------|-----|----------|------|\n"
  for i, e in queue:
    let testMark = if e.hasTest: "✓" else: "✗"
    let sadStr = if e.hasTest: $(e.sadScore * 100).formatFloat(ffDecimal, 1) & "%" else: "—"
    result &= "| " & $(i + 1) & " | " & e.moduleName & " | " & e.filePath &
              " | " & $e.editCount & " | " & testMark & " | " & sadStr &
              " | " & $e.priorityScore & " | " & tierEmoji(e.tier) & " " & tierLabel(e.tier) & " |\n"

func renderJson*(queue: seq[HotspotEntry]; sinceDays: int): string =
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

func renderTTY*(queue: seq[HotspotEntry]; sinceDays: int): string =
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
{.pop.}
