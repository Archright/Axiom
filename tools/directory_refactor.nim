## directory_refactor — Deterministic Directory Refactoring Tool
##
## Moves files/directories and automatically updates all import paths
## that reference them. Produces identical output for identical input (deterministic).
##
## Usage:
##   directory_refactor --mapping MAP_FILE [--src-root DIR] [--dry-run] [--execute] [--verify]
##
## Exit codes:
##   0 = success
##   1 = validation / configuration error
##   2 = destination conflict
##   3 = verify failure (nim check errors)

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[json, os, osproc, parseopt, sequtils, strutils, algorithm, sets]
import import_resolver
import safe_move

# ── Types ──────────────────────────────────────────────────────────────

type
  MoveEntry = object
    fromDir: string        # source directory prefix (no trailing slash)
    toDir: string          # destination directory prefix (no trailing slash)
    files: seq[string]     # specific filenames to move (empty = all)
    description: string    # human-readable description

  ImportRewrite = object
    filePath: string       # absolute path of file containing the import
    lineIndex: int         # 0-based line index
    oldImport: string      # the raw import token before rewrite
    newImport: string      # the raw import token after rewrite
    oldLine: string        # original line content
    newLine: string        # rewritten line content

  FileMove = object
    srcPath: string        # absolute source path
    dstPath: string        # absolute destination path
    description: string    # inherited from MoveEntry

  RefactorPlan = object
    moves: seq[FileMove]
    rewrites: seq[ImportRewrite]
    affectedFiles: seq[string]  # files that need import rewriting (deduped, sorted)

  Config = object
    mappingPath: string
    srcRoot: string
    dryRun: bool
    execute: bool
    verify: bool

# ── Helpers ────────────────────────────────────────────────────────────

proc normalizePrefix(p: string): string =
  ## Strip leading/trailing slashes from a directory prefix.
  result = p.replace('\\', '/')
  while result.startsWith("/"):
    result = result[1 .. ^1]
  while result.endsWith("/"):
    result = result[0 .. ^2]
  while "//" in result:
    result = result.replace("//", "/")

proc warning(msg: string) =
  stderr.writeLine("[directory_refactor] WARNING: ", msg)

proc error(msg: string) =
  stderr.writeLine("[directory_refactor] ERROR: ", msg)

proc collectNimFiles(dir: string): seq[string] =
  ## Recursively collect all .nim files under dir. Uses walkPattern to avoid
  ## walkDir/walkDirRec tuple-ambiguity with std/json.
  result = @[]
  for filePath in walkPattern(dir / "**/*.nim"):
    result.add(filePath)
  result.sort(cmp)

proc collectNimFilesFlat(dir: string): seq[string] =
  ## Collect .nim files in a single directory (non-recursive).
  result = @[]
  for filePath in walkPattern(dir / "*.nim"):
    result.add(filePath)
  result.sort(cmp)

# ── Mapping Loading ───────────────────────────────────────────────────

proc loadMapping(path: string): seq[MoveEntry] =
  ## Load and validate the JSON mapping file.
  ## Returns sorted entries (deterministic order).
  if not fileExists(path):
    error("Mapping file not found: " & path)
    quit(1)

  let content = readFile(path)
  let root = parseJson(content)

  if not root.hasKey("moves"):
    error("Mapping JSON must have a 'moves' array")
    quit(1)

  let moves = root["moves"]
  if moves.kind != JArray:
    error("'moves' must be a JSON array")
    quit(1)

  result = @[]
  for item in moves:
    if not item.hasKey("from") or not item.hasKey("to"):
      error("Each move must have 'from' and 'to' fields")
      quit(1)

    var entry = MoveEntry()
    entry.fromDir = normalizePrefix(item["from"].getStr())
    entry.toDir = normalizePrefix(item["to"].getStr())
    entry.description = item{"description"}.getStr("")

    if item.hasKey("files") and item["files"].kind == JArray:
      for f in item["files"]:
        let fname = f.getStr().strip()
        if fname.len > 0:
          entry.files.add(fname)
      entry.files.sort(cmp)

    if entry.fromDir.len == 0 or entry.toDir.len == 0:
      error("Empty 'from' or 'to' path in mapping")
      quit(1)

    if entry.fromDir == entry.toDir:
      warning("Skipping self-move: " & entry.fromDir)
      continue

    result.add(entry)

  result.sort(proc (a, b: MoveEntry): int =
    cmp(a.fromDir, b.fromDir)
  )

# ── Validation ────────────────────────────────────────────────────────

proc validateMapping(moves: seq[MoveEntry], srcRoot: string): seq[string] =
  ## Check that all source paths in the mapping actually exist.
  result = @[]
  for entry in moves:
    if entry.files.len > 0:
      for fname in entry.files:
        let srcPath = srcRoot / entry.fromDir / fname
        if not fileExists(srcPath):
          result.add("Source file not found: " & srcPath)
    else:
      let srcDir = srcRoot / entry.fromDir
      if not dirExists(srcDir):
        result.add("Source directory not found: " & srcDir)

proc checkDestConflicts(moves: seq[MoveEntry], srcRoot: string): seq[string] =
  ## Check that no destination file already exists.
  result = @[]
  for entry in moves:
    if entry.files.len > 0:
      for fname in entry.files:
        let dstPath = srcRoot / entry.toDir / fname
        if fileExists(dstPath):
          result.add("Destination already exists: " & dstPath)
    else:
      let srcDir = srcRoot / entry.fromDir
      if dirExists(srcDir):
        for nimFile in collectNimFilesFlat(srcDir):
          let fname = nimFile.extractFilename()
          let dstPath = srcRoot / entry.toDir / fname
          if fileExists(dstPath):
            result.add("Destination already exists: " & dstPath)

# ── Plan Building ─────────────────────────────────────────────────────

proc buildFileMoves(moves: seq[MoveEntry], srcRoot: string): seq[FileMove] =
  ## Build the list of file moves from the mapping.
  result = @[]
  for entry in moves:
    if entry.files.len > 0:
      for fname in entry.files:
        var fm = FileMove()
        fm.srcPath = srcRoot / entry.fromDir / fname
        fm.dstPath = srcRoot / entry.toDir / fname
        fm.description = entry.description
        result.add(fm)
    else:
      let srcDir = srcRoot / entry.fromDir
      if dirExists(srcDir):
        var fileNames: seq[string] = @[]
        for nimFile in collectNimFilesFlat(srcDir):
          fileNames.add(nimFile.extractFilename())
        fileNames.sort(cmp)
        for fname in fileNames:
          var fm = FileMove()
          fm.srcPath = srcRoot / entry.fromDir / fname
          fm.dstPath = srcRoot / entry.toDir / fname
          fm.description = entry.description
          result.add(fm)

  result.sort(proc (a, b: FileMove): int =
    cmp(a.srcPath, b.srcPath)
  )

proc buildImportRewrites(moves: seq[MoveEntry], srcRoot: string,
                          fileMoves: seq[FileMove]): seq[ImportRewrite] =
  ## Scan all .nim files and find imports that need rewriting.
  result = @[]

  # Build lookup: old prefix -> new prefix
  var prefixMap: seq[tuple[oldPrefix: string, newPrefix: string]] = @[]
  for entry in moves:
    prefixMap.add((entry.fromDir, entry.toDir))

  # Sort by longest old prefix first (most specific match wins)
  prefixMap.sort(proc (a, b: tuple[oldPrefix: string, newPrefix: string]): int =
    let lenDiff = b.oldPrefix.len - a.oldPrefix.len
    if lenDiff != 0: return lenDiff
    return cmp(a.oldPrefix, b.oldPrefix)
  )

  # Collect all source paths from file moves for quick lookup
  var movePathSet = initHashSet[string]()
  for fm in fileMoves:
    movePathSet.incl(fm.srcPath)

  # Scan all .nim files under srcRoot
  let filesToScan = collectNimFiles(srcRoot)

  for filePath in filesToScan:
    var content: string
    try:
      content = readFile(filePath)
    except IOError:
      warning("Cannot read file: " & filePath)
      continue

    let lines = content.splitLines()
    var fileRewrites: seq[ImportRewrite] = @[]

    # Parse imports using import_resolver
    let rawImports = parseRawImports(content)

    # For each raw import, check if it matches any from prefix
    for rawImport in rawImports:
      for pm in prefixMap:
        let oldPrefix = pm.oldPrefix
        let newPrefix = pm.newPrefix

        # Check if this import starts with the old prefix
        if rawImport.startsWith(oldPrefix & "/") or rawImport == oldPrefix:
          var newImport: string
          if rawImport == oldPrefix:
            newImport = newPrefix
          else:
            newImport = newPrefix & "/" & rawImport[(oldPrefix.len + 1) .. ^1]

          # Find the line containing this import
          for lineIdx, line in lines:
            if rawImport in line or (rawImport & ".nim") in line:
              var rewrite = ImportRewrite()
              rewrite.filePath = filePath
              rewrite.lineIndex = lineIdx
              rewrite.oldImport = rawImport
              rewrite.newImport = newImport
              rewrite.oldLine = line
              rewrite.newLine = line.replace(rawImport, newImport)
              fileRewrites.add(rewrite)
              break  # One rewrite per import token

          break  # First matching prefix wins

    result.add(fileRewrites)

  # Deterministic sort: by file path, then line index
  result.sort(proc (a, b: ImportRewrite): int =
    let pathCmp = cmp(a.filePath, b.filePath)
    if pathCmp != 0: return pathCmp
    cmp(a.lineIndex, b.lineIndex)
  )

proc buildPlan(moves: seq[MoveEntry], srcRoot: string): RefactorPlan =
  ## Build the complete refactoring plan.
  result.moves = buildFileMoves(moves, srcRoot)
  result.rewrites = buildImportRewrites(moves, srcRoot, result.moves)

  # Collect unique affected files
  var affected = initHashSet[string]()
  for rw in result.rewrites:
    affected.incl(rw.filePath)
  for aPath in affected:
    result.affectedFiles.add(aPath)
  result.affectedFiles.sort(cmp)

# ── Dry-Run Output ────────────────────────────────────────────────────

proc printDryRun(plan: RefactorPlan) =
  echo "=== Directory Refactor Dry-Run Report ==="
  echo ""

  echo "Moves to execute:"
  for fm in plan.moves:
    echo "  ", fm.srcPath, " -> ", fm.dstPath
  echo ""

  echo "Import rewrites:"
  var currentFile = ""
  for rw in plan.rewrites:
    if rw.filePath != currentFile:
      currentFile = rw.filePath
      echo ""
      echo "  ", currentFile
    echo "    :", $(rw.lineIndex + 1)
    echo "    - ", rw.oldLine.strip()
    echo "    + ", rw.newLine.strip()
  echo ""

  echo "Summary: ", $plan.moves.len, " files to move, ",
       $plan.rewrites.len, " imports to rewrite across ",
       $plan.affectedFiles.len, " files"

# ── Execute ────────────────────────────────────────────────────────────

proc executeMoves(plan: RefactorPlan, srcRoot: string) =
  ## Perform all file moves and import rewrites.
  ## Moves are done first, then rewrites.

  # Phase 1: Move files
  echo "[directory_refactor] Moving files..."
  for fm in plan.moves:
    let dstDir = fm.dstPath.dirName()
    if not dirExists(dstDir):
      createDir(dstDir)
      echo "  mkdir: ", dstDir
    safeMoveFile(fm.srcPath, fm.dstPath)
    echo "  move: ", fm.srcPath, " -> ", fm.dstPath

  # Phase 2: Rewrite imports
  echo "[directory_refactor] Rewriting imports..."
  var rewrittenFiles: seq[string] = @[]

  # Group rewrites by file (already sorted)
  var i = 0
  while i < plan.rewrites.len:
    let filePath = plan.rewrites[i].filePath
    var content: string
    try:
      content = readFile(filePath)
    except IOError:
      warning("Cannot read file for rewriting: " & filePath)
      while i < plan.rewrites.len and plan.rewrites[i].filePath == filePath:
        inc i
      continue

    var lines = content.splitLines()
    var fileModified = false

    while i < plan.rewrites.len and plan.rewrites[i].filePath == filePath:
      let rw = plan.rewrites[i]
      if rw.lineIndex < lines.len:
        if rw.oldImport in lines[rw.lineIndex]:
          lines[rw.lineIndex] = lines[rw.lineIndex].replace(rw.oldImport, rw.newImport)
          fileModified = true
        else:
          warning("Line " & $((rw.lineIndex + 1)) & " in " & filePath &
                  " no longer contains '" & rw.oldImport & "' -- skipping rewrite")
      inc i

    if fileModified:
      let newContent = lines.join("\n")
      writeFile(filePath, newContent)
      rewrittenFiles.add(filePath)
      echo "  rewrite: ", filePath

  echo "[directory_refactor] Done. Moved ", $plan.moves.len, " files, ",
       "rewrote ", $rewrittenFiles.len, " files."

# ── Verify ─────────────────────────────────────────────────────────────

proc verifyAfterRewrite(plan: RefactorPlan): seq[string] =
  ## Re-scan and confirm no old paths remain in imports.
  result = @[]

  var oldImportsSeen = initHashSet[string]()
  for rw in plan.rewrites:
    oldImportsSeen.incl(rw.oldImport)

  for filePath in plan.affectedFiles:
    if not fileExists(filePath):
      result.add("Affected file missing after rewrite: " & filePath)
      continue

    var content: string
    try:
      content = readFile(filePath)
    except IOError:
      result.add("Cannot read affected file: " & filePath)
      continue

    let rawImports = parseRawImports(content)
    for rawImport in rawImports:
      if rawImport in oldImportsSeen:
        result.add("Leftover old import in " & filePath & ": " & rawImport)

proc runNimCheck(files: seq[string]): seq[string] =
  ## Run `nim check` on each file. Returns list of error strings.
  result = @[]
  for filePath in files:
    let (output, exitCode) = execCmdEx("nim check " & quoteShell(filePath))
    if exitCode != 0:
      result.add(filePath & ":\n" & output.strip())

# ── Argument Parsing ──────────────────────────────────────────────────

proc parseArgs(): Config =
  result.dryRun = true  # Default mode
  result.srcRoot = "src"
  result.execute = false
  result.verify = false
  result.mappingPath = ""

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "mapping":
        result.mappingPath = p.val
      of "src-root":
        result.srcRoot = p.val
      of "dry-run":
        result.dryRun = true
        result.execute = false
      of "execute":
        result.execute = true
        result.dryRun = false
      of "verify":
        result.verify = true
      else:
        discard
    of cmdArgument:
      if result.mappingPath.len == 0:
        result.mappingPath = p.key

# ── Main ───────────────────────────────────────────────────────────────

proc main() =
  let config = parseArgs()

  if config.mappingPath.len == 0:
    stderr.writeLine("Usage: directory_refactor --mapping MAP_FILE [--src-root DIR] [--dry-run] [--execute] [--verify]")
    stderr.writeLine("")
    stderr.writeLine("Deterministic directory refactoring: moves files and rewrites all imports.")
    stderr.writeLine("")
    stderr.writeLine("Options:")
    stderr.writeLine("  --mapping FILE   JSON file with move mappings (required)")
    stderr.writeLine("  --src-root DIR   Source root directory (default: src)")
    stderr.writeLine("  --dry-run        Show what would change without modifying files (default)")
    stderr.writeLine("  --execute        Perform the moves and import rewrites")
    stderr.writeLine("  --verify         After execute, run nim check on affected files")
    quit(1)

  # Phase 1: Load and validate mapping
  let moves = loadMapping(config.mappingPath)
  if moves.len == 0:
    stderr.writeLine("[directory_refactor] No valid moves in mapping. Exiting.")
    quit(1)

  let srcRoot = config.srcRoot
  if not dirExists(srcRoot):
    error("Source root directory not found: " & srcRoot)
    quit(1)

  # Validate source paths exist
  let validationErrors = validateMapping(moves, srcRoot)
  if validationErrors.len > 0:
    for err in validationErrors:
      error(err)
    quit(1)

  # Check destination conflicts (for execute mode)
  if config.execute:
    let conflicts = checkDestConflicts(moves, srcRoot)
    if conflicts.len > 0:
      for c in conflicts:
        error(c)
      stderr.writeLine("[directory_refactor] Destination conflicts detected. Aborting.")
      quit(2)

  # Phase 2: Build plan
  let plan = buildPlan(moves, srcRoot)

  if config.dryRun:
    printDryRun(plan)
    quit(0)

  if config.execute:
    # Phase 3: Execute
    executeMoves(plan, srcRoot)

    # Phase 4: Post-rewrite verification (always runs after execute)
    let leftoverErrors = verifyAfterRewrite(plan)
    if leftoverErrors.len > 0:
      for err in leftoverErrors:
        error(err)
      stderr.writeLine("[directory_refactor] Post-rewrite verification FAILED.")
      stderr.writeLine("  Old import paths still detected. Manual review needed.")
      quit(3)
    else:
      echo "[directory_refactor] Post-rewrite verification passed."

    # Phase 5: Optional nim check verification
    if config.verify and plan.affectedFiles.len > 0:
      echo "[directory_refactor] Running nim check on ", $plan.affectedFiles.len, " files..."
      let checkErrors = runNimCheck(plan.affectedFiles)
      if checkErrors.len > 0:
        stderr.writeLine("[directory_refactor] nim check FAILED on ", $checkErrors.len, " file(s):")
        for err in checkErrors:
          stderr.writeLine("  ", err)
        stderr.writeLine("")
        stderr.writeLine("Suggested rollback:")
        stderr.writeLine("  1. Use `git checkout -- <affected-files>` to restore imports")
        stderr.writeLine("  2. Move files back manually: ", srcRoot, "/<to>/ -> ", srcRoot, "/<from>/")
        quit(3)
      else:
        echo "[directory_refactor] nim check passed on all affected files."

    echo "[directory_refactor] Refactoring complete."

when isMainModule:
  main()
