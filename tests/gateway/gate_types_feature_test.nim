## Gate Types Feature Test.
## Verifies core type definitions for the Axiom gate layer.
##
## Tests:
##   - GateSeverity enum values and ordinals
##   - GateWeight enum values and ordinals
##   - GateStage enum values
##   - GateLayer enum values
##   - GateRunMode enum values
##   - GateErrorCode enum values
##   - GateResult $ formatting
##   - gateOk / gateFail / gateErr helpers

import std/[unittest, strformat, strutils, times]
import gate/gate_types
import core/types/results

suite "Gate Types — Enum Values":

  test "GateSeverity ordinals: gsWarn=0, gsError=1":
    ## Given the GateSeverity enum
    ## When ordinals are checked
    ## Then gsWarn is 0 and gsError is 1
    check ord(gsWarn) == 0
    check ord(gsError) == 1

  test "GateWeight values: gwLight=1, gwMedium=2, gwHeavy=4":
    ## Given the GateWeight enum with explicit values
    ## When ordinals are checked
    ## Then they match the concurrency cost classification
    check ord(gwLight) == 1
    check ord(gwMedium) == 2
    check ord(gwHeavy) == 4

  test "GateStage has 5 values":
    ## Given the GateStage enum
    ## When counting values
    ## Then there are 5 stages (pre-commit, pre-push, manual, CI, any-CI)
    check ord(high(GateStage)) - ord(low(GateStage)) + 1 == 5

  test "GateLayer has exactly 2 values":
    ## Given the GateLayer enum
    ## When counting values
    ## Then there are exactly 2 layers: glMeta and glFunctional
    check ord(glMeta) == 0
    check ord(glFunctional) == 1

  test "GateRunMode has exactly 2 values":
    ## Given the GateRunMode enum
    ## When counting values
    ## Then there are exactly 2 modes: incremental and exhaustive
    check ord(grmIncremental) == 0
    check ord(grmExhaustive) == 1

  test "GateErrorCode has 7 values":
    ## Given the GateErrorCode enum
    ## When counting values
    ## Then there are exactly 7 error codes
    check ord(high(GateErrorCode)) - ord(low(GateErrorCode)) + 1 == 7

suite "Gate Types — GateResult Formatting":

  test "$GateResult shows Passed for ok=true":
    ## Given a passing GateResult
    ## When $ is called
    ## Then the string contains "Passed"
    let r = GateResult(ok: true, name: "test-gate", duration: initDuration(milliseconds = 42))
    let s = $r
    check s.contains("test-gate")
    check s.contains("Passed")
    check s.contains("42ms")

  test "$GateResult shows Failed for ok=false":
    ## Given a failing GateResult
    ## When $ is called
    ## Then the string contains "Failed"
    let r = GateResult(ok: false, name: "test-gate",
                       duration: initDuration(milliseconds = 10),
                       failureCategory: fcValidation)
    let s = $r
    check s.contains("test-gate")
    check s.contains("Failed")
    check s.contains("fcValidation")

suite "Gate Types — Helper Functions":

  test "gateOk creates ok outcome":
    ## Given a passing GateResult
    ## When gateOk is called
    ## Then the outcome is ok with the correct value
    let gr = GateResult(ok: true, name: "test", duration: initDuration())
    let outcome = gateOk(gr)
    check outcome.ok == true
    check outcome.value.name == "test"

  test "gateFail creates err outcome":
    ## Given error parameters
    ## When gateFail is called
    ## Then the outcome is an error with the correct code and message
    let outcome = gateFail(gecTimeout, "exceeded budget", "my-gate")
    check outcome.ok == false
    check outcome.err.code == gecTimeout
    check outcome.err.message == "exceeded budget"
    check outcome.err.gateId == "my-gate"

  test "gateErr creates GateError with all fields":
    ## Given error code, message, and gate ID
    ## When gateErr is called
    ## Then the GateError has all fields set correctly
    let err = gateErr(gecCompileFail, "nim c failed", "nim-check")
    check err.code == gecCompileFail
    check err.message == "nim c failed"
    check err.gateId == "nim-check"
