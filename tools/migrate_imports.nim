import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/shared_types
import std/[os, strutils, json, algorithm]
const
  SrcDirs = ["src", "tests"]
func fileToNimImport(filePath: string): string =
  ## Convert a source-tree file path to a Nim import path.
  ## ``src/core/io/file_utils.nim`` → ``core/io/file_utils``
  # Normalize path separators and split on '/'.
  let normalized = filePath.replace('\\', '/')
  var segments: seq[string] = @[]
  for s in normalized.split('/'):
    if s.len > 0:
      segments.add(s)

  # Strip leading ``src/`` directory if present.
  if segments.len > 0 and segments[0] == "src":
    segments = segments[1..^1]

  # Strip ``.nim`` extension from the last component.
  if segments.len > 0 and segments[^1].endsWith(".nim"):
    segments[^1] = segments[^1][0..^5]

  result = segments.join("/")
func buildImportMapping(mappings: JsonNode): seq[(string, string)] =
  ## Return ``(old_nim_import, new_nim_import)`` pairs from the JSON data.
  result = @[]
  for entry in mappings:
    let oldPath = entry["old"].getStr()
    let newPath = entry["new"].getStr()
    result.add((fileToNimImport(oldPath), fileToNimImport(newPath)))
func nimImportVariants(importPath: string): seq[string] =
  ## Return the canonical ``/``-form and the dotted ``.``-form.
  result = @[importPath]
  let dotted = importPath.replace("/", ".")
  if dotted != importPath:
    result.add(dotted)
func boundaryReplace(line, old, new: string): (string, int) =
  ## Replace all occurrences of `old` with `new` in `line`, but only when
  ## `old` appears as a complete module path token (boundary-aware).
  ## Returns the modified line and the number of replacements made.
  result = (line, 0)
  if old.len == 0:
    return

  var output = ""
  var count = 0
  var i = 0
  while i < line.len:
    # Try to match `old` starting at position i.
    var matched = false
    if i + old.len <= line.len:
      var matchesHere = true
      for j in 0 ..< old.len:
        if line[i + j] != old[j]:
          matchesHere = false
          break
      if matchesHere:
        # Check lookbehind: char before must NOT be in PathInterior.
        var lookbehindOk = true
        if i > 0:
          let prev = line[i - 1]
          if prev in Letters or prev in Digits or prev == '_' or prev == '/' or prev == '.':
            lookbehindOk = false
        # Check lookahead: char after must NOT be in PathInterior.
        var lookaheadOk = true
        let afterPos = i + old.len
        if afterPos < line.len:
          let nxt = line[afterPos]
          if nxt in Letters or nxt in Digits or nxt == '_' or nxt == '/' or nxt == '.':
            lookaheadOk = false
        if lookbehindOk and lookaheadOk:
          output.add(new)
          i += old.len
          inc count
          matched = true
    if not matched:
      output.add(line[i])
      inc i

  result = (output, count)
proc findNimFiles(projectRoot: string): seq[string] {.axiomEffect: IoEffect.} =
  ## Return sorted list of all ``.nim`` files under ``src/`` and ``tests/``.
  result = @[]
  for d in SrcDirs:
    let dirPath = projectRoot / d
    if not dirExists(dirPath):
      continue
    for path in walkDirRec(dirPath, yieldFilter = {pcFile}):
      if path.endsWith(".nim"):
        result.add(path)
  result.sort()
proc emitStderr(msg: string) {.axiomEffect: IoEffect.} =
  ## Write a line to stderr.
  write(stderr, msg & "\n")
proc processFile(filepath: string; importMapping: seq[(string, string)];
                 dryRun: bool): int {.axiomEffect: IoEffect.} =
  ## Process a single ``.nim`` file, rewriting old import paths.
  ## Returns the number of individual import references that were updated.
  result = 0
  var content: string
  try:
    content = readFile(filepath)
  except CatchableError:
    return 0

  var lines = content.splitLines()

  # Sort mapping keys longest-first so that ``core/file_utils/helper``
  # is replaced before ``core/file_utils``, preventing partial matches
  # on already-processed text.
  var sortedMappings = importMapping
  sortedMappings.sort(proc (a, b: (string, string)): int =
    b[0].len - a[0].len
  )

  var newLines: seq[string] = @[]
  var updatedCount = 0

  for line in lines:
    var newLine = line

    # Only touch lines that carry import semantics.
    let stripped = line.strip()
    let isImportLine = stripped.startsWith("import ") or
                       stripped.startsWith("from ") or
                       stripped.startsWith("include ")

    if not isImportLine:
      newLines.add(line)
      continue

    for (oldPath, newPath) in sortedMappings:
      let oldVariants = nimImportVariants(oldPath)
      let newVariants = nimImportVariants(newPath)

      for i in 0 ..< oldVariants.len:
        let oldVariant = oldVariants[i]
        let newVariant = newVariants[i]
        let (replacement, count) = boundaryReplace(newLine, oldVariant, newVariant)
        if count > 0:
          newLine = replacement
          updatedCount += count

    newLines.add(newLine)

  if updatedCount > 0 and not dryRun:
    try:
      writeFile(filepath, newLines.join("\n"))
    except CatchableError: # axiom:best-effort(write failure is non-fatal; batch migration continues)
      discard

  result = updatedCount
proc main() {.axiomEffect: IoEffect.} =
  let params = commandLineParams()
  var dryRun = false
  var targets: seq[string] = @[]

  # --- Parse arguments ---
  var i = 0
  while i < params.len:
    case params[i]
    of "--dry-run":
      dryRun = true
    of "--target":
      inc i
      while i < params.len and not params[i].startsWith("--"):
        targets.add(expandFilename(params[i]))
        inc i
    of "--help", "-h":
      echo "Usage: migrate_imports.nim [--dry-run] [--target FILE [FILE ...]]"
      echo "  --dry-run          Preview changes without modifying files"
      echo "  --target FILE ...  Only process specified file(s)"
      quit(0)
    else:
      emitStderr("Unknown option: " & params[i])
      quit(1)
    inc i

  # --- Locate project root (parent of tools/) ---
  let projectRoot = getAppDir().parentDir
  let migrationMapPath = projectRoot / "data" / "migration_map.json"

  # --- Load migration map ---
  if not fileExists(migrationMapPath):
    emitStderr("Error: migration map not found at " & migrationMapPath)
    quit(1)

  var migrationData: JsonNode
  try:
    migrationData = parseFile(migrationMapPath)
  except CatchableError:
    emitStderr("Error: failed to parse migration map JSON")
    quit(1)

  let mappings = migrationData["mappings"]
  let importMapping = buildImportMapping(mappings)

  if importMapping.len == 0:
    emitStderr("No mappings found in migration map.")
    quit(1)

  echo "Loaded " & $importMapping.len & " migration mapping(s):"
  for (old, newPath) in importMapping:
    echo "  " & old & "  ->  " & newPath
  echo ""

  # --- Collect target files ---
  var nimFiles: seq[string]
  if targets.len > 0:
    nimFiles = targets
    for f in nimFiles:
      if not fileExists(f):
        emitStderr("Warning: target file not found: " & f)
  else:
    nimFiles = findNimFiles(projectRoot)

  if nimFiles.len == 0:
    emitStderr("No .nim files found to process.")
    quit(1)

  # --- Process ---
  var totalUpdates = 0
  var filesUpdated = 0
  var filesUnchanged = 0

  for filepath in nimFiles:
    let count = processFile(filepath, importMapping, dryRun)
    if count > 0:
      inc filesUpdated
      totalUpdates += count
      let relPath = filepath.relativePath(projectRoot)
      let prefix = if dryRun: "[DRY RUN] Would update" else: "Updated"
      echo "  " & prefix & " " & $count & " import(s) in " & relPath
    else:
      inc filesUnchanged

  # --- Summary ---
  echo ""
  let mode = if dryRun: "DRY RUN: " else: ""
  echo mode & "Summary: " & $totalUpdates & " import(s) updated in " &
       $filesUpdated & " file(s), " & $filesUnchanged & " file(s) unchanged."

  if dryRun and filesUpdated > 0:
    echo "\nRun without --dry-run to apply changes."

when isMainModule:
  main()
