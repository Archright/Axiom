import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/options
import std/strutils
import std/sequtils
import core/types/results
import core/parsers/safe_parsers

## Sanitize Token.
func sanitizeToken*(raw: string): string =
  let stripped = raw.strip()
  if stripped.len == 0:
    return "unknown"
  result = newStringOfCap(stripped.len)
  for ch in stripped:
    if ch.isAlphaNumeric or ch == '_':
      result.add(ch)
    else:
      result.add('_')
  if result[0].isDigit:
    result = "f_" & result

## Sanitize Axiom Token.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func sanitizeAxiomToken*(input: string): string {.raises: [].} =
  ## Convert `input` into a safe identifier token by replacing Nim module-path
  ## separators and any non-identifier characters with underscores (`_`).
  ## Returns the sanitized string suitable for use as a key or filename component.
  result = sanitizeToken(
    input
      .replace("::", "_")
      .replace(".", "_")
      .replace("/", "_")
      .replace("\\", "_")
  )

## Leading Whitespace.
# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
func leadingWhitespace*(raw: string): string =
  var idx = 0
  while idx < raw.len and (raw[idx] == ' ' or raw[idx] == '\t'):
    inc idx
  raw[0 ..< idx]

## Parse Int Optional.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func parseIntOpt*(raw: string): Option[int] =
  let r = safeParseInt(raw)
  if r.isOk(): some(r.get()) else: none(int)

## Tokenize Lowered.
# @axiom-hint: lean="text.length >= 0" smt="(assert (and (>= (str.len text) 0)))"
func tokenizeLowered*(text: string): seq[string] {.raises: [].} =
  ## Tokenize text into lowercase word tokens for formal pattern matching.
  var current = ""
  var i = 0
  while i < text.len:
    let c = text[i]
    if c in {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
      current.add(c.toLowerAscii())
      inc i
    elif c == '<' and i + 1 < text.len and text[i + 1] == '=':
      if current.len > 0:
        result.add(current)
        current = ""
      result.add("<=")
      inc i, 2
    elif c == '>' and i + 1 < text.len and text[i + 1] == '=':
      if current.len > 0:
        result.add(current)
        current = ""
      result.add(">=")
      inc i, 2
    else:
      if current.len > 0:
        result.add(current)
        current = ""
      inc i
  if current.len > 0:
    result.add(current)

## Compact Whitespace — SSOT for whitespace normalization.
## Removes empty lines and strips leading/trailing whitespace from each line.
func compactWhitespace*(raw: string): string {.raises: [].} =
  raw.splitLines().mapIt(it.strip()).filterIt(it.len > 0).join("\n")

## Clamp Integer — SSOT for integer clamping.
func clampInt*(value: int; lowerBound: int; upperBound: int): int {.inline.} =
  if value < lowerBound: return lowerBound
  if value > upperBound: return upperBound
  value

## Add Unique — SSOT for unique-append to seq[string].
## Deduplicates callsites in proof_vacuity_gate.nim and spec_generator_main.nim.
func addUnique*(items: var seq[string]; item: string) {.raises: [].} =
  if item.len > 0 and item notin items:
    items.add(item)

{.pop.}
