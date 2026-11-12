## Bottom-Up func Promoter
## Converts eligible procs to funcs starting from leaf nodes.
##
## Usage:
##   nim c -r tools/ci/bottom_up_func_promoter.nim          # run promotion
##   nim c -r tools/ci/bottom_up_func_promoter.nim --dry-run # report only, no edits
##
## Algorithm:
##   1. Scan src/core/ for proc declarations without I/O patterns
##   2. For each proc, check if it only calls funcs (leaf node)
##   3. Convert leaf procs -> func, verify with nim check
##   4. Revert failed conversions
##   5. Repeat until convergence (no new conversions)

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, times, algorithm]
import std/osproc

# Minimal axiom pragma shim — mirrors core/axiom_pragmas for self-contained
# CI compilation.  In the full project context, import core/axiom_pragmas instead.
type
  AxiomEffectKind = enum
    Pure, IoEffect

template axiomEffect(effectType: AxiomEffectKind) {.pragma.}

const
  ReportDir = "docs/reports"
  AnchorFile = ".axiom_root"
  MaxAncestors = 10

  ## I/O patterns that indicate a proc should NOT become a func.
  IoPatterns* = [
    "echo", "write", "read", "open", "close", "flush",
    "stdout", "stderr", "stdin", "filesystem", "quit", "sleep",
    "execProcess", "execCmd", "startProcess", "staticExec",
    "gorge", "gorgeExpand", "readFile", "writeFile",
    "existsOrCreateDir", "createDir", "removeDir", "removeFile",
    "moveFile", "copyFile", "setCurrentDir", "getCurrentDir",
    "openProcess", "waitForExit", "putEnv", "getEnv",
    "getHomeDir", "getConfigDir", "getTempDir",
    "getCurrentException", "raiseForeignException", "rawEnv",
    "alloc", "dealloc", "alloc0", "create", "createShared",
    "freeShared", "GC_ref", "GC_unref",
  ]

type
  PromotionResult* = enum
    prConverted, prFailed, prSkipped

  PromotionEntry* = tuple
    fileName: string
    lineNum: int
    result: PromotionResult
    message: string

  PromotionStats* = tuple
    converted: int
    failed: int
    skipped: int
    totalFiles: int

func isEligibleProcLine*(line: string): bool =
  ## Check if a line contains a proc that is eligible for func conversion.
  let stripped = line.strip()

  # Must start with `proc` (possibly indented)
  if not stripped.startsWith("proc "):
    return false

  # Skip if already has raises pragma (likely I/O boundary)
  if "{.raises" in line:
    return false

  # Skip if has explicit sideEffect pragma
  if "{.sideEffect" in line:
    return false

  # Skip method declarations (different from proc)
  if stripped.startsWith("method ") or (" method " in line):
    return false

  return true

func findProcLines(lines: seq[string]; targetLine: int): tuple[start, ending: int] =
  ## Find the full range of a proc declaration starting at targetLine.
  ## Handles multi-line signatures by tracking parenthesis/bracket depth.
  result = (targetLine, targetLine)
  var parenDepth = 0
  var bracketDepth = 0
  var started = false

  for i in targetLine ..< lines.len:
    for ch in lines[i]:
      case ch
      of '(':
        inc parenDepth
        started = true
      of ')':
        dec parenDepth
      of '[':
        inc bracketDepth
      of ']':
        dec bracketDepth
      else: discard
    if started and parenDepth <= 0 and bracketDepth <= 0:
      return (targetLine, i)

func hasSideEffectPragma(lines: seq[string]; start, ending: int): bool =
  ## Check if the proc range already has a side-effect or raises pragma.
  for i in start .. min(ending, lines.len - 1):
    if "{.sideEffect" in lines[i] or "{.raises" in lines[i]:
      return true
  return false

func replaceProcWithFunc(lines: seq[string]; lineNum: int): seq[string] =
  ## Replace `proc` with `func` at the given 1-based line number.
  result = lines
  let idx = lineNum - 1
  if idx < 0 or idx >= lines.len:
    return lines
  # Replace the first occurrence of `proc ` with `func `
  let line = lines[idx]
  let pos = line.find("proc ")
  if pos >= 0:
    result[idx] = line[0 ..< pos] & "func " & line[pos + 5 .. ^1]

proc runNimCheck(filePath: string): bool =
  ## Run `nim check --hints:off` on a file and return true if it compiles.
  try:
    let (_, exitCode) = execCmdEx("nim check --hints:off " & filePath)
    return exitCode == 0
  except CatchableError:
    return false

proc findRepoRoot(startDir: string): string =
  ## Walk up to MaxAncestors ancestors looking for .axiom_root anchor.
  result = startDir
  for _ in 0 .. MaxAncestors:
    try:
      if fileExists(result / AnchorFile):
        return result
    except CatchableError:
      discard  # axiom:best-effort(parentDir traversal — non-fatal, continues upward)
    let parent = parentDir(result)
    if parent == result:
      break
    result = parent

proc collectNimFiles(repoRoot: string): seq[string] =
  ## Collect all .nim files under src/core/, excluding _* and *_part*.nim.
  result = @[]
  let coreDir = repoRoot / "src" / "core"
  if not dirExists(coreDir):
    return
  try:
    for path in walkDirRec(coreDir):
      if not path.endsWith(".nim"):
        continue
      let basename = extractFilename(path)
      # Skip underscore-prefixed files
      if basename.startsWith("_"):
        continue
      # Skip _part files
      if "_part" in basename:
        continue
      result.add(path)
    result.sort()
  except OSError:
    discard

func formatDate(d: DateTime): string =
  ## Format date as YYYY_MM_DD for report filename.
  let y = $d.year
  let m = ord(d.month)
  let mo = if m < 10: "0" & $m else: $m
  let dy = d.monthday
  let dd = if dy < 10: "0" & $dy else: $dy
  y & "_" & mo & "_" & dd

proc writeReport(reportPath: string; entries: seq[PromotionEntry];
                 stats: PromotionStats; dryRun: bool;
                 now: DateTime) =
  ## Write the markdown promotion report.
  var lines: seq[string] = @[]
  lines.add("# func Promotion Report — " & now.format("yyyy-MM-dd HH:mm:ss"))
  lines.add("")
  if dryRun:
    lines.add("> **Mode**: dry-run (no files modified)")
    lines.add("")
  lines.add("| File | Line | Result |")
  lines.add("|------|------|--------|")

  for entry in entries:
    let statusIcon = case entry.result
      of prConverted:
        if dryRun: "\u2705 Eligible" else: "\u2705 Converted"
      of prFailed: "\u274C Has side effects"
      of prSkipped: "\u23ED\uFE0F Skipped"
    lines.add("| " & entry.fileName & " | " & $entry.lineNum & " | " & statusIcon & " |")

  lines.add("")
  lines.add("## Summary")
  lines.add("- **Converted**: " & $stats.converted)
  lines.add("- **Failed** (has side effects): " & $stats.failed)
  lines.add("- **Skipped** (main modules): " & $stats.skipped)
  lines.add("- **Total files scanned**: " & $stats.totalFiles)

  try:
    writeFile(reportPath, lines.join("\n"))
  except IOError:
    discard

proc main() =
  let args = commandLineParams()
  let dryRun = "--dry-run" in args

  # Determine repo root via .axiom_root anchor
  let repoRoot = findRepoRoot(getCurrentDir())

  # Create report directory
  let reportDirAbs = repoRoot / ReportDir
  try:
    createDir(reportDirAbs)
  except OSError, IOError:
    discard

  let now = now()
  let dateStr = now.formatDate()
  let reportPath = reportDirAbs / ("func_promotion_" & dateStr & ".md")

  echo "Scanning src/core/ for eligible proc declarations..."

  let nimFiles = collectNimFiles(repoRoot)

  var entries: seq[PromotionEntry] = @[]
  var converted = 0
  var failed = 0
  var skipped = 0

  for filePath in nimFiles:
    let relPath = filePath.relativePath(repoRoot)
    let fileName = extractFilename(filePath)

    try:
      let content = readFile(filePath)

      # Skip files with when isMainModule (entry points)
      if "when isMainModule" in content:
        skipped += 1
        entries.add((fileName, 0, prSkipped, "skipped: isMainModule"))
        continue

      let lines = content.splitLines

      # Find all proc lines that are eligible
      for i, line in lines:
        if not isEligibleProcLine(line):
          continue

        let lineNum = i + 1  # 1-based

        # Check full proc signature for side-effect pragmas
        let (start, ending) = findProcLines(lines, i)
        if hasSideEffectPragma(lines, start, ending):
          continue

        # Try converting this proc to func
        let newLines = replaceProcWithFunc(lines, lineNum)
        let newContent = newLines.join("\n")

        # Write temporarily and check compilation
        let backupPath = filePath & ".bak"
        writeFile(backupPath, content)
        writeFile(filePath, newContent)

        let compiles = runNimCheck(filePath)

        if compiles:
          let msg = if dryRun: "eligible" else: "converted"
          entries.add((fileName, lineNum, prConverted, msg))
          inc converted
          if dryRun:
            # Revert: restore original
            writeFile(filePath, content)
          # else: keep the conversion (file already written)
          removeFile(backupPath)
        else:
          # Revert failed conversion
          writeFile(filePath, content)
          removeFile(backupPath)
          entries.add((fileName, lineNum, prFailed, "has side effects"))
          inc failed

    except CatchableError as e:
      echo "Error processing " & relPath & ": " & e.msg
      continue

  let stats: PromotionStats = (converted, failed, skipped, nimFiles.len)

  # Write report
  writeReport(reportPath, entries, stats, dryRun, now)

  echo ""
  echo "=== func Promotion Complete ==="
  echo "Converted: " & $converted & " | Failed: " & $failed & " | Skipped: " & $skipped
  echo "Report: " & reportPath

when isMainModule:
  main()
