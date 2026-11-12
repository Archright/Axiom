## Unit tests for candidate_eligibility.nim — Phase F Step 5 acceptance.
##
## Oracle design (design-change-sensitive — update header when spec changes):
## Each test case is an oracle row: (RuntimeAxiomEntry, IRFuncDef) → EligibilityClass.
##
## Oracle columns verified per test:
## 1. Input value (RuntimeAxiomEntry + IRFuncDef)
## 2. Obligation generation result kind (ogrGenerated / ogrNoApplicable / ogrUnsupported / ogrIllFormed)
## 3. EligibilityClass (elProofCandidate / elNoObligation / elUnsupported / elMalformed)
## 4. VerifiedFragmentV1 membership (for Generated results)
## 5. Determinism (re-call produces identical classification)
## 6. Frontier selection gate (isFrontierSelectionEligible)
## 7. Promotion guard (noObligation/unsupported never promoted)
## 8. Census rule S (semantic universe: censusEligible / rejection token / proofCandidateCount)
##
## Failure mode: any mismatch → test FAIL. Design changes require updating
## this header and the expected values below.

import std/[unittest, strutils, options, sequtils]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_pragmas
import verification/obligation/canonical_obligation_generator
import verification/obligation/obligation_types
import verification/obligation/obligation_ir
import verification/obligation/candidate_eligibility
import verification/obligation/verified_fragment
import verification/cert_promotion

suite "Candidate Eligibility — Phase F Step 5":

  # -----------------------------------------------------------------------
  # Fixture helpers
  # -----------------------------------------------------------------------

  func makeEntry(name: string, bmcSkippable: bool = false,
                 isKernel: bool = true, irSerialized: string = ""): RuntimeAxiomEntry =
    RuntimeAxiomEntry(
      name: name,
      irSerialized: irSerialized,
      isKernel: isKernel,
      effectKind: Pure,
      bmcSkippable: bmcSkippable,
      expectedObligation: false
    )

  # -----------------------------------------------------------------------
  # 1. Four-class mapping
  # -----------------------------------------------------------------------

  test "safe_div (irDiv) → elProofCandidate (Generated + okSafetyDiv in fragment)":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("safe_div", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let entry = makeEntry("safe_div")
    let result = classifyCandidateEligibility(entry, funcDef)
    check result == elProofCandidate

  test "double (irMul, no targets) → elNoObligation":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irMul(x, y)
    let funcDef = irFuncDef("double", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let entry = makeEntry("double")
    let result = classifyCandidateEligibility(entry, funcDef)
    check result == elNoObligation

  test "recursive funcDef → elUnsupported (detectUnsupported → ogrUnsupported)":
    let x = irVar("x", irTypeBitVec64())
    let body = irRecCall(@[x])
    let funcDef = irFuncDef("recursive_func", @[("x", irTypeBitVec64())], irTypeBitVec64(), body, true)
    let entry = makeEntry("recursive_func")
    let result = classifyCandidateEligibility(entry, funcDef)
    check result == elUnsupported

  test "ill-formed funcDef (nil body) → elMalformed (ogrIllFormed)":
    let funcDef = IRFuncDef(
      name: "broken",
      params: @[],
      retType: irTypeBitVec64(),
      body: nil,
      isRecursive: false,
      preConditions: @[],
      postConditions: @[]
    )
    let entry = makeEntry("broken")
    let result = classifyCandidateEligibility(entry, funcDef)
    check result == elMalformed

  test "bmcSkippable=true entry → elUnsupported (admissibility INELIGIBLE branch)":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("bmc_string_div", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let entry = makeEntry("bmc_string_div", bmcSkippable=true)
    let result = classifyCandidateEligibility(entry, funcDef)
    check result == elUnsupported

  test "ADMISSIBLE + Generated + fragment → elProofCandidate":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("admissible_div", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let entry = makeEntry("admissible_div")
    let result = classifyCandidateEligibility(entry, funcDef)
    check result == elProofCandidate

  test "DEFER_TO_RUNTIME + Generated + fragment → elProofCandidate":
    # A for-loop with sound bound (structural, but loop bound resolved) → DEFER_TO_RUNTIME.
    # Combined with division → Generated + fragment → elProofCandidate.
    let i = irVar("i", irTypeBitVec64())
    let loopCond = irLt(i, irLit(10))
    let loopStep = irAdd(i, irLit(1))
    let loopBody = irDiv(i, irLit(1))
    let loopExpr = irLoop(lkFor, @["i"], @[irLit(0)], loopCond, loopStep, loopBody, @[], nil)
    let funcDef = IRFuncDef(
      name: "structuralDiv",
      params: @[],
      retType: irTypeBitVec64(),
      body: loopExpr,
      isRecursive: false,
      preConditions: @[],
      postConditions: @[]
    )
    let entry = makeEntry("structuralDiv")
    let result = classifyCandidateEligibility(entry, funcDef)
    check result == elProofCandidate

  # -----------------------------------------------------------------------
  # 2. Test C forward: elProofCandidate ⇒ inVerifiedFragmentV1
  # -----------------------------------------------------------------------

  test "C forward: every elProofCandidate fixture has inVerifiedFragmentV1 == true":
    # safe_div fixture (ADMISSIBLE + Generated + fragment)
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("safe_div_cfwd", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let entry = makeEntry("safe_div_cfwd")
    let genResult = generateCanonicalObligations(funcDef, defaultScopePolicy())
    check genResult.kind == ogrGenerated
    check inVerifiedFragmentV1(entry, funcDef, genResult) == true

    # structuralDiv fixture (DEFER_TO_RUNTIME + Generated + fragment)
    let i2 = irVar("i", irTypeBitVec64())
    let loopCond2 = irLt(i2, irLit(10))
    let loopStep2 = irAdd(i2, irLit(1))
    let loopBody2 = irDiv(i2, irLit(1))
    let loopExpr2 = irLoop(lkFor, @["i"], @[irLit(0)], loopCond2, loopStep2, loopBody2, @[], nil)
    let structuralFuncDef = IRFuncDef(
      name: "structuralDiv_cfwd",
      params: @[],
      retType: irTypeBitVec64(),
      body: loopExpr2,
      isRecursive: false,
      preConditions: @[],
      postConditions: @[]
    )
    let structuralEntry = makeEntry("structuralDiv_cfwd")
    let structuralGenResult = generateCanonicalObligations(structuralFuncDef, defaultScopePolicy())
    check structuralGenResult.kind == ogrGenerated
    check inVerifiedFragmentV1(structuralEntry, structuralFuncDef, structuralGenResult) == true

  # -----------------------------------------------------------------------
  # 3. Test C backward: fragment membership ⇏ proof
  # -----------------------------------------------------------------------

  test "C backward: Generated with non-fragment obligation kind → inVerifiedFragmentV1 == false":
    # Directly construct an ObligationGenerationResult with okInvariant
    # (not in VerifiedFragmentAllowlist) to exercise the backward path.
    # NOTE: extractObligationCandidates only produces the 5 fragment kinds
    # (okContractPre, okContractPost, okSafetyDiv, okSafetyIndex,
    #  okSafetyLoopBound), so we cannot make classifyCandidateEligibility
    #  produce this case directly. We test inVerifiedFragmentV1 at the IR
    #  level instead, which is the function that enforces the fragment boundary.
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("safe_div_cback", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let entry = makeEntry("safe_div_cback")

    # Build a Generated result with okInvariant (not in the allowlist)
    let obl = VerificationObligation(
      id: "test-inv-id",
      kind: okInvariant,
      subject: "x ≠ 0",
      assumptions: "",
      predicate: "x ≠ 0",
      proposition: irUnaryOp(uoNot, irBinOp(boEq, irVar("x", irTypeBitVec64()), IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0))),
      derivationRule: "obs:injected",
      provenance: "injected:non-fragment"
    )
    let nonFragmentResult = makeGenerated(makeLightNonEmpty(@[obl]))
    check inVerifiedFragmentV1(entry, funcDef, nonFragmentResult) == false

  test "C backward: INELIGIBLE (bmcSkippable) blocks inVerifiedFragmentV1 even with fragment obligations":
    # inVerifiedFragmentV1 is NOT sufficient — INELIGIBLE admissibility
    # prevents fragment membership, which in turn prevents elProofCandidate.
    # This is the contrapositive of the forward path: fragment membership
    # does not guarantee proof candidacy when static admissibility fails.
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("bmc_blocked_div", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let entry = makeEntry("bmc_blocked_div", bmcSkippable=true)

    # The funcDef generates okSafetyDiv obligations (in the allowlist),
    # but bmcSkippable makes assessAdmissibility return INELIGIBLE,
    # so inVerifiedFragmentV1 returns false.
    let genResult = generateCanonicalObligations(funcDef, defaultScopePolicy())
    check genResult.kind == ogrGenerated
    check inVerifiedFragmentV1(entry, funcDef, genResult) == false
    # And the classifier maps this to elUnsupported
    check classifyCandidateEligibility(entry, funcDef) == elUnsupported

  # -----------------------------------------------------------------------
  # 4. Determinism / no double-call correctness
  # -----------------------------------------------------------------------

  test "determinism: generateCanonicalObligations is idempotent":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("div_det", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let policy = defaultScopePolicy()

    let r1 = generateCanonicalObligations(funcDef, policy)
    let r2 = generateCanonicalObligations(funcDef, policy)

    check r1.kind == r2.kind
    if r1.kind == ogrGenerated and r2.kind == ogrGenerated:
      check r1.obligations.len == r2.obligations.len
      for i in 0 ..< r1.obligations.len:
        check r1.obligations.items[i].kind == r2.obligations.items[i].kind
        check r1.obligations.items[i].id == r2.obligations.items[i].id

  test "determinism: classifyCandidateEligibility is idempotent":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("classify_det", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let entry = makeEntry("classify_det")

    let c1 = classifyCandidateEligibility(entry, funcDef)
    let c2 = classifyCandidateEligibility(entry, funcDef)
    check c1 == c2

  # -----------------------------------------------------------------------
  # 5. Capability witness static/actual split
  # -----------------------------------------------------------------------

  test "normalizeMaxWorkers → elProofCandidate (static boundary)":
    # normalizeMaxWorkers has a postcondition (result >= 1),
    # making it a Generated + fragment candidate.
    # Static boundary: the classifier says it is a proof candidate.
    let result = irVar("result", irTypeBitVec64())
    let postCond = irGe(result, irLit(1))
    let funcDef = IRFuncDef(
      name: "normalizeMaxWorkers",
      params: @[IRFuncParam(name: "maxWorkers", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: irIf(irGt(irVar("maxWorkers", irTypeBitVec64()), irLit(0)),
                  irVar("maxWorkers", irTypeBitVec64()),
                  irLit(1)),
      isRecursive: false,
      preConditions: @[],
      postConditions: @[postCond]
    )
    let entry = makeEntry("normalizeMaxWorkers")
    let cls = classifyCandidateEligibility(entry, funcDef)
    check cls == elProofCandidate

    # NOTE: the ACTUAL proof boundary is established only by
    # CanonicalLeanEvidence at execution time (runtime genuine KAA),
    # NOT statically. The static classifier (this module) only
    # determines whether a candidate is *eligible* for proof attempt;
    # proof success is a runtime property of the Lean kernel acceptance
    # and Axiom validation pipeline.

  # -----------------------------------------------------------------------
  # 6. isFrontierSelectionEligible
  # -----------------------------------------------------------------------

  test "isFrontierSelectionEligible: proof-candidate name → true":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("frontier_div", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let serialized = serializeIRFuncDef(funcDef)
    let entry = RuntimeAxiomEntry(
      name: "frontier_div",
      irSerialized: serialized,
      isKernel: true,
      effectKind: Pure,
      bmcSkippable: false,
      expectedObligation: false
    )
    let savedLen = runtimeAxiomRegistry.len
    runtimeAxiomRegistry.add(entry)
    try:
      check isFrontierSelectionEligible("frontier_div") == true
      check isFrontierSelectionEligible("frontier_div*") == true
    finally:
      runtimeAxiomRegistry.setLen(savedLen)

  test "isFrontierSelectionEligible: noObligation name → false":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irMul(x, y)
    let funcDef = irFuncDef("frontier_mul", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let serialized = serializeIRFuncDef(funcDef)
    let entry = RuntimeAxiomEntry(
      name: "frontier_mul",
      irSerialized: serialized,
      isKernel: true,
      effectKind: Pure,
      bmcSkippable: false,
      expectedObligation: false
    )
    let savedLen = runtimeAxiomRegistry.len
    runtimeAxiomRegistry.add(entry)
    try:
      check isFrontierSelectionEligible("frontier_mul") == false
    finally:
      runtimeAxiomRegistry.setLen(savedLen)

  test "isFrontierSelectionEligible: unsupported/ill-formed name → false":
    # ill-formed: nil body → ogrIllFormed → elMalformed → not eligible
    let brokenFuncDef = IRFuncDef(
      name: "frontier_broken",
      params: @[],
      retType: irTypeBitVec64(),
      body: nil,
      isRecursive: false,
      preConditions: @[],
      postConditions: @[]
    )
    let serialized = serializeIRFuncDef(brokenFuncDef)
    let entry = RuntimeAxiomEntry(
      name: "frontier_broken",
      irSerialized: serialized,
      isKernel: true,
      effectKind: Pure,
      bmcSkippable: false,
      expectedObligation: false
    )
    let savedLen = runtimeAxiomRegistry.len
    runtimeAxiomRegistry.add(entry)
    try:
      check isFrontierSelectionEligible("frontier_broken") == false
    finally:
      runtimeAxiomRegistry.setLen(savedLen)

  # -----------------------------------------------------------------------
  # 7. Test D regression: noObligation/unsupported never promote
  # -----------------------------------------------------------------------

  test "D regression: elNoObligation is never elProofCandidate (promotion guard)":
    # A noObligation-classified candidate must not be targeted for proof.
    # The promotion guard in cert_promotion.nim treats certNoObligation
    # (orchestrationNoObligation) as non-failure, never promoted.
    # At the classification level: elNoObligation ≠ elProofCandidate.
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irMul(x, y)
    let funcDef = irFuncDef("noOblig_mul", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let entry = makeEntry("noOblig_mul")
    let cls = classifyCandidateEligibility(entry, funcDef)
    check cls == elNoObligation
    check cls != elProofCandidate

  test "D regression: elUnsupported is never elProofCandidate (promotion guard)":
    # An unsupported-classified candidate must not be targeted for proof.
    # The promotion guard in cert_promotion.nim treats certNoObligation
    # and orchestrationNoObligation as non-failure, never promoted.
    # At the classification level: elUnsupported ≠ elProofCandidate.
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irRecCall(@[x])
    let funcDef = irFuncDef("unsupported_rec", @[("x", irTypeBitVec64())], irTypeBitVec64(), body, true)
    let entry = makeEntry("unsupported_rec")
    let cls = classifyCandidateEligibility(entry, funcDef)
    check cls == elUnsupported
    check cls != elProofCandidate

  test "D regression: promoteVerdict rejects certNoObligation status":
    # Mirrors the cert_promotion.nim guard: certNoObligation is never
    # promotion-eligible (isPromotionAllowedStatus returns false for it).
    # This is the runtime analogue of the static elNoObligation guard:
    # a no-obligation candidate is not promoted to proof.
    let candidate = CandidateEvidence(
      modulePath: "src/test.nim",
      functionName: "noObligFunc",
      irHash: "ir-hash-test",
      fingerprint: "abc123",
      contentHash: "sha256:abc",
      status: "certNoObligation",
      lifecycleStage: "transient",
      backend: "lean"
    )
    let gate = promoteVerdict(candidate, "src/test.nim", "noObligFunc", 5, false)
    check gate.verdict == psRejected

  # -----------------------------------------------------------------------
  # 8. Rule S — semantic universe gate on the census path
  # -----------------------------------------------------------------------
  # The census runs before any SemanticEnvironment exists, so a free variable
  # that is not a declared parameter is unknown Nim meaning at that point.
  # These two cases are the negative evidence for that gate: without it the
  # first case would count as a proof candidate.

  func censusEntry(name: string): RuntimeAxiomEntry =
    RuntimeAxiomEntry(
      name: name,
      sourcePath: "subject/" & name & ".nim",
      isKernel: false,
      effectKind: Pure,
      bmcSkippable: false,
      expectedObligation: false)

  func resolvedDivDef(name: string; divisor: IRExpr;
                      universeComplete: bool = true): IRFuncDef =
    # A one-parameter subject; `divisor` decides whether the generated
    # okSafetyDiv guard mentions a name the subject declares.
    var fd = irFuncDef(name, @[("x", irTypeBitVec64())], irTypeBitVec64(),
                       irDiv(irVar("x", irTypeBitVec64()), divisor), false)
    fd.bindingUniverseComplete = universeComplete
    # Hand-built IR carries no translator observation, so the scoped loss evidence
    # defaults to "not certified" (fail-closed). A fixture that wants to exercise
    # the free-variable closure rather than the loss gate must say so.
    fd.propositionRegionLossFree = true
    fd

  test "S reverse: undeclared free variable → semantic.unresolved-fact, no census eligibility":
    let secret = irVar("secretBits", irTypeBitVec64())
    let rec = classifyCandidateForCensus(
      censusEntry("unresolved_div"), resolvedDivDef("unresolved_div", secret))
    # Rule F passed — the guard is not a compile-time tautology — so rule S is
    # the only thing that can reject here, and eligibility stays untouched.
    check rec.eligibility == elProofCandidate
    check rec.nonTrivialObligationCount > 0
    check rec.rejection == some(crrSemanticUnresolvedFact)
    check rec.censusEligible == false

    let census = buildCandidacyCensus(@[rec])
    check census.proofCandidateCount == 0
    check census.proofCandidates.len == 0
    check census.rejectedCount == 1
    check census.terminal == CensusTerminalNoEligibleObligation

  test "S control: declared free variable + complete universe → not rejected by rule S":
    let declared = irVar("x", irTypeBitVec64())
    let rec = classifyCandidateForCensus(
      censusEntry("resolved_div"), resolvedDivDef("resolved_div", declared))
    check rec.rejection.isNone
    check rec.censusEligible == true
    check rec.nonTrivialObligationCount > 0

    let census = buildCandidacyCensus(@[rec])
    check census.proofCandidateCount == 1
    check census.proofCandidates.len == 1
    check census.terminal == CensusTerminalCandidateSelected

  test "S ordering: rule F token survives an unresolved universe — rule S never relabels it":
    # Constant divisor with an INCOMPLETE binding universe. Rule F decides this
    # candidate first, so rule S never runs and the token stays
    # divisor.constant instead of being rewritten to semantic.unresolved-fact.
    # This is the anti-regression lock for the order of the two rules.
    let rec = classifyCandidateForCensus(
      censusEntry("const_div"), resolvedDivDef("const_div", irLit(3), false))
    check rec.rejection == some(crrConstantDivisor)
    check rec.censusEligible == false
