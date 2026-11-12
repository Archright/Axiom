import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/strutils
import std/unicode
## Skip Json Whitespace.
## Skips JSON whitespace characters (space, tab, newline, carriage return)
## starting from the given index and returns the index of the first non-whitespace character.
func skipJsonWhitespace*(raw: string; start: int): int {.raises: [].} =
  result = start
  while result < raw.len and raw[result] in {' ', '\t', '\n', '\r'}:
    inc(result)

## Decode Json String.
## Decodes a JSON string starting at the given index.
## Returns the decoded string and the index after the closing quote.
func decodeJsonString*(raw: string; start: int): (string, int) {.raises: [].} =
  var i = start
  if i >= raw.len or raw[i] != '"':
    return ("", i)
  inc(i)  # skip opening quote
  var decoded = ""
  while i < raw.len and raw[i] != '"':
    if raw[i] == '\\' and i + 1 < raw.len:
      case raw[i + 1]
      of '"': decoded.add('"'); inc(i, 2)
      of '\\': decoded.add('\\'); inc(i, 2)
      of '/': decoded.add('/'); inc(i, 2)
      of 'b': decoded.add('\b'); inc(i, 2)
      of 'f': decoded.add('\f'); inc(i, 2)
      of 'n': decoded.add('\n'); inc(i, 2)
      of 'r': decoded.add('\r'); inc(i, 2)
      of 't': decoded.add('\t'); inc(i, 2)
      of 'u':
        # axiom:theater-fix Unicode escape \uXXXX with surrogate pair support
        if i + 5 >= raw.len:
          decoded.add('\\'); inc(i)
        else:
          try:
            let code = parseHexInt(raw[i+2..i+5])
            inc(i, 6)
            # Handle surrogate pairs for code points > 0xFFFF
            if code >= 0xD800 and code <= 0xDBFF and i + 5 < raw.len and raw[i] == '\\' and raw[i+1] == 'u':
              try:
                let low = parseHexInt(raw[i+2..i+5])
                if low >= 0xDC00 and low <= 0xDFFF:
                  inc(i, 6)
                  let cp = 0x10000 + (code - 0xD800) shl 10 + (low - 0xDC00)
                  if cp <= 0x10FFFF:
                    if cp < 0x80:
                      decoded.add(chr(cp))
                    elif cp < 0x800:
                      decoded.add(chr(0xC0 or (cp shr 6)))
                      decoded.add(chr(0x80 or (cp and 0x3F)))
                    elif cp < 0x10000:
                      decoded.add(chr(0xE0 or (cp shr 12)))
                      decoded.add(chr(0x80 or ((cp shr 6) and 0x3F)))
                      decoded.add(chr(0x80 or (cp and 0x3F)))
                    else:
                      decoded.add(chr(0xF0 or (cp shr 18)))
                      decoded.add(chr(0x80 or ((cp shr 12) and 0x3F)))
                      decoded.add(chr(0x80 or ((cp shr 6) and 0x3F)))
                      decoded.add(chr(0x80 or (cp and 0x3F)))
                  else:
                    decoded.add('\\')
                else:
                  decoded.add('\\')
              except ValueError:
                decoded.add('\\')
            elif code >= 0xD800 and code <= 0xDFFF:
              # Lone surrogate — high without low companion, or low only
              decoded.add('\\')
            else:
              if code <= 0x10FFFF:
                decoded.add(Rune(code).toUTF8())
              else:
                decoded.add('\\')
          except ValueError:
            decoded.add('\\')
            inc(i)
      else:
        decoded.add(raw[i + 1]); inc(i, 2)
    else:
      decoded.add(raw[i]); inc(i)
  if i < raw.len and raw[i] == '"':
    inc(i)  # skip closing quote
  (decoded, i)

## Skip Json Value.
## Skips a complete JSON value (string, number, object, array, true, false, null)
## starting from the given index and returns the index after the value.
## Returns -1 if the value is malformed.
func skipJsonValue*(raw: string; start: int): int {.raises: [].} =
  var i = skipJsonWhitespace(raw, start)
  if i >= raw.len:
    return -1
  case raw[i]
  of '"':
    # String
    inc(i)
    while i < raw.len:
      if raw[i] == '"':
        inc(i)
        return i
      elif raw[i] == '\\' and i + 1 < raw.len:
        inc(i, 2)
      else:
        inc(i)
    return -1
  of '{':
    # Object
    inc(i)
    while i < raw.len:
      i = skipJsonWhitespace(raw, i)
      if i >= raw.len:
        return -1
      if raw[i] == '}':
        inc(i)
        return i
      # Skip key
      if raw[i] != '"':
        return -1
      let keyEnd = decodeJsonString(raw, i)[1]
      if keyEnd < 0:
        return -1
      i = skipJsonWhitespace(raw, keyEnd)
      if i >= raw.len or raw[i] != ':':
        return -1
      inc(i)
      # Skip value
      let valueEnd = skipJsonValue(raw, i)
      if valueEnd < 0:
        return -1
      i = skipJsonWhitespace(raw, valueEnd)
      if i < raw.len and raw[i] == ',':
        inc(i)
        continue
      elif i < raw.len and raw[i] == '}':
        inc(i)
        return i
      else:
        return -1
    return -1
  of '[':
    # Array
    inc(i)
    while i < raw.len:
      i = skipJsonWhitespace(raw, i)
      if i >= raw.len:
        return -1
      if raw[i] == ']':
        inc(i)
        return i
      let valueEnd = skipJsonValue(raw, i)
      if valueEnd < 0:
        return -1
      i = skipJsonWhitespace(raw, valueEnd)
      if i < raw.len and raw[i] == ',':
        inc(i)
        continue
      elif i < raw.len and raw[i] == ']':
        inc(i)
        return i
      else:
        return -1
    return -1
  of 't':
    # true
    if i + 4 <= raw.len and raw[i..<i+4] == "true":
      return i + 4
    return -1
  of 'f':
    # false
    if i + 5 <= raw.len and raw[i..<i+5] == "false":
      return i + 5
    return -1
  of 'n':
    # null
    if i + 4 <= raw.len and raw[i..<i+4] == "null":
      return i + 4
    return -1
  of '-', '0'..'9':
    # Number
    if raw[i] == '-':
      inc(i)
    while i < raw.len and raw[i] in {'0'..'9'}:
      inc(i)
    if i < raw.len and raw[i] == '.':
      inc(i)
      while i < raw.len and raw[i] in {'0'..'9'}:
        inc(i)
    if i < raw.len and raw[i] in {'e', 'E'}:
      inc(i)
      if i < raw.len and raw[i] in {'+', '-'}:
        inc(i)
      while i < raw.len and raw[i] in {'0'..'9'}:
        inc(i)
    return i
  else:
    return -1

## Skip Json Literal.
## Skips a JSON literal (true, false, null) starting at the given index.
## If `expected` is provided, only matches that specific literal.
## Returns the index after the literal, or -1 if not a valid literal.
func skipJsonLiteral*(raw: string; start: int; expected: string = ""): int {.raises: [].} =
  if expected.len > 0:
    let expectedLen = expected.len
    if start + expectedLen <= raw.len and raw[start..<start+expectedLen] == expected:
      return start + expectedLen
    return -1
  # No expected value - try all literals
  if start + 4 <= raw.len and raw[start..<start+4] == "true":
    return start + 4
  if start + 5 <= raw.len and raw[start..<start+5] == "false":
    return start + 5
  if start + 4 <= raw.len and raw[start..<start+4] == "null":
    return start + 4
  return -1

{.pop.}
