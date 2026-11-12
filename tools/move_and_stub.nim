import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}
## move_and_stub.nim — Atomic symbol relocation with forwarding stub generation.
##
## Moves specified symbols from a source .nim file to a new destination file,
## replaces the source with a forwarding stub, and optionally rewrites imports.
##
## Usage:
##   nim c -r tools/move_and_stub.nim \
##     --old src/core/types/foo.nim \
##     --new src/core/bar/foo.nim \
##     --symbols runA,runB \
##     --move --rewrite-imports --dry-run
##
##   # Move entire file (no --symbols):
##   nim c -r tools/move_and_stub.nim \
##     --old src/core/types/foo.nim \
##     --new src/core/bar/foo.nim \
##     --move --dry-run

import std/algorithm
import std/json
import std/os
import std/re
import std/strutils
import std/times

const
  DefaultMapPath = "data/migration_map.json"
  SrcDir = "src"
  CacheDirs = [".nimcache", "nimcache", "__pycache__", ".git", "node_modules"]

# ── Regex patterns ────────────────────────────────────────────────────
let
  declOrTypeRe = re"^(proc|func|template|macro|type|const|var|let)\b"
  commentRe = re"^\s*##?[/! ]"
  identifierRe = re"(\w+)"
  bareTypeNextRe = re"\s+(\w+)"

# ── String helpers ────────────────────────────────────────────────────

func lstrip(s: string, chars: set[char] = {' '}): string =
  ## Strip leading characters from a string.
  var i = 0
  while i < s.len and s[i] in chars:
    inc i
  s[i .. ^1]

func countLeading(s: string, c: char = ' '): int =
  ## Count number of leading characters.
  var i = 0
  while i < s.len and s[i] == c:
    inc i
  i

# ═══════════════════════════════════════════════════════════════════════
# Import path helpers
# ═══════════════════════════════════════════════════════════════════════

func nimImportPath(filePath: string): (string, string) =
  ## Convert a file path like 'src/core/solver/wrappers.nim' to a
  ## Nim-style dotted import path and module name.
  var path = filePath.replace("\\", "/")

  # Strip 'src/' prefix
  if path.startsWith(SrcDir & "/"):
    path = path[SrcDir.len + 1 .. ^1]
  elif path.startsWith(SrcDir):
    path = path[SrcDir.len .. ^1]

  # Strip '.nim' extension
  if path.endsWith(".nim"):
    path = path[0 .. ^5]

  let importPath = path.replace("\\", "/").strip(chars = {'/'})
  let moduleName = if "/" in importPath:
    importPath.rsplit('/', 1)[1]
  else:
    importPath

  (importPath, moduleName)

# ═══════════════════════════════════════════════════════════════════════
# Symbol extraction
# ═══════════════════════════════════════════════════════════════════════

proc extractNameFromLine(line: string): string =
  ## Return the symbol name from a declaration line, or empty string.
  var matches: array[1, string]
  let stripped = line.lstrip()
  if not stripped.match(declOrTypeRe, matches):
    return ""

  let keyword = matches[0]
  # rest = everything after the keyword, then lstrip
  let rest = stripped[keyword.len .. ^1].lstrip()

  if keyword == "type":
    # type Foo* = ... or bare type\n
    if rest.len == 0 or rest[0] == '\n':
      return ""  # bare type block header
    var nameMatches: array[1, string]
    if rest.match(identifierRe, nameMatches):
      return nameMatches[0]
    return ""

  # proc/func/template/macro/const/var/let NAME
  var nameMatches: array[1, string]
  if rest.match(identifierRe, nameMatches):
    return nameMatches[0]
  return ""

proc isTopLevel(line: string): bool =
  ## True if line starts a top-level declaration (column 0).
  if not line.lstrip().match(declOrTypeRe):
    return false
  line.countLeading(' ') == 0

proc isCommentLine(line: string): bool =
  ## True if line is a comment that may precede a declaration.
  line.match(commentRe)

type
  SymbolBlock = object
    name: string
    keyword: string
    start: int
    endIdx: int
    text: string

proc parseSymbolBlocks(lines: seq[string]): seq[SymbolBlock] =
  ## Parse lines into a list of symbol blocks.
  var blocks: seq[SymbolBlock]
  var i = 0
  let n = lines.len

  while i < n:
    # ── Collect leading comment lines ──────────────────────────
    var commentLines: seq[string]
    let commentStart = i
    while i < n and isCommentLine(lines[i]):
      commentLines.add(lines[i])
      inc i

    if i >= n:
      break

    # ── Check for declaration ──────────────────────────────────
    if not isTopLevel(lines[i]):
      # Not a top-level decl; skip accumulated comments
      inc i
      continue

    # Found a top-level declaration
    let declLineIdx = i
    var name = extractNameFromLine(lines[i])
    var keyword = ""
    var kwMatches: array[1, string]
    if lines[i].lstrip().match(declOrTypeRe, kwMatches):
      keyword = kwMatches[0]

    # For bare `type` (no name on same line), peek at next indented line
    if keyword == "type" and name.len == 0 and declLineIdx + 1 < n:
      let nextLine = lines[declLineIdx + 1]
      var nmMatches: array[1, string]
      if nextLine.match(bareTypeNextRe, nmMatches):
        name = nmMatches[0]

    # Determine block boundary
    let blockStart = if commentLines.len > 0: commentStart else: declLineIdx
    inc i

    # Consume body lines until next top-level decl, un-indented non-blank
    # line, or EOF.
    while i < n:
      if isTopLevel(lines[i]):
        break
      let strippedLine = lines[i].lstrip()
      # Blank lines are part of the block body
      if strippedLine.len == 0:
        inc i
        continue
      # Continuation of body: must be indented relative to decl
      if lines[i].countLeading(' ') > 0:
        inc i
      else:
        break

    let blockText = lines[declLineIdx ..< i].join("")
    var allText = ""
    for cl in commentLines:
      allText.add(cl)
    allText.add(blockText)

    blocks.add(SymbolBlock(
      name: name,
      keyword: keyword,
      start: blockStart,
      endIdx: i,
      text: allText,
    ))

  blocks

proc extractSymbols(
  lines: seq[string],
  symbols: seq[string],
): (string, seq[string]) {.raises: [CatchableError].} =
  ## Extract the requested symbols from source lines.
  ## If symbols is empty, returns the full file content.
  if symbols.len == 0:
    return (lines.join(""), @[])

  let blocks = parseSymbolBlocks(lines)
  var wanted = symbols
  var foundNames: seq[string]
  var extractedParts: seq[string]

  for blk in blocks:
    let idx = wanted.find(blk.name)
    if idx >= 0:
      foundNames.add(blk.name)
      extractedParts.add(blk.text)
      wanted.delete(idx)

  if wanted.len > 0:
    wanted.sort()
    stderr.writeLine("Warning: symbols not found in source: ",
                     wanted.join(", "))

  (extractedParts.join(""), foundNames)

# ═══════════════════════════════════════════════════════════════════════
# Content generation
# ═══════════════════════════════════════════════════════════════════════

func makeNewFileContent(
  extracted: string,
  oldPath: string,
  symbolNames: seq[string],
): string =
  ## Wrap extracted symbols in {.push raises: [].} / {.pop.} block.
  let symLabel = if symbolNames.len > 0: symbolNames.join(", ")
                 else: "(all content)"
  "{.push raises: [].}\n" &
  "# Extracted from: " & oldPath & "\n" &
  "# Symbols: " & symLabel & "\n" &
  "\n" &
  extracted &
  "\n" &
  "{.pop.}\n"

func makeForwardingStub(
  newImportPath: string,
  moduleName: string,
): string =
  ## Generate Pattern-B forwarding stub with {.push raises: [].}.
  "{.push raises: [].}\n" &
  "import " & newImportPath & "\n" &
  "export " & moduleName & "\n" &
  "{.pop.}\n"

# ═══════════════════════════════════════════════════════════════════════
# Migration map
# ═══════════════════════════════════════════════════════════════════════

proc currentDateStr(): string =
  ## Return current UTC date as YYYY-MM-DD.
  let now = utc(getTime())
  now.format("yyyy-MM-dd")

proc loadMap(mapPath: string): JsonNode =
  ## Load migration_map.json; create minimal structure if absent.
  if fileExists(mapPath):
    try:
      let data = parseJson(readFile(mapPath))
      if not data.hasKey("mappings"):
        data["mappings"] = newJArray()
      return data
    except CatchableError: # axiom:best-effort(corrupt migration map — start with empty map)
      discard

  result = %*{
    "version": "1.0.0",
    "description": "Module relocation map for forwarding stub generation.",
    "generated": currentDateStr(),
    "mappings": [],
    "deletions": [],
    "exemptions": [],
  }

proc saveMap(data: JsonNode, mapPath: string) {.raises: [CatchableError].} =
  ## Write migration_map.json with pretty formatting.
  let parent = parentDir(mapPath)
  if parent.len > 0 and not dirExists(parent):
    createDir(parent)
  writeFile(mapPath, data.pretty() & "\n")

proc appendMapping(
  data: JsonNode,
  oldPath: string,
  newPath: string,
  oldImport: string,
  newImport: string,
): bool {.raises: [CatchableError].} =
  ## Append a mapping entry. Returns true if added (false if duplicate).
  let mappings = data["mappings"]
  for i in 0..<mappings.len:
    let entry = mappings[i]
    if entry.getOrDefault("old").getStr() == oldPath and
       entry.getOrDefault("new").getStr() == newPath:
      return false  # already present — idempotent

  data["mappings"].add(%*{
    "old": oldPath,
    "new": newPath,
    "import_old": oldImport,
    "import_new": newImport,
  })
  true

# ═══════════════════════════════════════════════════════════════════════
# Import rewriting
# ═══════════════════════════════════════════════════════════════════════

func shouldPruneDir(dirname: string): bool =
  for d in CacheDirs:
    if dirname == d:
      return true
  false

proc findNimFiles(root: string): seq[string] {.raises: [CatchableError].} =
  ## Recursively find all .nim files under root, excluding cache dirs.
  for kind, path in walkDir(root):
    if kind == pcDir:
      let base = lastPathPart(path)
      if shouldPruneDir(base):
        continue
      result.add(findNimFiles(path))
    elif kind == pcFile and path.endsWith(".nim"):
      result.add(path)

func isWordBoundary(s: string, pos: int): bool =
  ## True if pos is at a word boundary (non-identifier char or edge).
  if pos < 0 or pos >= s.len:
    return true
  let c = s[pos]
  c notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}

func replaceImportPath(line, oldImport, newImport: string): string {.raises: [].} =
  ## Replace oldImport with newImport in import/from lines.
  result = line

  # Handle bracket imports: import core/[foo, old_path, bar]
  let bracketOpen = result.find("[")
  if bracketOpen >= 0:
    let bracketClose = result.rfind("]")
    if bracketClose > bracketOpen:
      let prefix = result[0 ..< bracketOpen + 1]
      let inner = result[bracketOpen + 1 ..< bracketClose]
      let suffix = result[bracketClose .. ^1]
      var parts: seq[string]
      var replaced = false
      for part in inner.split(","):
        let trimmed = part.strip()
        if trimmed == oldImport:
          parts.add(newImport)
          replaced = true
        else:
          parts.add(trimmed)
      if replaced:
        return prefix & parts.join(", ") & suffix

  # Simple import/from replacement
  for keyword in ["import ", "from "]:
    let kwPos = result.find(keyword)
    if kwPos >= 0:
      let pathStart = kwPos + keyword.len
      let pathEnd = pathStart + oldImport.len
      if pathEnd <= result.len and
         result[pathStart ..< pathEnd] == oldImport and
         isWordBoundary(result, pathEnd):
        result = result[0 ..< pathStart] & newImport & result[pathEnd .. ^1]
        break

proc rewriteImports(
  oldImport: string,
  newImport: string,
): int {.raises: [CatchableError].} =
  ## Search all .nim files for import oldImport and replace.
  ## Returns the number of files modified.
  let nimFiles = findNimFiles(".")
  var modifiedCount = 0

  for fpath in nimFiles:
    var content: string
    try:
      content = readFile(fpath)
    except CatchableError:
      continue

    if oldImport notin content:
      continue

    # Process line by line
    var newLines: seq[string]
    var changed = false
    for line in content.splitLines(keepEol = true):
      if oldImport in line and
         (line.strip().startsWith("import ") or
          line.strip().startsWith("from ")):
        let newLine = replaceImportPath(line, oldImport, newImport)
        if newLine != line:
          changed = true
        newLines.add(newLine)
      else:
        newLines.add(line)

    if changed:
      inc modifiedCount
      writeFile(fpath, newLines.join(""))

  modifiedCount

# ═══════════════════════════════════════════════════════════════════════
# Dry-run printer
# ═══════════════════════════════════════════════════════════════════════

proc printAction(verb, target, detail: string) =
  let suffix = if detail.len > 0: "  (" & detail & ")" else: ""
  echo "  ", verb.alignLeft(10), " ", target, suffix

# ═══════════════════════════════════════════════════════════════════════
# Main orchestrator
# ═══════════════════════════════════════════════════════════════════════

type
  CliOptions = object
    oldPath: string
    newPath: string
    symbols: seq[string]
    move: bool
    doRewriteImports: bool
    dryRun: bool
    mapPath: string

proc parseArgs(): CliOptions {.raises: [CatchableError].} =
  ## Parse command-line arguments.
  result = CliOptions(
    mapPath: DefaultMapPath,
  )

  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    case arg
    of "--old":
      inc i
      result.oldPath = paramStr(i)
    of "--new":
      inc i
      result.newPath = paramStr(i)
    of "--symbols":
      inc i
      let symStr = paramStr(i)
      for s in symStr.split(","):
        let trimmed = s.strip()
        if trimmed.len > 0:
          result.symbols.add(trimmed)
    of "--move":
      result.move = true
    of "--rewrite-imports":
      result.doRewriteImports = true
    of "--dry-run":
      result.dryRun = true
    of "--map":
      inc i
      result.mapPath = paramStr(i)
    of "--cst":
      stderr.writeLine("Note: --cst flag is not supported in the Nim port; ",
                       "using regex-based extraction.")
    else:
      stderr.writeLine("Unknown argument: ", arg)
      quit(1)
    inc i

proc main() {.raises: [CatchableError].} =
  let opts = parseArgs()

  # Validate required arguments
  if opts.oldPath.len == 0:
    stderr.writeLine("Error: --old is required")
    quit(1)
  if opts.newPath.len == 0:
    stderr.writeLine("Error: --new is required")
    quit(1)

  if opts.dryRun and not opts.move:
    stderr.writeLine(
      "Note: --dry-run without --move only prints a plan. " &
      "Add --move to see the full dry-run output.")

  # ── 1. Validate inputs ──────────────────────────────────────────
  if not fileExists(opts.oldPath):
    stderr.writeLine("Error: source file does not exist: ", opts.oldPath)
    quit(1)

  if fileExists(opts.newPath):
    stderr.writeLine("Error: destination file already exists: ", opts.newPath)
    quit(1)

  # Ensure destination parent directory exists
  let newParent = parentDir(opts.newPath)
  if newParent.len > 0 and not dirExists(newParent):
    if opts.dryRun:
      printAction("MKDIR", newParent, "")
    elif opts.move:
      createDir(newParent)

  # ── 2. Read source file ─────────────────────────────────────────
  let sourceText = readFile(opts.oldPath)

  # ── 3. Extract symbols (regex mode) ─────────────────────────────
  var sourceLines: seq[string]
  for line in sourceText.splitLines(keepEol = true):
    sourceLines.add(line)

  let (extractedText, foundNames) = extractSymbols(sourceLines, opts.symbols)

  if extractedText.strip().len == 0:
    stderr.writeLine("Error: no content extracted (check symbol names)")
    quit(1)

  let symLabel = if foundNames.len > 0: foundNames.join(", ")
                 else: "(all content)"
  echo "Symbols to move: ", symLabel, "  [parser=regex]"

  # ── 4. Compute import paths ─────────────────────────────────────
  let (newImportPath, newModuleName) = nimImportPath(opts.newPath)
  let (oldImportPath, _) = nimImportPath(opts.oldPath)

  # ── 5. Generate content ─────────────────────────────────────────
  let newFileContent = makeNewFileContent(extractedText, opts.oldPath, foundNames)
  let stubContent = makeForwardingStub(newImportPath, newModuleName)

  # ── 6. Migration map ────────────────────────────────────────────
  var mapData = loadMap(opts.mapPath)
  let added = appendMapping(mapData, opts.oldPath, opts.newPath,
                            oldImportPath, newImportPath)

  # ── 7. Print plan ───────────────────────────────────────────────
  echo ""
  echo "=".repeat(60)
  echo "  OLD:  ", opts.oldPath
  echo "  NEW:  ", opts.newPath
  echo "  IMPORT OLD: ", oldImportPath
  echo "  IMPORT NEW: ", newImportPath
  echo "=".repeat(60)
  echo ""

  if not opts.move:
    printAction("DRY-RUN", "(--move not set — no files written)", "")
    echo ""
    printAction("WOULD WRITE", opts.newPath,
                $newFileContent.len & " bytes")
    printAction("WOULD WRITE", opts.oldPath, "forwarding stub")
    if added:
      printAction("WOULD UPDATE", opts.mapPath, "append mapping")
    if opts.doRewriteImports:
      printAction("WOULD REWRITE", "imports",
                  "import " & oldImportPath & " -> " & newImportPath)
    return

  # ── 8. Execute — write new file ─────────────────────────────────
  if not opts.dryRun:
    writeFile(opts.newPath, newFileContent)
  printAction("CREATE", opts.newPath, $newFileContent.len & " bytes")

  # ── 9. Execute — write to old path ──────────────────────────────
  if not opts.dryRun:
    writeFile(opts.oldPath, stubContent)
  printAction("OVERWRITE", opts.oldPath, "forwarding stub")

  # ── 10. Execute — update migration map ──────────────────────────
  if opts.dryRun:
    let verb = if added: "UPDATE" else: "SKIP (dup)"
    printAction(verb, opts.mapPath, "")
  else:
    if added:
      saveMap(mapData, opts.mapPath)
      printAction("UPDATE", opts.mapPath, "appended mapping")
    else:
      printAction("SKIP", opts.mapPath, "duplicate entry")

  # ── 11. Execute — rewrite imports ───────────────────────────────
  if opts.doRewriteImports:
    if opts.dryRun:
      printAction("REWRITE", "imports",
                  "import " & oldImportPath & " -> " & newImportPath)
    else:
      let count = rewriteImports(oldImportPath, newImportPath)
      printAction("REWRITE", "imports", $count & " file(s) modified")

  # ── 12. Summary ─────────────────────────────────────────────────
  echo ""
  echo "=".repeat(60)
  echo "  DONE" & (if opts.dryRun: " (dry-run)" else: "")
  echo "=".repeat(60)

when isMainModule:
  main()
{.pop.}
