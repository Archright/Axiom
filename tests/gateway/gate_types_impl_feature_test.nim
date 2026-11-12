## Gate Types Implementation Feature Test.
## Verifies utility functions in gate_types_impl.nim.
##
## Tests:
##   - $ operator for GateResult
##   - gateErr construction
##   - gateOk / gateFail factories

import std/[unittest, strutils, times]
import core/results
import gate/gate_types

suite "Gate Types Impl — Utility Functions":

  let sampleResult = GateResult(
    ok: true,
    name: "sample-gate",
    stdout: "all clear",
    stderr: "",
    duration: initDuration(milliseconds = 42),
    failureCategory: fcValidation,
    failureReason: ""
  )

  test "$ GateResult contains name and duration":
    ## Given a GateResult
    ## When converted to string
    ## Then it contains the gate name and duration
    let s = $sampleResult
    check "sample-gate" in s
    check "42" in s

  test "gateErr constructs GateError with code and message":
    ## Given an error code and message
    ## When gateErr is called
    ## Then the GateError has the correct fields
    let err = gateErr(gecTimeout, "Z3 timeout", "z3-gate")
    check err.code == gecTimeout
    check "Z3 timeout" in err.message
    check err.gateId == "z3-gate"

  test "gateErr default gateId is empty":
    ## Given gateErr without explicit gateId
    ## When constructed
    ## Then gateId defaults to empty string
    let err = gateErr(gecUnknown, "bad config")
    check err.gateId == ""

  test "gateOk wraps GateResult in successful outcome":
    ## Given a GateResult
    ## When gateOk is called
    ## Then the outcome isOk and contains the result
    let outcome = gateOk(sampleResult)
    check outcome.isOk
    check outcome.get().name == "sample-gate"

  test "gateFail wraps GateError in failed outcome":
    ## Given an error code and message
    ## When gateFail is called
    ## Then the outcome isErr and contains the error
    let outcome = gateFail(gecSubprocessFail, "crash")
    check outcome.isErr
    check outcome.error.code == gecSubprocessFail
