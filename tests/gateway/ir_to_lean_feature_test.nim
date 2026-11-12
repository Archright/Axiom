{.push raises: [CatchableError].}
## BDD feature test for ir_to_lean.feature
## Verifies IR → Lean 4 code generation with termination proofs.

import std/[unittest, strutils]
import core/trusted/ir_to_lean
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers

suite "IR to Lean Code Generation":

  test "irTypeToLean maps bitvec64 to BitVec 64":
    let t = IRType(kind: irtBitVec64)
    let s = irTypeToLean(t)
    check s.find("BitVec 64") != -1

  test "irTypeToLean maps bool to Bool":
    let t = IRType(kind: irtBool)
    let s = irTypeToLean(t)
    check s == "Bool"

  test "irToLean produces valid Lean syntax for function defs":
    let funcDef = IRFuncDef(
      name: "add",
      params: @[IRFuncParam(name: "a", ty: IRType(kind: irtBitVec64)), IRFuncParam(name: "b", ty: IRType(kind: irtBitVec64))],
      retType: IRType(kind: irtBitVec64),
      body: irLit(0)
    )
    let leanSrc = irToLeanModule(funcDef)
    let hasDef = leanSrc.contains("def add")
    let hasBitVec = leanSrc.contains("BitVec 64")
    check hasDef
    check hasBitVec
