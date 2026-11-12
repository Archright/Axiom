import std/[unittest, options, strutils]
import core/trusted/backend_capability
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_ir_types
import core/trusted/symbol_table_types
import verification/batch_uap/ir_pipeline_runner

let bv64 = irTypeBitVec64()

proc makeModel(states: seq[StateVar]; loopFacts: Option[LoopFacts]): VerificationModel =
  var sem = VMSemantic()
  for st in states: sem.states.add(st)
  sem.loopFacts = loopFacts
  sem.initObligation(irLit(1), okUserContract, SymbolOrigin(kind: sokImplicit))
  sem.logicalDomain = ldBitVec
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: SymbolTable(), sourceLocation: ""))

suite "Backend admission decision":
  test "simply encodable+runnable bv scalar bounded loop → permitted, vbCanonicalChc":
    let model = makeModel(
      @[StateVar(name: "i", irType: bv64, origin: SymbolOrigin(kind: sokLoopIndex))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    let decision = admissionDecision(model, bpRequire)
    check decision.permitted == true
    check decision.backend == vbCanonicalChc
    check decision.reason.contains("runnable")

  test "not-encodable model (string) under bpRequire → not permitted, reason contains not, never BMC":
    let model = makeModel(
      @[StateVar(name: "s", irType: irTypeString(), origin: SymbolOrigin(kind: sokLoopState))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    let decision = admissionDecision(model, bpRequire)
    check decision.permitted == false
    check decision.reason.contains("not")
    check decision.reason.contains("not-admitted")
    check "BMC" notin decision.reason

  test "determinism: two calls same args → same result":
    let model = makeModel(
      @[StateVar(name: "i", irType: bv64, origin: SymbolOrigin(kind: sokLoopIndex))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    let d1 = admissionDecision(model, bpRequire)
    let d2 = admissionDecision(model, bpRequire)
    check d1.permitted == d2.permitted
    check d1.backend == d2.backend
    check d1.reason == d2.reason

  test "bpRequire default fail-closed — not-encodable obligation gets no implicit secondary":
    let model = makeModel(
      @[StateVar(name: "s", irType: irTypeString(), origin: SymbolOrigin(kind: sokLoopState))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    let decision = admissionDecision(model, bpRequire)
    check decision.permitted == false
    check decision.backend == vbCanonicalChc
    check decision.reason.contains("not-admitted")

  test "bpAllowFallback + encodable obligation → permitted via vbLegacy":
    let model = makeModel(
      @[StateVar(name: "i", irType: bv64, origin: SymbolOrigin(kind: sokLoopIndex))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    let decision = admissionDecision(model, bpAllowFallback)
    check decision.permitted == true
    check decision.backend == vbCanonicalChc

  test "bpAllowFallback + not-encodable obligation → not permitted":
    let model = makeModel(
      @[StateVar(name: "s", irType: irTypeString(), origin: SymbolOrigin(kind: sokLoopState))],
      some(LoopFacts(kind: lfkBounded, counterName: "i"))
    )
    let decision = admissionDecision(model, bpAllowFallback)
    check decision.permitted == false
    check "BMC" notin decision.reason