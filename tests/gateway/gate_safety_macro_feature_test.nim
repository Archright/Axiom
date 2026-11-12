{.push raises: [CatchableError].}

## BDD feature test for gate_safety_macro.feature
## Verifies compile-time assertions and value type safety.

import std/unittest
import gate/utils/gate_safety_macro

type
  TestValue = object
    x: int
    y: string

suite "Gate Safety Macro — Compile-Time Validation":

  test "InProcessGateContext is a pure value type":
    # Compile-time static asserts in gate_safety_macro.nim already verify this.
    # If this test compiles, the assertions passed.
    let ctx = InProcessGateContext(
      repoRoot: "/tmp",
      stagedFiles: @["a.nim"],
      gateId: "test",
      epoch: 0,
      subtreeRoot: "",
      stage: 0,
      maxJobs: 4,
      passFilenames: true)
    check ctx.repoRoot == "/tmp"
    check ctx.gateId == "test"

  test "LightGateAllowlist contains the allowed in-process gates":
    ## Implementation (gate_safety_macro.nim): doc-completeness-gate (perf fast
    ## path), trust-commit-scope (DEBT#471 enforcement path), decision-binding-gate
    ## and delegation-enforcer (DEBT#497 follow-up hollow-CAS closure).
    check LightGateAllowlist.len == 4
    for allowed in ["doc-completeness-gate", "trust-commit-scope",
                    "decision-binding-gate", "delegation-enforcer"]:
      check isLightGateAllowed(allowed)

  test "isLightGateAllowed returns false for unknown gate":
    check isLightGateAllowed("nonexistent-gate") == false
    check isLightGateAllowed("") == false

  test "isLightGateAllowed rejects the retired debt-scan-gate residual name":
    ## DEBT#471 follow-up hygiene: the debt scan runner merged into
    ## debt-integrity-gate; the allowlist entry was a dead key — no
    ## inProcessRegistry entry and no runGateInProcess branch exist for it,
    ## so dispatching by that name could only produce an undispatched hollow
    ## result. The name must stay out of the allowlist.
    check isLightGateAllowed("debt-scan-gate") == false
    check isLightGateAllowed("trust-commit-scope") == true

  test "TestValue type passes assertValueType":
    # assertValueType is a compile-time macro — if it compiles, it passed.
    # Verify the type is usable at runtime to confirm it's a real value type.
    assertValueType(TestValue)
    let v = TestValue(x: 42, y: "hello")
    check v.x == 42
    check v.y == "hello"

{.pop.}
