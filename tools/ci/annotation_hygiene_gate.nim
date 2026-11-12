## annotation_hygiene_gate.nim — Annotation Hygiene Gate
##
## Ensures all procs in src/core/ have explicit effect annotations
## ({.raises: [].} or {.axiomEffect: IoEffect} or inside {.push raises: []}).
##
## Ported from tools/ci/annotation_hygiene_gate.py
##
## Usage:
##   nim c -o:bin/annotation-hygiene-gate tools/ci/annotation_hygiene_gate.nim
##   bin/annotation-hygiene-gate                  # gate check
##   bin/annotation-hygiene-gate --update-baseline

import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/shared_types
import std/[os, strutils, json, sets, options, algorithm]
# ── Types ──────────────────────────────────────────────────────────────────

type
  Violation = object
    file: string
    line: int
    procName: string
    suggestion: string
const
  srcCoreRel = "src/core"
  lockFileRel = "src/gate/architecture_policy.lock"
  baselineFileRel = "data/annotation_hygiene_baseline.json"
  patchFileRel = "docs/reports/annotation_hygiene_patch.diff"

  ioPatterns = [
    "echo", "writeFile", "readFile", "getEnv", "getMonoTime",
    "epochTime", "randomize", "rand", "sleep", "execProcess",
    "existsEnv", "putEnv", "open", "close", "readLine", "write",
  ]
func extractProcName(line: string): string =
  ## Extract the proc name from a proc declaration line.
  let stripped = line.strip()
  if not stripped.startsWith("proc "):
    return ""
  var pos = 5
  if pos < stripped.len and stripped[pos] == '*':
    inc pos
  while pos < stripped.len and stripped[pos] == ' ':
    inc pos
  let start = pos
  while pos < stripped.len and (stripped[pos].isAlphaNumeric() or stripped[pos] == '_'):
    inc pos
  if pos > start:
    result = stripped[start ..< pos]
  else:
    result = ""
func insideMainModule(lines: seq[string], idx: int): bool =
  ## Return true if the line at idx is inside a `when isMainModule` block.
  for i in countdown(idx, 0):
    let stripped = lines[i].strip()
    if stripped.startsWith("when isMainModule"):
      return true
    if stripped.startsWith("when defined(testing)"):
      return true
  return false
func detectUnannotatedProcs(
  filepath: string,
  repoRoot: string,
  lines: seq[string],
  whitelist: HashSet[string]
): seq[Violation] =
  ## Scan lines for procs without effect annotations.
  let fullContent = lines.join("\n")
  if "axiomIoBoundary" in fullContent:
    return @[]

  result = @[]
  var inPushRaises = 0

  for i, line in lines:
    if "{.push raises:" in line or "{. push raises:" in line:
      inc inPushRaises
    if "{.pop.}" in line or "{. pop.}" in line:
      inPushRaises = max(0, inPushRaises - 1)

    let procName = extractProcName(line)
    if procName.len == 0:
      continue

    let contextEnd = min(i + 6, lines.len)
    let context = lines[i ..< contextEnd].join("\n")

    let hasRaises = "{.raises:" in context and "[" in context
    let hasAxiom = "axiomEffect:" in context
    let inPush = inPushRaises > 0

    if hasRaises or hasAxiom or inPush:
      continue

    if insideMainModule(lines, i):
      continue

    # Compute relative path
    var modPath = filepath
    if filepath.startsWith(repoRoot & "/"):
      modPath = filepath[(repoRoot.len + 1) .. ^1]
    let whitelistKey = modPath & ":" & procName
    if whitelistKey in whitelist:
      continue

    let bodyEnd = min(i + 20, lines.len)
    let bodyContext = lines[i ..< bodyEnd].join("\n")
    var hasIo = false
    for pat in ioPatterns:
      if pat in bodyContext:
        hasIo = true
        break
    let suggestion = if hasIo: "{.axiomEffect: IoEffect.}"
                     else: "{.raises: [].}"

    result.add(Violation(
      file: modPath,
      line: i + 1,
      procName: procName,
      suggestion: suggestion
    ))
proc log(msg: string) {.axiomEffect: IoEffect, raises: [].} =
  echo msg
proc loadWhitelist(lockPath: string): seq[string] {.
    axiomEffect: IoEffect, raises: [CatchableError].} =
  if not fileExists(lockPath):
    return @[]
  let content = readFile(lockPath)
  result = @[]
  var inSection = false
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped == "[impure_procedures_whitelist]":
      inSection = true
      continue
    if inSection and stripped.startsWith("[") and not stripped.startsWith("[["):
      break
    if inSection:
      var pos = 0
      while pos < line.len:
        let qStart = line.find('"', pos)
        if qStart == -1: break
        let qEnd = line.find('"', qStart + 1)
        if qEnd == -1: break
        let m = line[(qStart + 1) ..< qEnd]
        if ".nim:" in m:
          result.add(m)
        pos = qEnd + 1
## annotation_hygiene_gate.nim — Annotation Hygiene Gate
##
## Ensures all procs in src/core/ have explicit effect annotations
## ({.raises: [].} or {.axiomEffect: IoEffect} or inside {.push raises: []}).
##
## Ported from tools/ci/annotation_hygiene_gate.py
##
## Usage:
##   nim c -o:bin/annotation-hygiene-gate tools/ci/annotation_hygiene_gate.nim
##   bin/annotation-hygiene-gate                  # gate check
##   bin/annotation-hygiene-gate --update-baseline
proc collectCoreFiles(srcCore: string, files: var seq[string]) =
  ## Collect .nim files from srcCore, appending to `files`.
  ## Must NOT have raises/axiomEffect annotation — breaks walkDirRec iterator.
  ## walkDirRec can raise OSError, so wrap in try/except.
  try:
    for path in walkDirRec(srcCore, yieldFilter = {pcFile}, followFilter = {pcDir}):
      let (dir, _, ext) = splitFile(path)
      if dir.splitPath.tail.startsWith("_"):
        continue
      if dir.splitPath.tail == "tests" or dir.splitPath.tail == ".nimcache":
        continue
      if ext == ".nim":
        files.add(path)
  except OSError:
    discard
proc loadBaseline(path: string): Option[int] {.
    axiomEffect: IoEffect, raises: [].} =
  if not fileExists(path):
    return none(int)
  try:
    let data = parseJson(readFile(path))
    return some(data["count"].getInt())
  except CatchableError:
    return none(int)
proc generatePatch(path, repoRoot: string,
    violations: seq[Violation]) {.
    axiomEffect: IoEffect, raises: [CatchableError].} =
  createDir(path.parentDir())
  var f = open(path, fmWrite)
  defer: f.close()
  f.writeLine("# Annotation Hygiene Patch — " & $violations.len & " violations")
  f.writeLine("# Generated by tools/ci/annotation_hygiene_gate.nim")
  f.writeLine("")
  for v in violations:
    f.writeLine("# " & v.file & ":" & $v.line & ": proc " & v.procName)
    f.writeLine("#   → add " & v.suggestion)
    f.writeLine("")
  # Compute relative path for display
  var relPath = path
  if path.startsWith(repoRoot & "/"):
    relPath = path[(repoRoot.len + 1) .. ^1]
  log("[annotation-hygiene] Patch written to " & relPath)
proc updateBaselineCount(path: string, count: int) {.
    axiomEffect: IoEffect, raises: [CatchableError].} =
  createDir(path.parentDir())
  let payload = %*{
    "count": count,
    "source": "src/core/**/*.nim",
    "note": "Auto-generated by tools/ci/annotation_hygiene_gate.nim --update-baseline"
  }
  writeFile(path, pretty(payload) & "\n")
proc findProjectRoot(): string {.raises: [CatchableError].} =
  ## Walk upward to find .axiom_root. Checks CWD first, then binary location.
  let cwd = getCurrentDir()
  for start in [cwd, getAppDir()]:
    var d = start
    for _ in 0..10:
      if fileExists(d / ".axiom_root"):
        return d
      let parent = parentDir(d)
      if parent == d:
        break
      d = parent
  result = cwd
proc main(): int {.raises: [].} =
  var repoRoot: string
  try:
    repoRoot = findProjectRoot()
  except CatchableError:
    log("[annotation-hygiene] ERROR: could not determine project root.")
    return 1

  let srcCore = repoRoot / srcCoreRel
  let lockPath = repoRoot / lockFileRel
  let baselinePath = repoRoot / baselineFileRel
  let patchPath = repoRoot / patchFileRel

  var updateBaselineFlag = false
  for i in 1 .. paramCount():
    if paramStr(i) == "--update-baseline":
      updateBaselineFlag = true

  var whitelist: HashSet[string]
  var files: seq[string] = @[]
  var allViolations: seq[Violation] = @[]

  try:
    whitelist = loadWhitelist(lockPath).toHashSet()
  except CatchableError as e:
    log("[annotation-hygiene] ERROR: " & e.msg)
    return 1

  collectCoreFiles(srcCore, files)
  files.sort()

  for nimFile in files:
    var content: string
    try:
      content = readFile(nimFile)
    except IOError, OSError:
      continue
    let violations = detectUnannotatedProcs(nimFile, repoRoot, content.splitLines(), whitelist)
    allViolations.add(violations)

  let violationCount = allViolations.len

  if updateBaselineFlag:
    try:
      updateBaselineCount(baselinePath, violationCount)
    except CatchableError:
      log("[annotation-hygiene] ERROR: failed to write baseline.")
      return 1
    log("[annotation-hygiene] Baseline updated to " & $violationCount & " violations.")
    var relBaseline = baselinePath
    if baselinePath.startsWith(repoRoot & "/"):
      relBaseline = baselinePath[(repoRoot.len + 1) .. ^1]
    log("[annotation-hygiene] Stage and commit " & relBaseline & ".")
    return 0

  let baseline = loadBaseline(baselinePath)

  log("[annotation-hygiene] Project root: " & repoRoot)
  log("[annotation-hygiene] Files scanned: " & $files.len)
  log("[annotation-hygiene] Whitelist entries: " & $whitelist.len)
  log("[annotation-hygiene] Unannotated procs: " & $violationCount)

  if baseline.isNone:
    var relBase = baselinePath
    if baselinePath.startsWith(repoRoot & "/"):
      relBase = baselinePath[(repoRoot.len + 1) .. ^1]
    log("[annotation-hygiene] FAIL: baseline missing (" & relBase & ").")
    log("[annotation-hygiene] Generate it with: annotation_hygiene_gate --update-baseline")
    return 1

  log("[annotation-hygiene] Baseline: " & $baseline.get())

  if violationCount > baseline.get():
    log("[annotation-hygiene] FAIL: violations grew by " & $(violationCount - baseline.get()) & ".")
    for v in allViolations:
      log("  " & v.file & ":" & $v.line & ": " & v.procName & " → " & v.suggestion)
    try:
      generatePatch(patchPath, repoRoot, allViolations)
    except CatchableError:
      log("[annotation-hygiene] WARNING: failed to write patch file.")
    return 1

  if violationCount < baseline.get():
    log("[annotation-hygiene] OK: violations decreased (" & $baseline.get() & " → " & $violationCount & ").")
    log("[annotation-hygiene] Run with --update-baseline to sync, then commit.")
    for v in allViolations:
      log("  " & v.file & ":" & $v.line & ": " & v.procName & " → " & v.suggestion)
    return 0

  log("[annotation-hygiene] PASS: violation count is stable.")
  return 0

when isMainModule:
  quit(main())

{.pop.}
