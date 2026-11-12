{.push raises: [CatchableError].}

## Conflict Marker Gate Feature Test.
## See tests/features/conflict_marker_gate.feature for the specification.
##
## Validates the conflict marker detection gate.
## Tests observable behavior: exit codes and findings JSON against
## compiled binary at bin/conflict_marker_gate.

import std/[os, osproc, strutils, unittest, json]

const
  projectRoot = currentSourcePath().parentDir().parentDir().parentDir()
  gateBin = projectRoot / "bin" / "conflict_marker_gate"

proc runGate(repoRoot: string, files: seq[string] = @[]): (string, int) =
  var cmd = gateBin & " " & quoteShell(repoRoot) & " pre-commit 1"
  for f in files:
    cmd.add(" " & quoteShell(f))
  result = execCmdEx(cmd)

proc runGateOnContent(repoRoot, filename, content: string): (string, int) =
  ## Create a temp file, run gate on it, then clean up.
  let tmpFile = repoRoot / filename
  writeFile(tmpFile, content)
  defer:
    if fileExists(tmpFile):
      removeFile(tmpFile)
  result = runGate(repoRoot, @[tmpFile])

{.push warning[BareExcept]:off.}
suite "conflict marker gate — CLI validator":
  # -- conflict marker detection --

  test "detects conflict markers in staged files":
    let content = """
proc hello() =
  echo "hello"
<<<<<<< HEAD
  echo "ours"
=======
  echo "theirs"
>>>>>>> branch
"""
    let (output, exitCode) = runGateOnContent(projectRoot, "tmp_conflict_test.nim", content)
    check exitCode == 1
    check "FAIL" in output

  test "passes when no conflict markers found":
    let content = """
proc hello() =
  echo "hello"
  echo "world"
"""
    let (output, exitCode) = runGateOnContent(projectRoot, "tmp_clean_test.nim", content)
    check exitCode == 0
    check "PASS" in output

  test "detects CONFLICT_UNRESOLVED annotation":
    let content = """
proc hello() =
  # CONFLICT_UNRESOLVED
  echo "hello"
"""
    let (output, exitCode) = runGateOnContent(projectRoot, "tmp_annotation_test.nim", content)
    check exitCode == 1
    check "FAIL" in output

  test "exits with usage when no args provided":
    let (output, exitCode) = execCmdEx(gateBin)
    check exitCode == 1
    check "Usage" in output
