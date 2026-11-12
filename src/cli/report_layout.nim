import core/trusted/layer_declaration
axiomLayer "presentation"
import ../core/trusted/axiom_pragmas
import cli/version
type
  ReportColumn* = object
    name*: string
    width*: int

  ReportSummaryRow* = object
    columns*: seq[tuple[name: string, value: string]]

  ReportLayoutConfig* = object
    termWidth*: int
    columnWidth*: int
    maxLabelWidth*: int
const
  ArchrightEnterpriseVersion* = axiomVersionWithPrefix
  ArchrightEnterpriseTitle* = "ARCHRIGHT AXIOM ENGINE " & axiomVersionWithPrefix & " [Enterprise Alpha]"
  ArchrightEngineTitle* = "Axiom Integrity Engine"
  ArchrightCertificateTitle* = "Archright Integrity Certificate"

  UnicodeBoxTopLeft* = "┌"
  UnicodeBoxTopRight* = "┐"
  UnicodeBoxBottomLeft* = "└"
  UnicodeBoxBottomRight* = "┘"
  UnicodeBoxHorizontal* = "─"
  UnicodeBoxVertical* = "│"
  UnicodeBoxCross* = "┼"
  UnicodeBoxLeftTee* = "├"
  UnicodeBoxRightTee* = "┤"
  UnicodeBoxTopTee* = "┬"
  UnicodeBoxBottomTee* = "┴"

  AnsiReset* = "\x1b[0m"
  AnsiBold* = "\x1b[1m"
  AnsiRed* = "\x1b[31m"
  AnsiGreen* = "\x1b[32m"
  AnsiYellow* = "\x1b[33m"
  AnsiCyan* = "\x1b[36m"
  AnsiWhite* = "\x1b[37m"
  AnsiDim* = "\x1b[2m"

## Compute Column Width.
func computeColumnWidth*(dataWidth: int; minWidth: int = 16): int {.noSideEffect, axiom: ["(assert (and (and (>= dataWidth -9223372036854775808) (<= dataWidth 9223372036854775807)) (and (>= minWidth -9223372036854775808) (<= minWidth 9223372036854775807))))", "dataWidth ≥ -9223372036854775808 ∧ dataWidth ≤ 9223372036854775807 ∧ minWidth ≥ -9223372036854775808 ∧ minWidth ≤ 9223372036854775807"].} =
  max(minWidth, dataWidth)

## Compute Max Label Width.
func computeMaxLabelWidth*(labelWidth: int; termWidth: int; reserved: int = 20): int {.noSideEffect, axiom: ["(assert (and (and (>= labelWidth -9223372036854775808) (<= labelWidth 9223372036854775807)) (and (>= termWidth -9223372036854775808) (<= termWidth 9223372036854775807)) (and (>= reserved -9223372036854775808) (<= reserved 9223372036854775807))))", "labelWidth ≥ -9223372036854775808 ∧ labelWidth ≤ 9223372036854775807 ∧ termWidth ≥ -9223372036854775808 ∧ termWidth ≤ 9223372036854775807 ∧ reserved ≥ -9223372036854775808 ∧ reserved ≤ 9223372036854775807"].} =
  max(20, termWidth - reserved)

## Create Layout Config.
func createLayoutConfig*(termWidth: int; columnMinWidth: int = 16): ReportLayoutConfig {.noSideEffect, axiom: ["(assert (and (and (>= termWidth -9223372036854775808) (<= termWidth 9223372036854775807)) (and (>= columnMinWidth -9223372036854775808) (<= columnMinWidth 9223372036854775807)) ast_parse_failed_isolated))", "termWidth ≥ -9223372036854775808 ∧ termWidth ≤ 9223372036854775807 ∧ columnMinWidth ≥ -9223372036854775808 ∧ columnMinWidth ≤ 9223372036854775807 ∧ ast_parse_failed_isolated"].} =
  let safeWidth = max(60, termWidth)
  let safeColumnWidth = max(columnMinWidth, computeColumnWidth(0, columnMinWidth))
  ReportLayoutConfig(
    termWidth: safeWidth,
    columnWidth: safeColumnWidth,
    maxLabelWidth: computeMaxLabelWidth(0, safeWidth, 20),
  )

