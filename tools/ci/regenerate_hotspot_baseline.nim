## Regenerate data/code_health_baseline.json from current src/**/*.nim.
##
## Mirrors the heuristics in src/gate/runners/hotspot_gate.nim:
##   - deepNesting: lines with indentation >= 8 spaces (>= 4 levels)
##   - longProc:    proc/func/method whose first top-level return is >80 lines away
##   - denseBranching: case/if chain with >10 branches
##
## Usage: nim c -r tools/ci/regenerate_hotspot_baseline.nim

import core/trusted/layer_declaration
axiomLayer "tools"
import shared_types/shared_types
import api/tools_facade
import std/[os, strutils, json, algorithm]
const
  nestingThreshold = 4   # levels
  lineThreshold = 80     # lines
  branchThreshold = 10   # branches
  srcDir = "src"
  baselinePath = "data/code_health_baseline.json"

# ---------------------------------------------------------------------------
# Pure helpers (func — no side effects)
# ---------------------------------------------------------------------------
## Regenerate data/code_health_baseline.json from current src/**/*.nim.
##
## Mirrors the heuristics in src/gate/runners/hotspot_gate.nim:
##   - deepNesting: lines with indentation >= 8 spaces (>= 4 levels)
##   - longProc:    proc/func/method whose first top-level return is >80 lines away
##   - denseBranching: case/if chain with >10 branches
##
## Usage: nim c -r tools/ci/regenerate_hotspot_baseline.nim
func measureIndent(line: string): int =
  ## Count leading whitespace: space=1, tab=2.
  result = 0
  for ch in line:
    case ch
    of ' ': inc result
    of '\t': result += 2
    else: break
func isProcOrFuncStart(line: string): bool =
  let s = line.strip()
  s.startsWith("proc ") or s.startsWith("func ") or s.startsWith("method ")
type
  FileMetrics = object
    deepNesting: int
    longProc: int
    denseBranching: int
    hasAny: bool
func scanFileLines(text: string): FileMetrics =
  ## Scan file content for hotspot metrics.
  var
    deep = 0
    long = 0
    dense = 0
    inProc = false
    procStart = 0
    branchCount = 0

  var lineno = 0
  for raw in text.splitLines():
    inc lineno
    let stripped = raw.strip()
    if stripped.len == 0:
      continue

    # deep nesting
    let indent = measureIndent(raw)
    if indent >= nestingThreshold * 2 and not stripped.startsWith("#"):
      inc deep

    # long procedure
    if isProcOrFuncStart(raw):
      inProc = true
      procStart = lineno
    elif inProc and stripped.startsWith("return") and indent <= 2:
      let span = lineno - procStart
      if span > lineThreshold:
        inc long
      inProc = false

    # dense branching
    if stripped.startsWith("case ") or stripped.startsWith("if "):
      branchCount = 1
    elif branchCount > 0 and (
      stripped.startsWith("of ") or
      stripped.startsWith("elif ") or
      stripped.startsWith("else:")
    ):
      inc branchCount
      if branchCount > branchThreshold:
        inc dense
        branchCount = 0
    elif stripped.len > 0 and not stripped.startsWith("#") and indent <= 2:
      branchCount = 0

  result = FileMetrics(
    deepNesting: deep,
    longProc: long,
    denseBranching: dense,
    hasAny: deep > 0 or long > 0 or dense > 0,
  )

# ---------------------------------------------------------------------------
# I/O procs — these use {.axiomEffect: IoEffect.}
# ---------------------------------------------------------------------------
proc readFileContent(path: string): string {.axiomEffect: IoEffect.} =
  ## Read file contents, returning empty string on error.
  try:
    result = readFile(path)
  except IOError:
    result = ""
proc writeFileContent(path, content: string) {.axiomEffect: IoEffect.} =
  ## Write content to file. Silently ignores errors (CI tool).
  try:
    writeFile(path, content)
  except IOError, OSError:
    discard
proc printMsg(msg: string) {.axiomEffect: IoEffect.} =
  ## Print a message to stdout.
  echo msg
proc ensureParentDir(path: string) {.axiomEffect: IoEffect.} =
  ## Create parent directory if it doesn't exist.
  try:
    let parent = parentDir(path)
    if parent.len > 0 and not dirExists(parent):
      createDir(parent)
  except OSError, IOError:
    discard
proc collectNimPaths(root: string): seq[string] {.axiomEffect: IoEffect.} =
  ## Collect all .nim file paths under root, sorted.
  result = @[]
  try:
    for path in walkDirRec(root):
      if path.endsWith(".nim"):
        result.add(path)
    result.sort()
  except OSError:
    discard

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
proc main() {.axiomEffect: IoEffect.} =
  var byFile: seq[(string, FileMetrics)]
  var total = 0

  let paths = collectNimPaths(srcDir)

  for path in paths:
    let text = readFileContent(path)
    if text.len == 0:
      continue
    let metrics = scanFileLines(text)
    if metrics.hasAny:
      let rel = path.replace(DirSep, '/')
      byFile.add((rel, metrics))
      total += metrics.deepNesting + metrics.longProc + metrics.denseBranching

  # Build JSON baseline
  var byFileObj = newJObject()
  for (rel, metrics) in byFile:
    var fileObj = newJObject()
    if metrics.deepNesting > 0:
      fileObj["deepNesting"] = newJInt(metrics.deepNesting)
    if metrics.longProc > 0:
      fileObj["longProc"] = newJInt(metrics.longProc)
    if metrics.denseBranching > 0:
      fileObj["denseBranching"] = newJInt(metrics.denseBranching)
    byFileObj[rel] = fileObj

  let baseline = %*{
    "version": "1.0.0",
    "generatedAt": "2026-06-17",
    "metrics": {
      "hotspot": {
        "total": total,
        "byFile": byFileObj,
      }
    }
  }

  ensureParentDir(baselinePath)
  writeFileContent(baselinePath, pretty(baseline) & "\n")
  printMsg("[regenerate-hotspot-baseline] " & $byFile.len & " files, total=" & $total)

when isMainModule:
  main()
