## Integrity Workflow Gate Test
## Business scenario: Verify the 4-step integrity workflow orchestrator
## runs intent → spec → test → procedure in order and fails fast.

import std/[strutils, unittest]
import core/utils/test_helper

const
  GateBinary = "bin/integrity-workflow"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "integrity-workflow":
  test "self-test passes":
    ## Business scenario: Gate self-test validates step list and infrastructure.
    let (output, exitCode) = runGateInRepo(GateBinary,@["--self-test"])
    check exitCode == 0
    check output.contains("passed")
    check output.contains("0 failed")

  test "dry-run prints steps without execution":
    ## Business scenario: --dry-run shows the 4 planned steps.
    let (output, exitCode) = runGateInRepo(GateBinary,@["--dry-run"])
    check exitCode == 0
    check output.contains("--dry-run")
    check output.contains("intent-gate")
    check output.contains("spec-presence-gate")
    check output.contains("test-coverage-gate")
    check output.contains("procedure-gate")
    check output.contains("Step 1/4")
    check output.contains("Step 4/4")

  test "dry-run shows READY or MISSING for each gate":
    ## Business scenario: Each step shows its resolution status.
    let (output, exitCode) = runGateInRepo(GateBinary,@["--dry-run"])
    check exitCode == 0
    check output.contains("READY") or output.contains("MISSING")

  test "self-test validates 4 steps in canonical order":
    ## Business scenario: The workflow enforces Intent → Spec → Test → Code.
    let (output, exitCode) = runGateInRepo(GateBinary,@["--self-test"])
    check exitCode == 0
    check output.contains("4 steps defined")
    check output.contains("canonical order verified")

  test "self-test validates repo root resolution":
    ## Business scenario: Deterministic root resolution via .axiom_root works.
    let (output, exitCode) = runGateInRepo(GateBinary,@["--self-test"])
    check exitCode == 0
    check output.contains("REPO_ROOT")

  test "self-test validates history write":
    ## Business scenario: Gate history recording works end-to-end.
    let (output, exitCode) = runGateInRepo(GateBinary,@["--self-test"])
    check exitCode == 0
    check output.contains("history write succeeded")
