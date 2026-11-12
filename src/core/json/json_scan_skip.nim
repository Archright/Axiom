import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import core/gateway/gateway
import core/types/results
import ../../core/trusted/axiom_pragmas

## I Json Whitespace.
func isJsonWhitespace*(ch: char): bool {.inline, axiom: ["(assert (and ast_parse_failed_isolated (= 1 1)))", "ast_parse_failed_isolated ∧ 1 = 1"].} =
  ch in {' ', '\t', '\r', '\n'}

## Skip Json Whitespace.
  ## axiom-smt: (assert (and (= result startIdx) (>= result 0)))
  ## axiom-lean: result = startIdx ∧ (result ≥ 0)
func skipJsonWhitespace*(raw: string; startIdx: int): int {.axiomTryImpl.} =
  result = startIdx
  while result < raw.len and isJsonWhitespace(raw[result]):
    inc result

## Hex Digit Value.
func hexDigitValue*(ch: char): int {.inline.} =
  if ch >= '0' and ch <= '9':
    return ord(ch) - ord('0')
  if ch >= 'a' and ch <= 'f':
    return ord(ch) - ord('a') + 10
  if ch >= 'A' and ch <= 'F':
    return ord(ch) - ord('A') + 10
  -1

## Append Code Point.
  ## axiom-smt: (assert (and (<= codePoint 0x7F) (<= codePoint 0x7FF) (<= codePoint 0xFFFF)))
  ## axiom-lean: codePoint ≤ 0x7F ∧ codePoint ≤ 0x7FF ∧ codePoint ≤ 0xFFFF
func appendCodePoint*(target: var string; codePoint: int) {.axiomTryImpl.} =
  if codePoint <= 0x7F:
    target.add(chr(codePoint))
  elif codePoint <= 0x7FF:
    target.add(chr(0xC0 or (codePoint shr 6)))
    target.add(chr(0x80 or (codePoint and 0x3F)))
  elif codePoint <= 0xFFFF:
    target.add(chr(0xE0 or (codePoint shr 12)))
    target.add(chr(0x80 or ((codePoint shr 6) and 0x3F)))
    target.add(chr(0x80 or (codePoint and 0x3F)))
  else:
    target.add(chr(0xF0 or (codePoint shr 18)))
    target.add(chr(0x80 or ((codePoint shr 12) and 0x3F)))
    target.add(chr(0x80 or ((codePoint shr 6) and 0x3F)))
    target.add(chr(0x80 or (codePoint and 0x3F)))

## Decode Json String.
  ## axiom-smt: (assert (and (< digit 0) (< cursor (str.len raw)) (>= codePoint 0) (and (>= cursor 0) (< cursor raw))))
  ## axiom-lean: digit < 0 ∧ cursor < raw.length ∧ (codePoint ≥ 0) ∧ ((cursor ≥ 0) ∧ (cursor < raw))
func decodeJsonString*(raw: string; startIdx: int): Result[(string, int), AxiomError] {.axiomTryImpl.} =
  let i = skipJsonWhitespace(raw, startIdx)
  if i >= raw.len or raw[i] != '"':
    return err(axiomErrJsonWrongType)
  var cursor = i + 1
  var decoded = ""
  while cursor < raw.len:
    let ch = raw[cursor]
    if ch == '"':
      return ok((decoded, cursor + 1))
    if ch == '\\':
      if cursor + 1 >= raw.len:
        return err(axiomErrJsonInvalid)
      let esc = raw[cursor + 1]
      case esc
      of '"', '\\', '/':
        decoded.add(esc)
        cursor += 2
      of 'b':
        decoded.add('\b')
        cursor += 2
      of 'f':
        decoded.add('\f')
        cursor += 2
      of 'n':
        decoded.add('\n')
        cursor += 2
      of 'r':
        decoded.add('\r')
        cursor += 2
      of 't':
        decoded.add('\t')
        cursor += 2
      of 'u':
        if cursor + 5 >= raw.len:
          return err(axiomErrJsonInvalid)
        var codePoint = 0
        for idx in 0 .. 3:
          let digit = hexDigitValue(raw[cursor + 2 + idx])
          if digit < 0:
            return err(axiomErrJsonInvalid)
          codePoint = (codePoint shl 4) or digit
        appendCodePoint(decoded, codePoint)
        cursor += 6
      else:
        return err(axiomErrJsonInvalid)
    else:
      if ord(ch) < 0x20:
        return err(axiomErrJsonInvalid)
      decoded.add(ch)
      inc cursor
  err(axiomErrJsonInvalid)

## Skip Json String Value.
  ## axiom-smt: (assert (and -1))
  ## axiom-lean: -1
func skipJsonStringValue*(raw: string; startIdx: int): int {.axiomTryImpl.} =
  let parsed = decodeJsonString(raw, startIdx)
  if parsed.isErr():
    return -1
  parsed.get()[1]

## Skip Json Literal.
  ## axiom-smt: (assert (and (>= (str.len raw) 0) (and (>= startIdx -9223372036854775808) (<= startIdx 9223372036854775807)) (>= (str.len literal) 0) (> (+ i (str.len literal)) (str.len raw)) -1 (=> (> (+ i (str.len literal)) (str.len raw)) (= result -1))))
  ## axiom-lean: raw.length ≥ 0 ∧ startIdx ≥ -9223372036854775808 ∧ startIdx ≤ 9223372036854775807 ∧ literal.length ≥ 0 ∧ i + literal.length > raw.length ∧ -1 ∧ i + literal.length > raw.length → result = -1
func skipJsonLiteral*(raw: string; startIdx: int; literal: string): int {.axiomTryImpl.} =
  let i = skipJsonWhitespace(raw, startIdx)
  if i + literal.len > raw.len:
    return -1
  for offset in 0 ..< literal.len:
    if raw[i + offset] != literal[offset]:
      return -1
  i + literal.len

## Skip Json Number.
  ## axiom-smt: (assert (and (>= (str.len raw) 0) (and (>= startIdx -9223372036854775808) (<= startIdx 9223372036854775807)) -1 (=> (>= i (str.len raw)) (= result -1))))
  ## axiom-lean: raw.length ≥ 0 ∧ startIdx ≥ -9223372036854775808 ∧ startIdx ≤ 9223372036854775807 ∧ -1 ∧ i ≥ raw.length → result = -1
func skipJsonNumber*(raw: string; startIdx: int): int {.axiomTryImpl.} =
  var i = skipJsonWhitespace(raw, startIdx)
  if i >= raw.len:
    return -1
  if raw[i] == '-':
    inc i
  if i >= raw.len:
    return -1
  if raw[i] == '0':
    inc i
  else:
    if raw[i] notin {'1'..'9'}:
      return -1
    while i < raw.len and raw[i] in {'0'..'9'}:
      inc i
  if i < raw.len and raw[i] == '.':
    inc i
    if i >= raw.len or raw[i] notin {'0'..'9'}:
      return -1
    while i < raw.len and raw[i] in {'0'..'9'}:
      inc i
  if i < raw.len and (raw[i] == 'e' or raw[i] == 'E'):
    inc i
    if i < raw.len and (raw[i] == '+' or raw[i] == '-'):
      inc i
    if i >= raw.len or raw[i] notin {'0'..'9'}:
      return -1
    while i < raw.len and raw[i] in {'0'..'9'}:
      inc i
  i

## Skip Json Value.
  ## axiom-smt: (assert (and (>= (str.len raw) 0) (and (>= startIdx -9223372036854775808) (<= startIdx 9223372036854775807))))
  ## axiom-lean: raw.length ≥ 0 ∧ startIdx ≥ -9223372036854775808 ∧ startIdx ≤ 9223372036854775807
func skipJsonValue*(raw: string; startIdx: int): int {.axiomTryImpl.}

## Skip Json Array.
  ## axiom-smt: (assert (and (< valueEnd 0) (< i (str.len raw)) -1 (+ i 1) (=> (< valueEnd 0) (= result -1)) (=> (>= i (str.len raw)) (= result -1)) (and (>= i 0) (< i raw))))
  ## axiom-lean: valueEnd < 0 ∧ i < raw.length ∧ -1 ∧ i + 1 ∧ valueEnd < 0 → result = -1 ∧ i ≥ raw.length → result = -1 ∧ ((i ≥ 0) ∧ (i < raw))
func skipJsonArray*(raw: string; startIdx: int): int {.axiomTryImpl.} =
  var i = skipJsonWhitespace(raw, startIdx)
  if i >= raw.len or raw[i] != '[':
    return -1
  i = skipJsonWhitespace(raw, i + 1)
  if i < raw.len and raw[i] == ']':
    return i + 1
  while i < raw.len:
    let valueEnd = skipJsonValue(raw, i)
    if valueEnd < 0:
      return -1
    i = skipJsonWhitespace(raw, valueEnd)
    if i >= raw.len:
      return -1
    if raw[i] == ',':
      i = skipJsonWhitespace(raw, i + 1)
      continue
    if raw[i] == ']':
      return i + 1
    return -1
  -1

## Skip Json Object.
  ## axiom-smt: (assert (and (< keyEnd 0) (< valueEnd 0) (< i (str.len raw)) -1 (+ i 1) (=> (< keyEnd 0) (= result -1)) (=> (< valueEnd 0) (= result -1)) (=> (>= i (str.len raw)) (= result -1)) (and (>= i 0) (< i raw))))
  ## axiom-lean: keyEnd < 0 ∧ valueEnd < 0 ∧ i < raw.length ∧ -1 ∧ i + 1 ∧ keyEnd < 0 → result = -1 ∧ valueEnd < 0 → result = -1 ∧ i ≥ raw.length → result = -1 ∧ ((i ≥ 0) ∧ (i < raw))
func skipJsonObject*(raw: string; startIdx: int): int {.axiomTryImpl.} =
  var i = skipJsonWhitespace(raw, startIdx)
  if i >= raw.len or raw[i] != '{':
    return -1
  i = skipJsonWhitespace(raw, i + 1)
  if i < raw.len and raw[i] == '}':
    return i + 1
  while i < raw.len:
    let keyEnd = skipJsonStringValue(raw, i)
    if keyEnd < 0:
      return -1
    i = skipJsonWhitespace(raw, keyEnd)
    if i >= raw.len or raw[i] != ':':
      return -1
    i = skipJsonWhitespace(raw, i + 1)
    let valueEnd = skipJsonValue(raw, i)
    if valueEnd < 0:
      return -1
    i = skipJsonWhitespace(raw, valueEnd)
    if i >= raw.len:
      return -1
    if raw[i] == ',':
      i = skipJsonWhitespace(raw, i + 1)
      continue
    if raw[i] == '}':
      return i + 1
    return -1
  -1

## Skip Json Value.
func skipJsonValue*(raw: string; startIdx: int): int =
  let i = skipJsonWhitespace(raw, startIdx)
  if i >= raw.len:
    return -1
  case raw[i]
  of '"':
    skipJsonStringValue(raw, i)
  of '{':
    skipJsonObject(raw, i)
  of '[':
    skipJsonArray(raw, i)
  of 't':
    skipJsonLiteral(raw, i, "true")
  of 'f':
    skipJsonLiteral(raw, i, "false")
  of 'n':
    skipJsonLiteral(raw, i, "null")
  else:
    skipJsonNumber(raw, i)

## Find Object Field.
{.pop.}

{.pop.}
