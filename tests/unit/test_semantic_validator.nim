## P0.3.11 — P0.3.2a Semantic Validator tests.
## Contract SSOT: docs/spec/cfg_contract_specification.md (C2, C7).

import std/[unittest, options, sequtils, strutils]
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/private/semantic_validator

let bv64 = irTypeBitVec64()

proc makeModel(states: openArray[string]): VerificationModel =
  var sem = VMSemantic()
  var st = SymbolTable()
  for i, s in states:
    sem.initState(s, bv64, SymbolOrigin(kind: sokLoopState))
    sem.initExprs.add(irLit(0))
    st.addSymbol(s, SymbolOrigin(kind: sokLoopState), bv64)
  VerificationModel(
    semantic: sem,
    metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st, sourceLocation: "")
  )

suite "Semantic Validator — valid model passes":
  test "empty model is valid":
    let vm = makeModel([])
    let r = validateSemantic(vm)
    check r.valid == true
    check r.errors.len == 0

  test "i + sum model valid":
    let vm = makeModel(["i", "sum"])
    let r = validateSemantic(vm)
    check r.valid == true

suite "Semantic Validator — Layer 1 symbol resolution":
  test "undefined loop state symbol in init fails":
    var sem = VMSemantic()
    sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initExprs.add(irAdd(irVar("missing", bv64), irLit(1)))  # 'missing' not declared
    var st = SymbolTable()
    st.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
    let vm = VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st, sourceLocation: ""))
    let r = validateSemantic(vm)
    check r.valid == false
    check r.errors.anyIt(it.contains("missing"))

suite "Semantic Validator — Layer 2 scope":
  test "duplicate state name fails":
    var sem = VMSemantic()
    sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initState("i", bv64, SymbolOrigin(kind: sokLoopState))
    let st = SymbolTable()
    let vm = VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st, sourceLocation: ""))
    let r = validateSemantic(vm)
    check r.valid == false
    check r.errors.anyIt(it.contains("duplicate symbol")) == true

suite "Semantic Validator — Layer 5 assignment":
  test "assignment to non-state symbol fails":
    var sem = VMSemantic()
    sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initExprs.add(irLit(0))
    var update = ParallelUpdate()
    update.addAssignment("ghost", irLit(1))  # not a state var
    sem.initTransition(NodeId(1), NodeId(2), irLt(irVar("i", bv64), irLit(5)), update)
    let vm = VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: SymbolTable(), sourceLocation: ""))
    let r = validateSemantic(vm)
    check r.valid == false
    check r.errors.anyIt(it.contains("ghost"))

