## P0.3.11 — C5.1 Golden Transition-Formula Semantics tests.
## The single operational definition of ParallelUpdate, shared by CHC, Evidence
## (and BMC when migrated). SSOT: docs/spec/cfg_contract_specification.md §C5.1.
##
## Every encoder must derive its transition formula from
## `transition_formula_builder` — a divergence here is a soundness bug.

import std/unittest
import std/sequtils
import std/strutils
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/verification_model_types
import core/trusted/private/transition_formula_builder
import core/trusted/private/semantic_contract

let bv64 = irTypeBitVec64()

proc getNext(formula: TransitionFormula): seq[string] =
  formula.postArgs.mapIt(it.nextSmt)

suite "Golden Transition-Formula Semantics (C5.1)":
  let b = newTransitionFormulaBuilder(["x", "y", "z"])

  test "assignment swap is simultaneous, not sequential":
    # x := y ; y := x  ⇒  x' = y /\ y' = x   (NOT y' = x')
    var up = ParallelUpdate()
    up.addAssignment("x", irVar("y", bv64))
    up.addAssignment("y", irVar("x", bv64))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    let next = getNext(f)
    # stateNames order [x, y, z]; z is frame.
    check next[0] == "y"   # x' = y
    check next[1] == "x"   # y' = x   (independent of x')
    check next[2] == "z"   # frame: z' = z

  test "single assignment frames the rest":
    # x := e ⇒ x' = e(x) /\ forall z != x : z' = z
    var up = ParallelUpdate()
    up.addAssignment("x", irLit(5))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    let next = getNext(f)
    # irLit(5) serializes to the BV literal of 5; semantics is x' = 5.
    check next[0] == "#x0000000000000005"
    check next[1] == "y"   # frame
    check next[2] == "z"   # frame

  test "frame semantics: unassigned variable persists (v' = v)":
    var up = ParallelUpdate()
    up.addAssignment("x", irVar("x", bv64))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    check getNext(f)[1] == "y"

  test "havoc leaves post-state unconstrained":
    var up = ParallelUpdate()
    up.addHavoc("y")
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    let next = getNext(f)
    check next[0] == "x"      # frame
    check next[1].startsWith("__havoc")  # unconstrained
    check next[2] == "z"      # frame

  test "parallel distinct: both RHS evaluated in pre-state":
    # x := y ; y := z  ⇒  x' = y /\ y' = z   (both RHS from pre-state S)
    var up = ParallelUpdate()
    up.addAssignment("x", irVar("y", bv64))
    up.addAssignment("y", irVar("z", bv64))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    let next = getNext(f)
    check next[0] == "y"   # x' = y
    check next[1] == "z"   # y' = z
    check next[2] == "z"   # frame z' = z

  test "guard: non-nil guard serializes and is not true":
    let g = irLt(irVar("x", bv64), irLit(10))
    var up = ParallelUpdate()
    up.addAssignment("x", irLit(5))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: g, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    check f.guardSmt != "true"
    check f.guardSmt == "(bvslt x #x000000000000000A)"
    check conformsToGuardLaw(f)

  test "branch graph semantics: two outgoing transitions from same source are independent and well-formed":
    let trAB = Transition(source: NodeId(1), target: NodeId(2), guard: irLt(irVar("x", bv64), irLit(10)), update: ParallelUpdate())
    let trAC = Transition(source: NodeId(1), target: NodeId(3), guard: irGe(irVar("x", bv64), irLit(10)), update: ParallelUpdate())
    var fresh = 0
    let fAB = buildTransitionFormula(b, trAB, fresh)
    let fAC = buildTransitionFormula(b, trAC, fresh)
    # Both well-formed
    check fAB.postArgs.len == b.stateNames.len
    check fAC.postArgs.len == b.stateNames.len
    # Independent: distinct guards
    check fAB.guardSmt != fAC.guardSmt
    # Contract declares a branch law and both formulas conform
    let contract = makeSemanticContract()
    check contract.laws.anyIt(it.law == tlBranch)
    check conformsToBranchLaw(fAB, b.stateNames)
    check conformsToBranchLaw(fAC, b.stateNames)

  test "multi-edge: two transitions sharing a source yield independent guarded formulas":
    var up1 = ParallelUpdate()
    up1.addAssignment("x", irLit(1))
    var up2 = ParallelUpdate()
    up2.addAssignment("x", irLit(2))
    let tr1 = Transition(source: NodeId(1), target: NodeId(2), guard: irLt(irVar("x", bv64), irLit(5)), update: up1)
    let tr2 = Transition(source: NodeId(1), target: NodeId(3), guard: irGe(irVar("x", bv64), irLit(5)), update: up2)
    var fresh = 0
    let f1 = buildTransitionFormula(b, tr1, fresh)
    let f2 = buildTransitionFormula(b, tr2, fresh)
    # Each has its own guard
    check f1.guardSmt != "true"
    check f2.guardSmt != "true"
    check f1.guardSmt != f2.guardSmt
    # Each has its own post state
    check f1.postArgs[0].nextSmt != f2.postArgs[0].nextSmt
    # Each conforms to guard law
    check conformsToGuardLaw(f1)
    check conformsToGuardLaw(f2)

  test "frame-completeness: x := x + 1 leaves y framed (y' = y)":
    # Critical: evidence layer previously had problems where y' was not y
    var up = ParallelUpdate()
    up.addAssignment("x", irAdd(irVar("x", bv64), irLit(1)))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    let next = getNext(f)
    check next[0] == "(bvadd x #x0000000000000001)"  # x' = x + 1
    check next[1] == "y"   # y' = y (frame, not lost)
    check next[2] == "z"   # z' = z (frame)
    check conformsToAssignmentLaw(f, b.stateNames)

  test "empty / no-op transition: all state vars frame":
    var up = ParallelUpdate()
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    let next = getNext(f)
    check next[0] == "x"
    check next[1] == "y"
    check next[2] == "z"
    check conformsToEmptyNoopLaw(f, b.stateNames)
    check conformsToFrameLaw(f, b.stateNames)

  test "composed: guard + 2 assignments + frame var preserves conjunction of semantics":
    var up = ParallelUpdate()
    up.addAssignment("x", irLit(1))
    up.addAssignment("y", irAdd(irVar("y", bv64), irLit(1)))
    let g = irLt(irVar("x", bv64), irVar("y", bv64))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: g, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    # Guard retained
    check f.guardSmt != "true"
    check f.guardSmt == "(bvslt x y)"
    # Both updates in state order: x' = 1, y' = y + 1
    let next = getNext(f)
    check next[0] == "#x0000000000000001"  # x' = 1
    check next[1] == "(bvadd y #x0000000000000001)"  # y' = y + 1
    # Frame var z persists
    check next[2] == "z"  # z' = z
    # Conforms to composed law
    check conformsToComposedLaw(f, b.stateNames)
    check conformsToGuardLaw(f)

  test "contractSatisfiesAllLaws returns true for a valid assignment formula":
    var up = ParallelUpdate()
    up.addAssignment("x", irLit(5))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    let contract = makeSemanticContract()
    let assignmentContract = SemanticContract(
      laws: @[SemanticLaw(law: tlAssignment, description: "", subLaws: @[])],
      invariants: @[],
      conformancePredicates: @["conformsToAssignmentLaw"],
      contractIdentity: ""
    )
    check contractSatisfiesAllLaws(assignmentContract, f, b.stateNames)

  test "contractSatisfiesAllLaws returns false when two vars assigned (assignment law fails)":
    var up = ParallelUpdate()
    up.addAssignment("x", irLit(5))
    up.addAssignment("y", irLit(10))
    let tr = Transition(source: NodeId(1), target: NodeId(2), guard: nil, update: up)
    var fresh = 0
    let f = buildTransitionFormula(b, tr, fresh)
    let assignmentContract = SemanticContract(
      laws: @[SemanticLaw(law: tlAssignment, description: "", subLaws: @[])],
      invariants: @[],
      conformancePredicates: @["conformsToAssignmentLaw"],
      contractIdentity: ""
    )
    check not contractSatisfiesAllLaws(assignmentContract, f, b.stateNames)

  test "contractIdentity is deterministic across two contract instances":
    let c1 = makeSemanticContract()
    let c2 = makeSemanticContract()
    check c1.contractIdentity == c2.contractIdentity