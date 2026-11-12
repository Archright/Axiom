## gate_types_impl_test.nim
## Business scenario tests for gate/gate_types_impl.nim — the utility functions
## for gate type contracts.
##
## This module is part of the #5 hotspot (gate_types.nim, 19 changes).
## It provides type formatting, error constructors, and outcome helpers
## used throughout the gate execution pipeline.

import std/[unittest, strutils, times]
import gate/gate_contract
import gate/gate_types_impl
import core/types/gate_types
import core/results

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Gate Result Formatting
# Gate results are formatted for human-readable stderr output during
# orchestrator execution. Correct formatting helps operators diagnose
# failures in CI logs and gate execution reports.
# ══════════════════════════════════════════════════════════════════════════════

suite "GateResult $ formatting":
  test "passing gate shows Passed with duration":
    let result = GateResult(
      ok: true,
      name: "import-encapsulation",
      stdout: "", stderr: "",
      duration: initDuration(milliseconds = 42)
    )
    let formatted = $result
    check formatted.contains("Passed")
    check formatted.contains("import-encapsulation")
    check formatted.contains("42ms")

  test "failing gate shows Failed with category":
    let result = GateResult(
      ok: false,
      name: "type-integrity-gate",
      stdout: "", stderr: "",
      duration: initDuration(milliseconds = 150),
      failureCategory: fcValidation,
      failureReason: "type mismatch"
    )
    let formatted = $result
    check formatted.contains("Failed")
    check formatted.contains("type-integrity-gate")
    check formatted.contains("150ms")
    check formatted.contains("fcValidation")

  test "failing gate with fcPermanent shows category":
    let result = GateResult(
      ok: false,
      name: "config-gate",
      stdout: "", stderr: "",
      duration: initDuration(milliseconds = 5),
      failureCategory: fcPermanent,
      failureReason: "missing Z3"
    )
    let formatted = $result
    check formatted.contains("Failed")
    check formatted.contains("fcPermanent")

  test "zero-duration pass is formatted correctly":
    let result = GateResult(
      ok: true, name: "cached-gate",
      stdout: "", stderr: "",
      duration: initDuration(milliseconds = 0)
    )
    let formatted = $result
    check formatted.contains("0ms")
    check formatted.contains("Passed")

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Gate Error Construction
# Gate errors carry structured error codes for programmatic handling
# (retry policy, alert routing). Correct construction ensures errors
# propagate correctly through the Result[GateResult, GateError] pipeline.
# ══════════════════════════════════════════════════════════════════════════════

suite "gateErr: structured error construction":
  test "error carries code, message, and gateId":
    let err = gateErr(gecTimeout, "gate exceeded 120s budget", "import-check")
    check err.code == gecTimeout
    check err.message == "gate exceeded 120s budget"
    check err.gateId == "import-check"

  test "error with empty gateId":
    let err = gateErr(gecCompileFail, "nim c failed")
    check err.code == gecCompileFail
    check err.gateId.len == 0

  test "error with all error codes":
    for code in [gecTimeout, gecCompileFail, gecAssertionFail,
                 gecIoError, gecVfsKeyNotFound, gecSubprocessFail, gecUnknown]:
      let err = gateErr(code, "test", "gate")
      check err.code == code

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Gate Outcome Wrappers
# gateOk and gateFail wrap GateResult/GateError into the unified
# GateOutcome (Result[GateResult, GateError]) type used by the
# dispatch pipeline.
# ══════════════════════════════════════════════════════════════════════════════

suite "gateOk / gateFail: outcome construction":
  test "gateOk wraps passing result":
    let result = GateResult(
      ok: true, name: "test-gate",
      stdout: "", stderr: "",
      duration: initDuration(milliseconds = 10)
    )
    let outcome = gateOk(result)
    check outcome.isOk()
    check outcome.get().name == "test-gate"
    check outcome.get().ok == true

  test "gateFail wraps error with gateId":
    let outcome = gateFail(gecIoError, "disk full", "io-gate")
    check outcome.isErr()
    let err = outcome.error()
    check err.code == gecIoError
    check err.gateId == "io-gate"
    check err.message == "disk full"

  test "gateOk result preserves all fields":
    let result = GateResult(
      ok: true, name: "full-gate",
      stdout: "output text", stderr: "err text",
      duration: initDuration(milliseconds = 99),
      failureCategory: fcTransient,
      failureReason: "should be ignored for ok=true"
    )
    let outcome = gateOk(result)
    let unwrapped = outcome.get()
    check unwrapped.stdout == "output text"
    check unwrapped.stderr == "err text"

  test "gateFail error with empty message":
    let outcome = gateFail(gecUnknown, "", "mystery-gate")
    check outcome.isErr()
    let err = outcome.error()
    check err.message.len == 0
    check err.gateId == "mystery-gate"
