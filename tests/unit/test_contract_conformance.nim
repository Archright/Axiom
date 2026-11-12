import std/unittest
import std/sequtils
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/verification_model_types
import core/trusted/symbol_table_types
import core/trusted/private/transition_formula_builder
import core/trusted/private/semantic_contract
import core/trusted/private/contract_conformance

let bv64 = irTypeBitVec64()

proc makeAssignmentModel(): VerificationModel =
  var sem = VMSemantic()
  sem.initState("x", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initExprs.add(irLit(0))
  var up = ParallelUpdate()
  up.addAssignment("x", irAdd(irVar("x", bv64), irLit(1)))
  sem.initTransition(NodeId(1), NodeId(2), nil, up)
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0)))

proc makeMultiAssignModel(): VerificationModel =
  var sem = VMSemantic()
  sem.initState("x", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initState("y", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initExprs.add(irLit(0))
  var up = ParallelUpdate()
  up.addAssignment("x", irLit(1))
  up.addAssignment("y", irLit(2))
  sem.initTransition(NodeId(1), NodeId(2), nil, up)
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0)))

suite "Contract Conformance Gate (L1 blocking)":
  test "well-formed single-assignment model passes conformance":
    let model = makeAssignmentModel()
    let contract = SemanticContract(
      laws: @[SemanticLaw(law: tlAssignment, description: "", subLaws: @[])],
      invariants: @[],
      conformancePredicates: @["conformsToAssignmentLaw"],
      contractIdentity: ""
    )
    let result = verifyContractKernelConformance(model, contract)
    check result == true

  test "multi-assignment model fails the assignment law":
    let model = makeMultiAssignModel()
    let contract = SemanticContract(
      laws: @[SemanticLaw(law: tlAssignment, description: "", subLaws: @[])],
      invariants: @[],
      conformancePredicates: @["conformsToAssignmentLaw"],
      contractIdentity: ""
    )
    let result = verifyContractKernelConformance(model, contract)
    check result == false

  test "contractSatisfiesAllLaws returns false for multi-assignment formula under assignment contract":
    let b = newTransitionFormulaBuilder(["x", "y"])
    var up = ParallelUpdate()
    up.addAssignment("x", irLit(1))
    up.addAssignment("y", irLit(2))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    let contract = SemanticContract(
      laws: @[SemanticLaw(law: tlAssignment, description: "", subLaws: @[])],
      invariants: @[],
      conformancePredicates: @["conformsToAssignmentLaw"],
      contractIdentity: ""
    )
    check contractSatisfiesAllLaws(contract, f, b.stateNames) == false

  test "contractSatisfiesAllLaws returns true for single-assignment formula under assignment contract":
    let b = newTransitionFormulaBuilder(["x"])
    var up = ParallelUpdate()
    up.addAssignment("x", irAdd(irVar("x", bv64), irLit(1)))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    let contract = SemanticContract(
      laws: @[SemanticLaw(law: tlAssignment, description: "", subLaws: @[])],
      invariants: @[],
      conformancePredicates: @["conformsToAssignmentLaw"],
      contractIdentity: ""
    )
    check contractSatisfiesAllLaws(contract, f, b.stateNames) == true