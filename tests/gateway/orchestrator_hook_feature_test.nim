## Orchestrator Hook Feature Test.
## Verifies the sequential gate execution engine entry points.
##
## Tests:
##   - resolveStageFromArgs stage resolution
##   - resolveGateStage enum mapping
##   - verifyAxiomRoot root marker detection
##   - AxiomRootMarker constant value

import std/[unittest, os, times]
import gate/orchestrator_hook
import gate/types

suite "Orchestrator Hook — Stage Resolution":

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

  test "resolveStageFromArgs returns binary name for post-commit":
    ## Given the binary is invoked as 'post-commit'
    ## When resolveStageFromArgs is called
    ## Then it returns "post-commit"
    check resolveStageFromArgs("post-commit", @[]) == "post-commit"

  test "resolveStageFromArgs falls back to first argument":
    ## Given the binary is invoked with an unknown name and args = @["ci"]
    ## When resolveStageFromArgs is called
    ## Then it returns the first argument
    check resolveStageFromArgs("unknown", @["ci"]) == "ci"

  test "resolveStageFromArgs returns empty for unknown binary and no args":
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

  test "resolveGateStage maps ci to gsPreCommit":
    ## Given the stage string "ci"
    ## When resolveGateStage is called
    ## Then it returns gsPreCommit (ci reuses pre-commit stage)
    check resolveGateStage("ci") == gsPreCommit

  test "resolveGateStage maps post-commit to gsManual":
    ## Given the stage string "post-commit"
    ## When resolveGateStage is called
    ## Then it returns gsManual (deferred gates run in manual mode)
    check resolveGateStage("post-commit") == gsManual

  test "resolveGateStage maps unknown stage to gsManual":
    ## Given an unrecognized stage string
    ## When resolveGateStage is called
    ## Then it returns gsManual
    check resolveGateStage("unknown_stage") == gsManual

suite "Orchestrator Hook — Root Verification":

  test "AxiomRootMarker constant is .axiom_root":
    ## Given the AxiomRootMarker constant
    ## When checked
    ## Then it equals ".axiom_root"
    check AxiomRootMarker == ".axiom_root"

  test "verifyAxiomRoot returns true when .axiom_root exists":
    ## Given the current working directory has a .axiom_root file
    ## When verifyAxiomRoot is called with this directory
    ## Then it returns true
    let tmpDir = getTempDir() / "axiom_root_test_" & $epochTime().int
    createDir(tmpDir)
    writeFile(tmpDir / ".axiom_root", "")
    check verifyAxiomRoot(tmpDir) == true
    removeDir(tmpDir)

  test "verifyAxiomRoot returns false when .axiom_root is missing":
    ## Given a directory without .axiom_root
    ## When verifyAxiomRoot is called
    ## Then it returns false
    let tmpDir = getTempDir() / "axiom_no_root_test_" & $epochTime().int
    createDir(tmpDir)
    check verifyAxiomRoot(tmpDir) == false
    removeDir(tmpDir)
