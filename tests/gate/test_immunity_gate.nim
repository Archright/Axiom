{.push raises: [CatchableError].}

## Immunity Gate Tests — Unit tests for gate/runners/immunity_gate.nim
## Tests exported types (GateResult, GateLayer), register, and runAll.
## NOTE: `registry` is module-level with no clear function, so runAll() tests
## must be isolated to a single suite that runs first.

import std/[unittest, json, os, times]
import std/strutils
import gate/runners/immunity_gate

# ---------------------------------------------------------------------------
# GateResult type construction
# ---------------------------------------------------------------------------

suite "GateResult type":
  test "passing result has all fields":
    let gr = GateResult(passed: true, layer: "test", message: "OK")
    check gr.passed == true
    check gr.layer == "test"
    check gr.message == "OK"
    check gr.education.len == 0
    check gr.autoFix.len == 0

  test "fail result has education and autoFix":
    let gr = GateResult(
      passed: false,
      layer: "Quarantine",
      message: "stale files",
      education: "This matters because trust boundaries.",
      autoFix: "Remove stale quarantined files."
    )
    check gr.passed == false
    check gr.layer == "Quarantine"
    check gr.message.contains("stale")
    check gr.education.len > 0
    check gr.autoFix.len > 0

  test "empty layer name is valid":
    let gr = GateResult(passed: true, layer: "", message: "trivial")
    check gr.layer.len == 0
    check gr.passed == true

  test "unicode in message":
    let gr = GateResult(passed: false, layer: "unicode",
                        message: "§0.6 violation: 커버리지 감소",
                        education: "AGENTS.md §4 GUARDIAN: Ratchet.")
    check gr.message.contains("§0.6")
    check gr.message.contains("커버리지")
    check gr.education.contains("§4")

# ---------------------------------------------------------------------------
# GateLayer type
# ---------------------------------------------------------------------------

suite "GateLayer type":
  test "GateLayer holds name and check proc":
    proc myCheck(): GateResult =
      GateResult(passed: true, layer: "custom", message: "ok")
    let layer = GateLayer(name: "custom-layer", check: myCheck)
    check layer.name == "custom-layer"
    let r = layer.check()
    check r.passed == true
    check r.layer == "custom"

  test "dynamic result based on state":
    var counter = 0
    proc countingCheck(): GateResult =
      inc counter
      if counter > 1:
        GateResult(passed: false, layer: "count", message: "count=" & $counter)
      else:
        GateResult(passed: true, layer: "count", message: "first")
    let layer = GateLayer(name: "counting", check: countingCheck)
    let r1 = layer.check()
    check r1.passed == true
    let r2 = layer.check()
    check r2.passed == false
    check r2.message.contains("count=2")

# ---------------------------------------------------------------------------
# register + runAll behavior (isolated — runs FIRST)
# ---------------------------------------------------------------------------

suite "register and runAll":
  test "single passing layer → runAll returns true":
    proc passCheck(): GateResult =
      GateResult(passed: true, layer: "p", message: "OK")
    register(GateLayer(name: "pass-only", check: passCheck))
    check runAll() == true

  test "single failing layer → runAll returns false":
    proc failCheck(): GateResult =
      GateResult(passed: false, layer: "f", message: "FAIL",
                 education: "why", autoFix: "how")
    register(GateLayer(name: "fail-only", check: failCheck))
    check runAll() == false

  test "exception in check → runAll returns false":
    proc boomCheck(): GateResult =
      raise newException(CatchableError, "test explosion")
    register(GateLayer(name: "boom-layer", check: boomCheck))
    check runAll() == false

  test "passing check returns expected message":
    # Note: runAll() now runs ALL registered layers including previous ones.
    # Since fail-only and boom-layer are still registered, runAll() returns false.
    # Instead, test the individual layer's check proc directly.
    proc echoCheck(): GateResult =
      GateResult(passed: true, layer: "echo", message: "echo-ok")
    let layer = GateLayer(name: "echo-layer", check: echoCheck)
    let r = layer.check()
    check r.passed == true
    check r.message == "echo-ok"
    check r.layer == "echo"

{.pop.}
