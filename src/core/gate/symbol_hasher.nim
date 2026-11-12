import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/crypto/hash_kernel
import std/strutils
type
  SymbolKind* = enum
    ## Classification of Nim symbol definitions.
    skProc, skFunc, skType, skMethod, skConst, skVar,
    skIterator, skConverter, skTemplate, skMacro

  SymbolNode* {.acyclic.} = ref object
    ## A single symbol (proc/func/type/method/const/var) within a file.
    name*: string           ## e.g. "runNimtry", "HashValue"
    kind*: SymbolKind       ## Symbol classification
    lineRange*: (int, int)  ## (startLine, endLine) — 1-based inclusive
    contentHash*: string    ## SHA-256 of symbol source text
const
  callableKeywords = ["proc", "func", "method", "iterator", "template",
                      "macro", "converter"]
  blockKeywords = ["type", "const", "var"]
func classifyKeyword(kw: string): SymbolKind {.raises: [].} =
  ## Map a keyword string to its SymbolKind.
  case kw
  of "proc": return skProc
  of "func": return skFunc
  of "method": return skMethod
  of "iterator": return skIterator
  of "template": return skTemplate
  of "macro": return skMacro
  of "converter": return skConverter
  of "type": return skType
  of "const": return skConst
  of "var": return skVar
  else: return skProc
func countLeadingSpaces(line: string): int {.raises: [].} =
  ## Count leading whitespace characters.
  for i, c in line:
    if c != ' ' and c != '\t':
      return i
  result = line.len
func extractSymbolName(line, keyword: string): string {.raises: [].} =
  ## Extract the symbol name from a declaration line.
  ## e.g. "proc foo*(x: int): string =" → "foo"
  ## e.g. "type MyObj = object" → "MyObj"
  ## e.g. "const FOO = 42" → "FOO"
  var pos = keyword.len
  # Skip whitespace after keyword
  while pos < line.len and line[pos] in {' ', '\t'}:
    inc pos
  # Skip `*` prefix if present
  if pos < line.len and line[pos] == '*':
    inc pos
  # Skip whitespace after `*`
  while pos < line.len and line[pos] in {' ', '\t'}:
    inc pos
  # Read identifier characters
  let start = pos
  while pos < line.len and (line[pos] in Letters + Digits + {'_'}):
    inc pos
  result = line[start ..< pos]
func isTopLevelSymbolStart(line: string): bool {.raises: [].} =
  ## Check if a line starts a top-level symbol definition.
  ## Must be at indentation ≤ 1 (top level or one level inside a module).
  let indent = countLeadingSpaces(line)
  if indent > 1:
    return false
  let stripped = line.strip()
  for kw in callableKeywords:
    if stripped.startsWith(kw):
      if stripped.len == kw.len:
        return true
      let after = stripped[kw.len]
      if after in {' ', '*', '('}:
        return true
  for kw in blockKeywords:
    if stripped.startsWith(kw):
      if stripped.len == kw.len:
        return true
      let after = stripped[kw.len]
      if after in {' ', '*', '='}:
        return true
  return false
func findKeyword(line: string): string {.raises: [].} =
  ## Find the keyword that starts a top-level symbol. Returns "" if none.
  let stripped = line.strip()
  for kw in callableKeywords:
    if stripped.startsWith(kw):
      if stripped.len == kw.len:
        return kw
      let after = stripped[kw.len]
      if after in {' ', '*', '(', '{'}:
        return kw
  for kw in blockKeywords:
    if stripped.startsWith(kw):
      if stripped.len == kw.len:
        return kw
      let after = stripped[kw.len]
      if after in {' ', '*', '='}:
        return kw
  return ""
func hashSymbols*(symbols: seq[SymbolNode]): string =
  ## Compute Merkle hash of all symbols in a file.
  ## Concatenates (name, kind ordinal, contentHash) and SHA-256s the result.
  ## Empty symbol list returns SHA-256("") as a stable sentinel.
  if symbols.len == 0:
    return hash_kernel.sha256Hex("")
  var combined = ""
  for s in symbols:
    combined.add(s.name)
    combined.add($ord(s.kind))
    combined.add(s.contentHash)
  result = hash_kernel.sha256Hex(combined)
func extractSymbols*(source: string): seq[SymbolNode] =
  ## Extract top-level symbol definitions from Nim source text.
  ## Fast heuristic: scans for keyword-based declaration lines at low indentation.
  ## Returns symbols in source order with SHA-256 hashes of their text ranges.
  result = @[]
  if source.len == 0:
    return

  let lines = source.split('\n')
  if lines.len == 0:
    return

  # Phase 1: Find all top-level symbol start lines
  type SymbolStart = object
    lineIdx: int      ## 0-based line index
    keyword: string
    name: string
    kind: SymbolKind

  var starts: seq[SymbolStart] = @[]

  for i in 0..<lines.len:
    let line = lines[i]
    if isTopLevelSymbolStart(line):
      let kw = findKeyword(line)
      if kw.len > 0:
        let kind = classifyKeyword(kw)
        let name = extractSymbolName(line, kw)
        if name.len > 0:
          starts.add(SymbolStart(lineIdx: i, keyword: kw, name: name, kind: kind))

  # Phase 2: For each symbol, determine its line range and hash
  for i in 0..<starts.len:
    let s = starts[i]
    let startLine = s.lineIdx  # 0-based
    var endLine: int
    if i + 1 < starts.len:
      endLine = starts[i + 1].lineIdx - 1
    else:
      endLine = lines.len - 1

    # Skip empty ranges
    if endLine < startLine:
      continue

    # Extract source text for this symbol
    var symbolText = ""
    for ln in startLine..endLine:
      if symbolText.len > 0:
        symbolText.add('\n')
      symbolText.add(lines[ln])

    # Strip trailing blank lines from symbol text
    while symbolText.len > 0 and symbolText[^1] == '\n':
      symbolText.setLen(symbolText.len - 1)

    let contentHash = hash_kernel.sha256Hex(symbolText)

    result.add(SymbolNode(
      name: s.name,
      kind: s.kind,
      lineRange: (startLine + 1, endLine + 1),  # Convert to 1-based
      contentHash: contentHash
    ))

{.pop.}
