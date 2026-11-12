import core/trusted/layer_declaration
axiomLayer "tools"

import std/[json, os, strutils, times, sets]
import core/audit/content_hash
import core/crypto/hash_kernel

const
  RegistryPath = "data/debt_registry.json"
  SnippetRadius = 7

type
  ResolvedSymbol = object
    ok: bool
    symbol, filePath, lineRange, snippet, contentHash, missingReason: string

proc jsonStr(entry: JsonNode; key: string; default = ""): string =
  if entry == nil or not entry.hasKey(key): return default
  var node: JsonNode
  try:
    node = entry[key]
  except KeyError:
    node = nil
  if node == nil or node.kind == JNull: return default
  node.getStr(default)

proc isDigitChar(c: char): bool {.raises: [].} =
  c >= '0' and c <= '9'

proc isDigitStr(s: string): bool {.raises: [].} =
  if s.len == 0: return false
  for ch in s:
    if not isDigitChar(ch): return false
  true

proc parseDigitInt(s: string): int {.raises: [].} =
  if s.len == 0: return -1
  var n = 0
  for ch in s:
    if not isDigitChar(ch): return -1
    n = n * 10 + (ord(ch) - ord('0'))
  n

proc parseDebtNum(id: string): int {.raises: [].} =
  let marker = id.find('#')
  if marker < 0: return 0
  result = parseDigitInt(id[marker + 1 .. ^1])

proc cleanSymbol(s: string): string {.raises: [].} =
  var resultValue = s.strip()
  if resultValue.len == 0: return ""
  if resultValue.startsWith("`"):
    let endIdx = resultValue.find('`', 1)
    if endIdx >= 0: resultValue = resultValue[1 ..< endIdx].strip()
  let parenIdx = resultValue.find('(')
  if parenIdx >= 0: resultValue = resultValue[0 ..< parenIdx].strip()
  if resultValue.endsWith("*"): resultValue = resultValue[0 ..< resultValue.len - 1].strip()
  resultValue.strip()

proc isIgnoredSymbol(s: string): bool {.raises: [].} =
  case s
  of "src", "core", "gate", "tools", "tests", "docs", "See", "Source",
     "REMEDIATED", "CLOSED", "All", "phase", "Phase", "theater",
     "theater_audit", "theater_audit_medium_low", "true", "false":
    true
  else: false

proc addCandidate(candidates: var seq[string]; seen: var HashSet[string]; raw: string) =
  var s = raw.strip()
  if s.len == 0: return
  if s.startsWith("`"):
    let endIdx = s.find('`', 1)
    if endIdx >= 0: s = s[1 ..< endIdx].strip()
  let parenIdx = s.find('(')
  if parenIdx >= 0: s = s[0 ..< parenIdx].strip()
  let slashIdx = s.find('/')
  if slashIdx >= 0:
    for part in s.split('/'):
      addCandidate(candidates, seen, part)
    return
  let dotIdx = s.find('.')
  if dotIdx >= 0: s = s[0 ..< dotIdx].strip()
  if s.len == 0 or s.len > 80 or s in seen or isIgnoredSymbol(s): return
  if s.startsWith("DEBT"): return
  if s.len >= 2 and s[0] == 'S' and isDigitStr(s[1 .. ^1]): return
  seen.incl(s)
  candidates.add(s)

func isIdentStart(c: char): bool {.raises: [].} =
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'

func isIdentChar(c: char): bool {.raises: [].} =
  c.isIdentStart or isDigitChar(c)

proc collectBacktickSymbols(text: string; candidates: var seq[string]; seen: var HashSet[string]) =
  var i = 0
  while i < text.len:
    if text[i] == '`':
      let endIdx = text.find('`', i + 1)
      if endIdx < 0: break
      addCandidate(candidates, seen, text[i + 1 ..< endIdx])
      i = endIdx + 1
    else:
      inc i

proc collectIdentifierSymbols(text: string; candidates: var seq[string]; seen: var HashSet[string]) =
  var i = 0
  while i < text.len:
    if text[i].isIdentStart:
      let start = i
      inc i
      while i < text.len and text[i].isIdentChar:
        inc i
      addCandidate(candidates, seen, text[start ..< i])
    else:
      inc i

proc addFile(raw: string; result: var seq[string]; seen: var HashSet[string]) =
  for rawPart in raw.split(';'):
    for part in rawPart.split(','):
      for plusPart in part.split('+'):
        var file = plusPart.strip().replace('\\', '/')
        if file.len == 0 or file in seen: continue
        seen.incl(file)
        result.add(file)

proc collectFiles(entry: JsonNode): seq[string] {.raises: [].} =
  var seen = initHashSet[string]()
  let fileNode = entry{"file"}
  if fileNode != nil and fileNode.kind != JNull:
    if fileNode.kind == JArray:
      for item in fileNode:
        addFile(item.getStr(), result, seen)
    elif fileNode.kind == JString:
      addFile(fileNode.getStr(), result, seen)
  let filesNode = entry{"files"}
  if filesNode != nil and filesNode.kind != JNull:
    if filesNode.kind == JArray:
      for item in filesNode:
        addFile(item.getStr(), result, seen)
    elif filesNode.kind == JString:
      addFile(filesNode.getStr(), result, seen)

proc lastIndexOf(s: string; ch: char): int {.raises: [].} =
  var i = s.len - 1
  while i >= 0:
    if s[i] == ch: return i
    dec i
  -1

proc splitFileRef(pathRef: string): tuple[path: string; lineRange: string] {.raises: [].} =
  let idx = lastIndexOf(pathRef.strip(), ':')
  if idx > 0:
    result.path = pathRef[0 ..< idx].strip()
    result.lineRange = pathRef[idx + 1 .. ^1].strip()
  else:
    result.path = pathRef.strip()

proc parseLineRanges(lineRange: string): seq[tuple[start: int; finish: int]] {.raises: [].} =
  for token in lineRange.split(';'):
    for part in token.split(','):
      let s = part.strip()
      if s.len == 0: continue
      let dashIdx = s.find('-')
      if dashIdx >= 0:
        let start = parseDigitInt(s[0 ..< dashIdx])
        let finish = parseDigitInt(s[dashIdx + 1 .. ^1])
        if start >= 1 and finish >= start:
          result.add((start: start, finish: finish))
      else:
        let line = parseDigitInt(s)
        if line >= 1:
          result.add((start: line, finish: line))

proc makeLineRangeLabel(path: string; ranges: seq[tuple[start: int; finish: int]]): string {.raises: [].} =
  if ranges.len == 0 or path.len == 0: return ""
  let r = ranges[0]
  if r.start == r.finish:
    result = path & ":" & $r.start
  else:
    result = path & ":" & $r.start & "-" & $r.finish

proc lineStartOffsets(source: string): seq[int] {.raises: [].} =
  result.add(0)
  var i = 0
  while i < source.len:
    if source[i] == '\n': result.add(i + 1)
    inc i

proc strippedComment(line: string): string {.raises: [].} =
  var inString = false
  var inChar = false
  var escape = false
  var i = 0
  while i < line.len:
    let c = line[i]
    if escape:
      escape = false
      inc i
      continue
    if c == '\\' and (inString or inChar):
      escape = true
      inc i
      continue
    if c == '"' and not inChar:
      inString = not inString
    elif c == '\'' and not inString:
      inChar = not inChar
    elif c == '/' and i + 1 < line.len and line[i + 1] == '/' and not inString and not inChar:
      return line[0 ..< i]
    inc i
  line

proc parseDeclName(line: string): string {.raises: [].} =
  var s = strippedComment(line).strip()
  if s.startsWith("proc ") or s.startsWith("func "):
    s = s[5 .. ^1].strip()
  elif s.startsWith("method "):
    s = s[7 .. ^1].strip()
  elif s.startsWith("iterator "):
    s = s[9 .. ^1].strip()
  elif s.startsWith("converter "):
    s = s[10 .. ^1].strip()
  elif s.startsWith("template "):
    s = s[9 .. ^1].strip()
  elif s.startsWith("macro "):
    s = s[6 .. ^1].strip()
  elif s.startsWith("type "):
    s = s[5 .. ^1].strip()
  elif s.startsWith("const "):
    s = s[6 .. ^1].strip()
  elif s.startsWith("let "):
    s = s[4 .. ^1].strip()
  elif s.startsWith("var "):
    s = s[4 .. ^1].strip()
  if s.startsWith("`"):
    let endIdx = s.find('`', 1)
    if endIdx >= 0: s = s[1 ..< endIdx].strip()
  if s.startsWith("*"): s = s[1 .. ^1].strip()
  if s.startsWith("("): return ""
  var i = 0
  while i < s.len:
    let c = s[i]
    if c == ' ' or c in {'(', ')', '{', '}', '[', ']', ':', '=', ';', ',', '<', '>', '|', '&', '!', '?'}:
      break
    inc i
  cleanSymbol(s[0 ..< i].strip())

proc findDeclarationLine(source: string; symbol: string): int {.raises: [].} =
  let target = cleanSymbol(symbol)
  if target.len == 0: return -1
  let offsets = lineStartOffsets(source)
  for lineIdx in 0 ..< offsets.len:
    let lineStart = offsets[lineIdx]
    let lineEnd = if lineIdx + 1 < offsets.len: offsets[lineIdx + 1] else: source.len
    if parseDeclName(source[lineStart ..< lineEnd]) == target:
      return lineIdx
  -1

proc findNextDeclarationLine(source: string; startLine: int): int {.raises: [].} =
  let offsets = lineStartOffsets(source)
  for lineIdx in startLine + 1 ..< offsets.len:
    let lineStart = offsets[lineIdx]
    let lineEnd = if lineIdx + 1 < offsets.len: offsets[lineIdx + 1] else: source.len
    if parseDeclName(source[lineStart ..< lineEnd]).len > 0:
      return lineIdx
  offsets.len

proc extractDeclarationText(source: string; symbol: string): string {.raises: [].} =
  let startLine = findDeclarationLine(source, symbol)
  if startLine < 0: return ""
  let offsets = lineStartOffsets(source)
  let startOffset = offsets[startLine]
  let endLine = findNextDeclarationLine(source, startLine)
  let endOffset = if endLine < offsets.len: offsets[endLine] else: source.len
  result = source[startOffset ..< endOffset].strip()

proc lineSnippet(source: string; lineNumber: int): string {.raises: [].} =
  let lines = source.splitLines()
  if lines.len == 0: return ""
  let start = max(1, lineNumber - SnippetRadius)
  let finish = min(lines.len, lineNumber + SnippetRadius)
  for i in start ..< finish + 1:
    result.add(lines[i - 1])
    if i < finish + 1: result.add('\n')

proc firstSnippet(source: string): string {.raises: [].} =
  lineSnippet(source, 1)

proc makeDeclarationLineRange(filePath: string; startLine: int; source: string): string {.raises: [].} =
  if filePath.len == 0 or source.len == 0: return ""
  let offsets = lineStartOffsets(source)
  let endLine = findNextDeclarationLine(source, startLine)
  let finish = if endLine < offsets.len: endLine + 1 else: offsets.len
  if startLine + 1 == finish:
    result = filePath & ":" & $(startLine + 1)
  else:
    result = filePath & ":" & $(startLine + 1) & "-" & $finish

proc collectCandidateSymbols(entry: JsonNode): seq[string] {.raises: [].} =
  var candidates: seq[string] = @[]
  var seen = initHashSet[string]()
  collectBacktickSymbols(jsonStr(entry, "title"), candidates, seen)
  collectIdentifierSymbols(jsonStr(entry, "title"), candidates, seen)
  collectBacktickSymbols(jsonStr(entry, "description"), candidates, seen)
  collectIdentifierSymbols(jsonStr(entry, "description"), candidates, seen)
  for fileRef in collectFiles(entry):
    let split = splitFileRef(fileRef)
    addCandidate(candidates, seen, split.path)
    let base = splitFile(split.path).name
    addCandidate(candidates, seen, base)
  result = candidates

proc resolvedFromSymbol(filePath: string; source: string; symbol: string; startLine: int): ResolvedSymbol {.raises: [CatchableError].} =
  result.ok = true
  result.filePath = filePath
  result.symbol = symbol
  result.snippet = lineSnippet(source, startLine + 1)
  let body = extractProcText(source, symbol)
  let declarationBody = extractDeclarationText(source, symbol)
  let hashBody = if body.len > 0: body else: declarationBody
  result.lineRange = makeDeclarationLineRange(filePath, startLine, source)
  if hashBody.len > 0:
    result.contentHash = computeContentHash(hashBody)
  else:
    result.contentHash = computeContentHash(result.snippet)

proc resolvedFromLineRange(filePath: string; source: string; ranges: seq[tuple[start: int; finish: int]]): ResolvedSymbol {.raises: [CatchableError].} =
  if ranges.len == 0: return result
  let start = ranges[0].start
  result.ok = true
  result.filePath = filePath
  result.symbol = makeLineRangeLabel(filePath, ranges)
  result.lineRange = result.symbol
  result.snippet = lineSnippet(source, start)
  result.contentHash = computeContentHash(result.snippet)

proc resolvedFromArtifact(filePath: string; source: string): ResolvedSymbol {.raises: [CatchableError].} =
  let snippet = firstSnippet(source)
  result.ok = true
  result.filePath = filePath
  result.symbol = "artifact:" & filePath
  result.lineRange = makeLineRangeLabel(filePath, @[(start: 1, finish: max(1, min(15, snippet.splitLines().len)))])
  result.snippet = snippet
  result.contentHash = computeContentHash(snippet)

proc missingResult(reason: string): ResolvedSymbol {.raises: [].} =
  result.ok = false
  result.missingReason = reason

proc canonicalMissingArtifact(entry: JsonNode; files: seq[string]): string {.raises: [].} =
  var parts = @[jsonStr(entry, "id", "unknown")]
  for fileRef in files:
    parts.add(fileRef)
  let symbol = cleanSymbol(jsonStr(entry, "symbol"))
  if symbol.len > 0: parts.add("symbol=" & symbol)
  parts.add("missing")
  result = parts.join("\n")

proc findExplicitOrCandidate(entry: JsonNode; fileRef: string; source: string): ResolvedSymbol {.raises: [CatchableError].} =
  let explicit = cleanSymbol(jsonStr(entry, "symbol"))
  if explicit.len > 0:
    let startLine = findDeclarationLine(source, explicit)
    if startLine >= 0: return resolvedFromSymbol(fileRef, source, explicit, startLine)
  let candidates = collectCandidateSymbols(entry)
  for symbol in candidates:
    let startLine = findDeclarationLine(source, symbol)
    if startLine >= 0: return resolvedFromSymbol(fileRef, source, symbol, startLine)
  result = missingResult("no symbol declaration found in " & fileRef)

proc analyzeEntry(entry: JsonNode; repoRoot: string): ResolvedSymbol {.raises: [CatchableError].} =
  let files = collectFiles(entry)
  if files.len == 0:
    return missingResult("entry has no file/files")
  for fileRef in files:
    let split = splitFileRef(fileRef)
    if split.path.len == 0: continue
    let full = if split.path.startsWith('/'): split.path else: joinPath(repoRoot, split.path)
    if not fileExists(full): continue
    let source = readFile(full)
    let ranges = parseLineRanges(split.lineRange)
    let symbolResult = findExplicitOrCandidate(entry, split.path, source)
    if symbolResult.ok: return symbolResult
    if ranges.len > 0:
      return resolvedFromLineRange(split.path, source, ranges)
    return resolvedFromArtifact(split.path, source)
  missingResult("no existing file or symbol artifact found")

proc hasBlank(entry: JsonNode; key: string): bool =
  if not entry.hasKey(key): return true
  let node = entry[key]
  if node == nil or node.kind == JNull: return true
  node.getStr().len == 0

proc isTargetEntry(entry: JsonNode): bool =
  let id = jsonStr(entry, "id")
  let num = parseDebtNum(id)
  num >= 277 and num <= 356 and jsonStr(entry, "status") == "closed" and
    hasBlank(entry, "resolution") and hasBlank(entry, "contentHash")

proc targetEntries(registry: JsonNode): seq[JsonNode] =
  let entries = registry["entries"]
  if entries.kind != JArray: return result
  for entry in entries:
    if isTargetEntry(entry): result.add(entry)

proc prefixLines(text: string; prefix: string): string {.raises: [].} =
  var first = true
  for line in text.splitLines():
    if not first: result.add('\n')
    result.add(prefix & line)
    first = false

proc reportEntry(entry: JsonNode; index, total: int; repoRoot: string): int =
  let id = jsonStr(entry, "id")
  let category = jsonStr(entry, "category", "uncategorized")
  let title = jsonStr(entry, "title", jsonStr(entry, "description"))
  let analysis = analyzeEntry(entry, repoRoot)
  echo "[", index, "/", total, "] ", id, " ", category
  echo "  title: ", title
  if analysis.ok:
    echo "  file: ", analysis.filePath
    echo "  symbol: ", analysis.symbol
    echo "  lineRange: ", analysis.lineRange
    echo "  contentHash: ", analysis.contentHash
    echo "  suggested resolution: FIXED"
  else:
    echo "  missing: ", analysis.missingReason
    echo "  suggested resolution: ORPHANED"
    echo "  contentHash: ", computeContentHash(canonicalMissingArtifact(entry, collectFiles(entry)))
  echo "  snippet:"
  if analysis.snippet.len > 0:
    stdout.write(prefixLines(analysis.snippet, "    "))
    stdout.write('\n')
  else:
    echo "    <empty>"
  echo "  missing resolution + contentHash — apply through bin/debt_engine"
  return 1

proc usage() =
  echo "Usage: nim c -o:bin/debt_backfill tools/debt_backfill.nim"
  echo "       bin/debt_backfill [--limit N] [--registry path]"
  echo ""
  echo "Read-only audit: reports closed entries missing resolution/contentHash."
  echo "bin/debt_engine owns the registry; this tool never writes it."

proc findRegistryPath(): string {.raises: [CatchableError].} =
  var current = getCurrentDir()
  while true:
    let candidate = joinPath(current, RegistryPath)
    if fileExists(candidate): return candidate
    let parent = current.parentDir()
    if parent == current: return candidate
    current = parent

proc parseArgs(args: seq[string]; registryPath: var string; limit: var string): bool {.raises: [CatchableError].} =
  result = true
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg == "--help" or arg == "-h":
      usage()
      quit(0)
    elif arg == "--registry":
      inc i
      if i >= args.len:
        echo "ERROR: --registry requires a path"
        result = false
        return
      registryPath = args[i]
    elif arg == "--limit":
      inc i
      if i >= args.len:
        echo "ERROR: --limit requires a number"
        result = false
        return
      limit = args[i]
    else:
      echo "ERROR: unknown argument: ", arg
      result = false
      return
    inc i

proc repoRootForRegistry(path: string): string {.raises: [CatchableError].} =
  let dataDir = path.parentDir()
  if splitFile(dataDir).name == "data":
    dataDir.parentDir()
  else:
    getCurrentDir()

when isMainModule:
  var registryPath = findRegistryPath()
  var limitArg = ""
  if not parseArgs(commandLineParams(), registryPath, limitArg): quit(1)
  if not fileExists(registryPath):
    echo "ERROR: registry not found: ", registryPath
    quit(1)
  let repoRoot = repoRootForRegistry(registryPath)
  let registry = parseJson(readFile(registryPath))
  let entries = targetEntries(registry)
  echo "Registry: ", registryPath
  echo "Targets: ", entries.len, " closed DEBT#277..DEBT#356 entries missing resolution/contentHash"
  if entries.len == 0:
    echo "status: clean"
    quit(0)
  var processed = 0
  let limit = parseDigitInt(limitArg)
  let stopAt = if limit >= 1 and limit < entries.len: limit else: entries.len
  for entry in entries[0 ..< stopAt]:
    processed += reportEntry(entry, processed + 1, stopAt, repoRoot)
  echo "Audit complete: ", processed, " entries lack resolution/contentHash."
  echo "Registry is read-only here; apply through bin/debt_engine."
  if entries.len > stopAt:
    echo "NOTE: ", entries.len - stopAt, " further entries were not reported (--limit)."
  quit(1)
