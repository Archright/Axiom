## Stage 6: CFG branching — break/continue/return as Transition targets.
## Demonstrates that break/continue/return are modeled purely as Transition
## edges with guards routing control flow to the correct target NodeId,
## and that conformsToBranchLaw holds for the resulting branching model.
## Contract SSOT: docs/spec/cfg_contract_specification.md (C4, C14).

import std/[unittest, sequtils, strutils]
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/private/transition_formula_builder
import core/trusted/private/semantic_contract

let bv64 = irTypeBitVec64()

proc buildWhileLoopModel(): VMSemantic =
  var sem = VMSemantic()
  sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initState("sum", bv64, SymbolOrigin(kind: sokLoopState))
  sem.initExprs.add(irLit(0))
  sem.initExprs.add(irLit(0))
  sem.logicalDomain = ldBitVec
  sem

suite "CFG Branching — break/continue/return as Transition targets":
  test "while-loop with break and continue maps to Transition edges with guards":
    var sem = buildWhileLoopModel()
    let iVar = irVar("i", bv64)
    let sumVar = irVar("sum", bv64)

    sem.initTransition(NodeId(0), NodeId(1), nil, ParallelUpdate())
    sem.initTransition(NodeId(1), NodeId(2), irLt(iVar, irLit(10)), ParallelUpdate())
    sem.initTransition(NodeId(1), NodeId(3), irGe(iVar, irLit(10)), ParallelUpdate())

    var continueUpd = ParallelUpdate()
    continueUpd.addAssignment("i", irAdd(iVar, irLit(1)))
    continueUpd.addAssignment("sum", irAdd(sumVar, iVar))
    sem.initTransition(NodeId(2), NodeId(1), nil, continueUpd)

    sem.initTransition(NodeId(2), NodeId(4), nil, ParallelUpdate())

    let model = VerificationModel(
      semantic: sem,
      metadata: VMMetadata(
        functionExit: NodeId(3),
        symbolMap: SymbolTable(),
        sourceLocation: "tests/unit/test_cfg_branching.nim"
      )
    )

    let trs = model.semantic.transitions
    check trs.len == 5

    check trs[0].source == NodeId(0)
    check trs[0].target == NodeId(1)
    check trs[0].guard == nil

    check trs[1].source == NodeId(1)
    check trs[1].target == NodeId(2)
    check trs[1].guard != nil
    check trs[1].guard.kind == irBinOp
    check trs[1].guard.binOp == boLt

    check trs[2].source == NodeId(1)
    check trs[2].target == NodeId(3)
    check trs[2].guard != nil
    check trs[2].guard.binOp == boGe

    check trs[3].source == NodeId(2)
    check trs[3].target == NodeId(1)
    check trs[3].guard == nil
    check trs[3].update.assignments.len == 2

    check trs[4].source == NodeId(2)
    check trs[4].target == NodeId(4)
    check trs[4].guard == nil

  test "branching transitions from Condition node satisfy conformsToBranchLaw":
    var sem = VMSemantic()
    sem.initState("x", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initExprs.add(irLit(0))
    let xVar = irVar("x", bv64)

    sem.initTransition(NodeId(1), NodeId(2), irLt(xVar, irLit(5)), ParallelUpdate())
    sem.initTransition(NodeId(1), NodeId(3), irGe(xVar, irLit(5)), ParallelUpdate())

    let b = newTransitionFormulaBuilder(["x"])
    var fresh = 0
    let f1 = buildTransitionFormula(b, sem.transitions[0], fresh)
    let f2 = buildTransitionFormula(b, sem.transitions[1], fresh)

    check f1.postArgs.len == b.stateNames.len
    check f2.postArgs.len == b.stateNames.len
    check f1.guardSmt != f2.guardSmt

    check conformsToBranchLaw(f1, b.stateNames)
    check conformsToBranchLaw(f2, b.stateNames)

    let contract = makeSemanticContract()
    check contract.laws.anyIt(it.law == tlBranch)

  test "break edge routes to exit node with correct guard and frame semantics":
    var sem = VMSemantic()
    sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initState("sum", bv64, SymbolOrigin(kind: sokLoopState))
    sem.initExprs.add(irLit(0))
    sem.initExprs.add(irLit(0))
    let iVar = irVar("i", bv64)

    sem.initTransition(NodeId(2), NodeId(3), irGe(iVar, irLit(10)), ParallelUpdate())

    let b = newTransitionFormulaBuilder(["i", "sum"])
    var fresh = 0
    let tr = sem.transitions[0]
    let f = buildTransitionFormula(b, tr, fresh)

    check tr.guard != nil
    check tr.guard.binOp == boGe
    check tr.guard.binLhs.kind == irVar
    check tr.guard.binLhs.varName == "i"
    check tr.target == NodeId(3)

    check f.postArgs[0].nextSmt == "i"
    check f.postArgs[1].nextSmt == "sum"
    check conformsToBranchLaw(f, b.stateNames)

  test "continue edge routes to latch node with parallel update semantics":
    var sem = VMSemantic()
    sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initState("sum", bv64, SymbolOrigin(kind: sokLoopState))
    sem.initExprs.add(irLit(0))
    sem.initExprs.add(irLit(0))
    let iVar = irVar("i", bv64)
    let sumVar = irVar("sum", bv64)

    var upd = ParallelUpdate()
    upd.addAssignment("i", irAdd(iVar, irLit(1)))
    upd.addAssignment("sum", irAdd(sumVar, iVar))
    sem.initTransition(NodeId(2), NodeId(1), nil, upd)

    let b = newTransitionFormulaBuilder(["i", "sum"])
    var fresh = 0
    let tr = sem.transitions[0]
    let f = buildTransitionFormula(b, tr, fresh)

    check tr.target == NodeId(1)
    check f.postArgs[0].nextSmt == "(bvadd i #x0000000000000001)"
    check f.postArgs[1].nextSmt == "(bvadd sum i)"
    check conformsToBranchLaw(f, b.stateNames)

  test "return edge routes to function exit node with guard":
    var sem = VMSemantic()
    sem.initState("x", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initState("result", bv64, SymbolOrigin(kind: sokLoopState))
    sem.initExprs.add(irLit(0))
    sem.initExprs.add(irLit(0))
    let xVar = irVar("x", bv64)

    sem.initTransition(NodeId(2), NodeId(4), irGt(xVar, irLit(0)), ParallelUpdate())

    let b = newTransitionFormulaBuilder(["x", "result"])
    var fresh = 0
    let tr = sem.transitions[0]
    let f = buildTransitionFormula(b, tr, fresh)

    check tr.guard != nil
    check tr.guard.binOp == boGt
    check tr.target == NodeId(4)
    check f.postArgs[0].nextSmt == "x"
    check f.postArgs[1].nextSmt == "result"
    check conformsToBranchLaw(f, b.stateNames)

  test "loop exit transition (condition false) preserves all state via frame":
    var sem = VMSemantic()
    sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initState("sum", bv64, SymbolOrigin(kind: sokLoopState))
    sem.initExprs.add(irLit(0))
    sem.initExprs.add(irLit(0))
    let iVar = irVar("i", bv64)

    sem.initTransition(NodeId(1), NodeId(3), irGe(iVar, irLit(10)), ParallelUpdate())

    let b = newTransitionFormulaBuilder(["i", "sum"])
    var fresh = 0
    let tr = sem.transitions[0]
    let f = buildTransitionFormula(b, tr, fresh)

    check tr.guard != nil
    check tr.guard.binOp == boGe
    check f.postArgs[0].nextSmt == "i"
    check f.postArgs[1].nextSmt == "sum"
    check conformsToBranchLaw(f, b.stateNames)

  test "conformsToBranchLaw fails when postArgs length mismatches stateNames":
    var sem = VMSemantic()
    sem.initState("x", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initExprs.add(irLit(0))
    let xVar = irVar("x", bv64)

    sem.initTransition(NodeId(1), NodeId(2), irLt(xVar, irLit(5)), ParallelUpdate())

    let b = newTransitionFormulaBuilder(["x"])
    var fresh = 0
    let f = buildTransitionFormula(b, sem.transitions[0], fresh)

    check conformsToBranchLaw(f, b.stateNames)

    let badStateNames = @["x", "y"]
    check not conformsToBranchLaw(f, badStateNames)

  test "branching model with break and continue edges both conform to branch law":
    var sem = buildWhileLoopModel()
    let iVar = irVar("i", bv64)
    let sumVar = irVar("sum", bv64)

    sem.initTransition(NodeId(0), NodeId(1), nil, ParallelUpdate())
    sem.initTransition(NodeId(1), NodeId(2), irLt(iVar, irLit(10)), ParallelUpdate())
    sem.initTransition(NodeId(1), NodeId(3), irGe(iVar, irLit(10)), ParallelUpdate())

    var continueUpd = ParallelUpdate()
    continueUpd.addAssignment("i", irAdd(iVar, irLit(1)))
    continueUpd.addAssignment("sum", irAdd(sumVar, iVar))
    sem.initTransition(NodeId(2), NodeId(1), nil, continueUpd)

    sem.initTransition(NodeId(2), NodeId(4), nil, ParallelUpdate())

    let b = newTransitionFormulaBuilder(["i", "sum"])
    var fresh = 0

    let fCondToBody = buildTransitionFormula(b, sem.transitions[1], fresh)
    let fCondToExit = buildTransitionFormula(b, sem.transitions[2], fresh)
    let fBodyToLatch = buildTransitionFormula(b, sem.transitions[3], fresh)
    let fBodyToBreak = buildTransitionFormula(b, sem.transitions[4], fresh)

    check conformsToBranchLaw(fCondToBody, b.stateNames)
    check conformsToBranchLaw(fCondToExit, b.stateNames)
    check conformsToBranchLaw(fBodyToLatch, b.stateNames)
    check conformsToBranchLaw(fBodyToBreak, b.stateNames)

    check fCondToBody.guardSmt != fCondToExit.guardSmt
    check fBodyToLatch.guardSmt == "true"
    check fBodyToBreak.guardSmt == "true"