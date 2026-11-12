import std/options
import std/strutils
import core/ir/ir_types
import core/ir/ir_to_lean

proc assertEq(actual, expected: string; label: string) =
  doAssert actual == expected, label & " expected: " & expected & ", got: " & actual

proc assertLeanVerified(code: string; label: string) =
  doAssert verifyInLeanRepl(code), label

proc main() =
  let ir = AxiomIRNode(
    kind: irCall, name: "identity",
    params: @[AxiomParam(name: "x", typeStr: "Nat", refinement: none(IRExpr),
    isInductive: false)],
    preConditions: @[],
    postCondition: none(IRExpr))
  let leanCode = "theorem identity_spec (x : Nat) : x = x :="
  assertEq(selectFastTactic(ir), "by rfl", "Tier 1 fast tactic")
  assertLeanVerified(leanCode & "\n  " & selectFastTactic(ir), "Tier 1 Lean verification")
  assertEq(generateOptimalTactic(ir, leanCode).get(""), "by rfl", "Tier 1 solver")

  let pred = IRExpr(kind: ieBinaryOp,
    left: IRExpr(kind: ieVar, varName: "x"),
    op: ">=",
    right: IRExpr(kind: ieConst, val: "0"))
  let ir2 = AxiomIRNode(
    kind: irCall, name: "positive",
    params: @[AxiomParam(name: "x", typeStr: "Nat", refinement: none(IRExpr),
    isInductive: false)],
    preConditions: @[],
    postCondition: some(pred))
  let leanCode2 = "theorem positive_spec (x : Nat) : x >= 0 :="
  assertEq(selectFastTactic(ir2), "by simp [*]", "Tier 1 contract tactic")
  assertLeanVerified(leanCode2 & "\n  " & selectFastTactic(ir2), "Tier 1 contract Lean verification")
  assertEq(generateOptimalTactic(ir2, leanCode2).get(""), "by simp [*]", "Tier 1 contract solver")

  let pred3 = IRExpr(kind: ieBinaryOp,
    left: IRExpr(kind: ieVar, varName: "x"),
    op: ">",
    right: IRExpr(kind: ieConst, val: "0"))
  let ir3 = AxiomIRNode(
    kind: irCall, name: "requires_llm_or_z3",
    params: @[AxiomParam(name: "x", typeStr: "Int", refinement: none(IRExpr),
    isInductive: false)],
    preConditions: @[],
    postCondition: some(pred3))
  let leanCode3 = "theorem requires_llm_or_z3_spec (x : Int) : x > 0 :="
  let tacticOpt = generateOptimalTactic(ir3, leanCode3)
  doAssert tacticOpt.isNone, "Tier 3 fallback tactic: unprovable theorem must return none"

  echo "All 3 tests passed"

main()
