import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/shared_types
import std/algorithm
import std/json
import std/options
import std/os
import std/osproc
import std/re
import std/sets
import std/strtabs
import std/strutils
import std/tables
import std/times
import safe_move
axiomIoBoundary()

const
  WorkDirRel = "build/nimcache/auto_raises"
  ReportDirRel = "docs/history/reports"
  StateFileRel = "tools/ci/.raises_pipeline_state.json"
  VirtualEntryRel = "src/core/virtual_raises_main.nim"

  ForbiddenPragmas: array[5, string] = [
    "{.importc", "{.importcpp", "{.dynlib", "{.callback", "{.closure"
  ]

# Regex must be `let` (runtime) to avoid Nim 2.x VM cast limitation
let raisesErrorRe = re("^(?P<file>.+\\.nim)\\((?P<line>\\d+),\\s*\\d+\\)\\s+Error:\\s+'(?P<proc>[^']+)'\\s+can raise an? unlisted exception")
let raisesCleanup1Re = re("\\s*\\{\\.raises: \\[\\]\\.\\}")
let RaisesErrorRe = re("^(?P<file>.+\\.nim)\\((?P<line>\\d+),\\s*\\d+\\)\\s+Error:\\s+'(?P<proc>[^']+)'\\s+can raise an? unlisted exception")
let RaisesCleanup1Re = re("\\s*\\{\\.raises: \\[\\]\\.\\}")
let RaisesCleanup2Re = re(",\\s*raises: \\[\\]\\.")
let RaisesCleanup3Re = re("raises: \\[\\]\\.,?\\s*")
let ProcDeclRe = re("\\s*(?:proc|func|method)\\s+(`?[a-zA-Z_`][a-zA-Z_0-9`]*`?)")
let BodyStartRe = re("(?<!\\w)\\s*=\\s*(?:#.*)?$")

# std/re compatibility shim (Nim 2.x std/re lacks RegexMatch)
type RegexMatch = object
  first, last: int
  captures: array[32, string]
  numCaptures: int
proc find(s: string, pattern: Regex, m: var RegexMatch): bool =
  var caps: array[32, string]
  let bounds = findBounds(s, pattern, caps)
  m.first = bounds.first
  m.last = bounds.last
  m.numCaptures = 0
  if bounds.first >= 0:
    for i in 0..<caps.len:
      m.captures[i] = caps[i]
      m.numCaptures = i + 1
    return true
  return false
proc group(m: RegexMatch, idx: int, s: string): string =
  if idx == 0:
    if m.first >= 0: return s[m.first .. m.last]
    return ""
  if idx - 1 < m.numCaptures:
    return m.captures[idx - 1]
  return ""
proc log(msg: string) =
  echo msg
proc ensureDirs(repoRoot: string) =
  let workDir = repoRoot / WorkDirRel
  let reportDir = repoRoot / ReportDirRel
  if not dirExists(workDir):
    createDir(workDir)
  if not dirExists(reportDir):
    createDir(reportDir)
proc getCoreFiles(repoRoot: string): seq[string] =
  let coreDir = repoRoot / "src/core"
  for path in walkDirRec(coreDir):
    if not path.endsWith(".nim"):
      continue
    # Exclude test directories and hidden dirs
    let (_, dirPart, _) = splitFile(path)
    if "tests" in dirPart or "/_" in dirPart:
      continue
    result.add(path)
  result.sort()
proc extractProcInfo(line: string): Option[(string, string)] =
  var m: RegexMatch
  if line.find(ProcDeclRe, m):
    let kind = line.strip().split(' ')[0]
    let name = m.group(0, line).replace("`", "")
    return some((kind, name))
  none((string, string))
proc alreadyHasRaises(lineIdx: int, lines: seq[string]): bool =
  let limit = min(lineIdx + 8, lines.len)
  for i in lineIdx ..< limit:
    if "{.raises" in lines[i]:
      return true
    let stripped = lines[i].strip()
    if stripped.endsWith("=") and not stripped.startsWith("#"):
      break
  false
proc hasForbiddenPragma(lineIdx: int, lines: seq[string]): bool =
  let limit = min(lineIdx + 8, lines.len)
  for i in lineIdx ..< limit:
    for p in ForbiddenPragmas:
      if p in lines[i]:
        return true
    let stripped = lines[i].strip()
    if stripped.endsWith("=") and not stripped.startsWith("#"):
      break
  false
proc findBodyStartLine(lineIdx: int, lines: seq[string]): Option[int] =
  let limit = min(lineIdx + 10, lines.len)
  for i in lineIdx ..< limit:
    let stripped = lines[i].strip()
    if stripped.startsWith("#"):
      continue
    var m: RegexMatch
    if lines[i].find(BodyStartRe, m):
      return some(i)
    if "{.raises" in lines[i]:
      return none(int)
  none(int)
proc lineInsideMainModuleBlock(lines: seq[string], idx: int): bool =
  for i in countdown(idx, 0):
    let stripped = lines[i].strip()
    if stripped.startsWith("when isMainModule"):
      return true
    if stripped.startsWith("when defined(testing)"):
      return true
  false
proc insertRaisesInLine(line: string): string =
  let stripped = line.strip()

  # Case 1: Line has existing pragma block ending in .} =
  # e.g., `{.gcsafe.} =` or `): string {.gcsafe.} =`
  var m: RegexMatch
  let pragmaRe = re("^(.+)(\\{[^}]*\\.\\})\\s*(=\\s*(?:#.*)?)$")
  if stripped.find(pragmaRe, m):
    let prefix = m.group(0, stripped)
    let pragma = m.group(1, stripped)
    let rest = m.group(2, stripped)
    let newPragma = pragma[0 .. ^3] & ", raises: [].}"
    return prefix & newPragma & " " & rest

  # Case 2: Simple trailing `=` (most common)
  let simpleRe = re("^(.+?)(\\s*=\\s*(?:#.*)?)$")
  if stripped.find(simpleRe, m):
    let prefix = m.group(0, stripped)
    let rest = m.group(1, stripped)
    return prefix & " {.raises: [].}" & rest

  stripped
type
  InsertEntry = object
    file: string
    declLine: int
    bodyLine: int
    kind: string
    procName: string
proc bulkInsert(repoRoot: string, files: seq[string], whitelist: var HashSet[string]): (int, seq[InsertEntry], HashSet[string]) =
  var inserted = 0
  var insertLog: seq[InsertEntry]
  var skipped: HashSet[string]

  for filePath in files:
    try:
      let content = readFile(filePath)
      let lines = content.splitLines()
      var newLines = lines
      var changed = false

      for idx, line in lines:
        let info = extractProcInfo(line)
        if info.isNone:
          continue
        let (kind, name) = info.get()

        if lineInsideMainModuleBlock(lines, idx):
          continue

        let modPath = filePath.relativePath(repoRoot)
        let entry = modPath & ":" & name

        if whitelist.contains(entry):
          continue

        if alreadyHasRaises(idx, lines):
          skipped.incl(entry)
          continue

        if hasForbiddenPragma(idx, lines):
          skipped.incl(entry)
          continue

        let bodyLineOpt = findBodyStartLine(idx, lines)
        if bodyLineOpt.isNone:
          skipped.incl(entry)
          continue
        let bodyLine = bodyLineOpt.get()

        let original = newLines[bodyLine]
        let modified = insertRaisesInLine(original)
        if modified != original:
          newLines[bodyLine] = modified
          insertLog.add(InsertEntry(
            file: filePath,
            declLine: idx + 1,
            bodyLine: bodyLine + 1,
            kind: kind,
            procName: name
          ))
          changed = true
          inc inserted

      if changed:
        let newContent = newLines.join("\n")
        let trail = if content.endsWith("\n"): "\n" else: ""
        writeFile(filePath, newContent & trail)
    except CatchableError as e:
      stderr.writeLine("WARNING: error processing ", filePath, ": ", e.msg)

  (inserted, insertLog, skipped)
proc generateVirtualEntryPoint(repoRoot: string, files: seq[string]) {.axiomEffect: IoEffect.} =
  var imports = @["# Generated by auto_insert_raises.nim. Do not commit."]
  for filePath in files:
    let rel = filePath.relativePath(repoRoot / "src")
    let modPath = rel.changeFileExt("").replace('/', '.')
    imports.add("import " & modPath)
  writeFile(repoRoot / VirtualEntryRel, imports.join("\n") & "\n")
proc runProjectLevelCheck(repoRoot: string): string {.axiomEffect: IoEffect.} =
  let workDir = repoRoot / WorkDirRel
  let nimcache = workDir / "nc_raises"
  if dirExists(nimcache):
    removeDir(nimcache)

  let nimExe = findExe("nim")
  let cmd = nimExe & " check --errorMax:0 --hints:off --warnings:off " &
    "--nimcache:" & nimcache & " " & repoRoot / VirtualEntryRel

  let execResult = execCmdEx(cmd, workingDir = repoRoot)
  execResult.output
proc parseRaisesErrors(output: string): seq[(string, int, string)] =
  var seen: HashSet[(string, string)]
  for line in output.splitLines():
    let trimmed = line.strip()
    var m: RegexMatch
    if trimmed.find(raisesErrorRe, m):
      let file = m.group(0, trimmed)
      let lineNum = parseInt(m.group(1, trimmed))
      let procName = m.group(2, trimmed)
      let key = (file, procName)
      if not seen.contains(key):
        seen.incl(key)
        result.add((file, lineNum, procName))
proc removeRaisesFromProc(repoRoot: string, filePath: string, procName: string): bool =
  if not fileExists(filePath):
    return false
  try:
    let content = readFile(filePath)
    let lines = content.splitLines()
    var newLines = lines
    var changed = false

    for idx, line in lines:
      let info = extractProcInfo(line)
      if info.isSome and info.get()[1] == procName:
        let bodyIdx = findBodyStartLine(idx, lines)
        if bodyIdx.isSome:
          let bi = bodyIdx.get()
          if "{.raises: [].}" in newLines[bi]:
            let old = newLines[bi]
            var newLine = old.replace(raisesCleanup1Re, "")
            newLine = newLine.replace(RaisesCleanup2Re, ".")
            newLine = newLine.replace(RaisesCleanup3Re, "")
            if newLine != old:
              newLines[bi] = newLine
              changed = true

    if changed:
      let trail = if content.endsWith("\n"): "\n" else: ""
      writeFile(filePath, newLines.join("\n") & trail)
    changed
  except CatchableError:
    false
proc rollbackRaises(repoRoot: string, errors: seq[(string, int, string)]): HashSet[string] =
  for (filePath, _, procName) in errors:
    if removeRaisesFromProc(repoRoot, filePath, procName):
      let modPath = filePath.relativePath(repoRoot)
      result.incl(modPath & ":" & procName)
proc countRemainingErrors(output: string): int =
  for line in output.splitLines():
    if ")" in line and "Error:" in line:
      inc result
proc loadCheckpoint(repoRoot: string): (int, HashSet[string]) =
  let stateFile = repoRoot / StateFileRel
  if not fileExists(stateFile):
    return (0, initHashSet[string]())
  try:
    let data = parseJson(readFile(stateFile))
    let iteration = data.getOrDefault("iteration").getInt(0)
    var whitelist = initHashSet[string]()
    for entry in data.getOrDefault("raises_whitelist"):
      whitelist.incl(entry.getStr())
    (iteration, whitelist)
  except CatchableError:
    stderr.writeLine("WARNING: checkpoint file corrupted, starting from scratch")
    (0, initHashSet[string]())
proc saveCheckpoint(repoRoot: string, iteration: int, whitelist: HashSet[string]) =
  var entries: seq[string] = @[]
  for w in whitelist:
    entries.add(w)
  entries.sort()

  let state = %*{
    "stage": "Phase_4_Convergence",
    "last_successful_iteration": iteration,
    "raises_whitelist": entries
  }
  let stateFile = repoRoot / StateFileRel
  let tmpFile = stateFile & ".tmp"
  writeFile(tmpFile, $state & "\n")
  safeMoveFile(tmpFile, stateFile)
proc generateReport(repoRoot: string, files: seq[string], insertLog: seq[InsertEntry],
    whitelist: HashSet[string], iterations: int, otherErrors: seq[string]): string =
  let reportDir = repoRoot / ReportDirRel
  let dateStr = now().format("yyyy'_'MM'_'dd")
  let reportPath = reportDir / "auto_raises_report_" & dateStr & ".md"

  var lines: seq[string] = @[]
  lines.add("# {.raises: [].} Auto-Insertion Report — " & now().format("yyyy-MM-dd'T'HH:mm:ss"))
  lines.add("")
  lines.add("## Summary")
  lines.add("")
  lines.add("| Metric | Count |")
  lines.add("|--------|-------|")
  lines.add("| Files scanned | " & $files.len & " |")
  lines.add("| Procs annotated with {.raises: [].} | " & $insertLog.len & " |")
  lines.add("| Whitelist entries (can raise) | " & $whitelist.len & " |")
  lines.add("| Iterations to convergence | " & $iterations & " |")
  lines.add("")
  lines.add("## Annotated Procedures")
  lines.add("")

  let limit = min(50, insertLog.len)
  for i in 0 ..< limit:
    let entry = insertLog[i]
    lines.add("- `" & entry.file & ":" & $entry.declLine & "` — `" & entry.kind & " " & entry.procName & "`")
  if insertLog.len > 50:
    lines.add("- ... and " & $(insertLog.len - 50) & " more")

  lines.add("")
  lines.add("## Whitelist (procs that can raise)")
  lines.add("")
  lines.add("```")
  var sortedWl: seq[string] = @[]
  for w in whitelist:
    sortedWl.add(w)
  sortedWl.sort()
  for w in sortedWl:
    lines.add(w)
  lines.add("```")
  lines.add("")
  lines.add("## Non-Raises Errors (manual review)")
  lines.add("")
  if otherErrors.len > 0:
    let errLimit = min(20, otherErrors.len)
    for i in 0 ..< errLimit:
      lines.add("- " & otherErrors[i])
    if otherErrors.len > 20:
      lines.add("- ... and " & $(otherErrors.len - 20) & " more")
  else:
    lines.add("(none)")
  lines.add("")

  writeFile(reportPath, lines.join("\n"))
  reportPath
proc runPipeline(dryRun, reset: bool): int {.axiomEffect: IoEffect.} =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)
  ensureDirs(repoRoot)
  let files = getCoreFiles(repoRoot)

  log("=== {.raises: [].} Auto-Insertion Pipeline ===")
  log("Scope: " & $files.len & " files")
  log("Work dir: " & (repoRoot / WorkDirRel))
  log("")

  let stateFile = repoRoot / StateFileRel
  if reset and fileExists(stateFile):
    removeFile(stateFile)
    log("[reset] Checkpoint cleared.")

  let (startIteration, whitelist) = loadCheckpoint(repoRoot)
  var iteration = startIteration
  var wl = whitelist

  var insertLog: seq[InsertEntry] = @[]

  if iteration == 0:
    log("Phase 1: Bulk insertion of {.raises: [].}...")
    if dryRun:
      var count = 0
      for filePath in files:
        try:
          let lines = readFile(filePath).splitLines()
          for idx, line in lines:
            let info = extractProcInfo(line)
            if info.isNone:
              continue
            if lineInsideMainModuleBlock(lines, idx):
              continue
            if alreadyHasRaises(idx, lines):
              continue
            if hasForbiddenPragma(idx, lines):
              continue
            if findBodyStartLine(idx, lines).isSome:
              inc count
        except CatchableError:
          discard  # axiom:best-effort(file processing error)
      log("  [DRY-RUN] Would insert {.raises: [].} into " & $count & " proc declarations")
    else:
      let (inserted, logEntries, skipped) = bulkInsert(repoRoot, files, wl)
      for s in skipped:
        wl.incl(s)
      insertLog = logEntries
      log("  Inserted {.raises: [].} into " & $inserted & " proc declarations (" & $skipped.len & " skipped)")
    log("")

    if dryRun:
      discard generateReport(repoRoot, files, insertLog, wl, 0, @[])
      log("Report generated.")
      return 0
  else:
    log("Resuming from checkpoint: iteration " & $iteration & ", " & $wl.len & " whitelist entries")

  log("Generating project-level virtual entry point...")
  generateVirtualEntryPoint(repoRoot, files)

  var otherErrors: seq[string] = @[]
  let maxIterations = 20

  while true:
    inc iteration
    log("Phase 2/3: Iteration " & $iteration & " — compiler check + error classification...")

    let output = runProjectLevelCheck(repoRoot)
    let raisesErrors = parseRaisesErrors(output)
    let totalErrors = countRemainingErrors(output)

    log("  " & $totalErrors & " compiler errors found, " & $raisesErrors.len & " classified as raises violations.")

    if raisesErrors.len == 0:
      if totalErrors == 0:
        log("  Convergence reached: zero compiler errors.")
      else:
        log("  No rollbackable raises errors remain but other errors present.")
        for line in output.splitLines():
          if ")" in line and "Error:" in line:
            var m: RegexMatch
            if not line.find(raisesErrorRe, m):
              otherErrors.add(line)
      break

    if dryRun:
      log("  [DRY-RUN] Would rollback raises annotations from failing procs")
      break

    let newEntries = rollbackRaises(repoRoot, raisesErrors)
    for e in newEntries:
      wl.incl(e)
    log("  Rolled back {.raises: [].} from " & $newEntries.len & " procs.")

    saveCheckpoint(repoRoot, iteration, wl)

    if iteration >= maxIterations:
      log("  WARNING: Max iterations reached (" & $maxIterations & "). Stopping.")
      break

  # Cleanup virtual entry point
  let virtualPath = repoRoot / VirtualEntryRel
  if fileExists(virtualPath):
    removeFile(virtualPath)

  if not dryRun:
    if fileExists(stateFile):
      removeFile(stateFile)
    let report = generateReport(repoRoot, files, insertLog, wl, iteration, otherErrors)
    log("")
    log("Pipeline complete.")
    log("  " & $insertLog.len & " procs annotated with {.raises: [].}")
    log("  " & $wl.len & " procs whitelisted (can raise)")
    log("  Report: " & report)

  if otherErrors.len > 0:
    log("")
    log("WARNING: Non-raises errors remain and require manual review:")
    let limit = min(10, otherErrors.len)
    for i in 0 ..< limit:
      log("  " & otherErrors[i])
    if otherErrors.len > 10:
      log("  ... and " & $(otherErrors.len - 10) & " more")
    return 1

  0
proc main() {.axiomEffect: IoEffect.} =
  var dryRun = false
  var reset = false
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg == "--dry-run":
      dryRun = true
    elif arg == "--reset":
      reset = true
  quit(runPipeline(dryRun, reset))

when isMainModule:
  main()
