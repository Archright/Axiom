{.push raises: [CatchableError].}

## Binary Freshness Gate Tests — Unit tests for gate/binary_freshness_gate.nim
## Tests FreshnessResult, EnvironmentIntegrity, verifyEnvironmentIntegrity,
## checkBinaryFreshness, and formatFreshnessReport.

import std/[unittest, os, times, strutils]
import gate/runners/binary_freshness_gate

# ---------------------------------------------------------------------------
# EnvironmentIntegrity
# ---------------------------------------------------------------------------

suite "verifyEnvironmentIntegrity":
  test "existing .axiom_root → rootValid=true":
    let tmpDir = getTempDir() / "axiom_test_envint_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / ".axiom_root", "")
    let integrity = verifyEnvironmentIntegrity(tmpDir)
    check integrity.rootValid == true

  test "missing .axiom_root → rootValid=false":
    let tmpDir = getTempDir() / "axiom_test_envint_missing_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let integrity = verifyEnvironmentIntegrity(tmpDir)
    check integrity.rootValid == false

  test "non-existent directory → rootValid=false":
    let integrity = verifyEnvironmentIntegrity("/nonexistent/path/xyz999")
    check integrity.rootValid == false

# ---------------------------------------------------------------------------
# FreshnessResult type
# ---------------------------------------------------------------------------

suite "FreshnessResult type":
  test "default construction":
    var fr = FreshnessResult()
    check fr.binaryPath.len == 0
    check fr.binaryExists == false
    check fr.isStale == false
    check fr.staleSources.len == 0

  test "non-existent binary → isStale=true, binaryExists=false":
    let tmpDir = getTempDir() / "axiom_test_fresh_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let srcFile = tmpDir / "source.nim"
    writeFile(srcFile, "echo 1")
    let fr = checkBinaryFreshness(tmpDir / "nonexistent_bin", [srcFile])
    check fr.binaryExists == false
    check fr.isStale == true

# ---------------------------------------------------------------------------
# checkBinaryFreshness
# ---------------------------------------------------------------------------

suite "checkBinaryFreshness":
  test "binary exists but no manifest → isStale=true (hash mismatch)":
    let tmpDir = getTempDir() / "axiom_test_cb_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let binPath = tmpDir / "mybin"
    let srcFile = tmpDir / "src.nim"
    writeFile(binPath, "binary content")
    writeFile(srcFile, "source content")
    let fr = checkBinaryFreshness(binPath, [srcFile])
    check fr.binaryExists == true
    check fr.isStale == true
    check fr.staleSources.len > 0

  test "non-existent source files listed as missing":
    let tmpDir = getTempDir() / "axiom_test_cb_missing_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let binPath = tmpDir / "mybin"
    writeFile(binPath, "binary content")
    let fr = checkBinaryFreshness(binPath, ["/nonexistent/src.nim"])
    check fr.binaryExists == true
    check fr.isStale == true
    check fr.staleSources.len == 1
    check "missing" in fr.staleSources[0]

  test "empty sources list with existing binary":
    let tmpDir = getTempDir() / "axiom_test_cb_empty_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let binPath = tmpDir / "mybin"
    writeFile(binPath, "data")
    let fr = checkBinaryFreshness(binPath, [])
    check fr.binaryExists == true
    check fr.isStale == true  # manifest empty → hash mismatch

# ---------------------------------------------------------------------------
# formatFreshnessReport
# ---------------------------------------------------------------------------

suite "formatFreshnessReport":
  test "non-existent binary → FAIL report":
    var fr = FreshnessResult(
      binaryPath: "bin/ax",
      binaryExists: false,
      isStale: true
    )
    let report = formatFreshnessReport(fr)
    check "FAIL" in report
    check "does not exist" in report

  test "fresh binary → PASS report":
    var fr = FreshnessResult(
      binaryPath: "bin/ax",
      binaryExists: true,
      isStale: false
    )
    let report = formatFreshnessReport(fr)
    check "PASS" in report
    check "up to date" in report

  test "stale binary → STALE report with source list":
    var fr = FreshnessResult(
      binaryPath: "bin/ax",
      binaryExists: true,
      isStale: true,
      staleSources: @["src/cli/main.nim (missing)", "src/cli/types.nim (missing)"]
    )
    let report = formatFreshnessReport(fr)
    check "STALE" in report
    check "2 source(s)" in report
    check "src/cli/main.nim" in report

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

suite "exported constants":
  test "DefaultBinaryPath is bin/ax":
    check DefaultBinaryPath == "bin/ax"

  test "GateHookBinaryPath is bin/gate_hook":
    check GateHookBinaryPath == "bin/gate_hook"

  test "CliSourcePaths is non-empty array":
    check CliSourcePaths.len > 0

  test "GateHookSourcePaths is non-empty array":
    check GateHookSourcePaths.len > 0

  test "CliSourcePaths contains main.nim":
    var found = false
    for p in CliSourcePaths:
      if "main.nim" in p:
        found = true
        break
    check found

{.pop.}
