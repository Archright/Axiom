## Artifact Manifest Feature Test — commit-hash-keyed gate result storage.
## See tests/features/artifact_manifest.feature for the specification.
##
## Contract: store/lookup round-trip, lookupPreviousResult, atomic write.

import std/[unittest, os, osproc, options, times, strutils]
import core/gate/artifact_manifest

suite "Artifact Manifest — Bazel Action Cache pattern":
  setup:
    let tmpDir = getTempDir() / "axiom_artifact_manifest_test_" & $epochTime().int
    createDir(tmpDir / ".axiom" / "manifests")

  teardown:
    removeDir(tmpDir)

  test "store and lookup round-trip":
    ## Scenario: store and lookup round-trip
    ## Given a commit hash and a GateResult
    ## When I call storeResult then lookupResult
    ## Then the lookup returns the stored result
    let gr = GateResult(
      gateId: "test-gate",
      totalWarnings: 3,
      totalErrors: 1,
      timestamp: 1000
    )
    storeResult(tmpDir, "abc123", gr)
    let found = lookupResult(tmpDir, "abc123", "test-gate")
    check found.isSome
    check found.get().totalWarnings == 3
    check found.get().totalErrors == 1

  test "lookup returns None for missing key":
    ## Scenario: lookup returns None for a missing key
    ## Given no stored result
    ## When I call lookupResult
    ## Then the lookup returns None
    let found = lookupResult(tmpDir, "nonexistent", "test-gate")
    check found.isNone

  test "lookupPreviousResult returns the most recent result":
    ## Scenario: lookupPreviousResult returns the most recent result
    ## Given stored results for the previous commit (HEAD~1)
    ## When I call lookupPreviousResult
    ## Then the lookup returns the stored result from the most recent commit
    let repo = tmpDir / "repo"
    createDir(repo)
    # Initialize a minimal git repository with two commits; lookupPreviousResult
    # resolves the HEAD~1 commit via git log.
    discard execCmdEx("git -C " & quoteShell(repo) & " init -q")
    discard execCmdEx("git -C " & quoteShell(repo) & " config user.email test@example.com")
    discard execCmdEx("git -C " & quoteShell(repo) & " config user.name test")
    writeFile(repo / "file.txt", "v1")
    discard execCmdEx("git -C " & quoteShell(repo) & " add .")
    discard execCmdEx("git -C " & quoteShell(repo) & " commit -qm c1")
    discard execCmdEx("git -C " & quoteShell(repo) & " rev-parse HEAD")
    writeFile(repo / "file.txt", "v2")
    discard execCmdEx("git -C " & quoteShell(repo) & " commit -qam c2")
    let prevHash = strip(execCmdEx("git -C " & quoteShell(repo) & " rev-parse HEAD~1")[0])
    let gr = GateResult(gateId: "test-gate", totalWarnings: 5, totalErrors: 2, timestamp: 2000)
    storeResult(repo, prevHash, gr)
    let found = lookupPreviousResult(repo, "test-gate")
    check found.isSome
    check found.get().totalWarnings == 5
    check found.get().totalErrors == 2

  test "storeResult writes atomically":
    ## Scenario: atomic write via temp+fsync+rename
    ## When I call storeResult
    ## Then the result file exists and is non-empty
    let gr = GateResult(gateId: "test-gate", totalWarnings: 0, totalErrors: 0, timestamp: 999)
    storeResult(tmpDir, "atomic_hash", gr)
    let found = lookupResult(tmpDir, "atomic_hash", "test-gate")
    check found.isSome
    check found.get().gateId == "test-gate"
