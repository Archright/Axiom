# NIMTRY TEST FIXTURE — intentionally violates SOLID/SRP (Single Responsibility Principle)
#
# This module exports 22+ functions that do completely unrelated things with
# no shared variable references. Each function uses explicit `return` instead
# of `result` to avoid the shared `result` variable inflating cohesion metrics.
#
# This yields LCOM ≈ 1.0 (very low cohesion) and TCC ≈ 0.0 (no tight class
# cohesion), both exceeding policy thresholds (lcomThreshold=0.6, tccThreshold=0.3),
# triggering the `solid-srp` cohesion check via checkCohesionV2.

import std/math

proc validateEmail*(email: string): bool =
  var atPos = 0
  var dotPos = 0
  for i, ch in email:
    if ch == '@': atPos = i
    if ch == '.': dotPos = i
  return atPos > 0 and dotPos > atPos + 1

proc computeFibonacci*(n: int): int =
  var a = 0
  var b = 1
  var cnt = 0
  while cnt < n:
    let next = a + b
    a = b
    b = next
    inc cnt
  return a

proc formatTimestamp*(year: int; month: int; day: int): string =
  var yStr = $year
  var mStr = $month
  var dStr = $day
  if mStr.len < 2: mStr = "0" & mStr
  if dStr.len < 2: dStr = "0" & dStr
  return yStr & "-" & mStr & "-" & dStr

proc parseCsvLine*(line: string): seq[string] =
  var items: seq[string] = @[]
  var cur = ""
  var inQuotes = false
  for ch in line:
    if ch == '"': inQuotes = not inQuotes
    elif ch == ',' and not inQuotes:
      items.add(cur)
      cur = ""
    else: cur.add(ch)
  if cur.len > 0: items.add(cur)
  return items

proc computeChecksum*(input: string): int =
  var h = 0
  for ch in input:
    h = h xor ord(ch)
    h = h * 31 + 7
  return h

proc encodeBase64*(data: seq[byte]): string =
  const table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  var outStr = ""
  var idx = 0
  while idx < data.len:
    let b0 = data[idx].int
    let b1 = if idx + 1 < data.len: data[idx + 1].int else: 0
    let b2 = if idx + 2 < data.len: data[idx + 2].int else: 0
    let triple = (b0 shl 16) or (b1 shl 8) or b2
    outStr.add(table[(triple shr 18) and 63])
    outStr.add(table[(triple shr 12) and 63])
    outStr.add(table[(triple shr 6) and 63])
    outStr.add(table[triple and 63])
    idx += 3
  return outStr

proc sortNumbers*(arr: var seq[int]) =
  var n = arr.len
  var swapped = true
  while swapped:
    swapped = false
    var i = 0
    while i < n - 1:
      if arr[i] > arr[i + 1]:
        let tmp = arr[i]
        arr[i] = arr[i + 1]
        arr[i + 1] = tmp
        swapped = true
      inc i
    dec n

proc tokenizeXml*(xml: string): seq[string] =
  var tokens: seq[string] = @[]
  var buf = ""
  var inTag = false
  var pos = 0
  while pos < xml.len:
    let ch = xml[pos]
    if ch == '<':
      if buf.len > 0: tokens.add(buf)
      buf = "<"
      inTag = true
    elif ch == '>':
      buf.add(">")
      tokens.add(buf)
      buf = ""
      inTag = false
    else:
      buf.add(ch)
    inc pos
  if buf.len > 0: tokens.add(buf)
  return tokens

proc renderProgressBar*(cur: int; total: int; w: int): string =
  let ratio = cur.float / total.float
  let filled = (ratio * w.float).int
  var bar = "["
  var j = 0
  while j < w:
    if j < filled: bar.add("#")
    else: bar.add(" ")
    inc j
  bar.add("] " & $cur & "/" & $total)
  return bar

proc detectAnomalies*(values: seq[float]; threshold: float): seq[int] =
  var outliers: seq[int] = @[]
  if values.len < 3: return outliers
  var mean = 0.0
  for v in values: mean += v
  mean = mean / values.len.float
  var variance = 0.0
  for v in values: variance += (v - mean) * (v - mean)
  variance = variance / values.len.float
  let stdDev = sqrt(variance)
  var k = 0
  while k < values.len:
    if abs(values[k] - mean) > threshold * stdDev:
      outliers.add(k)
    inc k
  return outliers

proc interpolateColor*(t: float): tuple[r, g, b: int] =
  let clamped = max(0.0, min(1.0, t))
  let red = (clamped * 255.0).int
  let green = ((1.0 - clamped) * 255.0).int
  let blue = ((abs(clamped - 0.5) * 2.0) * 255.0).int
  return (red, green, blue)

proc compressRunLength*(data: string): string =
  var compressed = ""
  var scan = 0
  while scan < data.len:
    let ch = data[scan]
    var runLen = 1
    while scan + runLen < data.len and data[scan + runLen] == ch:
      inc runLen
    compressed.add(ch)
    compressed.add($runLen)
    scan += runLen
  return compressed

proc evaluatePolynomial*(coeffs: seq[float]; x: float): float =
  var sum = 0.0
  var power = 1.0
  for c in coeffs:
    sum += c * power
    power *= x
  return sum

proc generateUuidV4*(): string =
  var uuid = ""
  var p = 0
  while p < 36:
    if p == 8 or p == 13 or p == 18 or p == 23:
      uuid.add("-")
    elif p == 14:
      uuid.add("4")
    elif p == 19:
      let hexChars = "89ab"
      let ix = (p * 7 + 3) mod 4
      uuid.add(hexChars[ix])
    else:
      let hexChars = "0123456789abcdef"
      let ix = (p * 13 + 7) mod 16
      uuid.add(hexChars[ix])
    inc p
  return uuid

proc jaroWinkler*(s: string; t: string): float =
  let sLen = s.len
  let tLen = t.len
  if sLen == 0 and tLen == 0: return 1.0
  if sLen == 0 or tLen == 0: return 0.0
  let matchDist = max(sLen, tLen) div 2 - 1
  var sMatches: seq[bool] = @[]
  var tMatches: seq[bool] = @[]
  sMatches.setLen(sLen)
  tMatches.setLen(tLen)
  var matches = 0
  var transpositions = 0
  var i = 0
  while i < sLen:
    let start = max(0, i - matchDist)
    let endV = min(tLen - 1, i + matchDist)
    var j = start
    while j <= endV:
      if not tMatches[j] and s[i] == t[j]:
        sMatches[i] = true
        tMatches[j] = true
        inc matches
        break
      inc j
    inc i
  if matches == 0: return 0.0
  var k = 0
  var ii = 0
  while ii < sLen:
    if sMatches[ii]:
      while not tMatches[k]: inc k
      if s[ii] != t[k]: inc transpositions
      inc k
    inc ii
  let m = matches.float
  let jaro = (m / sLen.float + m / tLen.float + (m - transpositions.float / 2.0) / m) / 3.0
  return jaro

proc levenshteinDistance*(a: string; b: string): int =
  let rows = a.len
  let cols = b.len
  var dp: seq[seq[int]] = @[]
  dp.setLen(rows + 1)
  var row = 0
  while row <= rows:
    dp[row].setLen(cols + 1)
    dp[row][0] = row
    inc row
  var col = 0
  while col <= cols:
    dp[0][col] = col
    inc col
  var r = 1
  while r <= rows:
    var c = 1
    while c <= cols:
      let cost = if a[r - 1] == b[c - 1]: 0 else: 1
      dp[r][c] = min(min(dp[r - 1][c] + 1, dp[r][c - 1] + 1), dp[r - 1][c - 1] + cost)
      inc c
    inc r
  return dp[rows][cols]

proc countSyllables*(word: string): int =
  var sylCount = 0
  var prevVowel = false
  for ch in word:
    let isVowel = ch in {'a', 'e', 'i', 'o', 'u', 'A', 'E', 'I', 'O', 'U'}
    if isVowel and not prevVowel: inc sylCount
    prevVowel = isVowel
  if sylCount == 0: sylCount = 1
  return sylCount

proc fizzbuzz*(n: int): seq[string] =
  var output: seq[string] = @[]
  output.setLen(n)
  var x = 1
  while x <= n:
    if x mod 15 == 0: output[x - 1] = "FizzBuzz"
    elif x mod 3 == 0: output[x - 1] = "Fizz"
    elif x mod 5 == 0: output[x - 1] = "Buzz"
    else: output[x - 1] = $x
    inc x
  return output

proc caesarCipher*(text: string; shift: int): string =
  var ciphered = ""
  for ch in text:
    if ch >= 'a' and ch <= 'z':
      let shifted = ((ord(ch) - ord('a') + shift) mod 26 + 26) mod 26
      ciphered.add(chr(shifted + ord('a')))
    elif ch >= 'A' and ch <= 'Z':
      let shifted = ((ord(ch) - ord('A') + shift) mod 26 + 26) mod 26
      ciphered.add(chr(shifted + ord('A')))
    else: ciphered.add(ch)
  return ciphered

proc parseJsonValue*(json: string): string =
  var depth = 0
  var inStr = false
  var buf = ""
  for ch in json:
    if ch == '"': inStr = not inStr
    elif ch in {'{', '['}: inc depth
    elif ch in {'}', ']'}: dec depth
    if depth == 0 and ch == ',' and not inStr: buf.add("\n")
    else: buf.add(ch)
  return buf

proc estimatePi*(iterations: int): float =
  var inside = 0
  var idx = 0
  while idx < iterations:
    let xi = (idx.float * 7.0 + 3.0) / iterations.float
    let yi = (idx.float * 11.0 + 5.0) / iterations.float
    if xi * xi + yi * yi <= 1.0: inc inside
    inc idx
  return 4.0 * inside.float / iterations.float

proc translateText*(text: string; lang: string): string =
  var translated = ""
  var pos = 0
  while pos < text.len:
    let ch = text[pos]
    if lang == "leetspeak":
      case ch
      of 'e': translated.add("3")
      of 'l': translated.add("1")
      of 'o': translated.add("0")
      of 'a': translated.add("4")
      of 's': translated.add("5")
      of 't': translated.add("7")
      else: translated.add(ch)
    else:
      translated.add(ch)
    inc pos
  return translated

proc spellCheck*(word: string; dictionary: seq[string]): string =
  var bestWord = word
  var bestDist = 1000
  var ix = 0
  while ix < dictionary.len:
    let d = levenshteinDistance(word, dictionary[ix])
    if d < bestDist:
      bestDist = d
      bestWord = dictionary[ix]
    inc ix
  return bestWord
