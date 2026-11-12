import std/[unittest, options, sequtils, strutils]
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/private/ir_loop_to_horn
import core/trusted/private/chc_build_result

let bv64 = irTypeBitVec64()

proc buildModelWithSymbolOrder(symbolOrder: seq[string]): VerificationModel =
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
  for name in symbolOrder:
    st.addSymbol(name, SymbolOrigin(kind: sokLet), bv64)
  VerificationModel(
    semantic: sem,
    metadata: VMMetadata(
      functionExit: NodeId(0),
      symbolMap: st,
      sourceLocation: "tests/unit/test_chc_emission_determinism.nim"
    )
  )

suite "CHC Emission Determinism":
  test "same model produces byte-identical CHC output":
    let vm = buildModelWithSymbolOrder(@["x", "y", "z"])
    let result1 = buildChcFromVerificationModel(vm, vm.metadata.symbolMap)
    let result2 = buildChcFromVerificationModel(vm, vm.metadata.symbolMap)
    check result1.kind == cbSuccess
    check result2.kind == cbSuccess
    check result1.program == result2.program

  test "different non-state symbol insertion order yields identical sorted declarations":
    let vm1 = buildModelWithSymbolOrder(@["z", "y", "x"])
    let vm2 = buildModelWithSymbolOrder(@["x", "y", "z"])
    let r1 = buildChcFromVerificationModel(vm1, vm1.metadata.symbolMap)
    let r2 = buildChcFromVerificationModel(vm2, vm2.metadata.symbolMap)
    check r1.kind == cbSuccess
    check r2.kind == cbSuccess
    check r1.program == r2.program

  test "different transition insertion order yields identical sorted transition rules":
    var sem1 = VMSemantic()
    sem1.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem1.initState("sum", bv64, SymbolOrigin(kind: sokLoopState))
    sem1.initExprs.add(irLit(0))
    sem1.initExprs.add(irLit(0))
    let iVar1 = irVar("i", bv64)
    let sumVar1 = irVar("sum", bv64)
    var update1 = ParallelUpdate()
    update1.addAssignment("sum", irAdd(sumVar1, iVar1))
    sem1.initTransition(NodeId(1), NodeId(2), irLt(iVar1, irLit(10)), update1)
    let iVar2 = irVar("i", bv64)
    let sumVar2 = irVar("sum", bv64)
    var update2 = ParallelUpdate()
    update2.addAssignment("sum", irAdd(sumVar2, iVar2))
    sem1.initTransition(NodeId(2), NodeId(3), irLt(iVar2, irLit(5)), update2)
    sem1.initObligation(irLe(sumVar1, irLit(100)), okImplicitSafety, SymbolOrigin(kind: sokImplicit))
    sem1.exitGuard = some(irLt(iVar1, irLit(10)))
    sem1.logicalDomain = ldBitVec
    var st1 = SymbolTable()
    st1.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
    st1.addSymbol("sum", SymbolOrigin(kind: sokLoopState), bv64)
    let vm1 = VerificationModel(
      semantic: sem1,
      metadata: VMMetadata(
        functionExit: NodeId(0),
        symbolMap: st1,
        sourceLocation: "tests/unit/test_chc_emission_determinism.nim"
      )
    )

    var sem2 = VMSemantic()
    sem2.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem2.initState("sum", bv64, SymbolOrigin(kind: sokLoopState))
    sem2.initExprs.add(irLit(0))
    sem2.initExprs.add(irLit(0))
    let iVar3 = irVar("i", bv64)
    let sumVar3 = irVar("sum", bv64)
    var update3 = ParallelUpdate()
    update3.addAssignment("sum", irAdd(sumVar3, iVar3))
    sem2.initTransition(NodeId(2), NodeId(3), irLt(iVar3, irLit(5)), update3)
    let iVar4 = irVar("i", bv64)
    let sumVar4 = irVar("sum", bv64)
    var update4 = ParallelUpdate()
    update4.addAssignment("sum", irAdd(sumVar4, iVar4))
    sem2.initTransition(NodeId(1), NodeId(2), irLt(iVar4, irLit(10)), update4)
    sem2.initObligation(irLe(sumVar3, irLit(100)), okImplicitSafety, SymbolOrigin(kind: sokImplicit))
    sem2.exitGuard = some(irLt(iVar3, irLit(10)))
    sem2.logicalDomain = ldBitVec
    var st2 = SymbolTable()
    st2.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
    st2.addSymbol("sum", SymbolOrigin(kind: sokLoopState), bv64)
    let vm2 = VerificationModel(
      semantic: sem2,
      metadata: VMMetadata(
        functionExit: NodeId(0),
        symbolMap: st2,
        sourceLocation: "tests/unit/test_chc_emission_determinism.nim"
      )
    )

    let r1 = buildChcFromVerificationModel(vm1, vm1.metadata.symbolMap)
    let r2 = buildChcFromVerificationModel(vm2, vm2.metadata.symbolMap)
    check r1.kind == cbSuccess
    check r2.kind == cbSuccess
    check r1.program == r2.program