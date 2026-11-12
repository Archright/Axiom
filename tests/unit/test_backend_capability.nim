import std/[unittest, options, tables]
import core/trusted/backend_capability
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types

let bv64 = irTypeBitVec64()

proc makeModel(states: seq[StateVar]; loopFacts: Option[LoopFacts]): VerificationModel =
  var sem = VMSemantic()
  for st in states: sem.states.add(st)
  sem.loopFacts = loopFacts
  sem.initObligation(irLit(1), okUserContract, SymbolOrigin(kind: sokImplicit))
  sem.logicalDomain = ldBitVec
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: SymbolTable(), sourceLocation: ""))

suite "Backend capability — sound-representation gate (P2)":
  test "bounded bit-vec loop → both CHC and BMC encode":
    let model = makeModel(
      @[StateVar(name: "i", irType: bv64, origin: SymbolOrigin(kind: sokLoopIndex))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    check canEncode(model, bkChc)
    check canEncode(model, bkBmc)

  test "seq[int] loop → CHC encodes (Array), BMC encodes (bounded-loop + Array)":
    let arr = irTypeList(bv64)
    let model = makeModel(
      @[StateVar(name: "xs", irType: arr, origin: SymbolOrigin(kind: sokLoopState))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    check canEncode(model, bkChc)
    check canEncode(model, bkBmc)

  test "string sort → neither backend can represent (I2 territory)":
    let model = makeModel(
      @[StateVar(name: "s", irType: irTypeString(), origin: SymbolOrigin(kind: sokLoopState))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    check not canEncode(model, bkChc)
    check not canEncode(model, bkBmc)

  test "transition-system control → CHC encodes, BMC rejects (needs bounded-loop)":
    let model = makeModel(
      @[StateVar(name: "i", irType: bv64, origin: SymbolOrigin(kind: sokLoopIndex))],
      some(LoopFacts(kind: lfkUnbounded, counterName: "i"))
    )
    check canEncode(model, bkChc)
    check not canEncode(model, bkBmc)

  test "invariant contract → CHC encodes, BMC cannot (post-only)":
    var sem = VMSemantic()
    sem.states.add(StateVar(name: "i", irType: bv64, origin: SymbolOrigin(kind: sokLoopIndex)))
    sem.loopFacts = some(LoopFacts(kind: lfkBounded, counterName: "i"))
    sem.initObligation(irEq(irVar("i", bv64), irLit(0)), okImplicitSafety, SymbolOrigin(kind: sokImplicit))
    let vm = VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: SymbolTable()))
    check canEncode(vm, bkChc)
    check not canEncode(vm, bkBmc)

  test "pure — identical input gives identical output (determinism)":
    let model = makeModel(
      @[StateVar(name: "i", irType: bv64, origin: SymbolOrigin(kind: sokLoopIndex))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    check canEncode(model, bkChc) == canEncode(model, bkChc)
    check capabilitiesOf(bkChc) == capabilitiesOf(bkChc)

  test "isRunnable — CHC is runnable, BMC is not (no executor wired)":
    check isRunnable(bkChc) == true
    check isRunnable(bkBmc) == false

  test "capabilitiesOf.availableToRun — CHC true, BMC false":
    check capabilitiesOf(bkChc).availableToRun == true
    check capabilitiesOf(bkBmc).availableToRun == false

  test "isRunnable deterministic — pure, no side effects":
    check isRunnable(bkChc) == isRunnable(bkChc)
    check isRunnable(bkBmc) == isRunnable(bkBmc)

  test "canEncode semantics unchanged — representability ≠ runnability":
    ## A bounded bit-vec loop is representable by BMC (canEncode == true)
    ## but BMC is not runnable today (no executor wired). This locks the
    ## separation: capability (sound encoding) and execution-availability
    ## are independent dimensions.
    let model = makeModel(
      @[StateVar(name: "i", irType: bv64, origin: SymbolOrigin(kind: sokLoopIndex))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    check canEncode(model, bkBmc) == true
    check isRunnable(bkBmc) == false