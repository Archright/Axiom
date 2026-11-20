import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Strict JSON reader for evidence-bundle inputs.
##
## `std/json` accepts duplicate object keys (last value wins) and trailing
## garbage is rejected only after the fact. Both are unsound inputs for a
## verifier: a manifest with two `bundleDigest` keys, or a cert body with two
## `propositionHash` keys, has no single meaning. This module is a small
## recursive-descent reader that:
##
##   • rejects duplicate object keys at EVERY nesting level;
##   • rejects invalid UTF-8, BOMs, control bytes in strings, and bad escapes;
##   • rejects trailing non-whitespace bytes;
##   • bounds depth, node count, and string length.
##
## It returns the same `JsonNode` tree `std/json` would, so all downstream
## canonicalization stays on the RFC 8785 serializer.

import std/json
import std/sets
import std/strutils
import std/unicode
import core/results

const
  StrictJsonMaxDepth* = 64
  StrictJsonMaxNodes* = 2_000_000
  StrictJsonMaxStringBytes* = 16 * 1024 * 1024

type
  StrictParser = object
    text: string
    pos: int
    nodes: int
    err: string

func fail(p: var StrictParser; msg: string) {.raises: [].} =
  if p.err.len == 0:
    p.err = msg & " (offset " & $p.pos & ")"

func atEnd(p: StrictParser): bool {.inline.} =
  p.pos >= p.text.len

func peek(p: StrictParser): char {.inline.} =
  if p.pos < p.text.len: p.text[p.pos] else: '\0'

func skipWs(p: var StrictParser) {.raises: [].} =
  while p.pos < p.text.len:
    case p.text[p.pos]
    of ' ', '\t', '\n', '\r':
      inc p.pos
    else:
      break

func addUtf8(outBuf: var string; cp: int) {.raises: [].} =
  if cp <= 0x7F:
    outBuf.add(char(cp))
  elif cp <= 0x7FF:
    outBuf.add(char(0xC0 or (cp shr 6)))
    outBuf.add(char(0x80 or (cp and 0x3F)))
  elif cp <= 0xFFFF:
    outBuf.add(char(0xE0 or (cp shr 12)))
    outBuf.add(char(0x80 or ((cp shr 6) and 0x3F)))
    outBuf.add(char(0x80 or (cp and 0x3F)))
  else:
    outBuf.add(char(0xF0 or (cp shr 18)))
    outBuf.add(char(0x80 or ((cp shr 12) and 0x3F)))
    outBuf.add(char(0x80 or ((cp shr 6) and 0x3F)))
    outBuf.add(char(0x80 or (cp and 0x3F)))

func hexVal(c: char): int {.raises: [].} =
  case c
  of '0'..'9': ord(c) - ord('0')
  of 'a'..'f': ord(c) - ord('a') + 10
  of 'A'..'F': ord(c) - ord('A') + 10
  else: -1

func readHex4(p: var StrictParser): int {.raises: [].} =
  if p.pos + 4 > p.text.len:
    p.fail("truncated \\u escape")
    return -1
  result = 0
  for k in 0 ..< 4:
    let v = hexVal(p.text[p.pos + k])
    if v < 0:
      p.fail("invalid \\u escape")
      return -1
    result = result * 16 + v
  p.pos += 4

func parseString(p: var StrictParser): string {.raises: [].} =
  ## Caller has verified the current byte is '"'.
  inc p.pos
  var outBuf = ""
  while p.pos < p.text.len:
    let c = p.text[p.pos]
    if c == '"':
      inc p.pos
      return outBuf
    if c == '\\':
      inc p.pos
      if p.pos >= p.text.len:
        p.fail("truncated escape")
        return ""
      let esc = p.text[p.pos]
      inc p.pos
      case esc
      of '"': outBuf.add('"')
      of '\\': outBuf.add('\\')
      of '/': outBuf.add('/')
      of 'b': outBuf.add('\b')
      of 'f': outBuf.add('\f')
      of 'n': outBuf.add('\n')
      of 'r': outBuf.add('\r')
      of 't': outBuf.add('\t')
      of 'u':
        let first = readHex4(p)
        if first < 0:
          return ""
        if first in 0xD800 .. 0xDBFF:
          if p.pos + 2 > p.text.len or p.text[p.pos] != '\\' or p.text[p.pos + 1] != 'u':
            p.fail("unpaired high surrogate")
            return ""
          p.pos += 2
          let second = readHex4(p)
          if second < 0:
            return ""
          if second notin 0xDC00 .. 0xDFFF:
            p.fail("invalid low surrogate")
            return ""
          let cp = 0x10000 + ((first - 0xD800) shl 10) + (second - 0xDC00)
          outBuf.addUtf8(cp)
        elif first in 0xDC00 .. 0xDFFF:
          p.fail("unpaired low surrogate")
          return ""
        else:
          outBuf.addUtf8(first)
      else:
        p.fail("invalid escape")
        return ""
    else:
      let b = uint8(c)
      if b < 0x20:
        p.fail("unescaped control character in string")
        return ""
      outBuf.add(c)
      inc p.pos
    if outBuf.len > StrictJsonMaxStringBytes:
      p.fail("string exceeds the size limit")
      return ""
  p.fail("unterminated string")
  ""

func parseNumber(p: var StrictParser): JsonNode {.raises: [].} =
  let start = p.pos
  if peek(p) == '-': inc p.pos
  if p.atEnd or p.peek() notin {'0'..'9'}:
    p.fail("invalid number")
    return nil
  if p.peek() == '0':
    inc p.pos
  else:
    while not p.atEnd and p.peek() in {'0'..'9'}: inc p.pos
  var isFloat = false
  if not p.atEnd and p.peek() == '.':
    isFloat = true
    inc p.pos
    if p.atEnd or p.peek() notin {'0'..'9'}:
      p.fail("invalid fraction")
      return nil
    while not p.atEnd and p.peek() in {'0'..'9'}: inc p.pos
  if not p.atEnd and p.peek() in {'e', 'E'}:
    isFloat = true
    inc p.pos
    if not p.atEnd and p.peek() in {'+', '-'}: inc p.pos
    if p.atEnd or p.peek() notin {'0'..'9'}:
      p.fail("invalid exponent")
      return nil
    while not p.atEnd and p.peek() in {'0'..'9'}: inc p.pos
  let token = p.text[start ..< p.pos]
  if isFloat:
    try:
      return %parseFloat(token)
    except CatchableError:
      p.fail("number out of range")
      return nil
  else:
    try:
      return %parseBiggestInt(token)
    except CatchableError:
      p.fail("integer out of range")
      return nil

func parseValue(p: var StrictParser; depth: int): JsonNode {.raises: [].}

func parseObject(p: var StrictParser; depth: int): JsonNode {.raises: [].} =
  inc p.pos  # '{'
  result = newJObject()
  var seen = initHashSet[string]()
  p.skipWs()
  if not p.atEnd and p.peek() == '}':
    inc p.pos
    return
  while true:
    p.skipWs()
    if p.atEnd or p.peek() != '"':
      p.fail("object key must be a string")
      return nil
    let key = p.parseString()
    if p.err.len > 0: return nil
    if seen.contains(key):
      p.fail("duplicate object key: " & key)
      return nil
    seen.incl(key)
    p.skipWs()
    if p.atEnd or p.peek() != ':':
      p.fail("expected ':' after object key")
      return nil
    inc p.pos
    p.skipWs()
    let value = p.parseValue(depth + 1)
    if p.err.len > 0: return nil
    result[key] = value
    p.skipWs()
    if p.atEnd:
      p.fail("unterminated object")
      return nil
    case p.peek()
    of ',':
      inc p.pos
    of '}':
      inc p.pos
      return
    else:
      p.fail("expected ',' or '}'")
      return nil

func parseArray(p: var StrictParser; depth: int): JsonNode {.raises: [].} =
  inc p.pos  # '['
  result = newJArray()
  p.skipWs()
  if not p.atEnd and p.peek() == ']':
    inc p.pos
    return
  while true:
    p.skipWs()
    let value = p.parseValue(depth + 1)
    if p.err.len > 0: return nil
    result.add(value)
    p.skipWs()
    if p.atEnd:
      p.fail("unterminated array")
      return nil
    case p.peek()
    of ',':
      inc p.pos
    of ']':
      inc p.pos
      return
    else:
      p.fail("expected ',' or ']'")
      return nil

func parseValue(p: var StrictParser; depth: int): JsonNode {.raises: [].} =
  if depth > StrictJsonMaxDepth:
    p.fail("nesting depth exceeds the limit")
    return nil
  inc p.nodes
  if p.nodes > StrictJsonMaxNodes:
    p.fail("node count exceeds the limit")
    return nil
  p.skipWs()
  if p.atEnd:
    p.fail("unexpected end of input")
    return nil
  case p.peek()
  of '{':
    result = p.parseObject(depth)
  of '[':
    result = p.parseArray(depth)
  of '"':
    result = %p.parseString()
    if p.err.len > 0: return nil
  of 't':
    if p.pos + 4 <= p.text.len and p.text[p.pos ..< p.pos + 4] == "true":
      p.pos += 4
      result = %true
    else:
      p.fail("invalid literal")
      return nil
  of 'f':
    if p.pos + 5 <= p.text.len and p.text[p.pos ..< p.pos + 5] == "false":
      p.pos += 5
      result = %false
    else:
      p.fail("invalid literal")
      return nil
  of 'n':
    if p.pos + 4 <= p.text.len and p.text[p.pos ..< p.pos + 4] == "null":
      p.pos += 4
      result = newJNull()
    else:
      p.fail("invalid literal")
      return nil
  else:
    result = p.parseNumber()

func parseStrictJson*(text: string;
                      maxDepth = StrictJsonMaxDepth;
                      maxNodes = StrictJsonMaxNodes): Result[JsonNode, string] {.raises: [].} =
  ## Parse `text` as strict JSON. Every violation — duplicate key, unknown
  ## escape, trailing garbage, invalid UTF-8, oversized input — is an err.
  if text.len == 0:
    return err("empty JSON document")
  if text.len >= 3 and text[0] == '\xEF' and text[1] == '\xBB' and text[2] == '\xBF':
    return err("UTF-8 BOM is not permitted")
  if validateUtf8(text) != -1:
    return err("input is not valid UTF-8")
  var p = StrictParser(text: text, pos: 0, nodes: 0, err: "")
  p.skipWs()
  if p.atEnd:
    return err("JSON document contains no value")
  let root = p.parseValue(0)
  if p.err.len > 0:
    return err(p.err)
  p.skipWs()
  if not p.atEnd:
    return err("trailing bytes after the JSON value (offset " & $p.pos & ")")
  if root.isNil:
    return err("JSON document contains no value")
  ok(root)

{.pop.}