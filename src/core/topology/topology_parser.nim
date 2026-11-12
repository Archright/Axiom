import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/strutils
import core/topology/topology_types
export topology_types
import core/utils/text_utils
import ../../core/trusted/axiom_pragmas

# Auto-split from topology_engine.nim — parser functions
func countIndent*(raw: string): int =
  var cursor = 0
  while cursor < raw.len and raw[cursor] in {' ', '\t'}:
    inc cursor
  result = cursor

  ## axiom-smt: (assert (and (and (>= startLine -9223372036854775808) (<= startLine 9223372036854775807)) (and (>= endLine -9223372036854775808) (<= endLine 9223372036854775807)) (< endLine startLine) 1 (=> (< endLine startLine) (= result 1))))
  ## axiom-lean: startLine ≥ -9223372036854775808 ∧ startLine ≤ 9223372036854775807 ∧ endLine ≥ -9223372036854775808 ∧ endLine ≤ 9223372036854775807 ∧ endLine < startLine ∧ 1 ∧ endLine < startLine → result = 1
func normalizeLineSpan*(startLine: int; endLine: int): int {.axiomTryImpl.} =
  if endLine < startLine:
    return 1
  result = endLine - startLine + 1

  ## axiom-smt: (assert (and (>= depth 0)))
  ## axiom-lean: depth >= 0
func isIdentifierStart(ch: char): bool {.axiomTryImpl.} =
  result = ch in {'a' .. 'z', 'A' .. 'Z', '_', '~'}

  ## axiom-smt: (assert (and (>= depth 0)))
  ## axiom-lean: depth >= 0
func isIdentifierChar(ch: char): bool {.axiomTryImpl.} =
  result = ch in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '.', ':', '~'}

  ## axiom-smt: (assert (and (>= depth 0)))
  ## axiom-lean: depth >= 0
func isFunctionNameChar(ch: char): bool {.axiomTryImpl.} =
  result = ch in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '~'}

func countBraceDelta*(raw: string): int =
  for ch in raw:
    if ch == '{':
      inc result
    elif ch == '}':
      dec result

  ## axiom-smt: (assert (and (< cursor (str.len raw)) (and (>= cursor 0) (< cursor raw))))
  ## axiom-lean: cursor < raw.length ∧ ((cursor ≥ 0) ∧ (cursor < raw))
func stripInlineComment*(raw: string): string {.axiomTryImpl.} =
  var cursor = 0
  while cursor < raw.len:
    if cursor + 1 < raw.len and raw[cursor] == '/' and raw[cursor + 1] == '/':
      return raw[0 ..< cursor].strip()
    if raw[cursor] == '#':
      return raw[0 ..< cursor].strip()
    inc cursor
  result = raw.strip()

  ## axiom-smt: (assert (and (>= (str.len token) 0)))
  ## axiom-lean: token.length ≥ 0
func isReservedCallToken(token: string): bool {.axiomTryImpl.} =
  let lowered = token.toLowerAscii()
  result = lowered in [
    "if", "elif", "while", "for", "case", "when", "return",
    "proc", "func", "method", "iterator", "template", "macro",
    "converter", "let", "var", "const", "type", "block", "defer",
    "def", "fn", "match", "switch", "sizeof", "catch", "throw",
    "new", "delete", "class", "struct", "enum", "union", "ifconstexpr",
    "int", "long", "short", "bool", "void", "char", "float", "double",
    "usize", "isize", "str", "string", "self", "super", "this"
  ]

  ## axiom-smt: (assert (and (>= (str.len raw) 0) (and (>= cursor -9223372036854775808) (<= cursor 9223372036854775807)) result (>= result 0)))
  ## axiom-lean: raw.length ≥ 0 ∧ cursor ≥ -9223372036854775808 ∧ cursor ≤ 9223372036854775807 ∧ result ∧ (result ≥ 0)
func parseIdentifierAt(raw: string; cursor: var int): string {.axiomTryImpl.} =
  while cursor < raw.len and raw[cursor] in {' ', '\t'}:
    inc cursor
  if cursor < raw.len and raw[cursor] == '`':
    inc cursor
    let start = cursor
    while cursor < raw.len and raw[cursor] != '`':
      inc cursor
    if cursor >= raw.len:
      return ""
    result = raw[start ..< cursor]
    inc cursor
    return result
  if cursor >= raw.len or not isIdentifierStart(raw[cursor]):
    return ""
  let start = cursor
  inc cursor
  while cursor < raw.len and isFunctionNameChar(raw[cursor]):
    inc cursor
  result = raw[start ..< cursor]

  ## axiom-smt: (assert (and (< cursor 0) (and (>= idx 0) (< (+ idx 2) (str.len result))) (>= result 0)))
  ## axiom-lean: cursor < 0 ∧ idx ≥ 0 ∧ idx + 2 < result.length ∧ (result ≥ 0)
func extractTrailingIdentifier(raw: string): string {.axiomTryImpl.} =
  var cursor = raw.len - 1
  while cursor >= 0 and not isFunctionNameChar(raw[cursor]):
    dec cursor
  if cursor < 0:
    return ""
  let endPos = cursor
  while cursor >= 0 and isFunctionNameChar(raw[cursor]):
    dec cursor
  result = raw[cursor + 1 .. endPos]
  if result.find("::") >= 0:
    let idx = result.rfind("::")
    if idx >= 0 and idx + 2 < result.len:
      result = result[idx + 2 .. ^1]

  ## axiom-smt: (assert (and (>= (str.len trimmed) 0) (and (>= indent -9223372036854775808) (<= indent 9223372036854775807)) (= (str.len parsedName) 0) (and (>= bodyEq 0) (< (+ bodyEq 1) (str.len trimmed))) (and (>= braceIdx 0) (< (+ braceIdx 1) (str.len trimmed))) (= depth 0) (< cursor (str.len trimmed)) result (and (>= cursor 0) (< cursor trimmed)) (>= bodyFragment 0) (>= result 0) (>= nimKeywords 0)))
  ## axiom-lean: trimmed.length ≥ 0 ∧ indent ≥ -9223372036854775808 ∧ indent ≤ 9223372036854775807 ∧ parsedName.length = 0 ∧ bodyEq ≥ 0 ∧ bodyEq + 1 < trimmed.length ∧ braceIdx ≥ 0 ∧ braceIdx + 1 < trimmed.length ∧ depth = 0 ∧ cursor < trimmed.length ∧ result ∧ ((cursor ≥ 0) ∧ (cursor < trimmed)) ∧ (bodyFragment ≥ 0) ∧ (result ≥ 0) ∧ (nimKeywords ≥ 0)
func detectKeywordDeclaration(trimmed: string; indent: int): DeclParseResult {.axiomTryImpl.} =
  let nimKeywords = ["proc ", "func ", "method ", "iterator ", "template ", "macro ", "converter "]
  for keyword in nimKeywords:
    if not trimmed.startsWith(keyword):
      continue
    var cursor = keyword.len
    let parsedName = parseIdentifierAt(trimmed, cursor)
    if parsedName.len == 0:
      return DeclParseResult()
    result.found = true
    result.functionName = parsedName
    result.nodeType = keyword.strip()
    result.exported = cursor < trimmed.len and trimmed[cursor] == '*'
    result.indent = indent
    result.scopeKind = topologyScopeIndent
    let bodyEq = trimmed.find("=")
    if bodyEq >= 0 and bodyEq + 1 < trimmed.len:
      result.bodyFragment = trimmed[bodyEq + 1 .. ^1]
    if bodyEq >= 0:
      result.signatureText = trimmed[0 ..< bodyEq].strip()
    else:
      result.signatureText = trimmed.strip()
    return result

  if trimmed.startsWith("def "):
    var cursor = 4
    let parsedName = parseIdentifierAt(trimmed, cursor)
    if parsedName.len == 0:
      return DeclParseResult()
    return DeclParseResult(
      found: true,
      functionName: parsedName,
      exported: not parsedName.startsWith("_"),
      indent: indent,
      bodyFragment: "",
      scopeKind: topologyScopeIndent,
      initialBraceDepth: 0,
      braceSeen: false
    )

  if trimmed.startsWith("pub fn ") or trimmed.startsWith("fn "):
    var cursor = if trimmed.startsWith("pub fn "): 7 else: 3
    let parsedName = parseIdentifierAt(trimmed, cursor)
    if parsedName.len == 0:
      return DeclParseResult()
    let braceDepth = countBraceDelta(trimmed)
    let braceSeen = trimmed.find('{') >= 0
    var bodyFragment = ""
    let braceIdx = trimmed.find('{')
    if braceIdx >= 0 and braceIdx + 1 < trimmed.len:
      bodyFragment = trimmed[braceIdx + 1 .. ^1]
    return DeclParseResult(
      found: true,
      functionName: parsedName,
      exported: trimmed.startsWith("pub fn "),
      indent: indent,
      bodyFragment: bodyFragment,
      scopeKind: topologyScopeBrace,
      initialBraceDepth: braceDepth,
      braceSeen: braceSeen
    )

  if trimmed.startsWith("func "):
    var cursor = 5
    while cursor < trimmed.len and trimmed[cursor] in {' ', '\t'}:
      inc cursor
    if cursor < trimmed.len and trimmed[cursor] == '(':
      var depth = 0
      while cursor < trimmed.len:
        if trimmed[cursor] == '(':
          inc depth
        elif trimmed[cursor] == ')':
          dec depth
          if depth == 0:
            inc cursor
            break
        inc cursor
    let parsedName = parseIdentifierAt(trimmed, cursor)
    if parsedName.len == 0:
      return DeclParseResult()
    let braceDepth = countBraceDelta(trimmed)
    let braceSeen = trimmed.find('{') >= 0
    var bodyFragment = ""
    let braceIdx = trimmed.find('{')
    if braceIdx >= 0 and braceIdx + 1 < trimmed.len:
      bodyFragment = trimmed[braceIdx + 1 .. ^1]
    return DeclParseResult(
      found: true,
      functionName: parsedName,
      exported: true,
      indent: indent,
      bodyFragment: bodyFragment,
      scopeKind: topologyScopeBrace,
      initialBraceDepth: braceDepth,
      braceSeen: braceSeen
    )

  ## axiom-smt: (assert (and (>= (str.len trimmed) 0) (and (>= indent -9223372036854775808) (<= indent 9223372036854775807)) (<= openIdx 0) (< closeIdx openIdx) (and (>= braceIdx 0) (< (+ braceIdx 1) (str.len trimmed))) (>= bodyFragment 0)))
  ## axiom-lean: trimmed.length ≥ 0 ∧ indent ≥ -9223372036854775808 ∧ indent ≤ 9223372036854775807 ∧ openIdx ≤ 0 ∧ closeIdx < openIdx ∧ braceIdx ≥ 0 ∧ braceIdx + 1 < trimmed.length ∧ (bodyFragment ≥ 0)
func detectCStyleDeclaration(trimmed: string; indent: int): DeclParseResult {.axiomTryImpl.} =
  if trimmed.startsWith("if ") or trimmed.startsWith("for ") or trimmed.startsWith("while ") or
      trimmed.startsWith("switch ") or trimmed.startsWith("catch ") or trimmed.startsWith("return "):
    return DeclParseResult()
  let openIdx = trimmed.find('(')
  if openIdx <= 0:
    return DeclParseResult()
  let closeIdx = trimmed.rfind(')')
  if closeIdx < openIdx:
    return DeclParseResult()
  if trimmed.endsWith(";"):
    return DeclParseResult()
  let prefix = trimmed[0 ..< openIdx].strip()
  if prefix.len == 0 or prefix.endsWith("="):
    return DeclParseResult()
  if indent > 2 and prefix.find("::") < 0:
    return DeclParseResult()
  let hasTypeLikePrefix =
    prefix.find(' ') >= 0 or
    prefix.find('\t') >= 0 or
    prefix.find('*') >= 0 or
    prefix.find('&') >= 0 or
    prefix.find(':') >= 0 or
    prefix.find('<') >= 0 or
    prefix.find('>') >= 0
  if not hasTypeLikePrefix:
    return DeclParseResult()
  let parsedName = extractTrailingIdentifier(prefix)
  if parsedName.len == 0 or isReservedCallToken(parsedName):
    return DeclParseResult()
  let tail = trimmed[closeIdx + 1 .. ^1].strip()
  let plausibleDefinition =
    trimmed.find('{') >= 0 or
    tail.len == 0 or
    tail.startsWith("const") or
    tail.startsWith("noexcept") or
    tail.startsWith("->") or
    tail.startsWith("where")
  if not plausibleDefinition:
    return DeclParseResult()
  let braceDepth = countBraceDelta(trimmed)
  let braceSeen = trimmed.find('{') >= 0
  var bodyFragment = ""
  let braceIdx = trimmed.find('{')
  if braceIdx >= 0 and braceIdx + 1 < trimmed.len:
    bodyFragment = trimmed[braceIdx + 1 .. ^1]
  result = DeclParseResult(
    found: true,
    functionName: parsedName,
    exported: not parsedName.startsWith("_"),
    indent: indent,
    bodyFragment: bodyFragment,
    scopeKind: topologyScopeBrace,
    initialBraceDepth: braceDepth,
    braceSeen: braceSeen
  )

  ## axiom-smt: (assert (and (>= (str.len rawLine) 0) (or (= isNimSource true) (= isNimSource false)) (= (str.len trimmed) 0) isNimSource keywordDetected (or (= isNimSource true) (= isNimSource false))))
  ## axiom-lean: rawLine.length ≥ 0 ∧ isNimSource = true ∨ isNimSource = false ∧ trimmed.length = 0 ∧ isNimSource ∧ keywordDetected ∧ isNimSource = true ∨ isNimSource = false
func parseDeclaration*(rawLine: string; isNimSource: bool = false): DeclParseResult {.axiomTryImpl.} =
  let indent = countIndent(rawLine)
  if indent >= rawLine.len:
    return DeclParseResult()
  let trimmed = stripInlineComment(rawLine[indent .. ^1]).strip(trailing = false)
  if trimmed.len == 0:
    return DeclParseResult()
  if trimmed.startsWith("//") or trimmed.startsWith("#") or trimmed.startsWith("/*") or
      trimmed.startsWith("*") or trimmed.startsWith("*/"):
    return DeclParseResult()
  let keywordDetected = detectKeywordDeclaration(trimmed, indent)
  if keywordDetected.found:
    return keywordDetected
  if isNimSource:
    return DeclParseResult()
  result = detectCStyleDeclaration(trimmed, indent)

  ## axiom-smt: (assert (and (>= (str.len line) 0)))
  ## axiom-lean: line.length ≥ 0
func countControlSignals*(line: string): int {.axiomTryImpl.} =
  let normalized = line.strip().toLowerAscii()
  for token in ["if ", "elif ", "case ", "of ", "when ", "while ", "for "]:
    if normalized.startsWith(token):
      inc result
  if normalized.startsWith("if "):
    let tokens = tokenizeLowered(normalized)
    if "and" in tokens:
      inc result
    if "or" in tokens:
      inc result

  ## axiom-smt: (assert (and (>= (str.len rawLine) 0) ast_parse_failed_isolated))
  ## axiom-lean: rawLine.length ≥ 0 ∧ ast_parse_failed_isolated
func extractCallTargets*(rawLine: string): seq[string] {.axiomTryImpl.} =
  var cursor = 0
  while cursor < rawLine.len:
    if not isIdentifierStart(rawLine[cursor]):
      inc cursor
      continue
    let start = cursor
    inc cursor
    while cursor < rawLine.len and isIdentifierChar(rawLine[cursor]):
      inc cursor
    var token = rawLine[start ..< cursor]
    while cursor < rawLine.len and rawLine[cursor] in {' ', '\t'}:
      inc cursor
    if cursor < rawLine.len and rawLine[cursor] == '(':
      if token.find("::") >= 0:
        let idx = token.rfind("::")
        if idx >= 0 and idx + 2 < token.len:
          token = token[idx + 2 .. ^1]
      if token.find('.') >= 0:
        let dotIdx = token.rfind('.')
        if dotIdx >= 0 and dotIdx + 1 < token.len:
          token = token[dotIdx + 1 .. ^1]
      if not isReservedCallToken(token):
        result.add(token)

# @axiom-hint: lean="modulePath.length ≥ 0 ∧ functionName.length ≥ 0 ∧ exported = true ∨ exported = false" smt="(assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0) (or (= exported true) (= exported false))))"

{.pop.}
