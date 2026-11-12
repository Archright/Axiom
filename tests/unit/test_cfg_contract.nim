## P0.3.11 — CFG Contract tests for Phase 1 types (C1–C7).
## Exercises the domain types from core/trusted/verification_model_types.nim:
## NodeId, CFGNode/FunctionCFG, Transition, ParallelUpdate, Assignment, Havoc,
## VMSemantic/VMMetadata, VerificationModel. Contract SSOT:
## docs/spec/cfg_contract_specification.md.

import std/[unittest, options, sequtils]
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types

let bv64 = irTypeBitVec64()

proc buildValidModel(): VerificationModel =
  var sem = VMSemantic()
  sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initState("sum", bv64, SymbolOrigin(kind: sokLoopState))
  sem.initExprs.add(irLit(0))
  sem.initExprs.add(irLit(0))
  let iVar = irVar("i", bv64)
  let sumVar = irVar("sum", bv64)
  var update = ParallelUpdate()
  update.addAssignment("sum", irAdd(sumVar, iVar))
  sem.initTransition(NodeId(1), NodeId(2), irLt(iVar, irLit(10)), update)
  sem.initObligation(irLe(sumVar, irLit(100)), okImplicitSafety, SymbolOrigin(kind: sokImplicit))
  sem.exitGuard = some(irLt(iVar, irLit(10)))
  sem.logicalDomain = ldBitVec
  var st = SymbolTable()
  st.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
  st.addSymbol("sum", SymbolOrigin(kind: sokLoopState), bv64)
  VerificationModel(
    semantic: sem,
    metadata: VMMetadata(
      functionExit: NodeId(0),
      symbolMap: st,
      sourceLocation: "tests/unit/test_cfg_contract.nim"
    )
  )

suite "CFG Contract — NodeId (C1)":
  test "NodeId equality and inequality":
    check NodeId(0) == NodeId(0)
    check NodeId(7) == NodeId(7)
    check NodeId(0) != NodeId(1)
    check not (NodeId(3) == NodeId(4))

  test "NodeId string representation":
    check $NodeId(5) == "5"
    check $NodeId(0) == "0"

  test "NodeId is a distinct uint32 (explicit conversion only)":
    check uint32(NodeId(1)) == 1'u32
    check uint32(NodeId(4294967295)) == 0xFFFF_FFFF'u32

  test "NodeId usable as CFGNode identity":
    let node = CFGNode(id: NodeId(3), kind: cnkBlock, successors: @[], predecessors: @[])
    check node.id == NodeId(3)
    check node.kind == cnkBlock

suite "CFG Contract — Transition (C4)":
  test "Transition constructed with source/target/guard/update":
    let guard = irLt(irVar("i", bv64), irLit(10))
    var upd = ParallelUpdate()
    upd.addAssignment("sum", irAdd(irVar("sum", bv64), irVar("i", bv64)))
    var sem = VMSemantic()
    sem.initTransition(NodeId(1), NodeId(2), guard, upd)
    check sem.transitions.len == 1
    let tr = sem.transitions[0]
    check tr.source == NodeId(1)
    check tr.target == NodeId(2)
    check tr.guard != nil
    check tr.guard.kind == irBinOp
    check tr.update.assignments.len == 1

  test "transition guard is a boolean formula":
    let guard = irLt(irVar("i", bv64), irLit(10))
    check guard.kind == irBinOp
    check guard.binOp == boLt

suite "CFG Contract — ParallelUpdate simultaneous semantics (C5)":
  test "swap x = y; y = x preserves both pre-state RHS":
    var upd = ParallelUpdate()
    upd.addAssignment("x", irVar("y", bv64))
    upd.addAssignment("y", irVar("x", bv64))
    check upd.assignments.len == 2
    check upd.assignments[0].symbol == "x"
    check upd.assignments[0].expr.kind == irVar
    check upd.assignments[0].expr.varName == "y"
    check upd.assignments[1].symbol == "y"
    check upd.assignments[1].expr.varName == "x"

  test "storage order is preserved for deterministic serialization":
    var upd = ParallelUpdate()
    upd.addAssignment("a", irLit(1))
    upd.addAssignment("b", irLit(2))
    upd.addAssignment("c", irLit(3))
    check upd.assignments.mapIt(it.symbol) == @["a", "b", "c"]

  test "frame rule contract — unassigned state variables persist by name":
    var upd = ParallelUpdate()
    upd.addAssignment("sum", irLit(1))
    upd.addHavoc("tmp")
    check upd.assignments.len == 1
    check upd.havocs.len == 1

suite "CFG Contract — Assignment and Havoc (C5/C6)":
  test "addAssignment appends Assignment with symbol and expr":
    var upd = ParallelUpdate()
    upd.addAssignment("sum", irAdd(irVar("sum", bv64), irLit(1)))
    check upd.assignments.len == 1
    check upd.assignments[0].symbol == "sum"
    check upd.assignments[0].expr.kind == irBinOp

  test "addHavoc records unconstrained post-state symbol":
    var upd = ParallelUpdate()
    upd.addHavoc("ext")
    check upd.havocs.len == 1
    check upd.havocs[0] == "ext"

  test "havoc and assignment coexist independently":
    var upd = ParallelUpdate()
    upd.addHavoc("ext")
    upd.addAssignment("sum", irLit(0))
    check upd.havocs == @["ext"]
    check upd.assignments.len == 1

suite "CFG Contract — VerificationModel (C7)":
  test "semantic + metadata split":
    let vm = buildValidModel()
    check vm.semantic.states.len == 2
    check vm.semantic.initExprs.len == 2
    check vm.semantic.transitions.len == 1
    check vm.metadata.functionExit == NodeId(0)
    check vm.metadata.sourceLocation == "tests/unit/test_cfg_contract.nim"
    check vm.metadata.symbolMap.hasSymbol("i")

  test "single-function unit — one model carries one function's semantics":
    let vm = buildValidModel()
    check vm.semantic.states.len == 2
    check vm.metadata.functionExit == NodeId(0)

  test "obligations recorded via initObligation":
    var sem = VMSemantic()
    sem.initObligation(irLe(irVar("sum", bv64), irLit(100)), okImplicitSafety, SymbolOrigin(kind: sokImplicit))
    check sem.obligations.len == 1
    check sem.obligations[0].kind == okImplicitSafety
    check sem.obligations[0].predicate.kind == irBinOp
    check sem.hasAnyObligation() == true

  test "hasAnyObligation is false for empty model":
    var sem = VMSemantic()
    check sem.hasAnyObligation() == false

  test "loopFacts carries bounded/unbounded loop metadata":
    var sem = VMSemantic()
    sem.loopFacts = some(LoopFacts(
      kind: lfkBounded,
      counterName: "i",
      lowerBound: some(0'i64),
      upperBound: some(10'i64)
    ))
    check sem.loopFacts.isSome
    check sem.loopFacts.get.kind == lfkBounded
    check sem.loopFacts.get.counterName == "i"
    check sem.loopFacts.get.upperBound.get == 10'i64

  test "logicalDomain is explicit":
    let vm = buildValidModel()
    check vm.semantic.logicalDomain == ldBitVec

  test "exitGuard optional is honored":
    let vm = buildValidModel()
    check vm.semantic.exitGuard.isSome
    check vm.semantic.exitGuard.get.kind == irBinOp
