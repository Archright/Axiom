import std/unittest
import std/json
import cli/wf_runners

## Strict mode is a parameter of the exit decision, not ambient environment:
## the caller reads AXIOM_REQUIRE_PERFECT_ASI / AXIOM_CONTINUE_ON_ERROR once at
## the I/O boundary and passes them in. Same document, explicit decision.
##
## Every success case carries a canonical `runOutcome` verdict block: summary
## counts are telemetry and never establish success (contract §7).

proc passReport(extra: JsonNode = nil): JsonNode =
  result = %*{
    "runOutcome": {"verdict": "PASS", "gateVerdict": "PASS"},
    "summary": {
      "asi": 1.0,
      "verified": 3,
      "failedCount": 0,
      "timeoutCount": 0,
      "blockingFailure": false,
      "fatalErrors": 0
    }
  }
  if not extra.isNil:
    for k, v in extra.pairs:
      result["summary"][k] = v

suite "axProofShortcutExitCode (param-driven strict mode)":

  test "nil/malformed summary returns exit code 1 (fail-closed per DEBT#290)":
    let cleanReport = %*{ "notSummary": {} }
    check axProofShortcutExitCode(cleanReport) == 1

  test "blockingFailure true returns exit code 1":
    let mockReport = %*{
      "runOutcome": {"verdict": "PASS", "gateVerdict": "PASS"},
      "summary": {
        "asi": 1.0,
        "blockingFailure": true,
        "fatalErrors": 0
      }
    }
    check axProofShortcutExitCode(mockReport) == 1

  test "clean canonical PASS report returns exit code 0":
    check axProofShortcutExitCode(passReport()) == 0

  test "summary-only report without a verdict is fail-closed (1)":
    let mockReport = %*{
      "summary": {
        "asi": 1.0,
        "verified": 3,
        "failedCount": 0,
        "timeoutCount": 0,
        "blockingFailure": false,
        "fatalErrors": 0
      }
    }
    check axProofShortcutExitCode(mockReport) == 1

  test "requirePerfectAsi rejects an imperfect verifiedRatio only when asked":
    let mockReport = passReport(%*{"verifiedRatio": 0.75})
    check axProofShortcutExitCode(mockReport) == 0
    check axProofShortcutExitCode(mockReport, requirePerfectAsi = true) == 1

  test "requirePerfectAsi rejects a failed lean4 re-verification":
    let mockReport = passReport(%*{"verifiedRatio": 1.0, "lean4Reverified": false})
    check axProofShortcutExitCode(mockReport) == 0
    check axProofShortcutExitCode(mockReport, requirePerfectAsi = true) == 1

  test "continueOnError downgrades blockingFailure to the run decision":
    let mockReport = passReport(%*{"blockingFailure": true})
    check axProofShortcutExitCode(mockReport) == 1
    # With the guard waived the canonical verdict decides: PASS -> 0.
    check axProofShortcutExitCode(mockReport, continueOnError = true) == 0

  test "fatalErrors stays fail-closed even with continueOnError":
    let mockReport = passReport(%*{"fatalErrors": 2})
    check axProofShortcutExitCode(mockReport, continueOnError = true) == 1