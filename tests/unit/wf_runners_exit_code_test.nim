import std/[json, unittest]
import cli/wf_runners
import cli/cli_outcome
import core/utils/constants
import core/utils/decision_algebra

## Every case below is re-derived from the ONE run-exit rule
## (core/utils/decision_algebra.projectRunOutcome). The rule consumes only the
## canonical `runOutcome.verdict` authority block; `summary` is telemetry and
## can never establish success. A document without a readable verdict is
## UNRESOLVED and exits non-zero.

proc canonical(verdict: string; gate: string): JsonNode =
  %*{"runOutcome": {"verdict": verdict, "gateVerdict": gate},
     "summary": {"verified": 2, "failedCount": 0, "timeoutCount": 0}}

suite "v1 exit-state contract (productization_contract.md §7)":

  test "canonical PASS verdict -> success (0)":
    let reportNode = canonical("PASS", "PASS")
    check projectRunOutcome(reportNode) == OutcomeContinue
    check axProofShortcutExitCode(reportNode) == 0

  test "canonical FAIL verdict -> verification-failure (1)":
    let reportNode = canonical("FAIL", "FAIL")
    check projectRunOutcome(reportNode) == OutcomeBlock
    check axProofShortcutExitCode(reportNode) == 1

  test "INCONCLUSIVE verdict -> UNRESOLVED, exit 1":
    let reportNode = canonical("INCONCLUSIVE", "FAIL")
    check projectRunOutcome(reportNode) == OutcomeUnresolved
    check axProofShortcutExitCode(reportNode) == 1

  test "BLOCKED verdict -> UNRESOLVED, exit 1":
    let reportNode = canonical("BLOCKED", "FAIL")
    check projectRunOutcome(reportNode) == OutcomeUnresolved
    check axProofShortcutExitCode(reportNode) == 1

  test "unknown verdict vocabulary -> UNRESOLVED, exit 1":
    let reportNode = canonical("PROBABLY_FINE", "PASS")
    check projectRunOutcome(reportNode) == OutcomeUnresolved
    check axProofShortcutExitCode(reportNode) == 1

  test "verdict/gateVerdict contradiction -> UNRESOLVED, exit 1":
    ## A PASS verdict whose serialized projection says FAIL is an UNKNOWN
    ## document, never a PASS.
    check projectRunOutcome(canonical("PASS", "FAIL")) == OutcomeUnresolved
    check axProofShortcutExitCode(canonical("PASS", "FAIL")) == 1
    check projectRunOutcome(canonical("FAIL", "PASS")) == OutcomeUnresolved
    check axProofShortcutExitCode(canonical("FAIL", "PASS")) == 1

  test "absent gateVerdict leaves the verdict authoritative":
    let reportNode = %*{"runOutcome": {"verdict": "PASS"}, "summary": {"verified": 1}}
    check projectRunOutcome(reportNode) == OutcomeContinue
    check axProofShortcutExitCode(reportNode) == 0

  test "summary-only document is telemetry, never success (1)":
    ## The closed hole: verified>0 with zero recorded failures used to exit 0
    ## even when no canonical verdict existed.
    let reportNode = %*{"summary": {"verified": 2, "failedCount": 0, "timeoutCount": 0}}
    check projectRunOutcome(reportNode) == OutcomeUnresolved
    check axProofShortcutExitCode(reportNode) == 1

  test "summary-only with blocked obligations is not success (1)":
    let reportNode = %*{"summary": {"verified": 1, "failedCount": 0, "timeoutCount": 0,
                                    "blockedCount": 1}}
    check projectRunOutcome(reportNode) == OutcomeUnresolved
    check axProofShortcutExitCode(reportNode) == 1

  test "topology-scan summary without verdict is UNRESOLVED, exit 1":
    ## Preview is a separate execution path, not an inference from a boolean
    ## inside a verification document.
    let reportNode = %*{"summary": {"topologyScanComplete": true, "symbolCount": 4}}
    check projectRunOutcome(reportNode) == OutcomeUnresolved
    check axProofShortcutExitCode(reportNode) == 1

  test "malformed runOutcome block is UNRESOLVED, exit 1":
    check projectRunOutcome(%*{"runOutcome": "PASS"}) == OutcomeUnresolved
    check projectRunOutcome(%*{"runOutcome": {"verdict": 1}}) == OutcomeUnresolved
    check projectRunOutcome(%*{"runOutcome": {"verdict": "PASS", "gateVerdict": 1}}) ==
      OutcomeUnresolved
    check axProofShortcutExitCode(%*{"runOutcome": "PASS"}) == 1

  test "missing summary is a fail-closed input constraint (1)":
    let reportNode = %*{"runOutcome": {"verdict": "PASS", "gateVerdict": "PASS"}}
    check axProofShortcutExitCode(reportNode) == 1

  test "requirePerfectAsi can only demote, never promote":
    var imperfect = canonical("PASS", "PASS")
    imperfect["summary"]["verifiedRatio"] = %0.9
    check axProofShortcutExitCode(imperfect) == 0
    check axProofShortcutExitCode(imperfect, requirePerfectAsi = true) == 1

  test "blockingFailure is a fail-closed guard":
    var reportNode = canonical("PASS", "PASS")
    reportNode["summary"]["blockingFailure"] = %true
    check axProofShortcutExitCode(reportNode) == 1
    check axProofShortcutExitCode(reportNode, continueOnError = true) == 0

  test "fatalErrors is a fail-closed guard":
    var reportNode = canonical("PASS", "PASS")
    reportNode["summary"]["fatalErrors"] = %1
    check axProofShortcutExitCode(reportNode) == 1

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