{.push raises: [CatchableError].}

## Hotspot Coverage Gate Feature Test.
## See tests/features/hotspot_coverage.feature for the specification.
##
## Validates the hotspot coverage gate: churn computation, hotspot
## identification, test-file detection, and structured pass/fail output.

import std/[os, osproc, strutils, unittest]

const
  projectRoot = currentSourcePath().parentDir().parentDir().parentDir()
  gateBin = projectRoot / "bin" / "hotspot_coverage_gate"

proc runGate(repoRoot: string = ""): (string, int) =
  ## Run the hotspot-coverage-gate binary. Returns (stdout+stderr, exitCode).
  let root = if repoRoot.len > 0: repoRoot else: projectRoot
  let cmd = gateBin & " " & quoteShell(root)
  result = execCmdEx(cmd)

proc runSelfTest(): (string, int) =
  ## Run the built-in self-test.
  result = execCmdEx(gateBin & " --self-test")

{.push warning[BareExcept]:off.}
suite "hotspot coverage gate — self-test":
  test "self-test passes with exit code 0":
    let (output, exitCode) = runSelfTest()
    check exitCode == 0
    check "self-test PASS" in output

suite "hotspot coverage gate — functional":
  test "gate runs on project root without error":
    let (output, exitCode) = runGate(projectRoot)
    # Gate should complete without crash (exit 0 or 1, not crash)
    check exitCode in [0, 1]
    # Must output either PASS or FAIL
    check "PASS" in output or "FAIL" in output

  test "gate output contains hotspot-coverage marker":
    let (output, _) = runGate(projectRoot)
    check "[hotspot-coverage]" in output

  test "gate runs on a fresh git repo with no src/ without crash":
    # Create a temporary git repo with no src/ files
    let tmpDir = getTempDir() / "hotspot_coverage_test_repo"
    discard execCmdEx("rm -rf " & quoteShell(tmpDir))
    discard execCmdEx("mkdir -p " & quoteShell(tmpDir))
    discard execCmdEx("git init " & quoteShell(tmpDir))
    # Configure git user for commit
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " config user.email 'test@test.com'")
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " config user.name 'Test'")
    # Add a dummy file so git log has something
    writeFile(tmpDir / "README.md", "# test")
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " add .")
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " commit -m 'init'")
    defer:
      discard execCmdEx("rm -rf " & quoteShell(tmpDir))
    let (output, exitCode) = runGate(tmpDir)
    # No src/*.nim files → 0 hotspots → PASS
    check exitCode == 0
    check "PASS" in output

  test "gate handles nonexistent path gracefully":
    let (output, exitCode) = runGate("/nonexistent/path/to/repo")
    # Should fail with ERROR message, not crash
    check exitCode != 0 or "ERROR" in output or "FAIL" in output

{.pop.}
{.pop.}
