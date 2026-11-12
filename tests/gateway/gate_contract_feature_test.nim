## Gate Contract Feature Test.
## Verifies the gate_contract module exports all required types
## and maintains the forwarding stub compatibility.
##
## Tests:
##   - Type re-exports from core/gate_types
##   - GateOutcome type alias
##   - Forwarding stub re-export from gate_types

import std/[unittest, times]
import core/results
import gate/gate_types

suite "Gate Contract — Type Definitions":

  test "GateStage enum has all execution stages":
    ## Given the GateStage enum exported by gate_contract
    ## When checking for stage values
    ## Then all 4 stages are present
    let stages = [gsPreCommit, gsPrePush, gsManual, gsCI]
    check stages.len == 4

  test "GateLayer distinguishes Meta and Functional":
    ## Given the GateLayer enum
    ## When checking layer values
    ## Then Meta (L1) and Functional (L2) are distinct
    check glMeta != glFunctional

  test "GateResult can be constructed with all fields":
    ## Given the GateResult type
    ## When constructing with required fields
    ## Then all fields are accessible
    let gr = GateResult(
      ok: true,
      name: "test-gate",
      stdout: "test detail",
      stderr: "",
      duration: initDuration(milliseconds = 100),
      failureCategory: fcPermanent,
      failureReason: ""
    )
    check gr.name == "test-gate"
    check gr.duration.inMilliseconds == 100

  test "GateOutcome is Result[GateResult, GateError]":
    ## Given the GateOutcome type alias
    ## When creating ok and err outcomes
    ## Then they match the Result pattern
    let okOutcome = gateOk(GateResult(
      ok: true, name: "ok-gate", stdout: "", stderr: "",
      duration: initDuration(milliseconds = 50),
      failureCategory: fcPermanent, failureReason: ""
    ))
    check okOutcome.isOk

    let errOutcome = gateFail(gecTimeout, "timed out")
    check errOutcome.isErr

  test "FailureCategory re-exported from core":
    ## Given FailureCategory is re-exported by gate_contract
    ## When using it via gate_types
    ## Then it compiles and the values are accessible
    let cat = fcValidation
    check cat == fcValidation

  test "fcUnknown is a valid FailureCategory with TTL=0":
    ## Given the fcUnknown failure category
    ## When cacheTtl is queried
    ## Then TTL is 0 (never cached)
    let cat = fcUnknown
    check cat == fcUnknown
    check cacheTtl(cat) == 0
