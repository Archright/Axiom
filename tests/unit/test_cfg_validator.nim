## P0.3.11 — P0.3.2b CFG Validator tests.
## Contract SSOT: docs/spec/cfg_contract_specification.md (C3, C4).

import std/[unittest, options, sequtils, strutils]
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/private/cfg_validator

let bv64 = irTypeBitVec64()

proc makeCFG(): FunctionCFG =
  # B0: entry → B1 (block) → B2 (condition) → B3 (merge); merge → exit
  FunctionCFG(
    entry: NodeId(0),
    normalExit: NodeId(4),
    returnExits: @[NodeId(4)],
    nodes: @[
      CFGNode(id: NodeId(0), kind: cnkEntry, successors: @[NodeId(1)], predecessors: @[]),
      CFGNode(id: NodeId(1), kind: cnkBlock, successors: @[NodeId(2)], predecessors: @[NodeId(0)]),
      CFGNode(id: NodeId(2), kind: cnkCondition, successors: @[NodeId(3), NodeId(4)], predecessors: @[NodeId(1)]),
      CFGNode(id: NodeId(3), kind: cnkMerge, successors: @[NodeId(4)], predecessors: @[NodeId(2)]),
      CFGNode(id: NodeId(4), kind: cnkExit, successors: @[], predecessors: @[NodeId(2), NodeId(3)])
    ]
  )

proc makeModel(): VerificationModel =
  var sem = VMSemantic()
  sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initExprs.add(irLit(0))
  let iVar = irVar("i", bv64)
  var upd = ParallelUpdate()
  upd.addAssignment("i", irAdd(iVar, irLit(1)))
  sem.initTransition(NodeId(2), NodeId(3), irLt(iVar, irLit(10)), upd)
  var st = SymbolTable()
  st.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(4), symbolMap: st, sourceLocation: ""))

suite "CFG Validator — valid CFG passes":
  test "valid cfg and model":
    let r = validateCFG(makeCFG(), makeModel())
    check r.valid == true
    check r.errors.len == 0

suite "CFG Validator — reachability (1)":
  test "orphan node is unreachable":
    var cfg = makeCFG()
    cfg.nodes.add(CFGNode(id: NodeId(9), kind: cnkBlock, successors: @[], predecessors: @[]))
    let r = validateCFG(cfg, makeModel())
    check r.valid == false
    check r.errors.anyIt(it.contains("unreachable"))

suite "CFG Validator — terminator correctness (2)":
  test "condition node with wrong successor count":
    var cfg = makeCFG()
    cfg.nodes[2].successors = @[NodeId(3)]   # condition should have 2
    let r = validateCFG(cfg, makeModel())
    check r.valid == false
    check r.errors.anyIt(it.contains("successor count"))

suite "CFG Validator — edge validity (3)":
  test "transition endpoint not in cfg":
    let cfg = makeCFG()
    var model = makeModel()
    var upd = ParallelUpdate()
    upd.addAssignment("i", irLit(0))
    model.semantic.transitions[0] = Transition(source: NodeId(99), target: NodeId(3), guard: irLt(irVar("i", bv64), irLit(1)), update: upd)
    let r = validateCFG(cfg, model)
    check r.valid == false
    check r.errors.anyIt(it.contains("unknown transition endpoint"))

suite "CFG Validator — frame correctness (6)":
  test "assignment to non-state symbol":
    let cfg = makeCFG()
    var model = makeModel()
    model.semantic.transitions[0].update.assignments = @[Assignment(symbol: "nope", expr: irLit(1))]
    let r = validateCFG(cfg, model)
    check r.valid == false
    check r.errors.anyIt(it.contains("non-state"))

