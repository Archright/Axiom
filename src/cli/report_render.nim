## report_render.nim
## Report rendering utilities (boxes, headers, tables).

import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [ValueError].}
# axiomIoBoundary
import std/strformat
import std/strutils

import cli/version

## Render Unicode Box Top.
proc renderUnicodeBoxTop*(widths: seq[int]): string =
  result.add("┌")
  for i, w in widths:
    result.add(repeat("─", w))
    if i < widths.len - 1:
      result.add("┬")
  result.add("┐")

## Render Unicode Box Bottom.
proc renderUnicodeBoxBottom*(widths: seq[int]): string =
  result.add("└")
  for i, w in widths:
    result.add(repeat("─", w))
    if i < widths.len - 1:
      result.add("┴")
  result.add("┘")

## Render Unicode Box Separator.
proc renderUnicodeBoxSeparator*(widths: seq[int]): string =
  result.add("├")
  for i, w in widths:
    result.add(repeat("─", w))
    if i < widths.len - 1:
      result.add("┼")
  result.add("┤")

## Render Unicode Row.
proc renderUnicodeRow*(cells: seq[string]; widths: seq[int]; columnWidth: int): string =
  result.add("│")
  for i, cell in cells:
    let w = if i < widths.len: widths[i] else: columnWidth
    result.add(alignLeft(cell, w))
    if i < cells.len - 1:
      result.add("│")
  result.add("│")

## Format Section Title.
proc formatSectionTitle*(title: string; count: int): string =
  fmt"{title} ({count})"

## Render Summary Row.
proc renderSummaryRow*(name: string; value: string; percent: string; width: int): string =
  alignLeft(name, width) & " │ " & align(value, 8) & " │ " & align(percent, 6)

## Compute Summary Row Widths.
proc computeSummaryRowWidths*(columnWidth: int): seq[int] =
  @[columnWidth, 10, 8]

## Compute Dynamic Column Widths.
proc computeDynamicColumnWidths*(rowContents: seq[seq[string]]; minWidth: int = 16; padding: int = 2): seq[int] =
  if rowContents.len == 0:
    return @[minWidth]
  let colCount = rowContents[0].len
  result = newSeq[int](colCount)
  for i in 0 ..< colCount:
    result[i] = minWidth
  for row in rowContents:
    for i in 0 ..< min(row.len, colCount):
      result[i] = max(result[i], row[i].len + padding)

## Compute Row Widths From Summary.
proc computeRowWidthsFromSummary*(total: int; verified: int; verifiedPct: int; failed: int; failedPct: int; timeStr: string; attempted: int; unattempted: int; timedOut: int; cacheHits: int; minWidth: int = 16; padding: int = 2): seq[int] =
  let rows = @[
    @["Total", $total, ""],
    @["Verified", $verified, $verifiedPct & "%"],
    @["Failed", $failed, $failedPct & "%"],
    @["Time", timeStr, ""],
    @["Attempted", $attempted, ""],
    @["Unattempted", $unattempted, ""],
    @["Timed Out", $timedOut, ""],
    @["Cache Hits", $cacheHits, ""],
  ]
  computeDynamicColumnWidths(rows, minWidth, padding)

## Render Styled Box Line.
proc renderStyledBoxLine*(
  left: string; right: string; fill: string;
  width: int; style: string = ""
): string =
  result.add(left)
  result.add(repeat(fill, width - left.len - right.len))
  result.add(right)

## Render Single Column Box.
proc renderSingleColumnBox*(
  lines: seq[string]; width: int; style: string = ""
): seq[string] =
  result.add(renderStyledBoxLine("┌", "┐", "─", width))
  for line in lines:
    result.add("│ " & alignLeft(line, width - 4) & " │")
  result.add(renderStyledBoxLine("└", "┘", "─", width))

## Render Enterprise Header Lines.
proc renderEnterpriseHeaderLines*(vkdFixed4: string; useColor: bool = false): seq[string] =
  let versionStr = axiomVersionWithPrefix
  let asiStr = fmt"VKD {vkdFixed4}"
  result.add(fmt"Axiom Enterprise v{versionStr} — {asiStr}")
  result.add(repeat("─", 60))

## Render Integrity Certificate Lines.
proc renderIntegrityCertificateLines*(
  vkdFixed4: string;
  verifiedStatus: string = "PASSED"
): seq[string] =
  renderSingleColumnBox(@[
    "Certificate: " & vkdFixed4,
    "Status: " & verifiedStatus,
  ], 60)
{.pop.}

