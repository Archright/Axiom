import std/[json, unittest]
import cli/wf_runners
import cli/cli_outcome
import core/utils/constants
import core/utils/decision_algebra

## Every case below is re-derived from the ONE run-exit rule
## (core/utils/decision_algebra.projectRunOutcome). A timeout is a hang-guard
## node abort, not a verification verdict, but the exit axis is fail-closed
## about it: incomplete verification is "claims not established" -> 1.

suite "v1 exit-state contract (productization_contract.md §7)":

  test "topology-only preview (no verified key) preserves legacy behavior -> 0":
    let reportNode = %*{"summary": {"topologyScanComplete": true, "symbolCount": 4}}
    check axProofShortcutExitCode(reportNode) == 0
    check projectRunOutcome(reportNode) == OutcomeContinue

  test "verification ran, verified>0, failed=0, timeout=0 -> success (0)":
    let reportNode = %*{"summary": {"verified": 2, "failedCount": 0, "timeoutCount": 0}}
    check axProofShortcutExitCode(reportNode) == 0
    check projectRunOutcome(reportNode) == OutcomeContinue

  test "verification ran, verified=0, failed=1 -> verification-failure (1)":
    let reportNode = %*{"summary": {"verified": 0, "failedCount": 1, "timeoutCount": 0}}
    check axProofShortcutExitCode(reportNode) == 1
    check projectRunOutcome(reportNode) == OutcomeBlock

  test "verification ran, verified=2, failed=1 -> verification-failure (1)":
    let reportNode = %*{"summary": {"verified": 2, "failedCount": 1, "timeoutCount": 0}}
    check axProofShortcutExitCode(reportNode) == 1
    check projectRunOutcome(reportNode) == OutcomeBlock

  test "verification ran, verified=0, failed=0, timeout=1 -> verification-failure (1)":
    ## Nothing was established and the run was aborted: BLOCK on the exit axis.
    let reportNode = %*{"summary": {"verified": 0, "failedCount": 0, "timeoutCount": 1}}
    check axProofShortcutExitCode(reportNode) == 1
    check projectRunOutcome(reportNode) == OutcomeBlock

  test "verification ran, verified=2, failed=0, timeout=1 -> UNRESOLVED, exit 1":
    ## The hole this unification closes: a timeout-only run used to exit 0
    ## whenever verified>0. Incomplete verification is not success.
    let reportNode = %*{"summary": {"verified": 2, "failedCount": 0, "timeoutCount": 1}}
    check axProofShortcutExitCode(reportNode) == 1
    check projectRunOutcome(reportNode) == OutcomeUnresolved

  test "verification ran, verified>0, failed=1, timeout=2 -> BLOCK, exit 1":
    let reportNode = %*{"summary": {"verified": 3, "failedCount": 1, "timeoutCount": 2}}
    check axProofShortcutExitCode(reportNode) == 1
    check projectRunOutcome(reportNode) == OutcomeBlock

  test "verification ran, verified=0, failed=0 (empty run) -> success (0)":
    ## §7 requires a failed or timed-out node to make `verified == 0` a
    ## failure; an empty (no-obligation) run establishes nothing to fail.
    let reportNode = %*{"summary": {"verified": 0, "failedCount": 0, "timeoutCount": 0}}
    check axProofShortcutExitCode(reportNode) == 0
    check projectRunOutcome(reportNode) == OutcomeContinue

  test "counts absent alongside verified -> UNRESOLVED, fail-closed exit 1":
    ## "No failures recorded" is a claim that must be readable to be believed.
    let reportNode = %*{"summary": {"verified": 4}}
    check axProofShortcutExitCode(reportNode) == 1
    check projectRunOutcome(reportNode) == OutcomeUnresolved

  test "missing summary -> UNRESOLVED, fail-closed exit 1":
    let reportNode = %*{"notSummary": {}}
    check axProofShortcutExitCode(reportNode) == 1
    check projectRunOutcome(reportNode) == OutcomeUnresolved

  test "existing fail-closed signals still return 1":
    let reportNode = %*{"summary": {"verified": 1, "failedCount": 0, "fatalErrors": 1}}
    check axProofShortcutExitCode(reportNode) == 1

  test "blockingFailure without continue-on-error is fail-closed (1)":
    let reportNode = %*{"summary": {"verified": 1, "failedCount": 0, "blockingFailure": true}}
    check axProofShortcutExitCode(reportNode) == 1

  test "strict guards are parameters, not ambient environment":
    ## The decision function reads no environment: the same document with
    ## different parameters is a different, explicit decision.
    let imperfect = %*{"summary": {"verified": 2, "failedCount": 0, "timeoutCount": 0,
                                   "verifiedRatio": 0.9}}
    check axProofShortcutExitCode(imperfect) == 0
    check axProofShortcutExitCode(imperfect, requirePerfectAsi = true) == 1

  test "report schemaVersion const is stable contract identity":
    check axiomReportSchemaVersion == "axiom.report.v1"

suite "R7 CliOutcome 5-state gold matrix (design/r7_cli_outcome_contract.md)":

  test "SUCCESS maps to exit code 0":
    check exitCode(CliOutcome.SUCCESS) == 0

  test "NOT_CURRENT maps to exit code 4":
    check exitCode(CliOutcome.NOT_CURRENT) == 4

  test "VERIFICATION_FAILURE maps to exit code 1":
    check exitCode(CliOutcome.VERIFICATION_FAILURE) == 1

  test "INTERNAL_ERROR maps to exit code 2":
    check exitCode(CliOutcome.INTERNAL_ERROR) == 2

  test "INVALID_INPUT maps to exit code 3":
    check exitCode(CliOutcome.INVALID_INPUT) == 3

  test "INV-1: no internal error is ever mapped to SUCCESS(0)":
    # INTERNAL_ERROR must always map to 2, never 0.
    check exitCode(CliOutcome.INTERNAL_ERROR) != 0

  test "INV-7: mapping is bijective within valid range {0,1,2,3,4}":
    # Each outcome maps to a unique exit code; each exit code maps back uniquely.
    let codes = @[exitCode(CliOutcome.SUCCESS),
                  exitCode(CliOutcome.NOT_CURRENT),
                  exitCode(CliOutcome.VERIFICATION_FAILURE),
                  exitCode(CliOutcome.INTERNAL_ERROR),
                  exitCode(CliOutcome.INVALID_INPUT)]
    check codes.len == 5
    for i in 0 ..< codes.high:
      for j in i+1 ..< codes.high:
        check codes[i] != codes[j]
    # All codes are in {0,1,2,3,4}
    for c in codes:
      check c >= 0 and c <= 4

  test "severity order: INTERNAL_ERROR > INVALID_INPUT > VERIFICATION_FAILURE > NOT_CURRENT > SUCCESS":
    ## Enum declaration order is ascending severity — the order the r7
    ## contract documents, machine-checked directly via ordinals.
    check ord(CliOutcome.SUCCESS) < ord(CliOutcome.NOT_CURRENT)
    check ord(CliOutcome.NOT_CURRENT) < ord(CliOutcome.VERIFICATION_FAILURE)
    check ord(CliOutcome.VERIFICATION_FAILURE) < ord(CliOutcome.INVALID_INPUT)
    check ord(CliOutcome.INVALID_INPUT) < ord(CliOutcome.INTERNAL_ERROR)