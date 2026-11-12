import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import std/strutils
proc main() =
  echo "=== IR → SMT-LIB2 Conversion Tests ==="

  # -- Test 1: boAdd → bvadd -------------------------------------------------
  block:
    let e = irBinOp(boAdd, irLit(1), irLit(2))
    let smt = irExprToSmt(e)
    doAssert smt == "(bvadd #x0000000000000001 #x0000000000000002)",
      "Test 1: boAdd -> bvadd failed, got: " & smt
    echo "  Test 1 passed: boAdd -> bvadd"

  # -- Test 2: irBitVec64 → (_ BitVec 64) ------------------------------------
  block:
    let smt = irTypeToSmt(irTypeBitVec64())
    doAssert smt == "(_ BitVec 64)",
      "Test 2: irBitVec64 sort failed, got: " & smt
    let smtBool = irTypeToSmt(irTypeBool())
    doAssert smtBool == "Bool",
      "Test 2: irBool sort failed, got: " & smtBool
    echo "  Test 2 passed: irBitVec64 -> (_ BitVec 64), irBool -> Bool"

  # -- Test 3: ekIf → (ite ...) ----------------------------------------------
  block:
    let e = irIf(irLit(1), irLit(2), irLit(3))
    let smt = irExprToSmt(e)
    doAssert smt == "(ite #x0000000000000001 #x0000000000000002 #x0000000000000003)",
      "Test 3: irIf -> ite failed, got: " & smt
    echo "  Test 3 passed: ekIf -> (ite ...)"

  # -- Test 4: ekLet → (let ((...)) ...) -------------------------------------
  block:
    let e = irLet("x", irLit(42), irVar("x", irTypeBitVec64()))
    let smt = irExprToSmt(e)
    doAssert smt == "(let ((x #x000000000000002A)) x)",
      "Test 4: irLet -> let failed, got: " & smt
    echo "  Test 4 passed: ekLet -> (let ((...)) ...)"

  # -- Test 5: Overflow assertions for add ------------------------------------
  block:
    let a = irVar("a", irTypeBitVec64())
    let b = irVar("b", irTypeBitVec64())
    let addExpr = irBinOp(boAdd, a, b)
    let annotated = AnnotatedExpr(expr: addExpr, overflow: oNoOverflow)
    let assertions = generateOverflowAssertions(annotated)
    doAssert assertions.len == 2,
      "Test 5: expected 2 overflow assertions, got " & $assertions.len
    doAssert "(assert (no_overflow_add a b))" in assertions,
      "Test 5: missing no_overflow_add assertion, got: " & $assertions
    doAssert "(assert (no_underflow_add a b))" in assertions,
      "Test 5: missing no_underflow_add assertion"
    # Verify ocNone produces empty
    let noneAnnotated = AnnotatedExpr(expr: addExpr, overflow: ocNone)
    let noneAssertions = generateOverflowAssertions(noneAnnotated)
    doAssert noneAssertions.len == 0,
      "Test 5: ocNone should produce 0 assertions, got " & $noneAssertions.len
    # Verify mul overflow
    let mulExpr = irBinOp(boMul, a, b)
    let mulAnnotated = AnnotatedExpr(expr: mulExpr, overflow: oNoOverflow)
    let mulAssertions = generateOverflowAssertions(mulAnnotated)
    doAssert mulAssertions.len == 1,
      "Test 5: expected 1 mul overflow assertion, got " & $mulAssertions.len
    doAssert "(assert (no_overflow_mul a b))" in mulAssertions,
      "Test 5: missing no_overflow_mul assertion"
    echo "  Test 5 passed: overflow assertions for add and mul"

  # -- Test 6: Full function def → complete SMT-LIB2 script -------------------
  block:
    let body = irBinOp(boAdd, irVar("a", irTypeBitVec64()),
                         irVar("b", irTypeBitVec64()))
    var f = irFuncDef("add",
                       @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
                       irTypeBitVec64(), body)
    # Honest spec postcondition: add(a, b) = a + b (result let-bound in the
    # generated QF_BV BMC negation).
    f.postConditions = @[irBinOp(boEq, irVar("result", irTypeBitVec64()), body)]
    let script = irToSmtScript(f)
    doAssert "(set-logic QF_BV)" in script,
      "Test 6: missing (set-logic QF_BV)"
    doAssert "(set-option :rlimit 30000000)" in script,
      "Test 6: missing (set-option :rlimit 30000000)"
    doAssert "(declare-fun a () (_ BitVec 64))" in script,
      "Test 6: missing declare-fun a"
    doAssert "(declare-fun b () (_ BitVec 64))" in script,
      "Test 6: missing declare-fun b"
    doAssert "(define-fun add_impl ((a (_ BitVec 64)) (b (_ BitVec 64))) (_ BitVec 64)" in script,
      "Test 6: missing define-fun add_impl signature"
    doAssert "(bvadd a b)" in script,
      "Test 6: missing bvadd body"
    doAssert "(assert (let ((result (add_impl a b))) (not (= result (bvadd a b)))))" in script,
      "Test 6: missing BMC negation assert (let-bound result against _impl)"
    doAssert "(check-sat)" in script,
      "Test 6: missing (check-sat)"
    echo "  Test 6 passed: full function def -> complete SMT-LIB2 script"

  # -- Test 7: Boolean operations (and/or/not) --------------------------------
  block:
    let a = irVar("a", irTypeBool())
    let b = irVar("b", irTypeBool())
    let andExpr = irAnd(a, b)
    let orExpr = irOr(a, b)
    let notExpr = irNot(a)
    doAssert irExprToSmt(andExpr) == "(and a b)",
      "Test 7: and failed, got: " & irExprToSmt(andExpr)
    doAssert irExprToSmt(orExpr) == "(or a b)",
      "Test 7: or failed, got: " & irExprToSmt(orExpr)
    doAssert irExprToSmt(notExpr) == "(not a)",
      "Test 7: not failed, got: " & irExprToSmt(notExpr)
    # Also test bvnot and bvneg
    let bvVar = irVar("x", irTypeBitVec64())
    doAssert irExprToSmt(irBvNot(bvVar)) == "(bvnot x)",
      "Test 7: bvnot failed"
    doAssert irExprToSmt(irBvNeg(bvVar)) == "(bvneg x)",
      "Test 7: bvneg failed"
    # Test equality
    let eqExpr = irEq(irVar("x", irTypeBitVec64()), irVar("y", irTypeBitVec64()))
    doAssert irExprToSmt(eqExpr) == "(= x y)",
      "Test 7: eq failed, got: " & irExprToSmt(eqExpr)
    echo "  Test 7 passed: Boolean and bitwise operations"

  # -- Test 8: Overflow defines and script with overflow preamble ---------------
  block:
    let defines = generateOverflowDefines()
    doAssert defines.len == 6,
      "Test 8: expected 6 overflow define-funs, got " & $defines.len
    doAssert "(define-fun no_overflow_add" in defines[0],
      "Test 8: missing no_overflow_add define"
    doAssert "(define-fun no_underflow_add" in defines[1],
      "Test 8: missing no_underflow_add define"
    doAssert "(define-fun no_overflow_mul" in defines[2],
      "Test 8: missing no_overflow_mul define"
    doAssert "(define-fun no_underflow_mul" in defines[3],
      "Test 8: missing no_underflow_mul define"
    doAssert "(define-fun no_overflow_sub" in defines[4],
      "Test 8: missing no_overflow_sub define"
    doAssert "(define-fun no_underflow_sub" in defines[5],
      "Test 8: missing no_underflow_sub define"
    # Verify irToSmtScript with overflow defines
    let body = irBinOp(boAdd, irVar("x", irTypeBitVec64()),
                         irVar("y", irTypeBitVec64()))
    var f = irFuncDef("f_add",
                       @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())],
                       irTypeBitVec64(), body)
    f.postConditions = @[irBinOp(boEq, irVar("result", irTypeBitVec64()), body)]
    let script = irToSmtScript(f, includeOverflowDefines = true)
    doAssert "(define-fun no_overflow_add" in script,
      "Test 8: script missing overflow defines"
    doAssert "(set-logic QF_BV)" in script,
      "Test 8: script missing set-logic"
    doAssert "(set-option :rlimit 30000000)" in script,
      "Test 8: script missing rlimit option"
    # Verify irToSmtScript without overflow defines (default)
    let scriptPlain = irToSmtScript(f)
    doAssert "(define-fun no_overflow_add" notin scriptPlain,
      "Test 8: plain script should not have overflow defines"
    echo "  Test 8 passed: overflow defines and script preamble"

  # -- Test 9: floatLiteral fixed-point scaling --------------------------------
  block:
    # 5.0 * 100 = 500 = 0x1F4
    doAssert floatLiteral(5.0) == "#x00000000000001F4",
      "Test 9: 5.0 -> #x1F4 failed, got: " & floatLiteral(5.0)
    # 0.95 * 100 = 95 = 0x5F
    doAssert floatLiteral(0.95) == "#x000000000000005F",
      "Test 9: 0.95 -> #x5F failed, got: " & floatLiteral(0.95)
    # 0.0 * 100 = 0
    doAssert floatLiteral(0.0) == "#x0000000000000000",
      "Test 9: 0.0 -> #x0 failed, got: " & floatLiteral(0.0)
    echo "  Test 9 passed: floatLiteral fixed-point scaling"

  # -- Test 10: irFloatLit IR node → SMT conversion ---------------------------
  block:
    let e = irFloatLit(2.5)
    let smt = irExprToSmt(e)
    # 2.5 * 100 = 250 = 0xFA
    doAssert smt == "#x00000000000000FA",
      "Test 10: irFloatLit(2.5) failed, got: " & smt
    # irFloatLit in arithmetic context
    let sum = irBinOp(boAdd, irFloatLit(1.5), irFloatLit(3.5))
    let sumSmt = irExprToSmt(sum)
    # 1.5 * 100 = 150 = 0x96, 3.5 * 100 = 350 = 0x15E
    doAssert sumSmt == "(bvadd #x0000000000000096 #x000000000000015E)",
      "Test 10: irFloatLit arithmetic failed, got: " & sumSmt
    echo "  Test 10 passed: irFloatLit IR node -> SMT conversion"

  # -- Test 11: min/max special cases → QF_BV ite -----------------------------
  block:
    let a = irVar("x", irTypeBitVec64())
    let b = irVar("y", irTypeBitVec64())
    let minExpr = irCall("min", @[a, b])
    let minSmt = irExprToSmt(minExpr)
    doAssert minSmt == "(ite (bvslt x y) x y)",
      "Test 11: min -> ite bvslt failed, got: " & minSmt
    let maxExpr = irCall("max", @[a, b])
    let maxSmt = irExprToSmt(maxExpr)
    doAssert maxSmt == "(ite (bvsgt x y) x y)",
      "Test 11: max -> ite bvsgt failed, got: " & maxSmt
    # Non-min/max calls still go through default path
    let otherExpr = irCall("foo", @[a, b])
    let otherSmt = irExprToSmt(otherExpr)
    doAssert otherSmt == "(foo x y)",
      "Test 11: non-min/max call failed, got: " & otherSmt
    echo "  Test 11 passed: min/max special cases -> QF_BV ite"

  # -- Test 12: substVarsInExpr with irFloatLit --------------------------------
  block:
    let e = irLet("x", irFloatLit(1.0),
                  irBinOp(boAdd, irVar("x", irTypeBitVec64()), irFloatLit(2.0)))
    let subst = substVarsInExpr(e, @[("x", "x_0")])
    let smt = irExprToSmt(subst)
    # irFloatLit(1.0) -> #x0000000000000064 (100), irFloatLit(2.0) -> #x00000000000000C8 (200)
    doAssert "(let ((x #x0000000000000064)) (bvadd x_0 #x00000000000000C8))" == smt,
      "Test 12: substVarsInExpr with irFloatLit failed, got: " & smt
    echo "  Test 12 passed: substVarsInExpr with irFloatLit"

  echo "=== All 12 tests passed ==="

  # -- Phase 2 conformance: %% (unsigned) → boRemU → bvurem ---------------
  block:
    let a = irVar("a", irTypeBitVec64())
    let b = irVar("b", irTypeBitVec64())
    let remUExpr = irBinOp(boRemU, a, b)
    let remUSmt = irExprToSmt(remUExpr)
    doAssert remUSmt == "(bvurem a b)",
      "Phase2 %% conformance: boRemU -> bvurem failed, got: " & remUSmt
    let remExpr = irBinOp(boRem, a, b)  # signed `mod` must stay bvsrem
    doAssert irExprToSmt(remExpr) == "(bvsrem a b)",
      "Phase2 conformance: boRem -> bvsrem (signed) failed, got: " &
        irExprToSmt(remExpr)
    echo "  Phase2 conformance passed: %% -> bvurem, mod -> bvsrem"

  echo "=== Phase 2: %% conformance verified ==="

main()
