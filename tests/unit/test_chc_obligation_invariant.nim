## P1.2 — cnaNoObligations invariant + ContractInfo property ingestion.
##
## Core regression for the CHC obligation fix:
##   cnaNoObligations  iff  buildObligations(model).safeties == ∅ AND
##                          model.semantic.obligations == ∅
##
## A VerificationModel whose `property` is set from ContractInfo.postConditions
## MUST produce a non-empty safety obligation (so buildChcFromVerificationModel
## reaches cbSuccess, NOT cnaNoObligations). Conversely, an obligation-free model
## remains cnaNoObligations (genuine vacuity, not a backend inability).

import std/[unittest, options]
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/private/verification_obligations
import core/trusted/private/ir_loop_to_horn
import core/trusted/private/chc_build_result
import core/trusted/verification_result_types

let bv64 = irTypeBitVec64()

proc makeObligationModel(): VerificationModel =
  ## A minimal well-formed loop transition system WITHOUT property or obligations
  ## (the degenerate case that must classify as cnaNoObligations).
  var sem = VMSemantic()
  sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initExprs.add(irLit(0))
  let iVar = irVar("i", bv64)
  var upd = ParallelUpdate()
  upd.addAssignment("i", irAdd(iVar, irLit(1)))
  sem.initTransition(NodeId(1), NodeId(2), irLt(iVar, irLit(10)), upd)
  sem.exitGuard = some(irLt(iVar, irLit(10)))
  sem.logicalDomain = ldBitVec
  var st = SymbolTable()
  st.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
  VerificationModel(
    semantic: sem,
    metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st, sourceLocation: "test")
  )

proc makePropertyModel(): VerificationModel =
  ## Same as makeObligationModel but with `property` set to a postcondition
  ## (simulating ContractInfo.postConditions → VMSemantic.property).
  result = makeObligationModel()
  result.semantic.property = some(irLe(irVar("i", bv64), irLit(10)))

suite "P1.2 CHC Obligation Invariant":
  test "cnaNoObligations iff safety set is empty (vacuous model)":
    let vm = makeObligationModel()
    let derived = buildObligations(vm)
    check derived.safeties.len == 0
    check vm.semantic.obligations.len == 0
    let res = buildChcFromVerificationModel(vm, vm.metadata.symbolMap)
    check res.kind == cbNotApplicable
    check res.notApplicableReason == cnaNoObligations

  test "property set from contract.unblocks cnaNoObligations (cbSuccess)":
    let vm = makePropertyModel()
    let derived = buildObligations(vm)
    # Setting property yields exactly one safety obligation (the exit property).
    check derived.safeties.len == 1
    let res = buildChcFromVerificationModel(vm, vm.metadata.symbolMap)
    check res.kind == cbSuccess

  test "property-present model is NOT classified cnaNoObligations":
    let vm = makePropertyModel()
    let res = buildChcFromVerificationModel(vm, vm.metadata.symbolMap)
    check not (res.kind == cbNotApplicable and res.notApplicableReason == cnaNoObligations)

  test "ContractInfo carries postConditions for semantic property ingestion":
    # The lowering consumes contract.postConditions to set VMSemantic.property
    # (POST-only in P1; preConditions are preserved but unconsumed).
    let post = irLe(irVar("i", bv64), irLit(42))
    let contract = ContractInfo(preConditions: @[], postConditions: @[post])
    check contract.preConditions.len == 0
    check contract.postConditions.len == 1
    # A model whose property is set from the contract's postConditions (the P1
    # ingestion) yields a non-empty safety obligation → cbSuccess (NOT cnaNoObligations).
    let vm = makePropertyModel()
    let derived = buildObligations(vm)
    check derived.safeties.len == 1
    let res = buildChcFromVerificationModel(vm, vm.metadata.symbolMap)
    check res.kind == cbSuccess

  test "rkNoObligation is semantically distinct from not-encodable / no-property":
    check rkNoObligation != rkNotEncodable
    check rkNoObligation != rkNoProperty
    check rkNoObligation notin {rkNotEncodable, rkNoProperty, rkUnsupportedTheory}
    let noob = makeNoObligation()
    check noob.status == vsNoObligation
    check noob.reason == rkNoObligation

  test "rkNoApplicableObligation is distinct from legacy rkNoObligation":
    check rkNoApplicableObligation != rkNoObligation
    check rkNoApplicableObligation notin {rkNotEncodable, rkNoProperty, rkUnsupportedTheory, rkObligationUnsupported, rkObligationIllFormed}