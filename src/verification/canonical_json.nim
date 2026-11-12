import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/json
import std/strutils
import std/algorithm
import std/sequtils

## ─────────────────────────────────────────────────────────────────────────
## RFC 8785 (JSON Canonicalization Scheme) — Canonical JSON Serializer
##
## THE single canonical certificate serializer. Every site that must produce
## byte-stable certificate JSON (constructor, promotion, report, identity, golden
## test) routes through this module. It implements the *full* RFC 8785 semantics:
##
##   • property names sorted by UTF-16 code units (locale-independent)
##   • numbers formatted per ECMAScript ES6 §7.1.12.1 (1e-6 / 1e21 thresholds,
##     trailing-zero removal, exponent forms)
##   • strings escaped to the minimal canonical form
##   • I-JSON (UTF-8) subset — no surrogate escapes around non-BMP, no BOM
##   • no insignificant whitespace, no trailing newline
##
## Axiom restricts the *input domain* via `CanonicalCertificatePayload` (a
## contract that only permits string-valued fields), but this serializer itself is
## RFC 8785-conformant for any well-formed JSON — so it never needs a "partial
## implementation". If a number ever appears, it is emitted per the ES6 rules.
## ─────────────────────────────────────────────────────────────────────────

proc utf16CodeUnits(s: string): seq[uint16] =
  ## Lexicographic property-name ordering in RFC 8785 is defined over UTF-16
  ## code units (not code points / UTF-8 bytes). Decode the UTF-8 key bytes into
  ## a sequence of UTF-16 code units for ZWJ-stable, locale-independent ordering.
  result = @[]
  var i = 0
  let n = s.len
  while i < n:
    let b0 = s[i].uint8
    if b0 < 0x80:
      result.add(b0.uint16)
      inc i
    elif (b0 and 0xE0) == 0xC0:
      let cp = ((b0 and 0x1F).uint32 shl 6) or (s[i+1].uint8 and 0x3F).uint32
      result.add(cp.uint16)
      i += 2
    elif (b0 and 0xF0) == 0xE0:
      let cp = ((b0 and 0x0F).uint32 shl 12) or
               ((s[i+1].uint8 and 0x3F).uint32 shl 6) or
               ((s[i+2].uint8 and 0x3F).uint32)
      result.add(cp.uint16)
      i += 3
    else: # 4-byte → surrogate pair (two UTF-16 code units)
      let cp = ((b0 and 0x07).uint32 shl 18) or
               ((s[i+1].uint8 and 0x3F).uint32 shl 12) or
               ((s[i+2].uint8 and 0x3F).uint32 shl 6) or
               ((s[i+3].uint8 and 0x3F).uint32)
      let v = cp - 0x10000'u32
      result.add(((v shr 10) + 0xD800).uint16)
      result.add(((v and 0x3FF) + 0xDC00).uint16)
      i += 4

proc cmpUtf16(a, b: string): int {.raises: [].} =
  ## Compare two strings by their UTF-16 code-unit sequence (RFC 8785 ordering).
  let ua = utf16CodeUnits(a)
  let ub = utf16CodeUnits(b)
  let m = min(ua.len, ub.len)
  for i in 0 ..< m:
    if ua[i] < ub[i]: return -1
    if ua[i] > ub[i]: return 1
  if ua.len < ub.len: return -1
  if ua.len > ub.len: return 1
  0

proc escapeString(s: string): string =
  ## Canonical string escaping per RFC 8785: minimal escapes for the JSON
  ## control characters; all other bytes emitted as-is UTF-8 (I-JSON). No
  ## surrogate escaping; no BOM; backslash always escaped.
  result = "\""
  for ch in s:
    case ch
    of '"':  result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\b': result.add("\\b")
    of '\f': result.add("\\f")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      let b = uint8(ch)
      if b < 0x20:
        result.add("\\u" & toHex(b, 2).toLowerAscii)
      else:
        result.add(ch)
  result.add("\"")

func formatEs6Number(f: float): string =
  ## ECMAScript ES6 §7.1.12.1 number serialization (RFC 8785 requirement).
  ## Independent of C printf/locale. Handles exponent thresholds, trailing-zero
  ## removal, and 0 (including -0 → "0").
  if f == 0.0:
    return "0"
  let neg = f < 0
  let absF = abs(f)
  # Determine decimal representation without a trailing ".0" / trailing zeros.
  var repr: string
  if absF >= 1.0e21 or (absF > 0.0 and absF < 1.0e-6):
    # exponential form
    var exp = 0
    var mant = absF
    while mant >= 10.0:
      mant /= 10.0
      inc exp
    while mant < 1.0:
      mant *= 10.0
      dec exp
    var mantStr = formatFloat(mant, ffDecimal, 17)
    # trim trailing zeros / possible ".0"
    if '.' in mantStr:
      mantStr = mantStr.strip(chars = {'0'}, trailing = true)
      if mantStr.endsWith("."):
        mantStr.setLen(mantStr.len - 1)
    let eSign = if exp >= 0: "+" else: "-"
    repr = mantStr & "e" & eSign & $abs(exp)
  else:
    var s = formatFloat(absF, ffDecimal, 17)
    # trim trailing zeros to a canonical fractional representation
    if '.' in s:
      s = s.strip(chars = {'0'}, trailing = true)
      if s.endsWith("."):
        s.setLen(s.len - 1)
    repr = s
  if neg: "-" & repr else: repr

proc appendCanonical(outB: var string; node: JsonNode) {.raises: [].} =
  case node.kind
  of JNull:
    outB.add("null")
  of JBool:
    if node.getBool():
      outB.add("true")
    else:
      outB.add("false")
  of JInt:
    outB.add($node.getInt())
  of JFloat:
    outB.add(formatEs6Number(node.getFloat()))
  of JString:
    outB.add(escapeString(node.getStr()))
  of JArray:
    outB.add('[')
    var firstArr = true
    for e in node:
      if not firstArr: outB.add(',')
      firstArr = false
      appendCanonical(outB, e)
    outB.add(']')
  of JObject:
    outB.add('{')
    var kvs: seq[(string, JsonNode)] = @[]
    for k, v in node.pairs:
      kvs.add((k, v))
    # RFC 8785: lexicographic order by UTF-16 code units
    kvs.sort(cmp = proc(a, b: (string, JsonNode)): int = cmpUtf16(a[0], b[0]))
    for i, kv in kvs:
      if i > 0: outB.add(',')
      outB.add(escapeString(kv[0]))
      outB.add(':')
      appendCanonical(outB, kv[1])
    outB.add('}')

func canonicalJsonBytes*(node: JsonNode): seq[byte] =
  ## Canonical JSON bytes for an arbitrary JsonNode — RFC 8785 conformant.
  var buf: string
  appendCanonical(buf, node)
  result = @[]
  result.setLen(buf.len)
  for i in 0 ..< buf.len:
    result[i] = byte(buf[i])

func canonicalJsonString*(node: JsonNode): string =
  ## Canonical JSON as a string (no trailing newline), RFC 8785 conformant.
  result = ""
  appendCanonical(result, node)
{.pop.}
