## report_format.nim
## Report field formatting utilities.

import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
# axiomIoBoundary
import std/strformat
import std/strutils

const ESC* = "\x1b"

## Format Int Field.
func formatIntField*(value: int; width: int): string =
  align($value, width)

## Format Percent Field.
func formatPercentField*(value: int; total: int): string =
  if total == 0:
    "0%"
  else:
    fmt"{value * 100 div total}%"

## Format Time Field.
func formatTimeField*(timeMs: int): string =
  if timeMs < 1000:
    fmt"{timeMs}ms"
  elif timeMs < 60000:
    fmt"{timeMs div 1000}s"
  else:
    fmt"{timeMs div 60000}m {(timeMs mod 60000) div 1000}s"

## Ellipsize Text.
func ellipsizeText*(text: string; maxLen: int): string =
  if text.len <= maxLen:
    text
  else:
    text[0 ..< maxLen - 3] & "..."

## Apply Ansi Color.
func applyAnsiColor*(text: string; colorCode: string; useColor: bool): string =
  if useColor:
    fmt"{ESC}[{colorCode}m{text}{ESC}[0m"
  else:
    text

## Apply Ansi Dim.
func applyAnsiDim*(text: string; useColor: bool): string =
  applyAnsiColor(text, "2", useColor)

## Apply Ansi Bold.
func applyAnsiBold*(text: string; useColor: bool): string =
  applyAnsiColor(text, "1", useColor)
{.pop.}


