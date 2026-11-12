import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## conflict_marker_gate.nim — Conflict Marker Gate
##
## Detects leftover Git merge/rebase conflict markers and
## CONFLICT_UNRESOLVED annotations in staged source files.
##
## An incomplete merge/rebases leaves markers like:
##   <<<<<<< HEAD      ~~~~~~~ ours
##   =======
##   >>>>>>> branch    ~~~~~~~ theirs
##
## Such files must be resolved before they can be committed. This gate
## scans for these markers and FAILS the commit when any are present.
##
## CLI:
##   conflict_marker_gate <repoRoot> <mode> <maxJobs> [files...]
##
## Scanning rules (per line, stripped):
##   - Line starts with "<<" i.e. `<<<<<<<` conflict-start marker
##   - Line starts with "===" i.e. `=======` conflict-separator marker
##   - Line starts with ">>>" i.e. `>>>>>>>` conflict-end marker
##   - Line contains "CONFLICT_UNRESOLVED" annotation
##
## See: tests/features/conflict_marker_gate.feature

import std/[os, strutils]

const GateTag = "[conflict-marker]"

func isConflictMarkerLine*(line: string): bool {.raises: [].} =
  ## True if a line is a leftover conflict marker.
  let trimmed = line.strip()
  result =
    trimmed.startsWith("<<<<<<<") or
    trimmed.startsWith("=======") or
    trimmed.startsWith(">>>>>>>")

func containsConflictAnnotation*(content: string): bool {.raises: [].} =
  ## True if the content contains a CONFLICT_UNRESOLVED annotation.
  for line in content.splitLines():
    if line.contains("CONFLICT_UNRESOLVED"):
      return true
  return false

func scanContent*(content: string): seq[string] {.raises: [].} =
  ## Scan file content for conflict markers.
  ## Returns the offending lines.
  var lineno = 1
  for line in content.splitLines():
    if isConflictMarkerLine(line):
      result.add("L" & $lineno & ": " & line.strip())
    inc lineno

type
  ScanOutcome = enum
    soClean
    soConflict

proc scanFile*(filePath: string): tuple[outcome: ScanOutcome, lines: seq[string]] {.raises: [CatchableError].} =
  ## Read and scan a single file for conflict markers.
  result = (soClean, @[])
  if not fileExists(filePath):
    return
  let content = try: readFile(filePath) except CatchableError: ""
  if containsConflictAnnotation(content):
    result.outcome = soConflict
    result.lines.add("<CONFLICT_UNRESOLVED>")
  let markers = scanContent(content)
  if markers.len > 0:
    result.outcome = soConflict
    result.lines.add(markers)

proc runConflictMarkerScan*(repoRoot: string, files: seq[string]): bool {.raises: [CatchableError].} =
  ## Scan the given files (or all .nim under repoRoot/src when empty).
  ## Returns true (PASS) when no conflict markers are found.
  var targets: seq[string]
  if files.len > 0:
    targets = files
  else:
    let srcDir = repoRoot / "src"
    if dirExists(srcDir):
      for path in walkDirRec(srcDir):
        if path.endsWith(".nim"):
          targets.add(path)

  for f in targets:
    let r = scanFile(f)
    if r.outcome == soConflict:
      return false
  return true

proc collectFindings*(repoRoot: string, files: seq[string]): seq[string] {.raises: [CatchableError].} =
  ## Collect human-readable conflict finding strings for stderr.
  var targets: seq[string]
  if files.len > 0:
    targets = files
  else:
    let srcDir = repoRoot / "src"
    if dirExists(srcDir):
      for path in walkDirRec(srcDir):
        if path.endsWith(".nim"):
          targets.add(path)
  for f in targets:
    let r = scanFile(f)
    if r.outcome == soConflict:
      for line in r.lines:
        result.add(f & ": " & line)

proc main() {.raises: [CatchableError].} =
  let args = commandLineParams()
  if args.len < 3:
    stdout.writeLine("Usage: conflict_marker_gate <repoRoot> <mode> <maxJobs> [files...]")
    quit(1)

  let repoRoot = args[0]
  var files: seq[string] = @[]
  for i in 3 ..< args.len:
    files.add(args[i])

  let passed = runConflictMarkerScan(repoRoot, files)

  if passed:
    stdout.writeLine(GateTag & " PASS — no conflict markers found")
    quit(0)
  else:
    let findings = collectFindings(repoRoot, files)
    stdout.writeLine(GateTag & " FAIL — unresolved conflict markers:")
    for f in findings:
      stdout.writeLine("  " & f)
    quit(1)

when isMainModule:
  main()

{.pop.}
