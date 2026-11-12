import std/unittest
import std/json
import cli/wf_runners

## Strict mode is a parameter of the exit decision, not ambient environment:
## the caller reads AXIOM_REQUIRE_PERFECT_ASI / AXIOM_CONTINUE_ON_ERROR once at
## the I/O boundary and passes them in. Same document, explicit decision.

suite "axProofShortcutExitCode (param-driven strict mode)":

  test "nil/malformed summary returns exit code 1 (fail-closed per DEBT#290)":
    let cleanReport = %*{ "notSummary": {} }
    check axProofShortcutExitCode(cleanReport) == 1

  test "blockingFailure true returns exit code 1":
    let mockReport = %*{
      "summary": {
        "asi": 1.0,
        "blockingFailure": true,
        "fatalErrors": 0
      }
    }
    check axProofShortcutExitCode(mockReport) == 1

  test "clean report with no errors returns exit code 0":
    let mockReport = %*{
      "summary": {
        "asi": 1.0,
        "blockingFailure": false,
        "fatalErrors": 0
      }
    }
    check axProofShortcutExitCode(mockReport) == 0

  test "requirePerfectAsi rejects an imperfect verifiedRatio only when asked":
    let mockReport = %*{
      "summary": {
        "verified": 3,
        "failedCount": 0,
        "timeoutCount": 0,
        "verifiedRatio": 0.75
      }
    }
    check axProofShortcutExitCode(mockReport) == 0
    check axProofShortcutExitCode(mockReport, requirePerfectAsi = true) == 1

  test "requirePerfectAsi rejects a failed lean4 re-verification":
    let mockReport = %*{
      "summary": {
        "verified": 3,
        "failedCount": 0,
        "timeoutCount": 0,
        "verifiedRatio": 1.0,
        "lean4Reverified": false
      }
    }
    check axProofShortcutExitCode(mockReport) == 0
    check axProofShortcutExitCode(mockReport, requirePerfectAsi = true) == 1

  test "continueOnError downgrades blockingFailure to the run decision":
    let mockReport = %*{
      "summary": {
        "verified": 3,
        "failedCount": 0,
        "timeoutCount": 0,
        "blockingFailure": true
      }
    }
    check axProofShortcutExitCode(mockReport) == 1
    # With the guard waived the run itself decides: clean run -> 0.
    check axProofShortcutExitCode(mockReport, continueOnError = true) == 0

  test "fatalErrors stays fail-closed even with continueOnError":
    let mockReport = %*{
      "summary": {
        "verified": 3,
        "failedCount": 0,
        "timeoutCount": 0,
        "fatalErrors": 2
      }
    }
    check axProofShortcutExitCode(mockReport, continueOnError = true) == 1
