## tools/ax_hygiene_fix.nim — Idempotent stderr.writeLine/write → logging_facade migration engine.
##
## Transforms all stderr.writeLine/stderr.write calls in src/ to
## logging_facade equivalents (logInfo/logWarn/logError/logDebug).
## Uses lexicographic termination metric for deterministic finite termination.
## Self-contained: no imports from src/ (build boundary compliance).
##
## Usage:
##   nim c tools/ax_hygiene_fix.nim
##   ./tools/ax_hygiene_fix [--scan <path>] [--dry-run]

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, algorithm, hashes, sets]

# ═══════════════════════════════════════════════════════════════════════════════
# §1. Lexicographic termination (inlined from core/progress/lexicographic_terminator)
# ═══════════════════════════════════════════════════════════════════════════════

type
  LexVerdict = enum
    lvProgressReset, lvFuelBurned, lvFixedPoint, lvFuelExhausted

  LexProgressMetric = object
    unverifiedCount: int
    refinementFuel: int
    initialFuel: int
    stateHashHistory: HashSet[uint64]

proc initLexMetric(initialUnverified, initialFuel: int): LexProgressMetric =
  LexProgressMetric(
    unverifiedCount: initialUnverified,
    refinementFuel: initialFuel,
    initialFuel: initialFuel,
    stateHashHistory: initHashSet[uint64]()
  )

proc evaluate(m: var LexProgressMetric; newUnverified: int;
              stateHash: uint64): LexVerdict =
  if newUnverified < m.unverifiedCount:
    m.unverifiedCount = newUnverified
    m.refinementFuel = m.initialFuel
    m.stateHashHistory.incl(stateHash)
    return lvProgressReset
  if stateHash in m.stateHashHistory:
    return lvFixedPoint
  m.stateHashHistory.incl(stateHash)
  if m.refinementFuel <= 0:
    return lvFuelExhausted
  dec m.refinementFuel
  return lvFuelBurned

proc computeStateHash(nodeReportCount, refactorTaskCount, verifiedCount: int;
                      sourceFingerprints: openArray[string]): uint64 =
  var h: Hash = 0
  h = h !& nodeReportCount
  h = h !& refactorTaskCount
  h = h !& verifiedCount
  for fp in sourceFingerprints:
    h = h !& hash(fp)
  result = uint64(h)

# ═══════════════════════════════════════════════════════════════════════════════
# §2. Configuration
# ═══════════════════════════════════════════════════════════════════════════════

const
  toolDir = currentSourcePath().parentDir()
  projectRoot = toolDir.parentDir()

## Basenames to skip — the facade itself and this tool.
const skipBasenames = [
  "logging_facade.nim",
  "ax_hygiene_fix.nim",
]

## Top-level dir names to skip under scan path.
const skipDirNames = [
  "tools", "tests", "vendor", "build", "bin",
  ".lake", "nimcache", "node_modules"
]

# ═══════════════════════════════════════════════════════════════════════════════
# §3. Types
# ═══════════════════════════════════════════════════════════════════════════════

type
  FixStats = object
    filesScanned: int
    filesModified: int
    totalLinesChanged: int
    skippedCalls: seq[string]

# ═══════════════════════════════════════════════════════════════════════════════
# §4. File collection
# ═══════════════════════════════════════════════════════════════════════════════

proc collectNimFiles(scanPath: string): seq[string] =
  result = @[]
  if not dirExists(scanPath):
    return
  for kind, path in walkDir(scanPath):
    case kind
    of pcFile:
      if path.endsWith(".nim"):
        let base = path.extractFilename()
        if base notin skipBasenames:
          result.add(path)
    of pcDir:
      let dirName = path.extractFilename()
      if dirName.startsWith(".") or dirName in skipDirNames:
        continue
      for f in collectNimFiles(path):
        result.add(f)
    else: discard
  result.sort()

# ═══════════════════════════════════════════════════════════════════════════════
# §5. Pure helpers
# ═══════════════════════════════════════════════════════════════════════════════

proc inferModule(filePath: string): string =
  filePath.splitFile().name

proc inferLevel(argsText: string): string =
  let upper = argsText.toUpperAscii()
  if "ERROR" in upper or "FAIL" in upper or "BLOCKED" in upper:
    return "logError"
  if "WARN" in upper:
    return "logWarn"
  if "DEBUG" in upper or "TIMING" in upper:
    return "logDebug"
  return "logInfo"

proc isInsideString(text: string, pos: int): bool =
  var inSingle = false
  var inDouble = false
  var i = 0
  while i < pos and i < text.len:
    if text[i] == '\\' and (i + 1 < text.len):
      inc i
    elif not inSingle and not inDouble and text[i] == '#':
      # Skip to end of line — comment, not a string
      while i < pos and text[i] != '\n':
        inc i
      continue
    elif text[i] == '"' and not inSingle:
      inDouble = not inDouble
    elif text[i] == '\'' and not inDouble:
      # Distinguish char literals from numeric type suffixes (e.g. 65001'u32, 1'i64)
      if i > 0 and text[i - 1] in {'0'..'9', ']', ')'}:
        discard  # type suffix, not a char literal
      else:
        inSingle = not inSingle
    inc i
  return inDouble or inSingle

proc isInsideComment(text: string, pos: int): bool =
  var ls = pos
  while ls > 0 and text[ls - 1] != '\n':
    dec ls
  var i = ls
  while i < pos:
    if text[i] == '\\' and i + 1 < text.len:
      inc i
    elif text[i] == '"':
      inc i
      while i < pos and text[i] != '"':
        if text[i] == '\\': inc i
        inc i
      inc i
    elif text[i] == '#':
      return true
    else:
      inc i
  return false

# ═══════════════════════════════════════════════════════════════════════════════
# §6. Call span extraction
# ═══════════════════════════════════════════════════════════════════════════════

proc extractCallArgs(text: string, callStart: int): (string, int, bool) =
  let isWL = text[callStart ..< min(callStart + 16, text.len)] == "stderr.writeLine"
  let funcLen = if isWL: "stderr.writeLine".len
                else: "stderr.write".len

  var pos = callStart + funcLen

  while pos < text.len and text[pos] in {' ', '\t'}:
    inc pos

  if pos < text.len and text[pos] == '(':
    var depth = 1
    var inS = false
    var inD = false
    inc pos
    let contentStart = pos
    while pos < text.len and depth > 0:
      case text[pos]
      of '\\':
        inc pos
      of '"':
        inD = not inD
      of '\'':
        inS = not inS
      of '(':
        if not inS and not inD: inc depth
      of ')':
        if not inS and not inD: dec depth
      else:
        discard
      inc pos
    return (text[contentStart ..< pos - 1], pos, isWL)

  var lineEnd = pos
  while lineEnd < text.len and text[lineEnd] != '\n':
    inc lineEnd
  return (text[pos ..< lineEnd].strip(), lineEnd, isWL)

# ═══════════════════════════════════════════════════════════════════════════════
# §7. Variadic argument transformation (Pattern C)
# ═══════════════════════════════════════════════════════════════════════════════

proc hasCommaAtDepth0(argsText: string): bool =
  var depth = 0
  var inS = false
  var inD = false
  for ch in argsText:
    case ch
    of '\\':
      discard
    of '"':
      inD = not inD
    of '\'':
      inS = not inS
    of '(':
      if not inS and not inD: inc depth
    of ')':
      if not inS and not inD: dec depth
    of ',':
      if depth == 0 and not inS and not inD:
        return true
    else:
      discard
  return false

proc transformVariadicArgs(argsText: string): string =
  var parts: seq[string]
  var current = ""
  var depth = 0
  var inS = false
  var inD = false
  var i = 0
  while i < argsText.len:
    case argsText[i]
    of '\\':
      current.add(argsText[i])
      if i + 1 < argsText.len:
        current.add(argsText[i + 1])
        inc i
    of '"':
      inD = not inD
      current.add(argsText[i])
    of '\'':
      inS = not inS
      current.add(argsText[i])
    of '(':
      if not inS and not inD: inc depth
      current.add(argsText[i])
    of ')':
      if not inS and not inD: dec depth
      current.add(argsText[i])
    of ',':
      if depth == 0 and not inS and not inD:
        parts.add(current.strip())
        current = ""
      else:
        current.add(argsText[i])
    else:
      current.add(argsText[i])
    inc i
  if current.strip().len > 0:
    parts.add(current.strip())

  if parts.len <= 1:
    return argsText

  var transformed: seq[string]
  for part in parts:
    let s = part.strip()
    if s.len == 0: continue
    if s.len >= 2 and s[0] == '"' and s[^1] == '"':
      transformed.add(s)
    elif s.startsWith("&\"") and s.endsWith("\""):
      transformed.add(s)
    elif s.startsWith("fmt\"") and s.endsWith("\""):
      transformed.add("$(" & s & ")")
    elif s.startsWith("$(") and s.endsWith(")"):
      transformed.add(s)
    elif s.startsWith("$"):
      transformed.add(s)
    else:
      transformed.add("$(" & s & ")")

  if transformed.len == 0:
    return "\"\""
  return transformed.join(" & ")

# ═══════════════════════════════════════════════════════════════════════════════
# §8. Idempotency check
# ═══════════════════════════════════════════════════════════════════════════════

proc isAlreadyTransformed(text: string, pos: int): bool =
  var ls = pos
  while ls > 0 and text[ls - 1] != '\n':
    dec ls
  var le = pos
  while le < text.len and text[le] != '\n':
    inc le
  let line = text[ls ..< le]
  return "logInfo(" in line or "logWarn(" in line or
         "logError(" in line or "logDebug(" in line

# ═══════════════════════════════════════════════════════════════════════════════
# §9. Import injection
# ═══════════════════════════════════════════════════════════════════════════════

proc needsImport(content: string): bool =
  "import infrastructure/logging_facade" in content

proc addImport(content: string): string =
  if needsImport(content):
    return content

  let lines = content.splitLines()
  var lastImportEnd = -1

  for i, line in lines:
    let stripped = line.strip()
    if stripped.startsWith("import ") or stripped.startsWith("from "):
      lastImportEnd = i
    elif lastImportEnd >= 0 and i == lastImportEnd + 1:
      if lines[lastImportEnd].strip().endsWith(","):
        lastImportEnd = i

  if lastImportEnd < 0:
    var insertAt = 0
    for i, line in lines:
      let stripped = line.strip()
      if stripped.len == 0 or stripped.startsWith("##") or
         stripped.startsWith("#") or stripped.startsWith("{."):
        insertAt = i + 1
      else:
        break
    var newLines: seq[string]
    if insertAt > 0:
      newLines.add(lines[0 ..< insertAt])
    newLines.add("import infrastructure/logging_facade")
    if insertAt < lines.len and lines[insertAt].len > 0:
      newLines.add("")
    if insertAt < lines.len:
      newLines.add(lines[insertAt .. ^1])
    return newLines.join("\n")

  var newLines = lines[0 ..< lastImportEnd + 1]
  newLines.add("import infrastructure/logging_facade")
  if lastImportEnd + 1 < lines.len:
    newLines.add(lines[lastImportEnd + 1 .. ^1])
  return newLines.join("\n")

# ═══════════════════════════════════════════════════════════════════════════════
# §10. Core file transformation
# ═══════════════════════════════════════════════════════════════════════════════

proc transformFile(filePath: string, dryRun: bool,
                   stats: var FixStats): bool =
  let content = readFile(filePath)
  let moduleName = inferModule(filePath)

  var outBuf = ""
  var pos = 0
  var linesChanged = 0

  while pos < content.len:
    let wlIdx = content.find("stderr.writeLine", pos)
    let wIdx = content.find("stderr.write", pos)

    var matchIdx = -1
    var isWL = false

    if wlIdx >= 0 and (wIdx < 0 or wlIdx <= wIdx):
      matchIdx = wlIdx
      isWL = true
    elif wIdx >= 0:
      let endCheck = min(wIdx + 16, content.len)
      if content[wIdx ..< endCheck].startsWith("stderr.writeLine"):
        matchIdx = wIdx
        isWL = true
      else:
        matchIdx = wIdx
        isWL = false

    if matchIdx < 0:
      outBuf.add(content[pos .. ^1])
      break

    var skip = false
    if matchIdx > 0 and content[matchIdx - 1] in
        {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
      skip = true

    if not skip and isInsideString(content, matchIdx):
      skip = true

    if not skip and isInsideComment(content, matchIdx):
      skip = true

    if skip:
      outBuf.add(content[pos ..< matchIdx + 1])
      pos = matchIdx + 1
      continue

    if isAlreadyTransformed(content, matchIdx):
      outBuf.add(content[pos ..< matchIdx + 1])
      pos = matchIdx + 1
      continue

    var lineStart = matchIdx
    while lineStart > 0 and content[lineStart - 1] != '\n':
      dec lineStart

    let (argsText, callEnd, callIsWL) = extractCallArgs(content, matchIdx)
    isWL = callIsWL

    if argsText.strip().len == 0 and not isWL:
      stats.skippedCalls.add(
        "  " & filePath.relativePath(projectRoot) & ":" &
        $(content[0 ..< matchIdx].count('\n') + 1) &
        " — empty args, skipped for review")
      outBuf.add(content[pos ..< matchIdx + 1])
      pos = matchIdx + 1
      continue

    let level = inferLevel(argsText)

    let finalArgs = if hasCommaAtDepth0(argsText):
                      transformVariadicArgs(argsText)
                    else:
                      argsText

    let replacement = level & "(\"" & moduleName & "\", " & finalArgs & ")"

    outBuf.add(content[pos ..< lineStart])
    outBuf.add(content[lineStart ..< matchIdx])
    outBuf.add(replacement)

    pos = callEnd
    inc linesChanged

  stats.totalLinesChanged = linesChanged

  var finalContent = outBuf
  if linesChanged > 0:
    finalContent = addImport(outBuf)

  if finalContent != content:
    if not dryRun:
      writeFile(filePath, finalContent)
    return true

  return false

# ═══════════════════════════════════════════════════════════════════════════════
# §11. CLI entry point
# ═══════════════════════════════════════════════════════════════════════════════

proc main() =
  let params = commandLineParams()
  var scanPath = "src/"
  var dryRun = false

  var i = 0
  while i < params.len:
    case params[i]
    of "--scan":
      if i + 1 < params.len:
        scanPath = params[i + 1]
        inc i
    of "--dry-run":
      dryRun = true
    of "--help", "-h":
      stdout.writeLine("ax_hygiene_fix — stderr.writeLine/write → logging_facade migration")
      stdout.writeLine("")
      stdout.writeLine("Usage:")
      stdout.writeLine("  ax_hygiene_fix [--scan <path>] [--dry-run]")
      stdout.writeLine("")
      stdout.writeLine("Options:")
      stdout.writeLine("  --scan <path>  Directory to scan (default: src/)")
      stdout.writeLine("  --dry-run      Show what would change without writing")
      stdout.writeLine("  --help, -h     Show this help")
      quit(0)
    else:
      stderr.writeLine("Unknown option: " & params[i] & " (use --help)")
      quit(1)
    inc i

  echo "ax_hygiene_fix — stderr.writeLine/write → logging_facade migration"
  echo "═".repeat(60)
  echo "Scan path: " & scanPath
  echo "Dry run: " & $dryRun
  echo ""

  let files = collectNimFiles(scanPath)
  if files.len == 0:
    echo "No .nim files found under: " & scanPath
    quit(1)

  echo "Found " & $files.len & " .nim files to process"
  echo ""

  var metric = initLexMetric(files.len, files.len * 3)
  var stats = FixStats()
  stats.filesScanned = files.len

  for fi, filePath in files:
    let relPath = filePath.relativePath(projectRoot)

    var fileStats = FixStats()
    let modified = transformFile(filePath, dryRun, fileStats)

    if modified:
      inc stats.filesModified
      stats.totalLinesChanged += fileStats.totalLinesChanged
      echo "  ✓ " & relPath & " — " & $fileStats.totalLinesChanged &
           " lines transformed"

    for sc in fileStats.skippedCalls:
      stats.skippedCalls.add(sc)

    let remaining = files.len - fi - 1
    let stateHash = computeStateHash(
      remaining,
      stats.filesModified,
      fi + 1,
      [relPath]
    )
    let verdict = metric.evaluate(remaining, stateHash)
    case verdict
    of lvFixedPoint:
      echo "  ⚠ Fixed-point detected — pipeline state cycle"
      break
    of lvFuelExhausted:
      echo "  ✗ Fuel exhausted — termination guarantee triggered"
      quit(1)
    of lvProgressReset, lvFuelBurned:
      discard

  echo ""
  echo "═".repeat(60)
  echo "Summary:"
  echo "  Files scanned:     " & $stats.filesScanned
  echo "  Files modified:    " & $stats.filesModified
  echo "  Lines transformed: " & $stats.totalLinesChanged

  if stats.skippedCalls.len > 0:
    echo ""
    echo "  Skipped for manual review:"
    for sc in stats.skippedCalls:
      echo sc

  if dryRun:
    echo ""
    echo "  (dry run — no files were written)"

  echo ""

when isMainModule:
  main()
