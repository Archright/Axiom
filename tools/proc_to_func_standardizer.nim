## Phase D1-A: Convert proc→func in original files that have shadow counterparts.
## Scans src/ for *_shadow.nim files, compares with originals, and if the ONLY
## differences are proc→func (plus trailing blank), applies the conversion and
## deletes the shadow.
##
## Usage:
##   nim c -o:bin/proc_to_func_standardizer tools/proc_to_func_standardizer.nim
##   bin/proc_to_func_standardizer --dry-run
##   bin/proc_to_func_standardizer --apply

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[algorithm, os, osproc, strutils]

const
  ShadowSuffix = "_shadow.nim"
  MaxDiffLines = 5
  StubMaxLines = 5

type
  Candidate = object
    shadowPath: string
    origPath: string
    origLines: int
    diffLines: int
    isStub: bool

  Report = object
    candidates: seq[Candidate]
    converted: seq[string]
    manualReview: seq[string]
    skippedStubs: int
    skippedDivergent: int
    failedCheck: seq[string]

proc log(msg: string) =
  stderr.writeLine("proc_to_func_standardizer: ", msg)

proc normalizeForDiff(content: string): string =
  result = content
  result = result.replace("func ", "proc ")
  var lines = result.splitLines()
  for i in 0 ..< lines.len:
    lines[i] = lines[i].strip(leading = false, trailing = true, chars = {' ', '\t'})
  result = lines.join("\n")

proc diffLineCount(a, b: string): int =
  let na = a.splitLines()
  let nb = b.splitLines()
  var i = 0
  var j = 0
  while i < na.len or j < nb.len:
    if i < na.len and j < nb.len:
      if na[i] == nb[j]:
        inc i
        inc j
      else:
        inc result
        inc i
        inc j
    elif i < na.len:
      inc result
      inc i
    else:
      inc result
      inc j

proc findShadowFiles(srcDir: string): seq[string] =
  for path in walkDirRec(srcDir):
    if path.endsWith(ShadowSuffix):
      result.add(path)
  result.sort()

proc shadowToOriginal(shadowPath: string): string =
  let (dir, name, ext) = splitFile(shadowPath)
  if name.endsWith("_shadow"):
    result = dir / (name[0 .. ^("_shadow".len + 1)] & ext)
  else:
    result = shadowPath

proc buildCandidate(shadowPath: string): Candidate =
  let origPath = shadowToOriginal(shadowPath)
  result.shadowPath = shadowPath
  result.origPath = origPath

  if not fileExists(origPath):
    result.isStub = true
    result.diffLines = MaxDiffLines + 1
    return

  let origContent = readFile(origPath)
  let shadowContent = readFile(shadowPath)

  let origLines = origContent.splitLines().len
  result.origLines = origLines

  if origLines <= StubMaxLines:
    result.isStub = true
    result.diffLines = 0
    return

  # Also skip files with no proc/func declarations (true forwarding stubs)
  let hasProcDecl = origContent.contains("proc ") or origContent.contains("func ")
  if not hasProcDecl:
    result.isStub = true
    result.diffLines = 0
    return

  let normalizedShadow = normalizeForDiff(shadowContent)
  let normalizedOrig = origContent

  result.diffLines = diffLineCount(normalizedShadow, normalizedOrig)

proc applyConversion(origPath: string): string =
  let content = readFile(origPath)
  var lines = content.splitLines()
  var newLines: seq[string]
  for line in lines:
    let stripped = line.strip()
    if stripped.startsWith("proc "):
      let leading = line[0 ..< (line.len - stripped.len)]
      newLines.add(leading & "func " & stripped[5 .. ^1])
    else:
      newLines.add(line)
  let trail = if content.endsWith("\n"): "\n" else: ""
  result = newLines.join("\n") & trail

proc nimCheck(filePath: string): bool =
  let nimExe = findExe("nim")
  if nimExe.len == 0:
    log("ERROR: nim not found in PATH")
    return false
  let logFile = getTempDir() / "p2f_check.log"
  let cmd = nimExe & " check --hints:off --warnings:off " & quoteShell(filePath) &
            " > " & quoteShell(logFile) & " 2>&1"
  let exitCode = execCmd(cmd)
  result = exitCode == 0

proc main() =
  var dryRun = true
  var apply = false
  var limit = 0

  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg == "--dry-run":
      dryRun = true
      apply = false
    elif arg == "--apply":
      apply = true
      dryRun = false
    elif arg == "--limit" and i < paramCount():
      limit = parseInt(paramStr(i + 1))

  if not apply:
    dryRun = true

  let toolDir = parentDir(currentSourcePath())
  let repoRoot = parentDir(toolDir)
  let srcDir = repoRoot / "src"

  log("Scanning " & srcDir & " for shadow files...")
  let shadows = findShadowFiles(srcDir)
  log("Found " & $shadows.len & " shadow files")

  var report = Report()

  for shadowPath in shadows:
    let cand = buildCandidate(shadowPath)
    if cand.isStub:
      inc report.skippedStubs
      continue
    if cand.diffLines > MaxDiffLines:
      inc report.skippedDivergent
      report.manualReview.add(cand.origPath)
      continue
    report.candidates.add(cand)

  log($report.candidates.len & " clean candidates (<=" & $MaxDiffLines & " diff lines)")
  log($report.skippedStubs & " forwarding stubs skipped")
  log($report.skippedDivergent & " divergent files (manual review)")

  if dryRun:
    log("")
    log("=== DRY RUN - no changes will be made ===")
    log("")
    for cand in report.candidates:
      let rel = cand.origPath.relativePath(repoRoot)
      log("  CANDIDATE: " & rel & " (" & $cand.origLines & " lines, " & $cand.diffLines & " diffs)")
    log("")
    log("Run with --apply to convert and delete shadows.")
  else:
    log("")
    log("=== APPLY MODE ===")
    log("")
    if limit > 0:
      log("LIMIT: first " & $limit & " files only")

    for idx, cand in report.candidates:
      if limit > 0 and idx >= limit:
        log("Stopped at limit (" & $limit & " files)")
        break
      let rel = cand.origPath.relativePath(repoRoot)
      log("Processing " & rel & "...")

      let modified = applyConversion(cand.origPath)
      writeFile(cand.origPath, modified)

      if nimCheck(cand.origPath):
        log("  PASS - applying conversion")
        report.converted.add(rel)
        removeFile(cand.shadowPath)
      else:
        log("  FAIL - reverting")
        report.failedCheck.add(rel)
        discard execCmd("git checkout -- " & quoteShell(cand.origPath))

    log("")
    log("=== SUMMARY ===")
    log("Converted: " & $report.converted.len)
    log("Failed (reverted): " & $report.failedCheck.len)
    log("Manual review: " & $report.manualReview.len)

  echo "{"
  echo "  \"candidates\": ", $report.candidates.len, ","
  echo "  \"converted\": ", $report.converted.len, ","
  echo "  \"failedCheck\": ", $report.failedCheck.len, ","
  echo "  \"manualReview\": ", $report.manualReview.len, ","
  echo "  \"skippedStubs\": ", $report.skippedStubs, ","
  echo "  \"skippedDivergent\": ", $report.skippedDivergent, ","
  echo "  \"dryRun\": ", $dryRun, ","
  echo "  \"candidateFiles\": ["
  for i, cand in report.candidates:
    let comma = if i < report.candidates.len - 1: "," else: ""
    echo "    \"", cand.origPath.relativePath(repoRoot), "\"", comma
  echo "  ],"
  echo "  \"convertedFiles\": ["
  for i, f in report.converted:
    let comma = if i < report.converted.len - 1: "," else: ""
    echo "    \"", f, "\"", comma
  echo "  ],"
  echo "  \"failedFiles\": ["
  for i, f in report.failedCheck:
    let comma = if i < report.failedCheck.len - 1: "," else: ""
    echo "    \"", f, "\"", comma
  echo "  ],"
  echo "  \"manualReviewFiles\": ["
  for i, f in report.manualReview:
    let comma = if i < report.manualReview.len - 1: "," else: ""
    echo "    \"", f, "\"", comma
  echo "  ]"
  echo "}"

when isMainModule:
  main()
