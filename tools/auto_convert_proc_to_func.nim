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
import std/strutils
import std/times
import safe_move
axiomIoBoundary()

const
  WorkDirRel = "build/nimcache/auto_convert"
  ReportDirRel = "docs/history/reports"
  StateFileRel = "tools/ci/.purity_pipeline_state.json"
  VirtualEntryRel = "src/core/virtual_core_main.nim"

  ImpurePatterns: seq[string] = @[
    "{.importc", "{.importcpp", "{.dynlib", "{.sideEffect", "{.effectPattern",
    "axiomEffect: IoEffect", "axiomEffect(IoEffect)"
  ]

# Regex must be `let` (runtime) to avoid Nim 2.x VM cast limitation
let sideEffectRe = re("^(?P<file>.+\\.nim)\\((?P<line>\\d+),\\s*\\d+\\)\\s+Error:\\s+'(?P<func>[^']+)'\\s+can have side effects$")
let procNameRe = re("proc\\s+([a-zA-Z_`][a-zA-Z_0-9`]*)")
let procFuncDeclRe = re("^(\\s*)func\\s+(`?")
let SideEffectRe = re("^(?P<file>.+\\.nim)\\((?P<line>\\d+),\\s*\\d+\\)\\s+Error:\\s+'(?P<func>[^']+)'\\s+can have side effects$")
let ProcNameRe = re("proc\\s+([a-zA-Z_`][a-zA-Z_0-9`]*)")
let ProcFuncDeclRe = re("^(\\s*)func\\s+(`?")
let FuncEscapeRe = re("[.*+?^${}()|[\\]\\\\]")

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
    let (_, dirPart, _) = splitFile(path)
    if "tests" in dirPart or "/_" in dirPart:
      continue
    result.add(path)
  result.sort()
proc extractProcName(line: string): Option[string] =
  var m: RegexMatch
  if line.find(procNameRe, m):
    return some(m.group(0, line).replace("`", ""))
  none(string)
proc modulePathOf(filePath, repoRoot: string): string =
  filePath.relativePath(repoRoot)
proc shouldSkipLine(line: string): bool =
  not line.strip().startsWith("proc ")
proc declarationContainsImpure(lines: seq[string], startIdx: int): bool =
  let limit = min(startIdx + 8, lines.len)
  for i in startIdx ..< limit:
    let ln = lines[i]
    for p in ImpurePatterns:
      if p in ln:
        return true
    if "=" in ln and not ln.strip().startsWith("#"):
      let stripped = ln.strip()
      if stripped.endsWith("=") or "={" in stripped or stripped.endsWith("."):
        break
  false
proc lineInsideMainModuleBlock(lines: seq[string], idx: int): bool =
  for i in countdown(idx, 0):
    let stripped = lines[i].strip()
    if stripped.startsWith("when isMainModule"):
      return true
    if stripped.startsWith("when defined(testing)"):
      return true
  false
proc bulkConvert(repoRoot: string, files: seq[string], whitelist: var HashSet[string]):
    (int, seq[(string, int, string, string)], HashSet[string]) =
  var converted = 0
  var convertedLog: seq[(string, int, string, string)]
  var skipped: HashSet[string]

  for filePath in files:
    try:
      let content = readFile(filePath)
      let lines = content.splitLines()
      var newLines: seq[string]
      var changed = false

      for idx, line in lines:
        if shouldSkipLine(line):
          newLines.add(line)
          continue
        if lineInsideMainModuleBlock(lines, idx):
          newLines.add(line)
          continue
        let name = extractProcName(line)
        if name.isNone:
          newLines.add(line)
          continue
        let modPath = modulePathOf(filePath, repoRoot)
        let entry = modPath & ":" & name.get()
        if declarationContainsImpure(lines, idx):
          skipped.incl(entry)
          newLines.add(line)
          continue
        if whitelist.contains(entry):
          newLines.add(line)
          continue
        # Replace first 'proc ' with 'proc '
        let stripped = line
        let procIdx = stripped.find("proc ")
        if procIdx >= 0 and (procIdx == 0 or not stripped[procIdx-1].isAlphaNumeric()):
          let newLine = stripped[0 ..< procIdx] & "proc " & stripped[procIdx + 5 .. ^1]
          let kind = if "=" notin line: "forward_decl" else: "impl"
          convertedLog.add((filePath, idx + 1, name.get(), kind))
          changed = true
          inc converted
          newLines.add(newLine)
        else:
          newLines.add(line)

      if changed:
        let newContent = newLines.join("\n")
        let trail = if content.endsWith("\n"): "\n" else: ""
        writeFile(filePath, newContent & trail)
    except CatchableError as e:
      stderr.writeLine("WARNING: error processing ", filePath, ": ", e.msg)

  (converted, convertedLog, skipped)
proc generateVirtualEntryPoint(repoRoot: string, files: seq[string]) {.axiomEffect: IoEffect.} =
  var imports = @["# Generated by auto_convert_proc_to_func.nim. Do not commit."]
  for filePath in files:
    let rel = filePath.relativePath(repoRoot / "src")
    let modPath = rel.changeFileExt("").replace('/', '.')
    imports.add("import " & modPath)
  writeFile(repoRoot / VirtualEntryRel, imports.join("\n") & "\n")
proc runProjectLevelCheck(repoRoot: string): string {.axiomEffect: IoEffect.} =
  let workDir = repoRoot / WorkDirRel
  let nimcache = workDir / "nc_virtual_core"
  if dirExists(nimcache):
    removeDir(nimcache)

  let nimExe = findExe("nim")
  let cmd = nimExe & " check --errorMax:0 --hints:off --warnings:off " &
    "--hint:SideEffect:off --nimcache:" & nimcache & " " & repoRoot / VirtualEntryRel
  let execResult = execCmdEx(cmd, workingDir = repoRoot)
  execResult.output
proc parseSideEffectErrors(output: string): seq[(string, int, string)] =
  for line in output.splitLines():
    let trimmed = line.strip()
    var m: RegexMatch
    if trimmed.find(sideEffectRe, m):
      result.add((m.group(0, trimmed), parseInt(m.group(1, trimmed)), m.group(2, trimmed)))
proc rollbackFuncInFile(repoRoot: string, filePath: string, funcName: string): bool =
  if not fileExists(filePath):
    return false
  try:
    let content = readFile(filePath)
    let lines = content.splitLines()
    var newLines = lines
    var changed = false
    let pattern = re("^(\\s*)func\\s+(`?" & funcName.replace(FuncEscapeRe, r"\$&") & r"`?)\\b")

    for idx, line in lines:
      var m: RegexMatch
      if line.find(pattern, m):
        let prefix = m.group(0, line)
        let name = m.group(1, line)
        newLines[idx] = prefix & "proc " & name
        changed = true

    if changed:
      let trail = if content.endsWith("\n"): "\n" else: ""
      writeFile(filePath, newLines.join("\n") & trail)
    changed
  except CatchableError:
    false
proc rollbackFuncs(repoRoot: string, errors: seq[(string, int, string)]): HashSet[string] =
  for (filePath, _, funcName) in errors:
    if rollbackFuncInFile(repoRoot, filePath, funcName):
      let modPath = modulePathOf(filePath, repoRoot)
      result.incl(modPath & ":" & funcName)
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
    for entry in data.getOrDefault("impure_procedures_whitelist"):
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
    "impure_procedures_whitelist": entries
  }
  let stateFile = repoRoot / StateFileRel
  let tmpFile = stateFile & ".tmp"
  writeFile(tmpFile, $state & "\n")
  safeMoveFile(tmpFile, stateFile)
proc parseExistingWhitelist(content: string): HashSet[string] =
  var inSection = false
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped == "[impure_procedures_whitelist]":
      inSection = true
      continue
    if inSection and stripped.startsWith("[") and stripped.endsWith("]"):
      break
    if inSection:
      for match in line.findAll(re("\"([^\"]+)\"")):
        if ".nim:" in match:
          result.incl(match.strip(chars = {'"'}))
proc updateArchitecturePolicyLock(repoRoot: string, whitelist: HashSet[string]) {.axiomEffect: IoEffect.} =
  let lockPath = repoRoot / "src/gate/architecture_policy.lock"
  if not fileExists(lockPath):
    raise newException(IOError, $lockPath & " not found")

  let content = readFile(lockPath)
  let existing = parseExistingWhitelist(content)
  var merged = whitelist
  for e in existing:
    merged.incl(e)

  var entries: seq[string] = @[]
  for e in merged:
    entries.add("\"" & e & "\"")
  entries.sort()

  let sectionText = "\n[impure_procedures_whitelist]\n" &
    "# FCIS 분리 후에도 func이 불가능한 본질적 impure proc\n" &
    "# 이 목록 외에 proc이 새로 발견되면 CI 차단\n" &
    "whitelist = [" & entries.join(", ") & "]\n"

  # Remove existing sections and append new one
  var contentNoSection = content
  var sectionStart = contentNoSection.find("[impure_procedures_whitelist]")
  while sectionStart >= 0:
    # Find end of section (next [section] or EOF)
    var sectionEnd = contentNoSection.len
    var searchFrom = sectionStart + 1
    while searchFrom < contentNoSection.len:
      if contentNoSection[searchFrom] == '[' and
         (searchFrom == 0 or contentNoSection[searchFrom - 1] == '\n'):
        # Check if it's a section header (not inside a value)
        let lineStart = contentNoSection.rfind('\n', 0, searchFrom)
        let preceding = contentNoSection[max(0, lineStart + 1) ..< searchFrom]
        if preceding.strip().len == 0:
          sectionEnd = searchFrom
          break
      inc searchFrom
    contentNoSection = contentNoSection[0 ..< sectionStart] & contentNoSection[sectionEnd .. ^1]
    sectionStart = contentNoSection.find("[impure_procedures_whitelist]")

  let newContent = contentNoSection.strip() & "\n" & sectionText
  writeFile(lockPath, newContent)
proc generateReport(repoRoot: string, files: seq[string],
    convertedLog: seq[(string, int, string, string)], whitelist: HashSet[string],
    iterations: int, otherErrors: seq[string]): string =
  let reportDir = repoRoot / ReportDirRel
  let dateStr = now().format("yyyy'_'MM'_'dd")
  let reportPath = reportDir / "auto_convert_report_" & dateStr & ".md"

  var lines: seq[string] = @[]
  lines.add("# proc→proc Auto-Conversion Report — " & now().format("yyyy-MM-dd'T'HH:mm:ss"))
  lines.add("")
  lines.add("## Summary")
  lines.add("")
  lines.add("| Metric | Count |")
  lines.add("|--------|-------|")
  lines.add("| Files scanned | " & $files.len & " |")
  lines.add("| Procs converted to proc | " & $convertedLog.len & " |")
  lines.add("| Whitelist entries (impure) | " & $whitelist.len & " |")
  lines.add("| Iterations to convergence | " & $iterations & " |")
  lines.add("")
  lines.add("## Whitelist (to add to architecture_policy.lock)")
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
  lines.add("## Non-Side-Effect Errors (manual review)")
  lines.add("")
  if otherErrors.len > 0:
    for e in otherErrors:
      lines.add("- " & e)
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

  log("=== proc→proc Auto-Conversion Pipeline ===")
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

  var convertedLog: seq[(string, int, string, string)]

  if iteration == 0:
    log("Phase 1: Bulk conversion...")
    if dryRun:
      var count = 0
      var skippedCount = 0
      for filePath in files:
        try:
          let lines = readFile(filePath).splitLines()
          for idx, line in lines:
            if shouldSkipLine(line):
              continue
            let name = extractProcName(line)
            if name.isNone:
              continue
            let entry = modulePathOf(filePath, repoRoot) & ":" & name.get()
            if declarationContainsImpure(lines, idx):
              inc skippedCount
              continue
            if not wl.contains(entry):
              inc count
        except CatchableError:
          discard  # axiom:best-effort(file processing error)
      log("  [DRY-RUN] Would convert " & $count & " proc declarations to proc (" &
        $skippedCount & " impure procs would be whitelisted)")
    else:
      let (convCount, logEntries, skipped) = bulkConvert(repoRoot, files, wl)
      for s in skipped:
        wl.incl(s)
      convertedLog = logEntries
      log("  Converted " & $convCount & " proc declarations to proc (" &
        $skipped.len & " impure procs added to whitelist)")
    log("")

    if dryRun:
      discard generateReport(repoRoot, files, convertedLog, wl, 0, @[])
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
    log("Phase 2/3: Iteration " & $iteration & " — project-level compiler check + error classification...")

    let output = runProjectLevelCheck(repoRoot)
    let seErrors = parseSideEffectErrors(output)
    let totalErrors = countRemainingErrors(output)

    log("  " & $totalErrors & " compiler errors found, " & $seErrors.len & " classified as side-effect errors.")

    if seErrors.len == 0:
      if totalErrors == 0:
        log("  Convergence reached: zero compiler errors.")
      else:
        log("  No rollbackable side-effect errors remain but other errors present.")
        for line in output.splitLines():
          if ")" in line and "Error:" in line:
            var m: RegexMatch
            if not line.find(sideEffectRe, m):
              otherErrors.add(line)
      break

    if dryRun:
      log("  [DRY-RUN] Would rollback side-effect funcs")
      break

    let newEntries = rollbackFuncs(repoRoot, seErrors)
    for e in newEntries:
      wl.incl(e)
    log("  Rolled back " & $newEntries.len & " funcs to proc.")

    saveCheckpoint(repoRoot, iteration, wl)

    if iteration >= maxIterations:
      log("  WARNING: Max iterations reached (" & $maxIterations & "). Stopping.")
      break

  # Cleanup
  let virtualPath = repoRoot / VirtualEntryRel
  if fileExists(virtualPath):
    removeFile(virtualPath)

  if not dryRun:
    if fileExists(stateFile):
      removeFile(stateFile)
    updateArchitecturePolicyLock(repoRoot, wl)
    let report = generateReport(repoRoot, files, convertedLog, wl, iteration, otherErrors)
    log("")
    log("Pipeline complete.")
    log("  Whitelist updated in src/gate/architecture_policy.lock")
    log("  Report: " & report)

  if otherErrors.len > 0:
    log("")
    log("WARNING: Non-side-effect errors remain and require manual review:")
    for e in otherErrors:
      log("  " & e)
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
