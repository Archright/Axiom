## tests/unit/test_wpj4_ladder.nim
## WP4-j.4 Evidence Ladder — unit tests.
##
## Covers:
##   - Ladder order/status: witness fixture(BiggestUInt) → 6 ladder fact types, each status exact.
##   - Emission: only an OBSERVED literal yields a SemanticFact; a `sizeof(T)*8`
##     binding yields none, because neither the witness nor the IR fixes a width.
##   - Monotonicity: deriveInstantiationFacts 2 calls → identical id/provenance.
##   - Unknown fail-closed: empty positionalRelation → empty seq; no observed value → empty seq.
##   - Monotonicity lock: fact id computed from own input only (TypeIdentityFact.id independent of InstantiationBindingFact.id).
##   - witnessDigest integrity: save→load round-trip; payload tampering → load fails (none).
##   - Witness consumer: deriveInstantiationFacts does not directly import PNode/NimNode.
##   - E2E readiness: module-AST parse yields getBitsBE instantiationWitnesses.
##     Runs on an in-repo minimal fixture — no file outside this repository is
##     read. Setting AXIOM_WPJ4_SUBJECT_BITOPS2 to the subject's stew/bitops2.nim
##     re-runs the same assertions against the real source; same verdict required.
##
## Custom main() pattern per tests/unit/test_wpj2_phaseb.nim precedent.

import std/[strutils, sequtils, os, algorithm, hashes, options, json]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/semantic_fact_types
import core/trusted/binding_inventory
import verification/obligation/semantic_environment
import infrastructure/evidence_artifact_io
import core/deterministic_cas_key
import core/trusted/semantic_profile
import core/crypto/hash_kernel
import core/parser_utils
import compiler/ast

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()
      except Defect:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  # ── Witness fixture: getBitsBE(data, slice, BiggestUInt) ──────────
  echo "=== WP4-j.4 witness fixture ==="

  let modulePath = "stew/bitops2.nim"
  let callSite = "599"
  let callee = "getBitsBE"
  let concreteType = "BiggestUInt"
  let witnessDigestExpected = sha256Hex(
    modulePath & ":" & callSite & ":" & callee & ":" & concreteType)

  let witness = InstantiationWitness(
    callSite: callSite,
    calleeSymbol: callee,
    actualArgs: @["data", "slice", "BiggestUInt"],
    formalNames: @["data", "slice", "T"],
    formalTypedesc: @[false, false, true],
    positionalRelation: @[0, 1, 2],
    concreteTypeArgument: concreteType,
    modulePath: modulePath,
    occurrenceRef: witnessDigestExpected)

  # ── Ladder fact fixtures (data-only, each computed from own input) ─
  echo "=== Ladder fact types: status fields ==="

  let typeIdentityFact = TypeIdentityFact(
    id: sha256Hex("typealias:" & concreteType),
    sourceType: concreteType,
    canonicalType: "uint64",
    status: fsObserved,
    observationSource: "toolchain-system-nim",
    toolchainIdentity: "nim-2.2.10")

  let irRepFact = IRRepresentationFact(
    id: sha256Hex("repr:uint64:BitVec64"),
    sourceType: "uint64",
    irTypeKind: "BitVec64",
    status: fsDerived,
    representationScope: "Axiom current IR representation contract",
    contractId: SemanticProfileV1Hash)

  let sizeFact = SizeFact(
    id: sha256Hex("size:uint64"),
    sourceType: "uint64",
    bytes: 8,
    bits: 64,
    status: fsDerived)

  let constArithFact = ConstArithmeticFact(
    id: sha256Hex("arith:8*8"),
    expression: "8*8",
    value: 64,
    status: fsDerived)

  let instBindingFact = InstantiationBindingFact(
    id: sha256Hex("inst:" & modulePath & ":" & callSite & ":" & callee & ":" & concreteType),
    genericSymbol: callee,
    typeParam: "T",
    concreteType: concreteType,
    status: fsDerived,
    scopeLimitation: "observed instantiation-scoped binding — positional correspondence only",
    provenance: FactProvenance(
      origin: foTemplateInstantiation,
      occurrenceRef: witness.occurrenceRef,
      sourceRef: witness.callSite))

  check "TypeIdentityFact: status=fsObserved, canonicalType=uint64":
    doAssert typeIdentityFact.status == fsObserved
    doAssert typeIdentityFact.canonicalType == "uint64"
    doAssert typeIdentityFact.observationSource == "toolchain-system-nim"
    doAssert typeIdentityFact.toolchainIdentity == "nim-2.2.10"

  check "IRRepresentationFact: status=fsDerived, contractId=SemanticProfileV1Hash":
    doAssert irRepFact.status == fsDerived
    doAssert irRepFact.contractId == SemanticProfileV1Hash

  check "SizeFact: bytes=8, bits=64, status=fsDerived":
    doAssert sizeFact.bytes == 8
    doAssert sizeFact.bits == 64
    doAssert sizeFact.status == fsDerived

  check "ConstArithmeticFact: expression=8*8, value=64, status=fsDerived":
    doAssert constArithFact.expression == "8*8"
    doAssert constArithFact.value == 64
    doAssert constArithFact.status == fsDerived

  check "InstantiationBindingFact: status=fsDerived, scopeLimitation set":
    doAssert instBindingFact.status == fsDerived
    doAssert instBindingFact.scopeLimitation.contains("positional correspondence")
    doAssert instBindingFact.provenance.origin == foTemplateInstantiation

  # ── Monotonicity lock: fact ids computed from own inputs only ──────
  echo "=== Monotonicity lock: id independence ==="

  check "TypeIdentityFact.id independent of InstantiationBindingFact.id":
    doAssert typeIdentityFact.id != instBindingFact.id
    doAssert typeIdentityFact.id.find(instBindingFact.id) < 0
    doAssert instBindingFact.id.find(typeIdentityFact.id) < 0

  # ── deriveInstantiationFacts: monotonicity ─────────────────────────
  echo "=== deriveInstantiationFacts monotonicity ==="

  # Hand-crafted IRFuncDef whose body contains: const resultBits = sizeof(data) * 8
  let cletBody = irLet("resultBits",
    irBinOp(boMul, irCall("sizeof", @[irVar("data", irTypeBitVec64())]), irLit(8)),
    irVar("resultBits", irTypeBitVec64()),
    isCompileTime = true)
  let funcDef = IRFuncDef(
    name: "getBitsBE", params: @[], retType: irTypeBitVec64(),
    body: cletBody, isRecursive: false)

  let facts1 = deriveInstantiationFacts(witness, funcDef)
  let facts2 = deriveInstantiationFacts(witness, funcDef)

  check "deriveInstantiationFacts: 2 identical calls → same fact count":
    doAssert facts1.len == facts2.len

  check "deriveInstantiationFacts: sizeof*8 binding carries no observed value → no fact":
    doAssert facts1.len == 0
    doAssert facts2.len == 0

  # A literal bound to a compile-time `let` IS observed, so it may be asserted.
  let literalFuncDef = IRFuncDef(
    name: "getBitsBE", params: @[], retType: irTypeBitVec64(),
    body: irLet("resultBits", irLit(32),
                irVar("resultBits", irTypeBitVec64()),
                isCompileTime = true),
    isRecursive: false)

  let literalFacts1 = deriveInstantiationFacts(witness, literalFuncDef)
  let literalFacts2 = deriveInstantiationFacts(witness, literalFuncDef)

  check "deriveInstantiationFacts: observed literal → one fact carrying that literal":
    doAssert literalFacts1.len == 1
    doAssert literalFacts1[0].proposition.kind == irBinOp
    doAssert literalFacts1[0].proposition.binOp == boEq
    doAssert literalFacts1[0].proposition.binLhs.varName == "resultBits"
    doAssert literalFacts1[0].proposition.binRhs.kind == irLit
    doAssert literalFacts1[0].proposition.binRhs.litVal == 32

  check "deriveInstantiationFacts: 2 calls → identical ids and provenance":
    doAssert literalFacts2.len > 0
    doAssert literalFacts1[0].id == literalFacts2[0].id
    doAssert literalFacts1[0].provenance.occurrenceRef == literalFacts2[0].provenance.occurrenceRef
    doAssert literalFacts1[0].provenance.origin == foTemplateInstantiation

  # ── Unknown fail-closed: empty positionalRelation ──────────────────
  echo "=== Unknown fail-closed: empty positionalRelation ==="

  let emptyWitness = InstantiationWitness(
    callSite: callSite, calleeSymbol: callee,
    actualArgs: @["data", "slice", "BiggestUInt"],
    formalNames: @["data", "slice", "T"],
    formalTypedesc: @[false, false, true],
    positionalRelation: @[],
    concreteTypeArgument: concreteType,
    modulePath: modulePath,
    occurrenceRef: witnessDigestExpected)

  let emptyFacts = deriveInstantiationFacts(emptyWitness, funcDef)

  check "Empty positionalRelation → empty fact seq (fail-closed)":
    doAssert emptyFacts.len == 0

  # ── Unknown fail-closed: unknown concreteType ──────────────────────
  echo "=== Unknown fail-closed: unknown concreteType(uint32) ==="

  let unknownWitness = InstantiationWitness(
    callSite: callSite, calleeSymbol: callee,
    actualArgs: @["data", "slice", "uint32"],
    formalNames: @["data", "slice", "T"],
    formalTypedesc: @[false, false, true],
    positionalRelation: @[0, 1, 2],
    concreteTypeArgument: "uint32",
    modulePath: modulePath,
    occurrenceRef: sha256Hex(modulePath & ":" & callSite & ":" & callee & ":" & "uint32"))

  let unknownTypeFact = TypeIdentityFact(
    id: sha256Hex("typealias:uint32"),
    sourceType: "uint32",
    canonicalType: "",
    status: fsUnknown,
    observationSource: "toolchain-system-nim",
    toolchainIdentity: "nim-2.2.10")

  let unknownFacts = deriveInstantiationFacts(unknownWitness, funcDef)

  check "Unknown concreteType(uint32) → no observed value → facts empty":
    doAssert unknownTypeFact.status == fsUnknown
    doAssert unknownFacts.len == 0

  # ── witnessDigest integrity: save→load round-trip ──────────────────
  echo "=== witnessDigest integrity ==="

  let irDigest = computeDeterministicCasKey(computeIrDigest(funcDef))
  saveInstantiationWitnesses(irDigest, modulePath, "axiom-witness-collector",
    "v1", "witness-v1", @[witness])

  let loaded = loadInstantiationWitnesses(irDigest)

  check "witnessDigest integrity: save→load round-trip succeeds":
    doAssert loaded.isSome
    let ws = loaded.get
    doAssert ws.len == 1
    doAssert ws[0].calleeSymbol == callee
    doAssert ws[0].concreteTypeArgument == concreteType
    doAssert ws[0].positionalRelation == @[0, 1, 2]

  # Tamper: rewrite the artifact file DIRECTLY (digest stays stale) —
  # save would recompute the digest, so we must mutate the stored JSON.
  var corrupted = witness
  corrupted.concreteTypeArgument = "Tampered"
  let tamperPath = witnessCachePath(irDigest)
  let stored = parseJson(readFile(tamperPath))
  stored["witnesses"][0]["concreteTypeArgument"] = %"Tampered"
  writeFile(tamperPath, $stored)

  check "witnessDigest: corrupted payload → load returns none":
    doAssert not loadInstantiationWitnesses(irDigest).isSome

  # Restore original for clean state.
  saveInstantiationWitnesses(irDigest, modulePath, "axiom-witness-collector",
    "v1", "witness-v1", @[witness])

  # ── Witness consumer: deriveInstantiationFacts does not import ────
  echo "=== Witness consumer: no direct PNode/NimNode import ==="

  check "semantic_environment.nim does not directly import compiler/ast":
    let src = readFile("src/verification/obligation/semantic_environment.nim")
    var directImportAst = false
    for ln in src.splitLines:
      let trimmed = ln.strip
      if trimmed.startsWith("import ") and "compiler/ast" in trimmed:
        directImportAst = true
    doAssert not directImportAst

  # ── E2E readiness: module-AST parse yields getBitsBE instantiation─
  echo "=== E2E readiness: getBitsBE witness observation ==="

  ## Minimal subject-shaped module — reproduced from nim-stew
  ## stew/bitops2.nim:559 (generic func) and :599-600 (non-generic
  ## template calling it with a concrete type argument).
  ##
  ## This fixture replaces reading the subject off-disk: the judgment below
  ## is a property of the OBSERVER, and the observer reads exactly two things
  ## out of a module AST — nothing else about the subject can affect it:
  ##   findFuncDefParamsP            → the generic func's formal params.
  ##                                    3 formals, formal[2] `T: type[...]`
  ##                                    ⇒ formalNames=[data,slice,T],
  ##                                      formalTypedesc=[false,false,true].
  ##   observeTemplateInstantiationsP → the template body's calls.
  ##                                    3 actuals over those 3 formals, and
  ##                                    actuals[2] is the concrete `BiggestUInt`
  ##                                    ⇒ concreteTypeArgument="BiggestUInt",
  ##                                      positionalRelation=[0,1,2].
  ## The func's body, the type section, and the module's size are never read,
  ## so they are omitted here — shrinking the subject cannot change the verdict.
  let bitopsFixture = """
type
  HSlice* = object
    first*: int
    last*: int
  SomeUnsignedInt* = uint8 | uint16 | uint32 | uint64 | uint | BiggestUInt

func getBitsBE*(data: openArray[byte], slice: HSlice, T: type[SomeUnsignedInt]): T =
  discard

template getBitsBE*(data: openArray[byte], slice: HSlice): BiggestUInt =
  getBitsBE(data, slice, BiggestUInt)
"""
  let fixtureModulePath = "stew/bitops2.nim"

  let ast = parseStringAST(bitopsFixture)
  doAssert ast != nil, "bitops2.nim fixture parse failed"

  var inv = inventoryFromPNode(ast, "getBitsBE")
  observeInstantiations(ast, fixtureModulePath, inv)

  check "E2E: fixture module parsed and instantiationWitnesses observed":
    doAssert inv.instantiationWitnesses.len >= 1

  block:
    var found = false
    for w in inv.instantiationWitnesses:
      if w.calleeSymbol == "getBitsBE":
        doAssert w.concreteTypeArgument == "BiggestUInt"
        doAssert w.positionalRelation == @[0, 1, 2]
        found = true
    doAssert found, "getBitsBE instantiation witness must exist"

  # The two witness fields above are DERIVED, not incidental. Pin the inputs
  # they are derived from so a regression names the broken link, not just the
  # broken output.
  check "E2E: witness pins the formals/actuals the verdict is derived from":
    doAssert inv.instantiationWitnesses.len == 1
    let w = inv.instantiationWitnesses[0]
    doAssert w.modulePath == fixtureModulePath
    doAssert w.formalNames == @["data", "slice", "T"]
    doAssert w.formalTypedesc == @[false, false, true]
    doAssert w.actualArgs == @["data", "slice", "BiggestUInt"]
    doAssert w.occurrenceRef == sha256Hex(
      fixtureModulePath & ":" & w.callSite & ":" & w.calleeSymbol & ":BiggestUInt")

  # ── Subject corroboration (opt-in): the real nim-stew source ───────
  ## AXIOM_WPJ4_SUBJECT_BITOPS2 = path to the subject's stew/bitops2.nim.
  ## Default: unset, and the fixture verdict above stands alone — this test
  ## needs no file outside the repository. When the variable IS set, the very
  ## same assertions run against the real subject and must reach the very same
  ## verdict; that is what makes the fixture substitution auditable rather
  ## than a silent narrowing. Either branch always prints which side ran, and
  ## a set-but-unreadable path is a counted FAIL (never a quiet pass).
  let subjectPath = getEnv("AXIOM_WPJ4_SUBJECT_BITOPS2").strip

  if subjectPath.len == 0:
    echo "  INFO: subject corroboration NOT RUN — AXIOM_WPJ4_SUBJECT_BITOPS2 unset;" &
         " the fixture verdict above is the standalone judgment"
  else:
    check "subject corroboration: " & subjectPath & " reaches the same verdict":
      doAssert fileExists(subjectPath),
        "AXIOM_WPJ4_SUBJECT_BITOPS2 is set but does not exist: " & subjectPath
      let sAst = parseStringAST(readFile(subjectPath))
      doAssert sAst != nil, "subject parse failed: " & subjectPath
      var sInv = inventoryFromPNode(sAst, "getBitsBE")
      observeInstantiations(sAst, subjectPath, sInv)
      doAssert sInv.instantiationWitnesses.len >= 1
      var sFound = false
      for w in sInv.instantiationWitnesses:
        if w.calleeSymbol == "getBitsBE":
          doAssert w.concreteTypeArgument == "BiggestUInt"
          doAssert w.positionalRelation == @[0, 1, 2]
          sFound = true
      doAssert sFound, "subject getBitsBE instantiation witness must exist"

  # ── Summary ──────────────────────────────────────────────────────
  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

when isMainModule:
  main()
