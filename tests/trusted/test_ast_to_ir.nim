## Tests for Nim AST → Axiom Core IR conversion (Phase 2C).
##
## All conversion tests run at compile time via macro.
## If any assertion fails, it produces a compile-time error.

import std/macros
import core/trusted/ast_to_ir
proc main() =
  echo "=== AST → IR Conversion Tests ==="

  macro runConversionTests() =
    # -- Test 1: func add*(a, b: int): int = a + b → IR with irBinOp(boAdd) --
    block:
      # quote do with func returns nnkFuncDef directly
      let funcNode = quote do:
        func add*(a, b: int): int = a + b
      let irDef = convertFuncDef(funcNode)

      doAssert irDef.name == "add",
        "Test 1: expected name 'add', got '" & irDef.name & "'"
      doAssert irDef.params.len == 2,
        "Test 1: expected 2 params, got " & $irDef.params.len
      doAssert irDef.params[0].name == "a",
        "Test 1: expected param 'a', got '" & irDef.params[0].name & "'"
      doAssert irDef.params[1].name == "b",
        "Test 1: expected param 'b', got '" & irDef.params[1].name & "'"
      doAssert irDef.retType.kind == irtBitVec64,
        "Test 1: expected return type irtBitVec64"
      doAssert irDef.body.kind == irBinOp,
        "Test 1: expected body irBinOp, got " & $irDef.body.kind
      doAssert irDef.body.binOp == boAdd,
        "Test 1: expected op boAdd, got " & $irDef.body.binOp
      doAssert not irDef.isRecursive,
        "Test 1: expected not recursive"

    # -- Test 2: func abs*(n: int): int = (if n < 0: -n else: n) → irIf -----
    block:
      let funcNode = quote do:
        func abs*(n: int): int = (if n < 0: -n else: n)
      let irDef = convertFuncDef(funcNode)

      doAssert irDef.name == "abs",
        "Test 2: expected name 'abs', got '" & irDef.name & "'"
      doAssert irDef.body.kind == irIf,
        "Test 2: expected body irIf, got " & $irDef.body.kind
      doAssert irDef.body.ifCond.kind == irBinOp,
        "Test 2: expected condition irBinOp"
      doAssert irDef.body.ifCond.binOp == boLt,
        "Test 2: expected cond op boLt"
      doAssert irDef.body.ifThen.kind == irUnaryOp,
        "Test 2: expected then branch irUnaryOp (negation)"
      doAssert irDef.body.ifThen.unaryOp == uoBvNeg,
        "Test 2: expected unary op uoBvNeg"
      doAssert irDef.body.ifElse.kind == irVar,
        "Test 2: expected else branch irVar"

    # -- Test 3: Overflow check injection for a + b --------------------------
    block:
      let funcNode = quote do:
        func add*(a, b: int): int = a + b
      let irDef = convertFuncDef(funcNode)
      let annotated = annotateOverflow(irDef.body)

      doAssert annotated.overflow == oNoOverflow,
        "Test 3: expected oNoOverflow, got " & $annotated.overflow
      doAssert annotated.expr.kind == irBinOp,
        "Test 3: expected inner expr irBinOp"
      doAssert annotated.expr.binOp == boAdd,
        "Test 3: expected inner op boAdd"

    # -- Test 4: Overflow check for multiplication ---------------------------
    block:
      let funcNode = quote do:
        func mul*(a, b: int): int = a * b
      let irDef = convertFuncDef(funcNode)
      let annotated = annotateOverflow(irDef.body)

      doAssert annotated.overflow == oNoOverflow,
        "Test 4: expected oNoOverflow for mul"
      doAssert annotated.expr.binOp == boMul,
        "Test 4: expected inner op boMul"

    # -- Test 5: Non-arithmetic gets ocNone ----------------------------------
    block:
      let funcNode = quote do:
        func cmp*(a, b: int): bool = a < b
      let irDef = convertFuncDef(funcNode)
      let annotated = annotateOverflow(irDef.body)

      doAssert annotated.overflow == ocNone,
        "Test 5: expected ocNone for comparison"
      doAssert annotated.expr.binOp == boLt,
        "Test 5: expected inner op boLt"

    # -- Test 6: axiomBody entry point ---------------------------------------
    block:
      let funcNode = quote do:
        func add*(a, b: int): int = a + b
      let irDef = axiomBody(funcNode)

      doAssert irDef.name == "add",
        "Test 6: axiomBody name mismatch"
      doAssert irDef.body.kind == irBinOp,
        "Test 6: axiomBody body mismatch"

    # -- Test 7: for-loop `0 ..< n` → irLoop with cond boLt, loss-free ------
    block:
      let funcNode = quote do:
        func sumTo*(n: int): int =
          result = 0
          for i in 0 ..< n:
            result = result + i
      let irDef = convertFuncDef(funcNode)

      doAssert irDef.name == "sumTo",
        "Test 7: expected name 'sumTo'"
      var e = irDef.body
      while e.kind == irLet: e = e.letVal
      doAssert e.kind == irLoop,
        "Test 7: expected an irLoop in the let-chain, got " & $e.kind
      doAssert e.loopCond.kind == irBinOp,
        "Test 7: expected loop cond irBinOp"
      doAssert e.loopCond.binOp == boLt,
        "Test 7: expected cond op boLt for `..<`, got " & $e.loopCond.binOp
      doAssert irDef.translationLossFree,
        "Test 7: `..<` is a supported range — translation must stay loss-free"

    # -- Test 8: for-loop `0 .. n` → inclusive bound boLe, loss-free --------
    block:
      let funcNode = quote do:
        func sumToInclusive*(n: int): int =
          result = 0
          for i in 0 .. n:
            result = result + i
      let irDef = convertFuncDef(funcNode)

      var e = irDef.body
      while e.kind == irLet: e = e.letVal
      doAssert e.kind == irLoop,
        "Test 8: expected an irLoop in the let-chain, got " & $e.kind
      doAssert e.loopCond.binOp == boLe,
        "Test 8: expected cond op boLe for `..`, got " & $e.loopCond.binOp
      doAssert irDef.translationLossFree,
        "Test 8: `..` inclusive range must stay loss-free"

    result = newStmtList()
    result.add quote do:
      echo "  All 8 conversion tests passed (compile-time)."

  runConversionTests()
  echo "=== Done ==="

main()
