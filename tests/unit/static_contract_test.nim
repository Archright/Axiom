## Static Contract Unit Tests — AST extraction + SMT-LIB2 transpilation
##
## Tests the contract extraction from Nim AST and SMT-LIB2 conversion.
## Z3 integration tests require Z3 to be installed.

import std/[unittest, macros]
import core/test_support/static_contract

# ── SMT-LIB2 Transpilation Tests ─────────────────────────────────────────────

suite "NimNode → SMT-LIB2 Transpilation":

  macro testSmtLib2(): untyped =
    # All NimNode operations must be in compile-time context
    doAssert nimNodeToSmtLib2(newLit(42)) == "42"
    doAssert nimNodeToSmtLib2(ident"true") == "true"
    doAssert nimNodeToSmtLib2(ident"false") == "false"
    doAssert nimNodeToSmtLib2(ident"x") == "x"
    doAssert nimNodeToSmtLib2(infix(ident"a", "+", newLit(1))) == "(+ a 1)"
    doAssert nimNodeToSmtLib2(infix(ident"x", "==", newLit(0))) == "(= x 0)"
    doAssert nimNodeToSmtLib2(infix(ident"x", "<", newLit(100))) == "(< x 100)"
    doAssert nimNodeToSmtLib2(infix(ident"p", "implies", ident"q")) == "(=> p q)"
    doAssert nimNodeToSmtLib2(prefix(ident"flag", "not")) == "(not flag)"
    # Complex: x > 0 and x < 100
    let inner1 = infix(ident"x", ">", newLit(0))
    let inner2 = infix(ident"x", "<", newLit(100))
    doAssert nimNodeToSmtLib2(infix(inner1, "and", inner2)) == "(and (> x 0) (< x 100))"
    result = newStmtList()

  test "SMT-LIB2 transpilation (all cases)":
    testSmtLib2()

# ── Contract Extraction Tests ────────────────────────────────────────────────

suite "Contract Extraction from AST":

  macro extractAssertContracts(): untyped =
    let body = quote do:
      assert x > 0
    let contracts = extractContracts(body)
    result = newLit(contracts.len)

  macro extractRequiresContracts(): untyped =
    let body = quote do:
      requires(x > 0)
    let contracts = extractContracts(body)
    result = newLit(contracts.len)

  macro extractEnsuresContracts(): untyped =
    let body = quote do:
      ensures(result > 0)
    let contracts = extractContracts(body)
    result = newLit(contracts.len)

  macro extractMultipleContracts(): untyped =
    let body = quote do:
      assert x > 0
      assert y < 100
      requires(z >= 0)
    let contracts = extractContracts(body)
    result = newLit(contracts.len)

  macro extractNestedContracts(): untyped =
    let body = quote do:
      if true:
        assert x > 0
      else:
        assert y > 0
    let contracts = extractContracts(body)
    result = newLit(contracts.len)

  macro extractAssertKind(): untyped =
    let body = quote do:
      assert x > 0
    let contracts = extractContracts(body)
    if contracts.len > 0:
      result = newLit(ord(contracts[0].kind))
    else:
      result = newLit(-1)

  test "extracts assert statement":
    check extractAssertContracts() == 1

  test "extracts requires statement":
    check extractRequiresContracts() == 1

  test "extracts ensures statement":
    check extractEnsuresContracts() == 1

  test "extracts multiple contracts":
    check extractMultipleContracts() == 3

  test "returns empty for nil body":
    let contracts = extractContracts(nil)
    check contracts.len == 0

  test "extracts contracts from nested if blocks":
    check extractNestedContracts() == 2

  test "assert kind is ckAssert":
    check extractAssertKind() == ord(ckAssert)

# ── Z3 Integration Tests ───────────────────────────────────────────────────

suite "Z3 Integration":

  test "queryZ3: sat case (x > 0)":
    let r = queryZ3("(declare-const x Int)\n(assert (> x 0))\n(check-sat)")
    check r.isSat == true

  test "queryZ3: unsat case (contradiction)":
    let r = queryZ3("(declare-const x Int)\n(assert (> x 0))\n(assert (< x 0))\n(check-sat)")
    check r.isSat == false

  test "queryZ3: model extraction":
    let r = queryZ3("(declare-const x Int)\n(assert (= x 42))\n(check-sat)\n(get-model)")
    check r.isSat == true
    check r.model.len > 0

  test "queryZ3: invalid SMT-LIB2 returns error":
    let r = queryZ3("(this is not valid smt-lib2)")
    check r.isSat == false

  test "queryZ3: empty input returns sat (trivially satisfiable)":
    let r = queryZ3("")
    check r.isSat == true  # no assertions = trivially satisfiable

  test "verifyContract: tautology passes verification":
    # x > 0 or x <= 0 is always true — negation is always false → unsat → verified
    let c = Contract(
      kind: ckAssert,
      expr: "x > 0 or x <= 0",
      smtLib2: "(or (> x 0) (<= x 0))",
      sourceLine: 1,
      description: "assert tautology"
    )
    let vr = verifyContract(c)
    check vr.verified == true

  test "verifyContract: unsat contract fails":
    let c = Contract(
      kind: ckAssert,
      expr: "x > 0 and x < 0",
      smtLib2: "(and (> x 0) (< x 0))",
      sourceLine: 1,
      description: "assert contradiction"
    )
    let vr = verifyContract(c)
    check vr.verified == false

# ── newContractSpec Macro Tests ─────────────────────────────────────────────

suite "newContractSpec Macro":

  test "extracts contracts from proc-like body":
    let specs = newContractSpec:
      assert x > 0
      requires(y >= 0)
      ensures(result > 0)
    check specs.len == 3
    check specs[0].kind == ckAssert
    check specs[1].kind == ckPrecondition
    check specs[2].kind == ckPostcondition

  test "extracts SMT-LIB2 from contracts":
    let specs = newContractSpec:
      assert x > 0
    check specs.len == 1
    check specs[0].smtLib2 == "(> x 0)"

  test "empty body returns empty seq":
    let specs = newContractSpec:
      let a = 1
      echo a
    check specs.len == 0

# ── End-to-End Integration ─────────────────────────────────────────────────

suite "End-to-End: Extract + Verify":

  macro extractAndVerify(): untyped =
    ## Extract contracts from a proc body and verify all at compile time.
    let body = quote do:
      assert x > 0
      assert y < 100
    let contracts = extractContracts(body)
    # Return contract count and SMT-LIB2 for verification at runtime
    result = newLit(contracts.len)

  test "extract and count contracts end-to-end":
    check extractAndVerify() == 2

  test "verifyContracts batch verification":
    let contracts = @[
      Contract(kind: ckAssert, expr: "x > 0", smtLib2: "(> x 0)",
        sourceLine: 1, description: "assert x > 0"),
      Contract(kind: ckAssert, expr: "true", smtLib2: "true",
        sourceLine: 2, description: "assert true"),
    ]
    let results = verifyContracts(contracts)
    check results.len == 2
    # x > 0 is not a tautology → negation is sat → verified = false
    check results[0].verified == false
    # true is a tautology → negation is unsat → verified = true
    check results[1].verified == true
