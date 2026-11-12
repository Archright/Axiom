import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}
## Compile-time purity tester: determines which proc declarations can safely
## be converted to func by using the Nim compiler as the arbiter.
##
## Algorithm: for each file with proc candidates, create a shadow file with
## ALL procs→func, run `nim check` ONCE on that shadow, parse errors.
## Shadow files live in the SAME directory as originals (relative imports work).

import std/[json, os, osproc, re, strutils, sets, tables, algorithm]

const
  ShadowSuffix = "_shadow"

# --- Regex compatibility shim for Nim 2.x std/re ---
type RegexMatch = object
  first, last: int
  captures: array[32, string]
  numCaptures: int

proc findMatch(s: string, pattern: Regex, m: var RegexMatch): bool =
  var caps: array[32, string]
  let bounds = findBounds(s, pattern, caps)
  m.first = bounds.first
  m.last = bounds.last
  m.numCaptures = 0
  if bounds.first >= 0:
    for i in 0 ..< caps.len:
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

# --- Types ---

type
  ProcCandidate = object
    file: string        # absolute path to original file
    line: int           # 1-based line number
    name: string        # proc name (without backticks)

# --- Regexes ---

# Match proc/func declarations
let procDeclRe = re("^(\\s*)(proc|func)\\s+([a-zA-Z_`][a-zA-Z_0-9`]*)")

# Match axiomEffect annotation (skip already-annotated procs)
let impureRe = re("\\{\\.axiomEffect")

# Match compiler error lines: file(line, col) Error: message
let errorRe = re("^(.+\\.nim)\\((\\d+),\\s*(\\d+)\\)\\s+Error:\\s+(.+)")

# --- Core Logic ---

proc collectNimFiles(srcDir: string): seq[string] {.raises: [CatchableError].} =
  ## Recursively collect all .nim files under srcDir.
  for path in walkDirRec(srcDir):
    if path.endsWith(".nim"):
      result.add(path)
  result.sort()

proc findCandidates(filePath: string): seq[ProcCandidate] {.raises: [CatchableError].} =
  ## Find proc declarations that are candidates for func conversion.
  ## Skips: already-func declarations, lines with axiomEffect annotation.
  let content = readFile(filePath)
  let lines = content.splitLines()
  for idx, line in lines:
    var m: RegexMatch
    if not line.findMatch(procDeclRe, m):
      continue
    # Skip if already func (already pure)
    if m.group(2, line) == "func":
      continue
    # Skip if already has axiomEffect annotation
    var m2: RegexMatch
    if line.findMatch(impureRe, m2):
      continue
    let name = m.group(3, line).replace("`", "")
    result.add(ProcCandidate(file: filePath, line: idx + 1, name: name))

proc createShadowFile(origPath: string,
    candidates: seq[ProcCandidate]): string {.raises: [CatchableError].} =
  ## Create a shadow file with candidate procs replaced by func.
  ## Shadow file lives in the SAME directory as the original (relative imports work).
  ## Returns the shadow file path.
  let (dir, name, ext) = splitFile(origPath)
  let shadowPath = dir / (name & ShadowSuffix & ext)

  let content = readFile(origPath)
  var lines = content.splitLines()

  # Build set of 0-based line indices to replace
  var replaceLines = initHashSet[int]()
  for c in candidates:
    replaceLines.incl(c.line - 1)

  var newLines: seq[string]
  for idx, line in lines:
    if idx in replaceLines:
      # Find first "proc " and replace with "func "
      let procIdx = line.find("proc ")
      if procIdx >= 0 and (procIdx == 0 or not line[procIdx - 1].isAlphaNumeric()):
        newLines.add(line[0 ..< procIdx] & "func " & line[procIdx + 5 .. ^1])
      else:
        newLines.add(line)
    else:
      newLines.add(line)

  let trail = if content.endsWith("\n"): "\n" else: ""
  writeFile(shadowPath, newLines.join("\n") & trail)
  shadowPath

proc parseCompilerErrors(output: string): seq[tuple[
    file: string, line: int, col: int, message: string]] =
  ## Parse nim check output into structured error records.
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    var m: RegexMatch
    if trimmed.findMatch(errorRe, m):
      var lineNum = 0
      var colNum = 0
      try:
        lineNum = parseInt(m.group(2, trimmed))
        colNum = parseInt(m.group(3, trimmed))
      except ValueError:
        continue
      result.add((m.group(1, trimmed), lineNum, colNum, m.group(4, trimmed)))

proc shadowToOriginal(shadowPath: string): string =
  ## Convert shadow file path back to original file path.
  ## src/foo/bar_shadow.nim → src/foo/bar.nim
  let (dir, name, ext) = splitFile(shadowPath)
  if name.endsWith(ShadowSuffix):
    result = dir / (name[0 .. ^(ShadowSuffix.len + 1)] & ext)
  else:
    result = shadowPath

proc main() {.raises: [CatchableError].} =
  # Resolve repo root from compile-time source path
  let toolDir = parentDir(currentSourcePath())
  let repoRoot = parentDir(toolDir)
  let srcDir = repoRoot / "src"

  stderr.writeLine("proc_to_func_tester: scanning ", srcDir)

  # Step 1: Collect all .nim files under src/
  let files = collectNimFiles(srcDir)
  stderr.writeLine("  Found ", files.len, " .nim files")

  # Step 2: Find proc candidates in each file
  var allCandidates: seq[ProcCandidate]
  var fileCandidates: seq[tuple[path: string, candidates: seq[ProcCandidate]]]

  for filePath in files:
    let candidates = findCandidates(filePath)
    if candidates.len > 0:
      fileCandidates.add((filePath, candidates))
      allCandidates.add(candidates)

  stderr.writeLine("  Found ", allCandidates.len, " proc candidates in ",
      fileCandidates.len, " files")

  if allCandidates.len == 0:
    echo "[]"
    return

  # Step 3: Find nim executable
  let nimExe = findExe("nim")
  if nimExe.len == 0:
    stderr.writeLine("ERROR: nim not found in PATH")
    quit(1)

  # Step 4a: Create ALL shadow files first
  var errorMap = initTable[(string, int), string]()
  var shadowPaths: seq[string]

  stderr.writeLine("  Creating ", fileCandidates.len, " shadow files...")
  for fc in fileCandidates:
    let shadowPath = createShadowFile(fc.path, fc.candidates)
    shadowPaths.add(shadowPath)

  # Step 4b: Run nim check in parallel via execProcesses (O(1) wall-clock)
  let logDir = getTempDir() / "axiom_p2f_logs"
  createDir(logDir)
  stderr.writeLine("  Checking ", shadowPaths.len, " shadows in parallel...")

  var cmds: seq[string]
  var logPaths: seq[string]
  for i, shadowPath in shadowPaths:
    let logPath = logDir / ("check_" & $i & ".log")
    logPaths.add(logPath)
    # cd to repoRoot so nim finds config.nims; redirect all output to log file
    cmds.add("cd " & quoteShell(repoRoot) & " && " & nimExe &
             " check --errorMax:0 --hints:off --warnings:off " &
             quoteShell(shadowPath) & " > " & quoteShell(logPath) & " 2>&1")

  let nWorkers = max(1, osproc.countProcessors() - 1)
  stderr.writeLine("  Using ", nWorkers, " parallel workers")
  discard execProcesses(cmds, n = nWorkers)

  # Step 4c: Parse errors from all log files
  for i, logPath in logPaths:
    if fileExists(logPath):
      let output = readFile(logPath)
      let errors = parseCompilerErrors(output)
      for err in errors:
        let origFile = shadowToOriginal(err.file)
        let key = (origFile, err.line)
        if not errorMap.hasKey(key):
          errorMap[key] = err.message
      removeFile(logPath)

  # Step 4d: Cleanup ALL shadow files
  for shadowPath in shadowPaths:
    if fileExists(shadowPath):
      removeFile(shadowPath)
  removeDir(logDir)

  stderr.writeLine("  Parsed ", errorMap.len, " error entries across all files")

  # Step 5: Classify each candidate — pure or io
  var arr = newJArray()
  for fc in fileCandidates:
    for cand in fc.candidates:
      let key = (cand.file, cand.line)
      if errorMap.hasKey(key):
        arr.add(%*{
          "file": cand.file,
          "line": cand.line,
          "proc": cand.name,
          "result": "io",
          "reason": errorMap[key]
        })
      else:
        arr.add(%*{
          "file": cand.file,
          "line": cand.line,
          "proc": cand.name,
          "result": "pure"
        })

  # Step 6: Output JSON to stdout
  echo pretty(arr)
  stderr.writeLine("  Done: ", arr.len, " candidates classified (",
      arr.len - errorMap.len, " pure, ", errorMap.len, " io)")

when isMainModule:
  main()
