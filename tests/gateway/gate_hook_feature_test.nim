## Gate Hook Feature Test.
## See tests/features/gate_hook.feature for the specification.
##
## Verifies the gate hook entry point:
##   - Module compiles (gate_hook delegates to orchestrator_hook)
##   - Stage resolution from binary name / arguments
##   - GateStage enum mapping
##   - Dangling symlink detection logic

import std/[unittest, os, strutils, times]
import gate/runners/gate_hook
import gate/orchestrator_hook
import gate/gate_contract
import gate/types

suite "Gate Hook — Stage Resolution":
  test "gate_hook module compiles and can be imported":
    ## Given the gate_hook module wraps orchestrator_hook
    ## When imported by a test
    ## Then compilation succeeds
    check true  # axiom:compile-check

  test "resolveStageFromArgs returns binary name for pre-commit":
    ## Given the binary is invoked as 'pre-commit'
    ## When resolveStageFromArgs is called
    ## Then it returns "pre-commit"
    check resolveStageFromArgs("pre-commit", @[]) == "pre-commit"

  test "resolveStageFromArgs returns binary name for pre-push":
    ## Given the binary is invoked as 'pre-push'
    ## When resolveStageFromArgs is called
    ## Then it returns "pre-push"
    check resolveStageFromArgs("pre-push", @[]) == "pre-push"

  test "resolveStageFromArgs falls back to first argument":
    ## Given the binary is invoked with an unknown name but args = @["ci"]
    ## When resolveStageFromArgs is called
    ## Then it returns the first argument
    check resolveStageFromArgs("gate_hook", @["ci"]) == "ci"

  test "resolveStageFromArgs returns empty string when no args":
    ## Given the binary is invoked with an unknown name and no arguments
    ## When resolveStageFromArgs is called
    ## Then it returns empty string
    check resolveStageFromArgs("unknown_binary", @[]) == ""

  test "resolveGateStage maps pre-commit to gsPreCommit":
    ## Given the stage string "pre-commit"
    ## When resolveGateStage is called
    ## Then it returns gsPreCommit
    check resolveGateStage("pre-commit") == gsPreCommit

  test "resolveGateStage maps pre-push to gsPrePush":
    ## Given the stage string "pre-push"
    ## When resolveGateStage is called
    ## Then it returns gsPrePush
    check resolveGateStage("pre-push") == gsPrePush

  test "resolveGateStage maps ci to gsPreCommit (special case)":
    ## Given the stage string "ci"
    ## When resolveGateStage is called
    ## Then it returns gsPreCommit (ci reuses pre-commit stage)
    check resolveGateStage("ci") == gsPreCommit

  test "resolveGateStage maps unknown stage to gsManual":
    ## Given an unrecognized stage string
    ## When resolveGateStage is called
    ## Then it returns gsManual
    check resolveGateStage("unknown") == gsManual

suite "Gate Hook — Dangling Symlink Detection":
  setup:
    let tmpDir = getTempDir() / "axiom_symlink_test_" & $epochTime().int
    createDir(tmpDir / "bin")

  teardown:
    removeDir(tmpDir)

  test "dangling symlink is detected and can be removed":
    ## Given a bin/ directory with a symlink pointing to a nonexistent target
    ## When the dangling symlink detection logic runs
    ## Then the symlink is removed
    let binDir = tmpDir / "bin"
    # Create a symlink to a nonexistent target
    createSymlink("/nonexistent/target/file", binDir / "dangling_link")
    check symlinkExists(binDir / "dangling_link")
    check not fileExists(binDir / "dangling_link")
    # Replicate the gate_hook dangling symlink detection logic
    for kind, path in walkDir(binDir):
      if kind == pcLinkToFile or kind == pcLinkToDir:
        if not fileExists(path):
          removeFile(path)
    check not symlinkExists(binDir / "dangling_link")

  test "valid symlink is preserved during detection":
    ## Given a bin/ directory with a valid symlink
    ## When the dangling symlink detection logic runs
    ## Then the symlink is preserved
    let binDir = tmpDir / "bin"
    let target = binDir / "real_target"
    writeFile(target, "data")
    createSymlink(target, binDir / "valid_link")
    check symlinkExists(binDir / "valid_link")
    # Run detection logic
    for kind, path in walkDir(binDir):
      if kind == pcLinkToFile or kind == pcLinkToDir:
        if not fileExists(path):
          removeFile(path)
    # valid_link should still exist
    check symlinkExists(binDir / "valid_link")

  test "non-symlink files in bin/ are untouched":
    ## Given a bin/ directory with a regular file (not a symlink)
    ## When the dangling symlink detection logic runs
    ## Then the file is untouched
    let binDir = tmpDir / "bin"
    writeFile(binDir / "regular_file", "content")
    # Run detection logic
    for kind, path in walkDir(binDir):
      if kind == pcLinkToFile or kind == pcLinkToDir:
        if not fileExists(path):
          removeFile(path)
    check fileExists(binDir / "regular_file")
    check readFile(binDir / "regular_file") == "content"

suite "Gate Hook — AOT pre-flight entry resolution":
  test "every manifest gate entry resolves to an on-disk source file":
    ## Given the SSOT gate list consumed by the CI AOT guard
    ## When every entry is audited
    ## Then none is skipped or unresolved (DEBT#520)
    let report = auditAotPreflightEntries(allGates(), getCurrentDir())
    check report.resolved.len == allGates().len
    check report.resolved.len == AxiomTotalGates
    check report.skipped.len == 0
    check report.unresolved.len == 0
    for resolved in report.resolved:
      check resolved.sourcePath.endsWith(".nim")
      check fileExists(getCurrentDir() / resolved.sourcePath)

  test "extensionless entry resolves through the '.nim' candidate":
    ## Given an entry declared without its extension
    ## When audited
    ## Then the resolver recovers the .nim source path
    let report = auditAotPreflightEntries(
      @[GateConfig(id: "anti-theater-gate", entry: "src/gate/runners/anti_theater_gate")],
      getCurrentDir())
    check report.resolved.len == 1
    check report.resolved[0].sourcePath == "src/gate/runners/anti_theater_gate.nim"

  test "missing non-empty entry is reported unresolved (fail-closed input)":
    ## Given an entry whose source file does not exist
    ## When audited
    ## Then the entry is reported with its id, not silently skipped
    let report = auditAotPreflightEntries(
      @[GateConfig(id: "deleted-gate", entry: "src/gate/runners/deleted_gate")],
      getCurrentDir())
    check report.unresolved.len == 1
    check report.unresolved[0].id == "deleted-gate"
    check report.unresolved[0].sourcePath == ""
    check report.resolved.len == 0
    check report.skipped.len == 0

  test "empty entry is recorded as a declared non-file skip":
    ## Given an entry declared empty (non-file gate contract)
    ## When audited
    ## Then it is recorded as a skip, not as a resolution failure
    let report = auditAotPreflightEntries(
      @[GateConfig(id: "in-process-gate", entry: "")], getCurrentDir())
    check report.skipped.len == 1
    check report.skipped[0].id == "in-process-gate"
    check report.unresolved.len == 0
    check report.resolved.len == 0
