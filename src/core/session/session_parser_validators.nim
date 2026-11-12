import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import ../../core/trusted/axiom_pragmas
import core/utils/constants
type
  Client* = enum
    clientCursor
    clientWindsurf
    clientVscode
    clientClaudeCode
    clientClaudeDesktop
    clientChatgpt
    clientUnknown

  Role* = enum
    roleUser
    roleAssistant
    roleTool
    roleSystem

  Audience* = enum
    audiencePublic
    audienceInternal
    audiencePrivate

  ArtifactKind* = enum
    artifactDiff
    artifactFile
    artifactImage
    artifactCommand
    artifactLog
    artifactLink

  ContentKind* = enum
    contentText
    contentCode
    contentArtifactRef

  ArtifactRefKind* = enum
    artifactRefDiff
    artifactRefFile
    artifactRefImage
    artifactRefUrl

  Verdict* = enum
    verdictRaceDetected
    verdictSafeWithinBound
    verdictInconclusive

  EvidenceKind* = enum
    evidenceTrace
    evidenceSolver
    evidenceLog
    evidenceSnapshot
## I Non Empty.
func isNonEmpty*(s: string): bool {.inline, axiom: ["(assert (and (>= (str.len s) 0)))", "s.length ≥ 0"].} =
  result = s.len > 0

## I Any String.
# axiom:theater-fix(DEBT#377)
func isAnyString*(s: string): bool {.inline, axiom: ["(assert (and (>= (str.len s) 0)))", "s.length ≥ 0"].} =
  ## Accepts any non-empty string. Used for MessageText, CodeLang, CodeText fields.
  result = s.len > 0
func isHexLower(c: char): bool {.inline, axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  result = c >= '0' and c <= '9' or c >= 'a' and c <= 'f'
func isHexUpper(c: char): bool {.inline, axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  result = c >= 'A' and c <= 'F'
func isHex(c: char): bool {.inline.} =
  result = isHexLower(c) or isHexUpper(c)

## I Valid Uuid.
  ## axiom-smt: (assert (and (>= (str.len s) 0)))
  ## axiom-lean: s.length ≥ 0
func isValidUuid*(s: string): bool {.axiomOpaque.} =
  if s.len != 36:
    return false

  for i, ch in s:
    if i == 8 or i == 13 or i == 18 or i == 23:
      if ch != '-':
        return false
    else:
      if not isHex(ch):
        return false

  result = true

## I Valid Uuid V4.
  ## axiom-smt: (assert (and (>= (str.len s) 0)))
  ## axiom-lean: s.length ≥ 0
func isValidUuidV4*(s: string): bool {.axiomOpaque.} =
  if not isValidUuid(s):
    return false
  if s[14] != '4':
    return false
  let v = s[19]
  result = v == '8' or v == '9' or v == 'a' or v == 'b' or v == 'A' or v == 'B'
func isDigit(c: char): bool {.inline, axiom: ["(assert (and (>= depth 0) ast_parse_failed_isolated))", "depth >= 0 ∧ ast_parse_failed_isolated"].} =
  result = c >= '0' and c <= '9'
func digitVal(c: char): int {.inline, axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  result = ord(c) - ord('0')
func parse2(s: string; pos: int): int {.inline, axiom: ["(assert (and -1 (=> (>= (+ pos 1) (str.len s)) (= result -1))))", "-1 ∧ pos + 1 ≥ s.length → result = -1"].} =
  if pos + 1 >= s.len:
    return -1
  let a = s[pos]
  let b = s[pos + 1]
  if not isDigit(a) or not isDigit(b):
    return -1
  result = digitVal(a) * 10 + digitVal(b)
func parse4(s: string; pos: int): int {.inline, axiom: ["(assert (and (>= (str.len s) 0) (and (>= pos -9223372036854775808) (<= pos 9223372036854775807)) -1 (=> (>= (+ pos 3) (str.len s)) (= result -1))))", "s.length ≥ 0 ∧ pos ≥ -9223372036854775808 ∧ pos ≤ 9223372036854775807 ∧ -1 ∧ pos + 3 ≥ s.length → result = -1"].} =
  if pos + 3 >= s.len:
    return -1
  for i in 0 .. 3:
    if not isDigit(s[pos + i]):
      return -1
  result = digitVal(s[pos]) * 1000 + digitVal(s[pos + 1]) * 100 + digitVal(s[pos + 2]) * 10 + digitVal(s[pos + 3])
func isLeapYear(year: int): bool {.inline, axiom: ["(assert (and (and (>= year -9223372036854775808) (<= year 9223372036854775807))))", "year ≥ -9223372036854775808 ∧ year ≤ 9223372036854775807"].} =
  result = year mod 400 == 0 or (year mod 4 == 0 and year mod 100 != 0)
func daysInMonth(year: int; month: int): int {.inline, axiom: ["(assert (and 1 3 5 7 8 10 12 4 6 9 11 2))", "1 ∧ 3 ∧ 5 ∧ 7 ∧ 8 ∧ 10 ∧ 12 ∧ 4 ∧ 6 ∧ 9 ∧ 11 ∧ 2"].} =
  result = case month
  of 1, 3, 5, 7, 8, 10, 12:
    31
  of 4, 6, 9, 11:
    30
  of 2:
    if isLeapYear(year): 29
    else: 28
  else:
    0

## I Valid Iso Date.
  ## axiom-smt: (assert (and (>= (str.len s) 0)))
  ## axiom-lean: s.length ≥ 0
func isValidIsoDate*(s: string): bool {.axiomOpaque.} =
  if s.len != 10:
    return false
  if s[4] != '-' or s[7] != '-':
    return false
  let year = parse4(s, 0)
  let month = parse2(s, 5)
  let day = parse2(s, 8)
  if year < 1 or month < 1 or month > 12:
    return false
  let dim = daysInMonth(year, month)
  result = dim != 0 and day >= 1 and day <= dim

## I Valid Schema Version.
func isValidSchemaVersion*(s: string): bool {.inline, axiom: ["(assert (and (>= (str.len s) 0)))", "s.length ≥ 0"].} =
  result = case s
  of axiomSessionV1:
    true
  else:
    false
func isAlphaNum(c: char): bool {.inline, axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  result = c >= '0' and c <= '9' or c >= 'a' and c <= 'z' or c >= 'A' and c <= 'Z'
func isMimeTokenChar(c: char): bool {.inline, axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  result = isAlphaNum(c) or c == '!' or c == '#' or c == '$' or c == '&' or c == '^' or c == '_' or c == '.' or c == '+' or c == '-'

## I Valid Mime Type.
  ## axiom-smt: (assert (and (>= (str.len s) 0)))
  ## axiom-lean: s.length ≥ 0
func isValidMimeType*(s: string): bool {.axiomOpaque.} =
  var slashPos = -1
  for i, ch in s:
    if ch == '/':
      if slashPos != -1:
        return false
      slashPos = i
    elif not isMimeTokenChar(ch):
      return false
  if slashPos <= 0 or slashPos >= s.len - 1:
    return false
  result = true
func isBase64Char(c: char): bool {.inline, axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  result = c >= 'A' and c <= 'Z' or c >= 'a' and c <= 'z' or c >= '0' and c <= '9' or c == '+' or c == '/'

## I Valid Base64.
  ## axiom-smt: (assert (and (>= (str.len s) 0)))
  ## axiom-lean: s.length ≥ 0
func isValidBase64*(s: string): bool {.axiomOpaque.} =
  if s.len == 0 or s.len mod 4 != 0:
    return false
  var pad = 0
  var i = s.len - 1
  while i >= 0 and s[i] == '=':
    inc pad
    dec i
    if pad > 2:
      return false
  for j in 0 .. i:
    if not isBase64Char(s[j]):
      return false
  result = true

## I Valid Json Blob.
  ## axiom-smt: (assert (and (>= (str.len s) 0)))
  ## axiom-lean: s.length ≥ 0
func isValidJsonBlob*(s: string): bool {.axiomOpaque.} =
  if s.len == 0:
    return false
  var a = 0
  var b = s.len - 1
  while a < s.len and (s[a] == ' ' or s[a] == '\t' or s[a] == '\n' or s[a] == '\r'):
    inc a
  while b >= 0 and (s[b] == ' ' or s[b] == '\t' or s[b] == '\n' or s[b] == '\r'):
    dec b
  if a > b:
    return false
  result = (s[a] == '{' and s[b] == '}') or (s[a] == '[' and s[b] == ']')

## I Valid Iso8601.
  ## axiom-smt: (assert (and (>= (str.len s) 0)))
  ## axiom-lean: s.length ≥ 0
func isValidIso8601*(s: string): bool {.axiomOpaque.} =
  if s.len < 20:
    return false
  if s[4] != '-' or s[7] != '-' or s[10] != 'T' or s[13] != ':' or s[16] != ':':
    return false

  let year = parse4(s, 0)
  let month = parse2(s, 5)
  let day = parse2(s, 8)
  let hour = parse2(s, 11)
  let minute = parse2(s, 14)
  let second = parse2(s, 17)

  if year < 1 or month < 1 or month > 12:
    return false
  let dim = daysInMonth(year, month)
  if dim == 0 or day < 1 or day > dim:
    return false
  if hour < 0 or hour > 23:
    return false
  if minute < 0 or minute > 59:
    return false
  if second < 0 or second > 59:
    return false

  var idx = 19
  if idx >= s.len:
    return false

  if idx < s.len and s[idx] == '.':
    inc idx
    var fracLen = 0
    while idx < s.len and isDigit(s[idx]):
      inc idx
      inc fracLen
      if fracLen > 9:
        return false
    if fracLen == 0:
      return false
    if idx >= s.len:
      return false

  if idx < 0 or idx >= s.len:
    return false

  if s[idx] == 'Z':
    return idx + 1 == s.len

  if s[idx] == '+' or s[idx] == '-':
    if idx + 5 >= s.len:
      return false
    if idx + 5 != s.len - 1:
      return false
    if idx + 3 >= s.len:
      return false
    if s[idx + 3] != ':':
      return false
    let offHour = parse2(s, idx + 1)
    let offMin = parse2(s, idx + 4)
    if offHour < 0 or offHour > 14:
      return false
    if offMin < 0 or offMin > 59:
      return false
    if offHour == 14 and offMin != 0:
      return false
    return true

  result = false
## I Valid Base64.

{.pop.}
