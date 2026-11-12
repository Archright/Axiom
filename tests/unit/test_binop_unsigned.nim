## Unit tests for boLtU — operator-resident unsigned strict comparison
## (rust_certified_subset.md §4 boLtU; axiom_core_ir_spec.md wire ordinal 16).
## One contract, five adapter views: append-only ordinal + text/binary
## codec round-trip, SMT bvult, Lean BitVec.ult, replay unsigned order,
## producer discrimination (uint params → boLtU; int/mixed → boLt, never
## a guess) on both producer paths (NimNode compile-time and canon runtime).
## Uses custom main() pattern to avoid unittest framework cleanup crashes.

import std/[strutils, tables, macros, options]
import compiler/ast
import core/parser_utils
import core/types/smt_types
import core/trusted/axiom_ir_helpers
import core/trusted/ast_to_ir
import core/trusted/pnode_to_canon
import core/trusted/ir_to_lean
import core/trusted/private/obligation_smt_lowering
import infrastructure/ir_binary_codec
import verification/counterexample_replay

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  initParserUtils()
  let bv64 = irTypeBitVec64()

  # =========================================================================
  # Section 1: enum ordinal stability (append-only wire contract)
  # =========================================================================
  echo "=== boLtU — enum & wire ordinal (append-only) ==="

  check "boLtU ordinal is 16": assert boLtU.ord == 16
  check "boLtU appends after boEq (16 after 15)":
    assert boEq.ord == 15 and boLtU.ord == boEq.ord + 1
  check "pre-existing ordinals unchanged":
    assert boLt.ord == 9 and boLe.ord == 10 and boGt.ord == 11 and
      boGe.ord == 12 and boAnd.ord == 13 and boOr.ord == 14

  # =========================================================================
  # Section 2: text & binary codec round-trips (wire ordinal 16)
  # =========================================================================
  echo ""
  echo "=== boLtU — codec round-trips ==="

  let eU = irBinOp(boLtU, irVar("x", bv64), irVar("y", bv64))

  let sU = serializeIRExpr(eU)
  check "text serializes BIN(boLtU,...)": assert "BIN(boLtU," in sU
  var pos = 0
  let backT = parseIRExpr(sU, pos)
  check "text round-trip keeps boLtU":
    assert backT != nil and backT.kind == irBinOp and backT.binOp == boLtU

  let wire = serializeIRExprAligned(eU)
  let backW = deserializeIRExprAligned(wire)
  check "binary wire round-trip keeps boLtU":
    assert backW != nil and backW.kind == irBinOp and backW.binOp == boLtU

  # fail-closed: ordinal 17 is out-of-domain (decode error, never a
  # reinterpretation)
  var bad17: seq[byte] = @[byte(0x08), byte(17)]
  for _ in 1 ..< 8: bad17.add(byte(0))
  check "out-of-domain ordinal 17 rejected":
    assert deserializeIRExprAligned(bad17) == nil

  # =========================================================================
  # Section 3: SMT lowering — bvult, never bvslt
  # =========================================================================
  echo ""
  echo "=== boLtU — SMT lowering (bvult) ==="

  check "binOpSmt boLtU is bvult":
    assert binOpSmt(boLtU, irTypeBitVec64(), irTypeBitVec64()) == "bvult"
  let smtOut = smtTermFor(eU, slQfBv)
  check "smtTermFor emits bvult": assert "bvult" in smtOut
  check "smtTermFor never bvslt for boLtU": assert "bvslt" notin smtOut
  let smtSigned = smtTermFor(irBinOp(boLt, irVar("x", bv64), irVar("y", bv64)), slQfBv)
  check "boLt stays bvslt (signed channel intact)":
    assert "bvslt" in smtSigned and "bvult" notin smtSigned

  # =========================================================================
  # Section 4: Lean emission — BitVec.ult, never BitVec.slt
  # =========================================================================
  echo ""
  echo "=== boLtU — Lean emission (BitVec.ult) ==="

  check "irBinOpToLean boLtU is BitVec.ult":
    assert irBinOpToLean(boLtU) == "BitVec.ult"
  let leanOut = irExprToLean(eU)
  check "irExprToLean emits BitVec.ult": assert "BitVec.ult" in leanOut
  check "irExprToLean never BitVec.slt for boLtU":
    assert "BitVec.slt" notin leanOut

  # =========================================================================
  # Section 5: replay — unsigned order (cross-region discrimination)
  # =========================================================================
  echo ""
  echo "=== boLtU — replay unsigned order ==="

  let v5 = ConcreteValue(kind: ckInt, i: 5'i64)
  # 2^63: as signed int64 the minimum, as unsigned 9223372036854775808
  let vMsb = ConcreteValue(kind: ckInt, i: -9223372036854775808'i64)
  let v0 = ConcreteValue(kind: ckInt, i: 0'i64)
  # 2^64 - 1 as unsigned
  let vMax = ConcreteValue(kind: ckInt, i: -1'i64)

  let rU1 = evalConcreteBinOp(boLtU, v5, vMsb)
  check "boLtU 5 < 2^63 unsigned → true":
    assert rU1.isSome and rU1.get.kind == ckBool and rU1.get.b == true
  let rU2 = evalConcreteBinOp(boLtU, vMsb, v5)
  check "boLtU 2^63 < 5 unsigned → false":
    assert rU2.isSome and rU2.get.kind == ckBool and rU2.get.b == false
  # the signed flip on the SAME operand pair — discriminating pair
  let rS2 = evalConcreteBinOp(boLt, vMsb, v5)
  check "boLt 2^63(= min signed) < 5 signed → true (the flip)":
    assert rS2.isSome and rS2.get.kind == ckBool and rS2.get.b == true
  # boundaries
  let rMax0 = evalConcreteBinOp(boLtU, vMax, v0)
  check "boLtU 2^64-1 < 0 unsigned → false":
    assert rMax0.isSome and not rMax0.get.b
  let r0Max = evalConcreteBinOp(boLtU, v0, vMax)
  check "boLtU 0 < 2^64-1 unsigned → true":
    assert r0Max.isSome and r0Max.get.b
  # non-int operand stays fail-closed
  let rBad = evalConcreteBinOp(boLtU, ConcreteValue(kind: ckBool, b: true), v0)
  check "boLtU non-int operand → none (fail closed)":
    assert rBad.isNone

  # =========================================================================
  # Section 6: producer discrimination — canon runtime path
  # (parseStringAST → pnodeToCanon → axiomBodyCanon)
  # =========================================================================
  echo ""
  echo "=== boLtU — producer discrimination (canon runtime path) ==="

  block:
    let astU = parseStringAST("proc isLessU(x, y: uint64): bool = x < y")
    doAssert not astU.isNil
    let canonU = pnodeToCanon(astU[].sons[0])
    let defU = axiomBodyCanon(canonU)
    check "canon uint64 < uint64 produces boLtU":
      assert defU.body.kind == irBinOp and defU.body.binOp == boLtU

  block:
    let astI = parseStringAST("proc isLessI(a, b: int): bool = a < b")
    let canonI = pnodeToCanon(astI[].sons[0])
    let defI = axiomBodyCanon(canonI)
    check "canon int < int keeps boLt":
      assert defI.body.kind == irBinOp and defI.body.binOp == boLt

  block:
    let astM = parseStringAST("proc isLessM(x: uint64, y: int): bool = x < y")
    let canonM = pnodeToCanon(astM[].sons[0])
    let defM = axiomBodyCanon(canonM)
    check "canon mixed uint64/int keeps boLt (never a guess)":
      assert defM.body.kind == irBinOp and defM.body.binOp == boLt

  block:
    let astW = parseStringAST("proc isLessW(a, b: uint16): bool = a < b")
    let canonW = pnodeToCanon(astW[].sons[0])
    let defW = axiomBodyCanon(canonW)
    check "canon uint16 < uint16 produces boLtU (uint family)":
      assert defW.body.kind == irBinOp and defW.body.binOp == boLtU

  # =========================================================================
  # Section 7: producer discrimination — NimNode compile-time path
  # (convertFuncDef via quote/do, the ast_to_ir_test macro pattern)
  # =========================================================================
  echo ""
  echo "=== boLtU — producer discrimination (NimNode compile-time path) ==="

  macro nimPathOpUint(): untyped =
    let irDef = convertFuncDef(quote do:
      proc isLessNU(x, y: uint64): bool = x < y)
    result = newLit(irDef.body.binOp.ord)

  macro nimPathOpInt(): untyped =
    let irDef = convertFuncDef(quote do:
      proc isLessNI(a, b: int): bool = a < b)
    result = newLit(irDef.body.binOp.ord)

  macro nimPathOpMixed(): untyped =
    let irDef = convertFuncDef(quote do:
      proc isLessNM(x: uint64, y: int): bool = x < y)
    result = newLit(irDef.body.binOp.ord)

  check "NimNode uint64 < uint64 produces boLtU":
    assert nimPathOpUint() == 16
  check "NimNode int < int keeps boLt":
    assert nimPathOpInt() == 9
  check "NimNode mixed uint64/int keeps boLt (never a guess)":
    assert nimPathOpMixed() == 9

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
