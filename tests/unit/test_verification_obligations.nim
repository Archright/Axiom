## P0.3 — Verification Obligation Model tests (C10, P4 per-edge disjunction).
## Verifies the backend-agnostic obligation derivation: per-edge consecutions,
## initiation conjuncts, exit safety, and the multi-edge (A->B, A->C) case.

import std/options
import std/sequtils
import std/unittest
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/verification_model_types
import core/trusted/symbol_table_types
import core/trusted/private/verification_obligations
import core/trusted/private/identity_core
import core/trusted/private/identity_mapping

let bv64 = irTypeBitVec64()

proc singleEdgeModel(): VerificationModel =
  var sem = VMSemantic()
  sem.initState("x", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initExprs.add(irLit(0))
  var up = ParallelUpdate()
  up.addAssignment("x", irAdd(irVar("x", bv64), irLit(1)))
  sem.initTransition(NodeId(1), NodeId(2), irLt(irVar("x", bv64), irLit(10)), up)
  sem.initObligation(irLe(irVar("x", bv64), irLit(10)), okImplicitSafety, SymbolOrigin(kind: sokImplicit))
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0)))

proc multiEdgeModel(): VerificationModel =
  var sem = VMSemantic()
  sem.initState("x", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initExprs.add(irLit(0))
  var up1 = ParallelUpdate()
  up1.addAssignment("x", irLit(1))
  sem.initTransition(NodeId(1), NodeId(2), irLt(irVar("x", bv64), irLit(5)), up1)  # A->B
  var up2 = ParallelUpdate()
  up2.addAssignment("x", irLit(2))
  sem.initTransition(NodeId(1), NodeId(3), irGe(irVar("x", bv64), irLit(5)), up2)  # A->C
  # no property/obligation here; init + initObligation arity must match size but
  # buildX only reads states/initExprs/transitions — leave obligations empty so
  # buildSafeties returns [] (valid: safety derivation is property-driven).
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0)))

suite "Verification Obligation Model (C10 / P4)":
  test "initiation family yields entry conjuncts":
    let m = singleEdgeModel()
    let obs = buildObligations(m)
    check obs.initiations.len == 1
    check obs.initiations[0].initConjuncts.len == 1

  test "consecution is per-edge (single edge)":
    let m = singleEdgeModel()
    let obs = buildObligations(m)
    check obs.consecutions.len == 1
    check obs.consecutions[0].transitionIndex == 0
    check obs.consecutions[0].postArgsSmt.len == 1  # one state var

  test "P4 disjunction: two edges from same source yield two distinct consecutions":
    let m = multiEdgeModel()
    let obs = buildObligations(m)
    check obs.consecutions.len == 2
    check obs.consecutions[0].sourceNode == obs.consecutions[1].sourceNode  # same A
    check obs.consecutions[0].targetNode != obs.consecutions[1].targetNode  # B vs C
    check obs.consecutions[0].guardSmt != obs.consecutions[1].guardSmt

  test "safety family derives from property/obligations":
    let m = singleEdgeModel()
    let obs = buildObligations(m)
    check obs.safeties.len == 1
    check obs.safeties[0].exitNode == NodeId(0)
    check obs.safeties[0].propertySmt.len > 0

  test "relation map is populated from transitions (C14)":
    let m = multiEdgeModel()
    let obs = buildObligations(m)
    check obs.relationMap.relationToNode.anyIt(it.relation == RelationId("rel_state"))

  test "consecution is kernel-derived: one per edge with non-trivial guardSmt and postArgsSmt":
    let m = singleEdgeModel()
    let obs = buildObligations(m)
    check obs.consecutions.len == 1
    check obs.consecutions[0].guardSmt.len > 0
    check obs.consecutions[0].guardSmt != "true"
    check obs.consecutions[0].postArgsSmt.len == 1
    check obs.consecutions[0].postArgsSmt[0].len > 0

  test "P4 disjunction: two edges yield two kernel-derived consecutions with distinct guards":
    let m = multiEdgeModel()
    let obs = buildObligations(m)
    check obs.consecutions.len == 2
    check obs.consecutions[0].guardSmt != "true"
    check obs.consecutions[1].guardSmt != "true"
    check obs.consecutions[0].postArgsSmt.len == 1
    check obs.consecutions[1].postArgsSmt.len == 1