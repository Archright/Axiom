## detect_proc_to_func_per_routine.nim — Per-Routine proc→func Detection
## (Nim port of tools/ci/detect_proc_to_func_per_routine.sh)
##
## Incremental + cache-optimized proc→func verification.
## Tests each proc→func conversion individually via `nim check`.
##
## Context7 verified: import path preservation + indentation handling + nimcache isolation.
##
## Usage:
##   nim c -r tools/ci/detect_proc_to_func_per_routine.nim              # full scan
##   nim c -r tools/ci/detect_proc_to_func_per_routine.nim src/foo.nim  # specific file

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[algorithm, os, osproc, strutils, hashes, times]

# ── Local Axiom pragmas (standalone CI tool — no project imports) ──────
type
  AxiomEffectKind = enum
    Pure, IoEffect

template axiomEffect*(effectType: AxiomEffectKind) {.pragma.}
template axiomIoBoundary*() = discard

axiomIoBoundary()

const
  CacheDirRel = ".nimcache/proc_to_func"
  ReportDirRel = "docs/reports"
  CoreDirRel = "src/core"

# ── Safe wrappers ( {.raises: []} compatibility ) ──────────────────────

proc safeReadFile(path: string): string =
  try:
    result = readFile(path)
  except CatchableError:
    result = ""

proc safeWriteFile(path, content: string): bool =
  try:
    writeFile(path, content)
    return true
  except CatchableError:
    return false

proc safeCreateDir(path: string): bool =
  try:
    createDir(path)
    return true
  except CatchableError:
    return false

proc safeRemoveFile(path: string): bool =
  try:
    removeFile(path)
    return true
  except CatchableError:
    return false

proc safeRemoveDir(path: string): bool =
  try:
    removeDir(path)
    return true
  except CatchableError:
    return false

proc safeNow(): DateTime =
  now()

proc safeFormat(dt: DateTime, f: string): string =
  try:
    result = dt.format(f)
  except CatchableError:
    result = "unknown"

proc safeParamStr(i: int): string =
  try:
    result = paramStr(i)
  except CatchableError:
    result = ""

proc log(msg: string) =
  try:
    echo msg
  except CatchableError:
    discard  # axiom:best-effort(console output failure — non-fatal)

# ── Pure helpers ───────────────────────────────────────────────────────

func repoRoot(): string =
  ## Resolve repo root from source file location (tools/ci/ → repo root).
  parentDir(parentDir(parentDir(currentSourcePath())))

func contentHash(data: string): string =
  ## Compute content hash for cache invalidation.
  $hash(data)

func cacheKey(path: string): string =
  ## Deterministic cache filename for a given source path.
  $hash(path) & ".hash"

func startsWithProcDecl(line: string): bool =
  ## Check if a line starts a proc declaration (handles leading whitespace).
  let s = line.strip(leading = true, trailing = false)
  s.startsWith("proc ")

func replaceFirstProcWord(line: string): string =
  ## Replace first word-boundary 'proc' with 'func' (sed \bproc\b equivalent).
  var i = 0
  while i <= line.len - 4:
    if line[i ..< i + 4] == "proc":
      let beforeOk = i == 0 or not line[i - 1].isAlphaNumeric()
      let afterOk = i + 4 >= line.len or not line[i + 4].isAlphaNumeric()
      if beforeOk and afterOk:
        return line[0 ..< i] & "func" & line[i + 4 .. ^1]
    inc i
  result = line

# ── File collection & caching ──────────────────────────────────────────

proc collectCoreFiles(root: string): seq[string] =
  ## Collect .nim files from src/core/, excluding _* dirs and *_part* files.
  let coreDir = root / CoreDirRel
  if not dirExists(coreDir):
    return
  try:
    for path in walkDirRec(coreDir):
      if not path.endsWith(".nim"):
        continue
      let (_, _, name) = splitFile(path)
      if name.startsWith("_") or "_part" in name:
        continue
      result.add(path)
  except CatchableError:
    discard  # axiom:best-effort(walkDirRec failure — returns partial results)
  result.sort()

proc filterChanged(root: string, files: seq[string]): seq[string] =
  ## Filter files that have changed since last check (hash cache).
  let cacheDir = root / CacheDirRel
  discard safeCreateDir(cacheDir)
  for f in files:
    if not fileExists(f):
      continue
    let data = safeReadFile(f)
    if data.len == 0:
      result.add(f)
      continue
    let h = contentHash(data)
    let cf = cacheDir / cacheKey(f)
    let cached = safeReadFile(cf).strip()
    if h != cached:
      result.add(f)
      discard safeWriteFile(cf, h)

# ── Per-routine analysis ───────────────────────────────────────────────

proc isMainModuleFile(path: string): bool =
  ## Check if file contains 'when isMainModule' (skip entire file).
  "when isMainModule" in safeReadFile(path)

proc findProcLineNums(path: string): seq[int] =
  ## Find 1-based line numbers of proc declarations.
  let content = safeReadFile(path)
  if content.len == 0:
    return
  var lineNum = 1
  for line in content.splitLines():
    if startsWithProcDecl(line):
      result.add(lineNum)
    inc lineNum

proc checkFuncConversion(filePath: string, lineIdx: int,
    nimcacheDir: string): bool =
  ## Try converting a specific proc→func and run `nim check`.
  ## Returns true if SAFE (compiles), false if EFFECT (side effects).
  let content = safeReadFile(filePath)
  if content.len == 0:
    return false

  let lines = content.splitLines()
  var modified = lines
  modified[lineIdx] = replaceFirstProcWord(modified[lineIdx])

  let tmpFile = filePath & ".tmp.nim"
  let trail = if content.endsWith("\n"): "\n" else: ""
  if not safeWriteFile(tmpFile, modified.join("\n") & trail):
    return false

  var nimExe = ""
  try:
    nimExe = findExe("nim")
  except CatchableError:
    discard  # axiom:best-effort(nim binary detection — falls back to false)
  if nimExe.len == 0:
    # nim not found — conservative: report as EFFECT
    discard safeRemoveFile(tmpFile)
    discard safeRemoveDir(nimcacheDir)
    return false

  let cmd = nimExe & " check --hints:off --nimcache:" &
            nimcacheDir & " " & tmpFile
  var exitCode = 1
  try:
    let (_, ec) = execCmdEx(cmd)
    exitCode = ec
  except CatchableError:
    exitCode = 1

  # Cleanup temp artifacts
  discard safeRemoveFile(tmpFile)
  discard safeRemoveDir(nimcacheDir)

  result = (exitCode == 0)

# ── Main entry point ───────────────────────────────────────────────────

proc main() {.axiomEffect: IoEffect.} =
  let root = repoRoot()
  discard safeCreateDir(root / CacheDirRel)
  discard safeCreateDir(root / ReportDirRel)

  # ── Argument parsing ──
  var files: seq[string]
  if paramCount() == 0:
    files = collectCoreFiles(root)
  else:
    for i in 1 .. paramCount():
      let arg = safeParamStr(i)
      if arg.len == 0:
        continue
      if isAbsolute(arg):
        files.add(arg)
      else:
        files.add(root / arg)

  # ── Incremental filter (SHA256 cache) ──
  let changed = filterChanged(root, files)
  if changed.len == 0:
    log("✅ Cache hit — no proc→func check needed.")
    quit(0)

  # ── Init report ──
  let currentTime = safeNow()
  let dateStr = safeFormat(currentTime, "yyyy_MM_dd")
  let reportPath = root / ReportDirRel / "proc_to_func_report_" &
                   dateStr & ".md"
  var reportLines: seq[string]
  reportLines.add("# proc→func Detection Report — " &
                  safeFormat(currentTime, "yyyy-MM-dd'T'HH:mm:ss"))
  reportLines.add("")
  reportLines.add("| File | Line | Status |")
  reportLines.add("|------|------|--------|")

  var safeCount = 0
  var effectCount = 0

  # ── Per-file, per-routine check ──
  for filePath in changed:
    if isMainModuleFile(filePath):
      continue

    let procLines = findProcLineNums(filePath)
    var relFile = filePath
    try:
      relFile = filePath.relativePath(root)
    except CatchableError:
      relFile = filePath

    for lineNum in procLines:
      let nimcacheDir = filePath & ".nimcache"
      let isSafe = checkFuncConversion(filePath, lineNum - 1, nimcacheDir)

      if isSafe:
        reportLines.add("| " & relFile & " | " & $lineNum &
                        " | ✅ SAFE |")
        inc safeCount
      else:
        reportLines.add("| " & relFile & " | " & $lineNum &
                        " | 🔴 EFFECT |")
        inc effectCount

  # ── Write report ──
  reportLines.add("")
  reportLines.add("## Summary")
  reportLines.add("- Safe to convert: " & $safeCount)
  reportLines.add("- Has side effects: " & $effectCount)
  reportLines.add("- Total: " & $(safeCount + effectCount))
  reportLines.add("- Date: " & safeFormat(safeNow(), "yyyy-MM-dd'T'HH:mm:ss"))

  discard safeWriteFile(reportPath, reportLines.join("\n"))

  log("")
  log("=== proc→func Detection Complete ===")
  log("✅ Safe: " & $safeCount & " | 🔴 Effect: " & $effectCount)
  log("Report: " & reportPath)

when isMainModule:
  main()
