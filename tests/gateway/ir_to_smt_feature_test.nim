{.push raises: [CatchableError].}
## BDD feature test for ir_to_smt.feature
## Verifies IR → SMT-LIB2 conversion.

import std/[unittest, strutils]
import core/trusted/ir_to_smt
import core/trusted/axiom_ir

suite "IR to SMT-LIB2 Conversion":

  test "irTypeToSmt maps bitvec64 to SMT-LIB2 BitVec":
    let t = IRType(kind: irtBitVec64)
    let s = irTypeToSmt(t)
    check s.find("BitVec 64") != -1

  test "irTypeToSmt maps bool to Bool":
    let t = IRType(kind: irtBool)
    let s = irTypeToSmt(t)
    check s == "Bool"

  test "irExprToSmt converts addition to bvadd":
    let a = IRExpr(kind: irVar, varName: "a", varType: IRType(kind: irtBitVec64))
    let b = IRExpr(kind: irVar, varName: "b", varType: IRType(kind: irtBitVec64))
    let expr = IRExpr(kind: irBinOp, binOp: boAdd, binLhs: a, binRhs: b)
    let s = irExprToSmt(expr)
    let hasBvadd = s.contains("bvadd")
    check hasBvadd
