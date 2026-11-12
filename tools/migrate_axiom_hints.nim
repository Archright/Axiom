import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/shared_types
import std/[os, strutils, sequtils, parseopt, algorithm, sets]
type
  AxiomHint* = object
    lean*: string
    smt*: string

  MigrationResult* = object
    filesScanned*: int
    hintsFound*: int
    migrationsApplied*: int
    filesSkipped*: int
    errors*: seq[string]
func isAxiomHintLine*(line: string): bool =
  ## Check if a line contains a `# @axiom-hint:` comment.
  let trimmed = line.strip()
  trimmed.startsWith("# @axiom-hint:")
func isAxiomHintContinuation*(line: string): bool =
  ## Check if a line is a continuation of a split axiom hint (Format B).
  ## Matches lines like `# smt="..."` or `# lean="..."` without the
  ## `@axiom-hint:` prefix.
  let trimmed = line.strip()
  if not trimmed.startsWith("#"):
    return false
  # Strip the leading `#` and optional space
  var rest = trimmed[1 .. ^1]
  if rest.len > 0 and rest[0] == ' ':
    rest = rest[1 .. ^1]
  rest.startsWith("smt=\"") or rest.startsWith("lean=\"")
func parseHintValue*(line: string; key: string): string =
  ## Extract a quoted value from a hint line by key name.
  ## Handles: lean="..." smt="..."
  ## The value may contain parentheses, Unicode, and other special characters.
  let trimmed = line.strip()
  let prefix = key & "=\""
  let keyIdx = trimmed.find(prefix)
  if keyIdx < 0:
    return ""

  let valueStart = keyIdx + prefix.len
  # Find the closing quote — it's the quote that follows the value.
  # Since values don't contain escaped quotes, find the next `"` after valueStart.
  # But we must be careful: the smt value may be the last thing on the line,
  # while lean is followed by ` smt="`.
  var depth = 0
  var i = valueStart
  while i < trimmed.len:
    if trimmed[i] == '(':
      inc depth
    elif trimmed[i] == ')':
      if depth > 0:
        dec depth
    elif trimmed[i] == '"' and depth == 0:
      return trimmed[valueStart ..< i]
    inc i
  # Fallback: take everything to end of line minus trailing quote
  if trimmed.len > 0 and trimmed[^1] == '"':
    return trimmed[valueStart ..< ^1]
  trimmed[valueStart .. ^1]
func parseAxiomHint*(line: string): AxiomHint =
  ## Parse a single `# @axiom-hint:` line into an AxiomHint object.
  result.lean = parseHintValue(line, "lean")
  result.smt = parseHintValue(line, "smt")
func combineHints*(hints: seq[AxiomHint]): AxiomHint =
  ## Combine multiple hints into one. Lean values joined with ` ∧ `.
  ## SMT assertions combined via `(and ...)` wrapper if multiple.
  if hints.len == 0:
    return
  if hints.len == 1:
    return hints[0]

  # Combine lean values
  var leanParts: seq[string] = @[]
  for h in hints:
    if h.lean.len > 0:
      leanParts.add(h.lean)
  result.lean = leanParts.join(" ∧ ")

  # Combine smt assertions: strip outer (assert ...) and rewrap in (and ...)
  var smtBodies: seq[string] = @[]
  for h in hints:
    if h.smt.len > 0:
      var body = h.smt.strip()
      # Strip (assert ...) wrapper: remove "(assert " prefix (8 chars) and trailing ")"
      if body.startsWith("(assert ") and body.endsWith(")"):
        body = body[8 .. ^2].strip()
        # Strip (and ...) wrapper if it wraps the entire body
        # This extracts just the arguments: (and expr1 expr2) → expr1 expr2
        if body.startsWith("(and ") and body.endsWith(")"):
          var depth = 0
          var allMatched = true
          for ci, ch in body:
            if ch == '(': inc depth
            elif ch == ')': dec depth
            if depth == 0 and ci < body.len - 1:
              allMatched = false
              break
          if allMatched:
            body = body[5 .. ^2].strip()
      smtBodies.add(body)

  if smtBodies.len == 1:
    result.smt = "(assert " & smtBodies[0] & ")"
  elif smtBodies.len > 1:
    result.smt = "(assert (and " & smtBodies.join(" ") & "))"
func findProcFuncStart*(lines: seq[string]; startIdx: int): int =
  ## Find the line index where the proc/func declaration begins.
  ## Scans forward from startIdx, skipping blank lines and comments.
  ## Only matches declaration types that can carry {.axiom:} pragmas.
  for i in startIdx ..< lines.len:
    let line = lines[i].strip()
    if line.len == 0:
      continue
    if line.startsWith("#"):
      continue
    # Only match proc/func and similar declaration types — NOT let/var/type/const
    if line.startsWith("proc ") or line.startsWith("func ") or
       line.startsWith("macro ") or line.startsWith("template ") or
       line.startsWith("iterator ") or line.startsWith("converter "):
      return i
    # Non-declaration line — no proc/func to attach pragma to
    return -1
  -1
func findProcEnd*(lines: seq[string]; procStart: int): int =
  ## Find the line that ends the proc/func signature (the line with `=` or `= \`).
  ## Returns the line index of the signature end, or -1 for forward declarations.
  ##
  ## Tracks cumulative paren/bracket depth across lines so that default parameter
  ## values like `param: Type = default` on intermediate lines are correctly skipped.
  ##
  ## For forward declarations (no `=`), returns the last line of the signature
  ## where all parens/brackets are balanced, so the caller can append the pragma.
  ## Returns -1 only if parens never balance (malformed code).
  var parenDepth = 0
  var bracketDepth = 0
  for i in procStart ..< lines.len:
    let line = lines[i]
    var j = 0
    while j < line.len:
      case line[j]
      of '(':
        inc parenDepth
      of ')':
        if parenDepth > 0:
          dec parenDepth
      of '[':
        inc bracketDepth
      of ']':
        if bracketDepth > 0:
          dec bracketDepth
      of '=':
        if parenDepth == 0 and bracketDepth == 0:
          # Check it's not `==` or `!=` or `<=` or `>=`
          let prevChar = if j > 0: line[j-1] else: ' '
          let nextChar = if j < line.len - 1: line[j+1] else: ' '
          if prevChar notin {'!', '<', '>', '='} and nextChar notin {'='}:
            return i
      else:
        discard
      inc j

    # After processing the entire line: if all parens/brackets are balanced,
    # the signature is complete. This handles:
    #   - Forward declarations: func foo*(x: int): bool  (no `=`)
    #   - Single-line procs: proc foo*(x: int): bool = ...
    # For forward declarations, return the current line so the caller
    # can append the pragma to it.
    if parenDepth == 0 and bracketDepth == 0:
      return i

  # Parens never balanced — malformed code. Return -1 to signal failure.
  -1
func hasExistingPragma*(line: string): bool =
  ## Check if a line contains an existing pragma block `{. ... .}`.
  let trimmed = line.strip()
  return "{." in trimmed and ".}" in trimmed
func insertAxiomPragma*(line: string; lean, smt: string): string =
  ## Insert `{.axiom: [...].}` before the `=` on the signature end line.
  ## Works for both single-line and multiline signature `=` lines.
  ## Uses rfind(" =") to always insert before the body assignment,
  ## correctly avoiding inner proc-type pragmas (e.g. in multiline signatures).
  let axiomPragma = "{.axiom: [\"" & smt & "\", \"" & lean & "\"].}"

  # Find the last ` =` on the line (the proc/func body assignment operator)
  let equalsIdx = line.rfind(" =")
  if equalsIdx >= 0:
    result = line[0 ..< equalsIdx] & " " & axiomPragma & line[equalsIdx .. ^1]
  else:
    # No ` =` found — append
    result = line & " " & axiomPragma
proc migrateFile*(filePath: string; apply: bool):
    tuple[hintsFound: int; modified: bool; output: string; error: string]
    {.axiomEffect: IoEffect.} =
  ## Migrate a single file. Returns (hintsFound, modified, output, error).
  result.hintsFound = 0
  result.modified = false
  result.error = ""

  var lines: seq[string]
  var fileContent: string
  try:
    fileContent = readFile(filePath)
    lines = fileContent.splitLines()
  except IOError as e:
    result.error = "Failed to read: " & e.msg
    return

  # NOTE: No longer skip files containing {.axiom: — pre-existing axiom
  # pragmas in the codebase are not affected by this tool. It only processes
  # `# @axiom-hint:` comment lines.

  var outputLines: seq[string] = @[]
  var i = 0

  while i < lines.len:
    let line = lines[i]
    let trimmed = line.strip()

    # Check if this is an axiom-hint comment line
    if isAxiomHintLine(trimmed):
      # Collect all consecutive hint lines (including Format B continuations)
      var hints: seq[AxiomHint] = @[]
      var hintLineIndices: seq[int] = @[]
      while i < lines.len:
        let curTrimmed = lines[i].strip()
        if isAxiomHintLine(curTrimmed):
          # Check if the next line is a continuation (Format B: split hint)
          if i + 1 < lines.len and isAxiomHintContinuation(lines[i + 1]):
            # Merge: parse the current line, then append the continuation
            hints.add(parseAxiomHint(lines[i] & " " & lines[i + 1].strip()))
            hintLineIndices.add(i)
            hintLineIndices.add(i + 1)
            i += 2
          else:
            hints.add(parseAxiomHint(lines[i]))
            hintLineIndices.add(i)
            inc i
        elif isAxiomHintContinuation(curTrimmed):
          # Orphan continuation line (no preceding @axiom-hint:) — treat standalone
          hints.add(parseAxiomHint(lines[i]))
          hintLineIndices.add(i)
          inc i
        else:
          break

      # Find the associated proc/func declaration
      let procIdx = findProcFuncStart(lines, i)
      if procIdx < 0:
        # No proc/func found after hints — emit warnings, keep hints
        for hi in hintLineIndices:
          outputLines.add(lines[hi])
        result.error = "Warning: No proc/func found after hints at lines " &
          hintLineIndices.mapIt($(it + 1)).join(", ")
        continue

      inc result.hintsFound

      # Combine all hints into one pragma
      let combined = combineHints(hints)
      if combined.lean.len == 0 and combined.smt.len == 0:
        # Empty hints — just remove the comment lines
        for hi in hintLineIndices:
          discard # skip hint lines
        outputLines.add(lines[procIdx])
        inc i
        continue

      # Find the end of the proc/func signature
      let procEndLine = findProcEnd(lines, procIdx)
      if procEndLine < 0:
        # Can't find signature end — keep the line as-is
        for hi in hintLineIndices:
          outputLines.add(lines[hi])
        outputLines.add(lines[procIdx])
        inc i
        continue

      # Add non-hint lines between hint group end and proc start.
      # `i` is now past the hints (first non-hint line), so lines[i..<procIdx]
      # are comments/blank lines between the hints and the proc declaration.
      for j in i ..< procIdx:
        if j notin hintLineIndices:
          outputLines.add(lines[j])

      # Add intermediate signature lines unchanged (between procIdx and procEndLine, exclusive)
      # These are the parameter lines for multiline signatures
      for j in procIdx ..< procEndLine:
        outputLines.add(lines[j])

      # Insert the axiom pragma before `=` on the end-of-signature line.
      # rfind(" =") targets the body assignment, not inner proc-type `=`
      outputLines.add(insertAxiomPragma(lines[procEndLine], combined.lean, combined.smt))

      # Mark as modified
      result.modified = true

      # Continue after the proc end line
      i = procEndLine + 1
    else:
      outputLines.add(line)
      inc i

  if result.modified and apply:
    let newContent = outputLines.join("\n")
    try:
      writeFile(filePath, newContent)
    except IOError as e:
      result.error = "Failed to write: " & e.msg
      result.modified = false

  # Build output string for dry-run display
  if result.modified:
    var diffLines: seq[string] = @[]
    for idx, line in outputLines:
      if idx < lines.len:
        if line != lines[idx]:
          diffLines.add("  ~ " & $(idx + 1) & ": " & line.strip())
      else:
        diffLines.add("  + " & $(idx + 1) & ": " & line.strip())
    result.output = diffLines.join("\n")
proc findAllNimFiles*(dir: string): seq[string]
    {.axiomEffect: IoEffect.} =
  ## Recursively find all .nim files in a directory.
  ## Excludes build output, vendor, and .git directories.
  result = @[]
  let excludeDirs = toHashSet([
    ".git", "nimcache", "build", "vendor", ".lake", ".kimi-code",
    "node_modules", ".agents", "logs"
  ])

  for kind, path in walkDir(dir):
    case kind
    of pcFile:
      if path.endsWith(".nim") and not path.extractFilename().startsWith("."):
        result.add(path)
    of pcDir:
      let dirName = path.parentDir().splitPath().tail
      if dirName notin excludeDirs:
        result.add(findAllNimFiles(path))
    else:
      discard

  result.sort()
proc main() {.axiomEffect: IoEffect.} =
  var dryRun = true
  var applyMode = false
  var scanAll = false
  var targetFile = ""
  var excludeFiles: seq[string] = @[]

  # Parse command-line arguments
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "dry-run":
        dryRun = true
        applyMode = false
      of "apply":
        dryRun = false
        applyMode = true
      of "file", "f":
        targetFile = val
      of "all", "a":
        scanAll = true
      of "exclude":
        # Support --exclude:path1,path2 or --exclude path1 --exclude path2
        for path in val.split(","):
          let trimmedPath = path.strip()
          if trimmedPath.len > 0:
            excludeFiles.add(trimmedPath)
      else:
        discard
    of cmdEnd:
      break
    else:
      discard

  if not dryRun and not applyMode:
    echo "Error: Must specify either --dry-run or --apply"
    quit(1)

  if targetFile.len == 0 and not scanAll:
    echo "Usage: migrate_axiom_hints --dry-run|--apply [--file <path>] [--all] [--exclude <path>[,<path>...]]"
    echo ""
    echo "Options:"
    echo "  --dry-run       Show what would be changed (default)"
    echo "  --apply         Write changes to files"
    echo "  --file PATH     Process a single file"
    echo "  --all           Scan all .nim files in src/"
    echo "  --exclude PATH  Comma-separated files to skip (relative to project root)"
    quit(1)

  let projectRoot = getCurrentDir()
  var files: seq[string] = @[]

  if targetFile.len > 0:
    if not fileExists(targetFile):
      echo "Error: File not found: ", targetFile
      quit(1)
    files.add(targetFile)
  elif scanAll:
    let srcDir = projectRoot / "src"
    if not dirExists(srcDir):
      echo "Error: src/ directory not found"
      quit(1)
    files = findAllNimFiles(srcDir)
    # Also scan tools/ directory
    let toolsDir = projectRoot / "tools"
    if dirExists(toolsDir):
      files.add(findAllNimFiles(toolsDir))
    files.sort()

  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Axiom Hint → Pragma Migration Tool"
  echo "  Mode: ", (if applyMode: "APPLY" else: "DRY RUN")
  echo "  Files: ", files.len
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""

  var stats = MigrationResult()
  stats.filesScanned = files.len

  for filePath in files:
    # Skip excluded files (match by suffix to handle relative/absolute paths)
    var excluded = false
    for ef in excludeFiles:
      if filePath.endsWith("/" & ef) or filePath == ef:
        excluded = true
        break
    if excluded:
      stats.filesSkipped += 1
      continue

    let relPath = filePath
    let (hintsFound, modified, output, error) = migrateFile(filePath, applyMode)

    if error.len > 0:
      stats.errors.add(relPath & ": " & error)

    if hintsFound > 0:
      stats.hintsFound += hintsFound
      if modified:
        stats.migrationsApplied += hintsFound
        echo "✓ ", relPath, " (", hintsFound, " hint", (if hintsFound > 1: "s" else: ""), " migrated)"
        if output.len > 0:
          echo output
      else:
        echo "○ ", relPath, " (", hintsFound, " hint", (if hintsFound > 1: "s" else: ""), " found, no changes)"
    else:
      stats.filesSkipped += 1

  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Summary"
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Files scanned:    ", stats.filesScanned
  echo "  Files skipped:    ", stats.filesSkipped
  echo "  Hints found:      ", stats.hintsFound
  echo "  Migrations applied: ", stats.migrationsApplied, (if dryRun: " (dry run)" else: "")
  if stats.errors.len > 0:
    echo "  Errors/warnings:  ", stats.errors.len
    for err in stats.errors:
      echo "    ⚠ ", err
  echo "═══════════════════════════════════════════════════════════════════"

main()
