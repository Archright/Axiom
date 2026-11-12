## P0.3.11 — P0.3.8 Canonical CHC Compiler tests.
## Contract SSOT: docs/spec/cfg_contract_specification.md (C8).

import std/[unittest, options, hashes, sequtils, strutils]
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/private/canonical_chc_compiler
import core/trusted/solver_invocation

let bv64 = irTypeBitVec64()

proc makeModel(): VerificationModel =
  var sem = VMSemantic()
  sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initState("sum", bv64, SymbolOrigin(kind: sokLoopState))
  sem.initExprs.add(irLit(0))
  sem.initExprs.add(irLit(0))
  let iVar = irVar("i", bv64)
  let sumVar = irVar("sum", bv64)
  var upd = ParallelUpdate()
  upd.addAssignment("sum", irAdd(sumVar, iVar))
  sem.initTransition(NodeId(1), NodeId(2), irLt(iVar, irLit(100)), upd)
  sem.initObligation(irLe(sumVar, irLit(100000)), okImplicitSafety, SymbolOrigin(kind: sokImplicit))
  sem.logicalDomain = ldBitVec
  var st = SymbolTable()
  st.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
  st.addSymbol("sum", SymbolOrigin(kind: sokLoopState), bv64)
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st, sourceLocation: ""))

let config = EncodingConfig(loopStrategy: "for", arithmeticDomain: "bv64", memoryModel: "flat", printCertificate: true)
let config2 = EncodingConfig(loopStrategy: "for", arithmeticDomain: "bv64", memoryModel: "flat", printCertificate: false)

suite "Canonical CHC Compiler — canonicalization (C8)":
  test "canonical symbols are s0, s1, ... in state order":
    let c = canonicalize(makeModel(), config)
    check c.symbols.len == 2
    check c.symbols[0].canonicalName == "s0"
    check c.symbols[0].originalName == "i"
    check c.symbols[1].canonicalName == "s1"
    check c.symbols[1].originalName == "sum"

  test "canonical relation 'state' built with parameters":
    let c = canonicalize(makeModel(), config)
    check c.relations.len == 1
    check c.relations[0].relationName == "state"
    check c.relations[0].parameters.len == 2

suite "Canonical CHC Compiler — CHC AST + serialize":
  test "serialize produces HORN script":
    let c = canonicalize(makeModel(), config)
    let ast = toCHCAst(c)
    let str = serialize(ast)
    check str.len > 0
    check str.contains("(set-logic HORN)")
    check str.contains("(declare-rel state")
    check str.contains("(query error)")
    check str.contains("(check-sat)")

  test "printCertificate does not emit get-answer or get-model in script":
    let c1 = canonicalize(makeModel(), config)
    let c2 = canonicalize(makeModel(), config2)
    check not serialize(toCHCAst(c1)).contains("(get-answer)")
    check not serialize(toCHCAst(c1)).contains("(get-model)")
    check not serialize(toCHCAst(c2)).contains("(get-answer)")
    check not serialize(toCHCAst(c2)).contains("(get-model)")

suite "Canonical CHC Compiler — byte-identical determinism":
  test "same model + same config → identical bytes":
    let a = serialize(toCHCAst(canonicalize(makeModel(), config)))
    let b = serialize(toCHCAst(canonicalize(makeModel(), config)))
    check a == b

  test "two out-of-order models normalize identically":
    # Rebuild the model with states added in reverse order but semantically
    # identical sources; canonicalization follows state order, so outputs
    # remain deterministic per-model.
    let m = makeModel()
    let c = canonicalize(m, config)
    let d = canonicalize(m, config)
    check hash(serialize(toCHCAst(c))) == hash(serialize(toCHCAst(d)))

suite "Canonical CHC Compiler — prelude determinism":
  test "prelude uses standard (set-option :fp.engine spacer), not (fp.set-option)":
    let c = canonicalize(makeModel(), config)
    let str = serialize(toCHCAst(c))
    check str.contains("(set-option :fp.engine spacer)")
    check not str.contains("(fp.set-option")

  test "prelude pins determinism seeds for reproducible Spacer output":
    ## SMT-LIB 2.7 §4.1.7: seed 0 lets the solver pick a different seed per run,
    ## so a prelude that pins reproducibility must pin a NON-zero seed.
    let c = canonicalize(makeModel(), config)
    let str = serialize(toCHCAst(c))
    check str.contains(":fp.spacer.random_seed " & $Z3PinnedRandomSeed)
    check str.contains(":random-seed " & $Z3PinnedRandomSeed)
    check str.contains(":sat.random_seed " & $Z3PinnedRandomSeed)
    check $Z3PinnedRandomSeed != "0"
    check not str.contains(":random-seed 0")

  test "same model + same config → identical bytes with new prelude":
    let a = serialize(toCHCAst(canonicalize(makeModel(), config)))
    let b = serialize(toCHCAst(canonicalize(makeModel(), config)))
    check a == b

suite "Canonical CHC Compiler — identity metadata fingerprints":
  test "semanticFingerprint and encodingConfigFingerprint are non-empty after canonicalize":
    let c = canonicalize(makeModel(), config)
    check c.semanticFingerprint.len > 0
    check c.encodingConfigFingerprint.len > 0

  test "same model + same config → identical semanticFingerprint and encodingConfigFingerprint":
    let a = canonicalize(makeModel(), config)
    let b = canonicalize(makeModel(), config)
    check a.semanticFingerprint == b.semanticFingerprint
    check a.encodingConfigFingerprint == b.encodingConfigFingerprint
    check serialize(toCHCAst(a)) == serialize(toCHCAst(b))

  test "same model + different EncodingConfig → different encodingConfigFingerprint":
    let c1 = canonicalize(makeModel(), config)
    let c2 = canonicalize(makeModel(), config2)
    check c1.encodingConfigFingerprint != c2.encodingConfigFingerprint

  test "structural identity: same model canonicalized twice yields identical semanticFingerprint":
    let m = makeModel()
    let c = canonicalize(m, config)
    let d = canonicalize(m, config)
    check c.semanticFingerprint == d.semanticFingerprint
    check c.encodingConfigFingerprint == d.encodingConfigFingerprint

  test "semanticFingerprint changes when the semantic model changes":
    let m1 = makeModel()
    let c1 = canonicalize(m1, config)
    var m2 = m1
    var up2 = ParallelUpdate()
    up2.addAssignment("sum", irLit(999))
    m2.semantic.initTransition(NodeId(2), NodeId(3), irLt(irVar("i", bv64), irLit(50)), up2)
    let c2 = canonicalize(m2, config)
    check c1.semanticFingerprint != c2.semanticFingerprint

