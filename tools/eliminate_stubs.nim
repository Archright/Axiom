import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, sequtils, algorithm, sets, tables]

const
  StubMarker = "Forwarding Module"
  PreserveFiles = ["axiom_catalog_validator.nim", "constants.nim", "domain_types.nim",
    "file_utils.nim", "io_utils.nim", "io_utils_isolation.nim", "json.nim",
    "layer_guard.nim", "metrics.nim", "results.nim", "safe_parsers.nim",
    "std_redirect.nim", "text_utils.nim", "type_registry.nim", "verified_axioms_catalog.nim"]
  SkipDirs = [".git", "vendor", "build", "logs"]

type
  StubMapping = Table[string, string]

proc isPreserveFile(fpath: string): bool =
  let fname = extractFilename(fpath)
  let parent = fpath.parentDir.absolutePath
  let srcRoot = absolutePath("src")
  if fname in PreserveFiles and parent == srcRoot:
    return true
  result = false

proc nimModulePath(fpath: string): string =
  let srcRoot = absolutePath("src")
  let rel = fpath.relativePath(srcRoot)
  result = rel.changeFileExt("").replace(DirSep, '/')

proc scanStubs(): tuple[mapping: StubMapping; stubPaths: Table[string, string]] =
  result.mapping = initTable[string, string]()
  result.stubPaths = initTable[string, string]()
  let srcRoot = absolutePath("src")
  for path in walkDirRec(srcRoot):
    if not path.endsWith(".nim"):
      continue
    let rel = path.relativePath(srcRoot)
    if rel.count(DirSep) != 1:
      continue
    if isPreserveFile(path):
      continue
    try:
      let content = readFile(path)
      let lines = content.splitLines
      var found = false
      for i in 0 ..< min(3, lines.len):
        if StubMarker in lines[i]:
          found = true
          break
      if not found:
        continue
      let importLine = lines[0].strip
      if not importLine.startsWith("import "):
        continue
      let newPath = importLine[7..^1].strip
      if newPath.startsWith("std/") or newPath.startsWith("compiler/"):
        continue
      let oldPath = nimModulePath(path)
      result.mapping[oldPath] = newPath
      result.stubPaths[oldPath] = path
    except CatchableError:
      discard  # axiom:best-effort(unreadable-import-path: skip this mapping, continue processing)

proc rewriteLine(line: string; mapping: StubMapping): string =
  result = line
  # Handle bracket imports: prefix/[a, b, c]
  var i = 0
  while i < result.len:
    let bracketOpen = result.find("/[", i)
    if bracketOpen < 0:
      break
    let prefixStart = bracketOpen - 1
    if prefixStart < 0 or result[prefixStart] notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '/'}:
      i = bracketOpen + 1
      continue
    var prefixStartIdx = prefixStart
    while prefixStartIdx >= 0 and result[prefixStartIdx] in {'a'..'z', 'A'..'Z', '0'..'9', '_', '/'}:
      dec prefixStartIdx
    inc prefixStartIdx
    let prefix = result[prefixStartIdx ..< bracketOpen + 1]  # includes "/"
    let bracketClose = result.find("]", bracketOpen + 2)
    if bracketClose < 0:
      break
    let itemsStr = result[bracketOpen + 2 ..< bracketClose]
    var items = itemsStr.split(",")
    var changed = false
    var newItems: seq[string] = @[]
    for item in items:
      let stripped = item.strip
      if stripped.len == 0:
        newItems.add(item)
        continue
      let fullPath = prefix & stripped
      if mapping.hasKey(fullPath):
        let newFull = mapping[fullPath]
        var newStripped = newFull
        if newFull.startsWith(prefix):
          newStripped = newFull[prefix.len ..^ 1]
        newItems.add(newStripped)
        changed = true
      else:
        newItems.add(item)
    if changed:
      let before = result[0 ..< prefixStartIdx]
      let after = result[bracketClose + 1 ..^ 1]
      result = before & prefix & "[" & newItems.join(",") & "]" & after
      i = prefixStartIdx + prefix.len + 1 + newItems.join(",").len + 1
    else:
      i = bracketClose + 1

  # Handle simple imports
  var start = 0
  while start < result.len:
    if result[start] in {'a'..'z', 'A'..'Z', '0'..'9', '_', '/'}:
      var endIdx = start + 1
      while endIdx < result.len and result[endIdx] in {'a'..'z', 'A'..'Z', '0'..'9', '_', '/'}:
        inc endIdx
      let word = result[start ..< endIdx]
      if mapping.hasKey(word):
        let before = result[0 ..< start]
        let after = result[endIdx ..^ 1]
        result = before & mapping[word] & after
        start = start + mapping[word].len
        continue
    inc start

proc isContinuationStart(line: string): bool =
  let stripped = line.strip
  if stripped == "import":
    return true
  if stripped.startsWith("from ") and stripped.endsWith(" import"):
    return true
  result = false

proc endsWithComma(line: string): bool =
  var s = line.strip
  let hashPos = s.find('#')
  if hashPos >= 0:
    s = s[0 ..< hashPos].strip
  result = s.endsWith(",")

proc processFile(filepath: string; mapping: StubMapping; dryRun: bool): tuple[changed: bool; diffs: seq[tuple[oldLine, newLine: string]]] =
  result.changed = false
  result.diffs = @[]
  try:
    let content = readFile(filepath)
    var lines = content.splitLines
    var newLines: seq[string] = @[]
    var inContinuation = false
    for line in lines:
      if inContinuation:
        let newLine = rewriteLine(line, mapping)
        if newLine != line:
          result.changed = true
          result.diffs.add((line, newLine))
        newLines.add(newLine)
        if not endsWithComma(line):
          inContinuation = false
        continue
      let isImportLine = line.strip.startsWith("import ") or line.strip.startsWith("from ")
      if isImportLine:
        let newLine = rewriteLine(line, mapping)
        if newLine != line:
          result.changed = true
          result.diffs.add((line, newLine))
        newLines.add(newLine)
        if isContinuationStart(line) or endsWithComma(line):
          inContinuation = true
      else:
        newLines.add(line)
    if result.changed and not dryRun:
      writeFile(filepath, newLines.join("\n"))
  except CatchableError:
    discard  # axiom:best-effort(write-failure: stub file may be read-only or missing, continue with remaining files)

proc collectNimFiles(dirs: seq[string]): seq[string] =
  result = @[]
  for d in dirs:
    if not dirExists(d):
      continue
    for path in walkDirRec(d):
      if not path.endsWith(".nim"):
        continue
      var skip = false
      for sd in SkipDirs:
        if sd in path:
          skip = true
          break
      if not skip:
        result.add(path)
  result.sort()

proc deleteStubs(stubPaths: Table[string, string]): int =
  result = 0
  for oldPath, fpath in stubPaths.pairs:
    if not fileExists(fpath):
      continue
    if isPreserveFile(fpath):
      echo "  SKIP (preserve): " & fpath
      continue
    removeFile(fpath)
    inc result

proc main() =
  let args = commandLineParams()
  if args.contains("--help") or args.contains("-h"):
    echo "Eliminate forwarding stubs from the Axiom project."
    echo "Usage: eliminate_stubs [--dry-run|--execute|--delete-stubs]"
    quit(0)

  let execute = args.contains("--execute")
  let delete = args.contains("--delete-stubs")

  if delete and execute:
    stderr.writeLine("ERROR: --execute and --delete-stubs are mutually exclusive.")
    stderr.writeLine("       Run --execute first, verify compilation, then run --delete-stubs.")
    quit(1)

  let dryRun = not execute and not delete
  let modeLabel = if delete: "delete-stubs" elif execute: "execute" else: "dry-run"

  echo "[Phase 1] Scanning src/ for forwarding stubs ..."
  let (mapping, stubPaths) = scanStubs()
  let stubsFound = mapping.len

  if stubsFound == 0:
    echo "  No forwarding stubs found. Nothing to do."
    quit(0)

  echo "  Found " & $stubsFound & " forwarding stub(s)."
  if dryRun:
    echo ""
    echo "  Mapping (old → new):"
    for old, new in mapping.pairs:
      echo "    " & old & "  →  " & new

  if delete:
    echo "\n[Phase 3] Deleting stub files ..."
    let deleted = deleteStubs(stubPaths)
    echo "  Deleted " & $deleted & " stub file(s)."
    let allFiles = collectNimFiles(@["src", "tests"])
    echo ""
    echo repeat('=', 60)
    echo "  eliminate_stubs — " & modeLabel
    echo repeat('=', 60)
    echo "  Files scanned:       " & $allFiles.len
    echo "  Stubs detected:      " & $stubsFound
    echo "  Mapping entries:     " & $mapping.len
    echo "  Files deleted:       " & $deleted
    echo repeat('=', 60)
    quit(0)

  echo "\n[Phase 2] Scanning imports in src/ and tests/ ..."
  let allFiles = collectNimFiles(@["src", "tests"])
  var filesModified = 0
  var modifications: seq[tuple[filePath, oldLine, newLine: string]] = @[]

  for fpath in allFiles:
    let content = readFile(fpath)
    var hasMapping = false
    for key in mapping.keys:
      if key in content:
        hasMapping = true
        break
    if not hasMapping:
      continue
    let (changed, diffs) = processFile(fpath, mapping, dryRun)
    if changed:
      inc filesModified
      if dryRun:
        for (oldL, newL) in diffs:
          modifications.add((fpath, oldL, newL))

  if dryRun and modifications.len > 0:
    echo ""
    echo "  Proposed changes:"
    echo ""
    for (fp, oldL, newL) in modifications:
      echo "  " & fp
      echo "    - " & oldL.strip
      echo "    + " & newL.strip
      echo ""

  echo ""
  echo repeat('=', 60)
  echo "  eliminate_stubs — " & modeLabel
  echo repeat('=', 60)
  echo "  Files scanned:       " & $allFiles.len
  echo "  Stubs detected:      " & $stubsFound
  echo "  Mapping entries:     " & $mapping.len
  if delete:
    discard
  else:
    echo "  Files to modify:     " & $filesModified
  echo repeat('=', 60)

  if dryRun and filesModified > 0:
    echo ""
    echo "  Run with --execute to apply these changes."
    echo "  After verifying compilation, run --delete-stubs to remove stubs."

when isMainModule:
  main()
