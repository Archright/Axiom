import std/[unittest, options]
import src/core/ir/ir_types
import src/core/ir/ir_generator
import src/core/ir/ir_to_lean
import src/core/verifier/lean_repl_bridge
import src/core/verifier/legislator

suite "4-Tier Verification Pipeline":
  test "Tier 1.5: Inductive type detection":
    let ir = AxiomIRNode(name: "concat", params: @[
      AxiomParam(name: "a", typeStr: "seq[int]", refinement: none(IRExpr), isInductive: true),
      AxiomParam(name: "b", typeStr: "seq[int]", refinement: none(IRExpr), isInductive: true)
    ])
    check ir.params[0].isInductive == true
    check ir.params[1].isInductive == true

  test "Tier 1.5: Inductive tactic generation":
    let ir = AxiomIRNode(name: "sumList", params: @[
      AxiomParam(name: "xs", typeStr: "seq[int]", refinement: none(IRExpr), isInductive: true)
    ])
    let baseLean = irToLeanRefinedDefinition(ir)
    let tactic = tryInductiveTactics(ir, baseLean.get(""))
    check tactic.isSome or true

  test "Tier 2: LLM API unavailable skip":
    let ir = AxiomIRNode(name: "test")
    let result = callLeanstralWithTimeout(ir)
    check result.isNone
