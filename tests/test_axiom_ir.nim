## Tests for Axiom Core IR type definitions and helpers.

import core/trusted/axiom_ir_helpers
import std/strutils
proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      body
      inc passed
      echo "  PASS: " & name

  echo "=== Axiom Core IR Tests ==="
  echo ""

  # -- Test 1: IRType constructors ------------------------------------------
  echo "1. IRType constructors"
  check "irTypeBitVec64":
    let t = irTypeBitVec64()
    assert t.kind == irtBitVec64

  check "irTypeBool":
    let t = irTypeBool()
    assert t.kind == irtBool

  check "irTypeList":
    let t = irTypeList(irTypeBitVec64())
    assert t.kind == irtList
    assert t.elemType.kind == irtBitVec64

  echo ""

  # -- Test 2: irTypeName ---------------------------------------------------
  echo "2. irTypeName"
  check "BitVec 64":
    assert irTypeName(irTypeBitVec64()) == "BitVec 64"

  check "Bool":
    assert irTypeName(irTypeBool()) == "Bool"

  check "List BitVec 64":
    assert irTypeName(irTypeList(irTypeBitVec64())) == "List BitVec 64"

  echo ""

  # -- Test 3: Expression constructors --------------------------------------
  echo "3. Expression constructors"
  check "irLit":
    let e = irLit(42)
    assert e.kind == irLit
    assert e.litVal == 42

  check "irVar":
    let e = irVar("x", irTypeBitVec64())
    assert e.kind == irVar
    assert e.varName == "x"
    assert e.varType.kind == irtBitVec64

  check "irLet":
    let body = irLit(1)
    let e = irLet("x", irLit(42), body)
    assert e.kind == irLet
    assert e.letName == "x"

  check "irIf":
    let e = irIf(irLit(1), irLit(2), irLit(3))
    assert e.kind == irIf

  check "irBinOp":
    let e = irBinOp(boAdd, irLit(1), irLit(2))
    assert e.kind == irBinOp
    assert e.binOp == boAdd

  check "irUnaryOp":
    let e = irUnaryOp(uoNot, irVar("b", irTypeBool()))
    assert e.kind == irUnaryOp
    assert e.unaryOp == uoNot

  check "irCall":
    let e = irCall("foo", @[irLit(1), irLit(2)])
    assert e.kind == irCall
    assert e.callName == "foo"
    assert e.callArgs.len == 2

  check "irRecCall":
    let e = irRecCall(@[irLit(1)])
    assert e.kind == irRecCall
    assert e.recArgs.len == 1

  echo ""

  # -- Test 4: Shortcut constructors ----------------------------------------
  echo "4. Shortcut constructors"
  check "irAdd":
    let e = irAdd(irLit(1), irLit(2))
    assert e.kind == irBinOp
    assert e.binOp == boAdd

  check "irMul":
    let e = irMul(irLit(3), irLit(4))
    assert e.binOp == boMul

  check "irLt":
    let e = irLt(irLit(1), irLit(2))
    assert e.binOp == boLt

  check "irEq":
    let e = irEq(irVar("a", irTypeBitVec64()),
                  irVar("b", irTypeBitVec64()))
    assert e.binOp == boEq

  echo ""

  # -- Test 5: irFuncDef for `func add(a, b: int): int = a + b` ------------
  echo "5. irFuncDef — simple add"
  let addDef = irFuncDef(
    name = "add",
    params = @[("a", irTypeBitVec64()), ("b", irTypeBitVec64())],
    ret = irTypeBitVec64(),
    body = irAdd(
      irVar("a", irTypeBitVec64()),
      irVar("b", irTypeBitVec64())
    )
  )

  check "funcDef name":
    assert addDef.name == "add"

  check "funcDef params":
    assert addDef.params.len == 2
    assert addDef.params[0].name == "a"
    assert addDef.params[1].ty.kind == irtBitVec64

  check "funcDef retType":
    assert addDef.retType.kind == irtBitVec64

  check "funcDef isRecursive false":
    assert addDef.isRecursive == false

  check "funcDef print contains 'add'":
    let s = $addDef
    assert "add" in s

  check "funcDef print contains param names":
    let s = $addDef
    assert "a:" in s
    assert "b:" in s

  check "funcDef print contains bvadd":
    let s = $addDef
    assert "bvadd" in s

  echo ""

  # -- Test 6: Recursive function definition --------------------------------
  echo "6. irFuncDef — recursive factorial"
  let facDef = irFuncDef(
    name = "factorial",
    params = @[("n", irTypeBitVec64())],
    ret = irTypeBitVec64(),
    body = irIf(
      irLe(irVar("n", irTypeBitVec64()), irLit(1)),
      irLit(1),
      irMul(
        irVar("n", irTypeBitVec64()),
        irRecCall(@[irSub(
          irVar("n", irTypeBitVec64()),
          irLit(1)
        )])
      )
    ),
    isRec = true
  )

  check "recursive funcDef name":
    assert facDef.name == "factorial"

  check "recursive funcDef isRecursive":
    assert facDef.isRecursive == true

  check "recursive funcDef print contains '[recursive]'":
    let s = $facDef
    assert "[recursive]" in s

  check "recursive funcDef print contains 'if'":
    let s = $facDef
    assert "(if" in s

  check "recursive funcDef print contains 'rec'":
    let s = $facDef
    assert "(rec" in s

  check "recursive funcDef print contains 'bvsle'":
    let s = $facDef
    assert "bvsle" in s

  echo ""

  # -- Test 7: Round-trip (construct → print → contains expected tokens) ----
  echo "7. Round-trip: construct → print → verify tokens"

  # Build: let x = 10 in bvadd(x, x)
  let letExpr = irLet(
    "x",
    irLit(10),
    irAdd(irVar("x", irTypeBitVec64()),
          irVar("x", irTypeBitVec64()))
  )
  let letStr = $letExpr

  check "round-trip let contains 'let'":
    assert "let" in letStr

  check "round-trip let contains binding name":
    assert "x" in letStr

  check "round-trip let contains literal value":
    assert "10" in letStr

  check "round-trip let contains bvadd":
    assert "bvadd" in letStr

  # Build: case expression
  let caseExpr = irCase(
    irVar("v", irTypeBitVec64()),
    @[
      CaseBranch(pattern: 0, body: irLit(0)),
      CaseBranch(pattern: 1, body: irLit(1)),
    ],
    default = irLit(-1)
  )
  let caseStr = $caseExpr

  check "round-trip case contains 'case'":
    assert "case" in caseStr

  check "round-trip case contains patterns":
    assert "0" in caseStr
    assert "1" in caseStr

  check "round-trip case contains 'default'":
    assert "default" in caseStr

  echo ""

  # -- Test 8: Type pretty-printing -----------------------------------------
  echo "8. Type pretty-printing"
  check "Nested List type":
    let nestedType = irTypeList(irTypeList(irTypeBool()))
    assert irTypeName(nestedType) == "List List Bool"

  # -- Test 9: OverflowCheck type -------------------------------------------
  echo "9. OverflowCheck and AnnotatedExpr"
  check "AnnotatedExpr construction":
    let ae = AnnotatedExpr(
      expr: irAdd(irLit(1), irLit(2)),
      overflow: oNoOverflow
    )
    assert ae.overflow == oNoOverflow
    assert ae.expr.kind == irBinOp

  echo ""

  # -- Test 10: Canonicalization — commutative ops produce same digest -------
  echo "10. Canonicalization — commutative ops"
  check "a+b and b+a produce same digest":
    let t = irTypeBitVec64()
    let aPlusB = irFuncDef(
      name = "add",
      params = @[("a", t), ("b", t)],
      ret = t,
      body = irAdd(irVar("a", t), irVar("b", t))
    )
    let bPlusA = irFuncDef(
      name = "add",
      params = @[("a", t), ("b", t)],
      ret = t,
      body = irAdd(irVar("b", t), irVar("a", t))
    )
    let d1 = computeIrDigest(aPlusB)
    let d2 = computeIrDigest(bPlusA)
    assert d1 == d2, "digests differ: " & d1 & " vs " & d2

  check "a*b and b*a produce same digest":
    let t = irTypeBitVec64()
    let aMulB = irFuncDef(
      name = "mul",
      params = @[("a", t), ("b", t)],
      ret = t,
      body = irMul(irVar("a", t), irVar("b", t))
    )
    let bMulA = irFuncDef(
      name = "mul",
      params = @[("a", t), ("b", t)],
      ret = t,
      body = irMul(irVar("b", t), irVar("a", t))
    )
    let d1 = computeIrDigest(aMulB)
    let d2 = computeIrDigest(bMulA)
    assert d1 == d2, "digests differ: " & d1 & " vs " & d2

  check "a-b and b-a produce DIFFERENT digest (non-commutative)":
    let t = irTypeBitVec64()
    let aSubB = irFuncDef(
      name = "sub",
      params = @[("a", t), ("b", t)],
      ret = t,
      body = irBinOp(boSub, irVar("a", t), irVar("b", t))
    )
    let bSubA = irFuncDef(
      name = "sub",
      params = @[("a", t), ("b", t)],
      ret = t,
      body = irBinOp(boSub, irVar("b", t), irVar("a", t))
    )
    let d1 = computeIrDigest(aSubB)
    let d2 = computeIrDigest(bSubA)
    assert d1 != d2, "non-commutative ops must differ"

  check "alpha-renaming: let x=v0 in x+x vs let y=v0 in y+y":
    let t = irTypeBitVec64()
    let f1 = irFuncDef(
      name = "f",
      params = @[("v0", t)],
      ret = t,
      body = irLet("x", irVar("v0", t),
        irAdd(irVar("x", t), irVar("x", t)))
    )
    let f2 = irFuncDef(
      name = "f",
      params = @[("v0", t)],
      ret = t,
      body = irLet("y", irVar("v0", t),
        irAdd(irVar("y", t), irVar("y", t)))
    )
    let d1 = computeIrDigest(f1)
    let d2 = computeIrDigest(f2)
    assert d1 == d2, "alpha-renamed locals must produce same digest: " & d1 & " vs " & d2

  echo ""

  # -- Summary --------------------------------------------------------------
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
