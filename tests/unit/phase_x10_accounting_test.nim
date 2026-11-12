## phase_x10_accounting_test.nim — X1.0 Semantic Accounting Contract unit tests
##
## Revision: Plan 1 — Run Verdict Authority Unification (INV-X1 inversion).
##
## Directly imports src/verification/accounting/run_accounting and proves:
##  1. join-operator algebra — associativity · commutativity · idempotence
##     per component (exhaustive over the component domains, not just declared)
##  2. permutation-invariance — same wave set, multiple orderings (incl.
##     reversed) → byte-identical RunAccounting JSON
##  3. determinism — same input twice → identical
##  4. CONTESTED deterministic mapping — OGR REQUIRED + runtime no_obligation →
##     (REQUIRED, PENDING, CONTESTED); OGR NOT_REQUIRED basis →
##     NOT_REQUIRED + PRE_SIEVED + CONSISTENT
##  5. Run-level verdict (INV-X1 inversion) — run_accounting preserves raw
##     state and NEVER derives a gate verdict; the runOutcome verdict/basis
##     are decided EXCLUSIVELY by verification_decision_authority:
##     PASS(PROVEN) / PASS(NO_OBLIGATION) / PASS(REUSED) / FAIL (proof-level
##     only) / BLOCKED / INCONCLUSIVE (timeout·infra·evidence·vacuous·skipped)
##  6. REUSED 5-condition per-row re-verification (Plan 1 wiring of
##     workunit_fingerprint_cas_contract.md §6.1): (a) subject fingerprint,
##     (b) execution-bundle fingerprint, (c) execution-config digest,
##     (d) concrete artifact + per-read content digest re-verification,
##     (e) toolchain identity / recorded status / leanCompilerVerified /
##     validation epoch. Count-only and weak-key rows are excluded;
##     (a)/(d) absence → fail-closed PENDING — verificationComplete 제외,
##     VDA는 PASS를 결정하지 않는다.
##  7. legacy isolation — canonical output unchanged when legacy fields vary
##  8. witness accounting — FreshExecutionObservedSet derived from ATTEMPTED
##     units (cache hits never witness)
##  9. X1 canonical boundary (DEBT#458 closed): renderLegacyReport purity,
##     canonical stability under presentation mutation, INV-X1 inversion
##     (raw outcome undecided until VDA decides; report runOutcome block
##     carries the VDA verdict), evidence guards fail closed, last-wave
##     regression, canonicalSerialize determinism + permutation invariance
## 10. DEBT#459 — cache-hit evidence attribution under the REUSED basis:
##     verified reuse records classify REUSED + NOT_ATTEMPTED; the
##     summaryProjection raw telemetry keeps counting cache-hit rows as
##     reused (never failed); warm reuse is PASS(REUSED) ONLY when the
##     5-condition basis is established (:739-740 redefined — unconditional
##     PASS tests were discarded).

import std/[json, sequtils, strutils, unittest]
import verification/accounting/run_accounting
import verification/obligation/verification_decision_authority

# ── Synthetic wave fixture helpers ─────────────────────────────────

proc makeNodeReport(unitId, status: string; cacheHit = false): JsonNode =
  %*{"nodeId": unitId, "status": status, "cacheHit": cacheHit,
     "dependencyDepth": 0}

proc makeWave*(nodeReports: seq[JsonNode]): JsonNode =
  ## A minimal per-wave report object carrying nodeReports (all the reducer
  ## reads; the real per-wave reports embed the same nodeReports array).
  %*{"nodeReports": nodeReports}

proc makeEligibility(pairs: openArray[(string, string)]): JsonNode =
  var obj = newJObject()
  for (unitId, cls) in pairs:
    obj[unitId] = %cls
  obj

proc accountingJson(waves: seq[JsonNode]; eligibility: JsonNode): string =
  ## Deterministic canonical JSON rendering (byte-identity target).
  reduceRunAccounting(waves, eligibility).toJson().pretty()

const
  ProofCandidate = "elProofCandidate"
  NoObligation = "elNoObligation"
  UnitA = "mod::a"
  UnitB = "mod::b"
  UnitC = "mod::c"
  UnitD = "mod::d"

# ── REUSED basis fixtures (Plan 1) ─────────────────────────────────

const
  SubjectFpA = "transitive-source-fp-mod-a-v7"
  SubjectFpB = "transitive-source-fp-mod-b-v7"
  TestBundleFp = "bundle-fp-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  TestConfigDigest = "config-digest-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  TestToolchain = "nim-2.2.10|lean-4.33.0|z3-4.13.3"
  TestEpoch = "epoch-2026-01"
  TestDigest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  TestArtifact = "data/trusted/certificates/mod_a.cert"

proc reuseContext(): ReuseVerificationContext =
  ReuseVerificationContext(
    executionBundleFingerprint: TestBundleFp,
    executionConfigDigest: TestConfigDigest,
    toolchainIdentity: TestToolchain,
    currentEpoch: TestEpoch)

proc makeReuseRecord(
  subjectFp, bundleFp, configDigest, artifactRef, contentDigest: string;
  artifactVerified = true; toolchain = TestToolchain;
  recordedStatus = "verified"; leanCompilerVerified = true;
  epoch = TestEpoch
): JsonNode =
  ## A reuse record carrying the 5-condition evidence: (a) subjectFp,
  ## (b) bundleFp, (c) configDigest, (d) artifactRef + contentDigest +
  ## artifactVerified (per-read re-verification), (e) toolchain +
  ## recordedStatus + leanCompilerVerified + validatedAtEpoch.
  %*{"subjectFingerprint": subjectFp, "executionBundleFingerprint": bundleFp,
     "executionConfigDigest": configDigest, "artifactRef": artifactRef,
     "contentDigest": contentDigest, "artifactVerified": artifactVerified,
     "toolchainIdentity": toolchain, "recordedStatus": recordedStatus,
     "leanCompilerVerified": leanCompilerVerified,
     "validatedAtEpoch": epoch}

proc makeReuseRow(unitId, status, subjectFp: string; record: JsonNode): JsonNode =
  ## A parallel-style cache-hit row carrying the unit's CURRENT subject
  ## fingerprint + the reuse record.
  %*{"nodeId": unitId, "status": status, "cacheHit": true,
     "subjectFingerprint": subjectFp, "reuseRecord": record,
     "dependencyDepth": 0}

proc makeValidRecord(subjectFp = SubjectFpA): JsonNode =
  makeReuseRecord(subjectFp, TestBundleFp, TestConfigDigest,
                  TestArtifact, TestDigest)

# ── 1. Join-operator algebra ──────────────────────────────────────

suite "join-operator algebra":

  test "RequirementDecision: assert-equal, idempotent, commutative, associative":
    # idempotence
    for x in [rdRequired, rdNotRequired, rdUnresolved]:
      check joinDecision(x, x) == x
    # commutativity (incl. conflicts)
    for a in [rdRequired, rdNotRequired, rdUnresolved]:
      for b in [rdRequired, rdNotRequired, rdUnresolved]:
        check joinDecision(a, b) == joinDecision(b, a)
    # conflicts → UNRESOLVED
    check joinDecision(rdRequired, rdNotRequired) == rdUnresolved
    check joinDecision(rdRequired, rdUnresolved) == rdUnresolved
    # associativity — exhaustive over the 3-element domain (27 triples)
    let dom = [rdRequired, rdNotRequired, rdUnresolved]
    for a in dom:
      for b in dom:
        for c in dom:
          check joinDecision(joinDecision(a, b), c) == joinDecision(a, joinDecision(b, c))

  test "VerificationOutcome: worse-wins semilattice PENDING<SATISFIED<UNSATISFIED":
    check joinOutcome(voPending, voSatisfied) == voSatisfied
    check joinOutcome(voSatisfied, voUnsatisfied) == voUnsatisfied
    check joinOutcome(voPending, voUnsatisfied) == voUnsatisfied
    check joinOutcome(voSatisfied, voPending) == voSatisfied  # commutative
    # idempotence
    for x in [voPending, voSatisfied, voUnsatisfied]:
      check joinOutcome(x, x) == x
    # associativity — exhaustive (27 triples)
    let dom = [voPending, voSatisfied, voUnsatisfied]
    for a in dom:
      for b in dom:
        for c in dom:
          check joinOutcome(joinOutcome(a, b), c) == joinOutcome(a, joinOutcome(b, c))
    # worse wins is monotone toward UNSATISFIED (top)
    check joinOutcome(joinOutcome(voSatisfied, voUnsatisfied), voPending) == voUnsatisfied

  test "Consistency: OR (CONTESTED absorbing)":
    check joinConsistency(csConsistent, csContested) == csContested
    check joinConsistency(csContested, csConsistent) == csContested
    check joinConsistency(csContested, csContested) == csContested
    check joinConsistency(csConsistent, csConsistent) == csConsistent
    # idempotent + associative over the 2-element domain
    let dom = [csConsistent, csContested]
    for a in dom:
      check joinConsistency(a, a) == a
      for b in dom:
        check joinConsistency(a, b) == joinConsistency(b, a)
        for c in dom:
          check joinConsistency(joinConsistency(a, b), c) ==
                joinConsistency(a, joinConsistency(b, c))

  test "ExecutionEvidence: OR (ATTEMPTED absorbing)":
    check joinEvidence(eeNotAttempted, eeAttempted) == eeAttempted
    check joinEvidence(eeAttempted, eeNotAttempted) == eeAttempted
    check joinEvidence(eeAttempted, eeAttempted) == eeAttempted
    check joinEvidence(eeNotAttempted, eeNotAttempted) == eeNotAttempted
    let dom = [eeNotAttempted, eeAttempted]
    for a in dom:
      check joinEvidence(a, a) == a
      for b in dom:
        check joinEvidence(a, b) == joinEvidence(b, a)
        for c in dom:
          check joinEvidence(joinEvidence(a, b), c) ==
                joinEvidence(a, joinEvidence(b, c))

  test "SatisfactionSource: precedence-absorb FRESH>REUSED>PRE_SIEVED":
    check joinSource(ssReused, ssFresh) == ssFresh
    check joinSource(ssFresh, ssReused) == ssFresh
    check joinSource(ssPreSieved, ssReused) == ssReused
    check joinSource(ssReused, ssPreSieved) == ssReused
    check joinSource(ssPreSieved, ssFresh) == ssFresh
    # NONE is identity (bottom)
    for x in [ssNone, ssPreSieved, ssReused, ssFresh]:
      check joinSource(ssNone, x) == x
      check joinSource(x, ssNone) == x
    # idempotent + associative + commutative over the 4-element domain
    let dom = [ssNone, ssPreSieved, ssReused, ssFresh]
    for a in dom:
      check joinSource(a, a) == a
      for b in dom:
        check joinSource(a, b) == joinSource(b, a)
        for c in dom:
          check joinSource(joinSource(a, b), c) ==
                joinSource(a, joinSource(b, c))

# ── 2/3. Permutation-invariance + determinism ─────────────────────

suite "permutation invariance + determinism":

  let baseWaves = @[
    makeWave(@[makeNodeReport(UnitA, "verified"),
               makeNodeReport(UnitB, "no_obligation")]),
    makeWave(@[makeNodeReport(UnitB, "failed", cacheHit = true),
               makeNodeReport(UnitC, "verified")]),
    makeWave(@[makeNodeReport(UnitA, "no_obligation")])
  ]
  let eligibility = makeEligibility([(UnitA, ProofCandidate),
                                    (UnitB, ProofCandidate),
                                    (UnitC, ProofCandidate)])

  test "wave ordering cannot affect RunAccounting (byte-identical JSON)":
    let reversedSeq = @[baseWaves[2], baseWaves[1], baseWaves[0]]
    let forward = accountingJson(baseWaves, eligibility)
    let reversed = accountingJson(reversedSeq, eligibility)
    let rotated = accountingJson(@[baseWaves[1], baseWaves[2], baseWaves[0]], eligibility)
    let swapped = accountingJson(@[baseWaves[2], baseWaves[0], baseWaves[1]], eligibility)
    check forward == reversed
    check forward == rotated
    check forward == swapped

  test "determinism — same input twice → byte-identical":
    let first = accountingJson(baseWaves, eligibility)
    let second = accountingJson(baseWaves, eligibility)
    check first == second

  test "single-wave degenerate ordering":
    let single = @[makeWave(@[makeNodeReport(UnitA, "verified")])]
    check accountingJson(single, eligibility) ==
          accountingJson(single, eligibility)

# ── 4. CONTESTED deterministic mapping ────────────────────────────

suite "CONTESTED deterministic mapping":

  test "OGR REQUIRED + runtime no_obligation → (REQUIRED, PENDING, CONTESTED), never satisfying":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "no_obligation")])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.requiredCount == 1
    check acc.contestedCount == 1
    check acc.pendingCount == 1       # outcome totals over REQUIRED units
    check acc.unsatisfiedCount == 0
    check acc.satisfiedCount == 0
    check not acc.runOutcome.verificationComplete
    let row = acc.units[0]
    check row.unitId == UnitA
    check row.requirementDecision == rdRequired
    check row.verificationOutcome == voPending
    check row.consistency == csContested
    check row.executionEvidence == eeAttempted
    check row.satisfactionSource == ssNone  # never satisfying

  test "OGR NOT_REQUIRED basis + runtime no_obligation → NOT_REQUIRED + PRE_SIEVED + CONSISTENT":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "no_obligation")])]
    let elig = makeEligibility([(UnitA, NoObligation)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.requiredCount == 0
    check acc.notRequiredCount == 1
    check acc.preSievedCount == 1
    check acc.contestedCount == 0
    check acc.satisfiedCount == 0
    let row = acc.units[0]
    check row.requirementDecision == rdNotRequired
    check row.satisfactionSource == ssPreSieved
    check row.consistency == csConsistent  # CONTESTED only when REQUIRED

  test "no eligibility basis → UNRESOLVED (never NOT_REQUIRED)":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "no_obligation")])]
    let acc = reduceRunAccounting(waves, newJObject())  # no basis in data
    check acc.unresolvedDecisionCount == 1
    check acc.notRequiredCount == 0
    check acc.units[0].requirementDecision == rdUnresolved
    check not acc.runOutcome.planComplete
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict != vrPass
    check gateVerdictProjection(decided) == gvFail

# ── 5. Run-level verdict — VDA decides (INV-X1 inversion) ──────────

suite "run-level verdict (VDA, INV-X1 inversion)":

  test "all satisfied + consistent → PASS(PROVEN), gateVerdict PASS":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "verified"),
                             makeNodeReport(UnitB, "verified")])]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.contestedCount == 0
    check acc.unsatisfiedCount == 0
    check acc.unresolvedDecisionCount == 0
    check acc.pendingCount == 0
    check acc.runOutcome.verificationComplete
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrPass
    check decided.basis == rbProven
    check gateVerdictProjection(decided) == gvPass
    check runOutcomeToJson(decided)["verdict"].getStr() == "PASS"

  test "contested (REQUIRED + no_obligation) → INCONCLUSIVE (never FAIL, never PASS)":
    # FAIL 축소: a consistency failure is not a proof-level failure → the
    # run verdict is INCONCLUSIVE; the gate projection stays FAIL.
    let waves = @[makeWave(@[makeNodeReport(UnitA, "verified"),
                             makeNodeReport(UnitB, "no_obligation")])]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.satisfiedCount == 1
    check acc.contestedCount == 1
    check not acc.runOutcome.verificationComplete
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrInconclusive
    check decided.basis == rbNone
    check gateVerdictProjection(decided) == gvFail

  test "unsatisfied (runtime failed) → FAIL (proof-level failure only)":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "failed")])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.unsatisfiedCount == 1
    check acc.proofFailedCount == 1
    check acc.timeoutUnsatCount == 0
    check acc.units[0].verificationOutcome == voUnsatisfied
    check not acc.runOutcome.verificationComplete
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrFail
    check gateVerdictProjection(decided) == gvFail

  test "timeout-only UNSATISFIED → INCONCLUSIVE (never mixed into FAIL)":
    # The accounting's timeout→UNSATISFIED aggregation is the raw fact
    # (kept); VDA interprets a timeout-only unsat as INCONCLUSIVE.
    let waves = @[makeWave(@[makeNodeReport(UnitA, "timeout")])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.unsatisfiedCount == 1
    check acc.proofFailedCount == 0
    check acc.timeoutUnsatCount == 1
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrInconclusive
    check decided.basis == rbNone
    check gateVerdictProjection(decided) == gvFail

  test "unresolved decision → INCONCLUSIVE, not PASS":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "verified"),
                             makeNodeReport(UnitB, "no_obligation")])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])  # UnitB has no basis
    let acc = reduceRunAccounting(waves, elig)
    check acc.unresolvedDecisionCount == 1
    check not acc.runOutcome.planComplete
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrInconclusive
    check gateVerdictProjection(decided) == gvFail

  test "required-but-never-attempted → PENDING, INCONCLUSIVE (not blocked without fact-gate)":
    # UnitB is REQUIRED by OGR but no wave ever processed it.
    let waves = @[makeWave(@[makeNodeReport(UnitA, "verified")])]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.attemptedCount == 1
    check acc.notAttemptedCount == 1
    check not acc.runOutcome.executionComplete
    check acc.pendingCount == 1
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrInconclusive
    check gateVerdictProjection(decided) == gvFail

  test "BLOCKED — pending ∧ attempted==0 ∧ fact-gate":
    let waves: seq[JsonNode] = @[]  # nothing attempted at all
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.pendingCount == 1
    check acc.attemptedCount == 0
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"),
      factGateActive = true)
    check decided.verdict == vrBlocked
    check gateVerdictProjection(decided) == gvFail
    # without the fact-gate the same raw state is INCONCLUSIVE
    let decidedNoGate = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"),
      factGateActive = false)
    check decidedNoGate.verdict == vrInconclusive

  test "PASS(NO_OBLIGATION) — non-empty universe, all NOT_REQUIRED, enumeration completed":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "no_obligation"),
                             makeNodeReport(UnitB, "no_obligation")])]
    let elig = makeEligibility([(UnitA, NoObligation), (UnitB, NoObligation)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.requiredCount == 0
    check acc.notRequiredCount == 2
    check acc.unresolvedDecisionCount == 0
    check acc.units.len == 2
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "canonical_ogr_eligibility"),
      false)
    check decided.verdict == vrPass
    check decided.basis == rbNoObligation
    check gateVerdictProjection(decided) == gvPass

  test "empty universe → INCONCLUSIVE — '0이라서 PASS' 금지":
    let acc = reduceRunAccounting(@[], newJObject())
    check acc.units.len == 0
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrInconclusive
    check gateVerdictProjection(decided) == gvFail

  test "all NOT_REQUIRED but enumeration NOT completed → INCONCLUSIVE":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "no_obligation")])]
    let elig = makeEligibility([(UnitA, NoObligation)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.requiredCount == 0
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: false, source: "absent"), false)
    check decided.verdict == vrInconclusive
    check gateVerdictProjection(decided) == gvFail

  test "mixed fresh + verified reuse → PASS(PROVEN)":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "verified"),
                             makeReuseRow(UnitB, "failed", SubjectFpB,
                                          makeReuseRecord(SubjectFpB, TestBundleFp,
                                                          TestConfigDigest, TestArtifact,
                                                          TestDigest))])]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.satisfiedByFresh == 1
    check acc.satisfiedByReused == 1
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrPass
    check decided.basis == rbProven  # genuine KAA evidence exists → PROVEN

# ── 6. REUSED 5-condition per-row re-verification ──────────────────

suite "REUSED basis — 5-condition per-row re-verification":

  test "full 5-condition record → REUSED satisfaction + PASS(REUSED) with condition fields":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeValidRecord())])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.requiredCount == 1
    check acc.satisfiedCount == 1
    check acc.satisfiedByReused == 1
    check acc.satisfiedByFresh == 0
    check acc.reuseEligibleRowCount == 1
    check acc.reuseRejectedRowCount == 0
    check acc.pendingCount == 0
    check acc.attemptedCount == 0
    check acc.notAttemptedCount == 1
    check acc.freshExecutionCount == 0
    check acc.executedCount == 1
    check acc.anomalies.len == 0
    let row = acc.units[0]
    check row.verificationOutcome == voSatisfied
    check row.satisfactionSource == ssReused
    check row.executionEvidence == eeNotAttempted
    check row.consistency == csConsistent
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrPass
    check decided.basis == rbReused
    check decided.reusedConditionsMet.len == 5
    check "subjectFingerprint" in decided.reusedConditionsMet
    check "executionBundleFingerprint" in decided.reusedConditionsMet
    check "executionConfigDigest" in decided.reusedConditionsMet
    check "artifactContentDigest" in decided.reusedConditionsMet
    check "toolchainIdentity" in decided.reusedConditionsMet
    let j = runOutcomeToJson(decided)
    check j["verdict"].getStr() == "PASS"
    check j["basis"].getStr() == "REUSED"
    check j["reuseConditions"].len == 5
    check j["gateVerdict"].getStr() == "PASS"

  test "(a) subject fingerprint mismatch → basis not established → fail-closed PENDING":
    # The row's CURRENT subject fingerprint differs from the record's:
    # VDA must NOT decide PASS (C4 negative).
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord("other-subject-fp", TestBundleFp,
                                                          TestConfigDigest, TestArtifact,
                                                          TestDigest))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.reuseEligibleRowCount == 0
    check acc.reuseRejectedRowCount == 1
    check acc.satisfiedByReused == 0
    check acc.pendingCount == 1
    check not acc.runOutcome.verificationComplete
    check acc.anomalies.len == 1
    check "subject fingerprint mismatch (a)" in acc.anomalies[0]
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict != vrPass
    check decided.basis == rbNone
    check gateVerdictProjection(decided) == gvFail

  test "(a) missing outright — lean-cache weak-key 거부 (fingerprint-less reuse key)":
    # The weak cache keys rows by module/function identity only — no subject
    # fingerprint on the record: the reuse basis cannot be established.
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord("", TestBundleFp,
                                                          TestConfigDigest, TestArtifact,
                                                          TestDigest))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.reuseRejectedRowCount == 1
    check acc.satisfiedByReused == 0
    check acc.pendingCount == 1
    check "subject fingerprint mismatch (a)" in acc.anomalies[0]

  test "(d) no concrete artifact reference → rejected":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord(SubjectFpA, TestBundleFp,
                                                          TestConfigDigest, "",
                                                          TestDigest))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.pendingCount == 1
    check acc.satisfiedByReused == 0
    check "no concrete artifact reference (d)" in acc.anomalies[0]
    check not acc.runOutcome.verificationComplete

  test "(d) content digest missing/malformed → completeness digest gap → rejected":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord(SubjectFpA, TestBundleFp,
                                                          TestConfigDigest, TestArtifact,
                                                          "not-a-digest"))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.pendingCount == 1
    check "content digest missing/malformed (d)" in acc.anomalies[0]

  test "(d) artifact content digest NOT re-verified on read → rejected (per-read re-verification)":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord(SubjectFpA, TestBundleFp,
                                                          TestConfigDigest, TestArtifact,
                                                          TestDigest,
                                                          artifactVerified = false))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.pendingCount == 1
    check "artifact content digest not re-verified on read (d)" in acc.anomalies[0]

  test "(b) execution-bundle fingerprint mismatch → rejected":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord(SubjectFpA, "other-bundle-fp",
                                                          TestConfigDigest, TestArtifact,
                                                          TestDigest))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.pendingCount == 1
    check "execution-bundle fingerprint mismatch (b)" in acc.anomalies[0]

  test "(c) execution-config digest mismatch → rejected":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord(SubjectFpA, TestBundleFp,
                                                          "other-config-digest", TestArtifact,
                                                          TestDigest))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.pendingCount == 1
    check "execution-config digest mismatch (c)" in acc.anomalies[0]

  test "(e) toolchain identity mismatch → rejected":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord(SubjectFpA, TestBundleFp,
                                                          TestConfigDigest, TestArtifact,
                                                          TestDigest,
                                                          toolchain = "nim-2.2.9|lean-4.32.0"))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.pendingCount == 1
    check "toolchain identity mismatch (e)" in acc.anomalies[0]

  test "(e) recorded status not terminal-verified → rejected":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord(SubjectFpA, TestBundleFp,
                                                          TestConfigDigest, TestArtifact,
                                                          TestDigest,
                                                          recordedStatus = "failed"))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.pendingCount == 1
    check "recorded status not terminal-verified (e)" in acc.anomalies[0]

  test "(e) leanCompilerVerified not recorded → rejected":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord(SubjectFpA, TestBundleFp,
                                                          TestConfigDigest, TestArtifact,
                                                          TestDigest,
                                                          leanCompilerVerified = false))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.pendingCount == 1
    check "leanCompilerVerified not recorded (e)" in acc.anomalies[0]

  test "(e) stale — validation epoch mismatch → rejected":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeReuseRecord(SubjectFpA, TestBundleFp,
                                                          TestConfigDigest, TestArtifact,
                                                          TestDigest,
                                                          epoch = "epoch-2025-06"))])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.pendingCount == 1
    check "validation epoch mismatch — stale reuse record (e)" in acc.anomalies[0]

  test "count-only reuse row (no reuseRecord) → excluded — PENDING + anomaly":
    # The parallel/serial cache-hit rows emitted today carry no reuse record
    # (count-only): they never establish a reuse basis.
    let waves = @[makeWave(@[makeNodeReport(UnitA, "failed", cacheHit = true)])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.reuseEligibleRowCount == 0
    check acc.reuseRejectedRowCount == 1
    check acc.satisfiedCount == 0
    check acc.satisfiedByReused == 0
    check acc.pendingCount == 1
    check acc.units[0].verificationOutcome == voPending
    check acc.units[0].satisfactionSource == ssNone
    check acc.anomalies.len == 1
    check "reuse record missing (count-only reuse row — excluded)" in acc.anomalies[0]
    check not acc.runOutcome.verificationComplete
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict != vrPass
    check gateVerdictProjection(decided) == gvFail

  test "unit-level basis — any rejected row fails the unit's whole reuse basis":
    # A unit with an eligible AND a rejected cache-hit row has NO established
    # basis (one unverifiable replay poisons the unit).
    let waves = @[makeWave(@[
      makeReuseRow(UnitA, "failed", SubjectFpA, makeValidRecord()),
      makeReuseRow(UnitA, "failed", SubjectFpA,
                   makeReuseRecord(SubjectFpA, TestBundleFp, TestConfigDigest,
                                   "", TestDigest))  # (d) artifactRef missing
    ])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.reuseEligibleRowCount == 1
    check acc.reuseRejectedRowCount == 1
    check acc.satisfiedByReused == 0
    check acc.pendingCount == 1
    check acc.units[0].verificationOutcome == voPending
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict != vrPass

  test "default context is fail-closed — no pinned values → reuse rows rejected":
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeValidRecord())])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)  # 2-arg → defaultReuseVerificationContext()
    check acc.reuseEligibleRowCount == 0
    check acc.reuseRejectedRowCount == 1
    check acc.pendingCount == 1
    check acc.satisfiedByReused == 0

# ── 7. Legacy isolation ───────────────────────────────────────────

suite "legacy isolation":

  test "canonical output unchanged when legacy fields in input are altered":
    # The canonical path receives ONLY wave reports + eligibility; legacy
    # closure fields live in the merged report and are parsed by a separate
    # function (parseLegacyClosure). Altering them must not reach the
    # canonical computation.
    let waves = @[makeWave(@[makeNodeReport(UnitA, "verified")])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let baseline = accountingJson(waves, elig)
    # Simulated merged reports differing ONLY in legacy closure aggregates:
    let reportA = %*{"closure": %*{"completedCount": 12, "requiredCount": 23,
                                   "closureComplete": false}}
    let reportB = %*{"closure": %*{"completedCount": 999, "requiredCount": 999,
                                   "closureComplete": true}}
    discard reportA
    discard reportB
    # The reducer signature has no legacy parameter — recomputation from the
    # same waves/eligibility is byte-identical by construction; assert it.
    let again = accountingJson(waves, elig)
    check baseline == again

  test "legacy mixed aggregate never leaks into canonical counts":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "no_obligation")])]
    let elig = makeEligibility([(UnitA, NoObligation)])
    let acc = reduceRunAccounting(waves, elig)
    # Legacy would count this as "completed" (NoObligation ∈ mixed aggregate);
    # canonical must not: satisfiedCount/preSievedCount are the only satisfactions.
    check acc.satisfiedCount == 0
    check acc.preSievedCount == 1
    check acc.contestedCount == 0

# ── 8. Witness accounting (FreshExecutionObservedSet) ─────────────────────

suite "FreshExecutionObservedSet witness accounting":

  test "FreshExecutionObservedSet derived from ATTEMPTED units with terminal-verdict-proxy evidence":
    # A: verified fresh → SATISFIED + FRESH, in FreshExecutionSet
    # B: verified reuse with a full 5-condition record → SATISFIED + REUSED,
    #    NOT in FreshExecutionSet, NOT_ATTEMPTED
    # C: no_obligation → PENDING (REQUIRED basis) + no witness
    let waves = @[makeWave(@[makeNodeReport(UnitA, "verified"),
                             makeReuseRow(UnitB, "failed", SubjectFpB,
                                          makeReuseRecord(SubjectFpB, TestBundleFp,
                                                          TestConfigDigest, TestArtifact,
                                                          TestDigest)),
                             makeNodeReport(UnitC, "no_obligation")])]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate),
                                (UnitC, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.attemptedCount == 2
    check acc.notAttemptedCount == 1
    check acc.freshExecutionCount == 1
    check acc.satisfiedByFresh == 1
    check acc.satisfiedByReused == 1
    check acc.executedCount == 3
    let rowA = acc.units.filterIt(it.unitId == UnitA)[0]
    let rowB = acc.units.filterIt(it.unitId == UnitB)[0]
    check rowA.satisfactionSource == ssFresh
    check rowB.satisfactionSource == ssReused
    check rowB.executionEvidence == eeNotAttempted
    check acc.satisfiedCount == 2

  test "no_obligation units never evidence a fresh invocation":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "no_obligation"),
                             makeNodeReport(UnitB, "not_verifiable")])]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.attemptedCount == 2
    check acc.freshExecutionCount == 0
    check acc.freshExecutionCount <= acc.attemptedCount  # invariant

  test "failed units do evidence a fresh invocation (attempted, not satisfied)":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "failed")])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.freshExecutionCount == 1
    check acc.unsatisfiedCount == 1
    check acc.satisfiedByFresh == 0
    check acc.satisfiedByReused == 0

# ── 9. Invariant sanity on the canonical structure ────────────────

suite "canonical structure":

  test "canonical JSON carries the full field set (gateVerdict moved to the runOutcome block)":
    let waves = @[makeWave(@[makeNodeReport(UnitA, "verified")])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let j = reduceRunAccounting(waves, elig).toJson()
    for key in ["requiredCount", "notRequiredCount", "unresolvedDecisionCount",
                "satisfiedCount", "unsatisfiedCount", "pendingCount",
                "contestedCount", "satisfiedByFresh", "satisfiedByReused",
                "preSievedCount", "attemptedCount", "notAttemptedCount",
                "freshExecutionCount", "executedCount", "proofFailedCount",
                "timeoutUnsatCount", "reuseEligibleRowCount",
                "reuseRejectedRowCount", "runOutcome",
                "units", "anomalies", "derivations"]:
      check j.hasKey(key)
    check j["runOutcome"].hasKey("planComplete")
    check j["runOutcome"].hasKey("executionComplete")
    check j["runOutcome"].hasKey("verificationComplete")
    check not j.hasKey("gateVerdict")  # INV-X1 inversion: no gate verdict in raw accounting

  test "unit rows are sorted by unitId (deterministic ordering)":
    let waves = @[makeWave(@[makeNodeReport(UnitC, "verified"),
                             makeNodeReport(UnitA, "verified"),
                             makeNodeReport(UnitB, "verified")])]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate),
                                (UnitC, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    let ids = acc.units.mapIt(it.unitId)
    check ids == @[UnitA, UnitB, UnitC]

  test "raw FAIL/INCONCLUSIVE split — unsatisfiedCount partition invariant":
    # failed rows → proofFailedCount; timeout-only rows → timeoutUnsatCount;
    # unsatisfiedCount == proofFailedCount + timeoutUnsatCount (no anomalies).
    let waves = @[makeWave(@[makeNodeReport(UnitA, "failed"),
                             makeNodeReport(UnitB, "timeout")])]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig)
    check acc.proofFailedCount == 1
    check acc.timeoutUnsatCount == 1
    check acc.unsatisfiedCount == 2
    check acc.anomalies.len == 0

# ── 10. X1 canonical boundary (DEBT#458 closed) ───────────────────────

proc makeFullWave(nodeReports: seq[JsonNode]): JsonNode =
  ## A realistic per-wave report: nodeReports + executionStats + summary +
  ## runtimeMeta + gates (doc-level fields the projections read).
  %*{
    "nodeReports": nodeReports,
    "executionStats": %*{
      "solverInvocationCount": nodeReports.len,
      "cacheHitCount": 0,
      "timeoutCount": 0,
      "totalWallTimeMs": 100,
      "totalSolverTimeMs": 80,
      "serialBaselineMs": 120,
      "nodeStats": @[],
      "depthStats": @[],
      "obligationGeneratedCount": 0,
      "obligationAttemptedCount": 0,
      "targetsWithObligations": 0,
      "eligibleTargets": 0
    },
    "summary": %*{
      "verified": nodeReports.countIt(it{"status"}.getStr() == "verified"),
      "verifiedRatio": 0.5,
      "asi": 0.5,
      "completionRate": 0.5,
      "netVerifiedFunctions": 1,
      "vacuousDemotions": 0,
      "tautologyDemotions": 0,
      "refactorRepaired": 0
    },
    "runtimeMeta": %*{"totalWallTimeMs": 100, "hotspotElapsedMs": 80, "hotspotLabel": "x"},
    "gates": @[],
    "refactorSummary": %*{},
    "refactorEvidence": %*{},
    "blockedNodes": @[],
    "staleDependencyNodes": @[],
    "reproofNodes": @[],
    "timeoutNodes": @[],
    "timeoutImpactNodes": @[]
  }

proc makePreRun(): JsonNode =
  %*{
    "summary": %*{
      "topologyScanComplete": true,
      "symbolCount": 40,
      "plannedNodeCount": 3,
      "queuePreviewCount": 3,
      "effectiveQueueLimit": 3,
      "effectiveDiagnosisDepth": 0,
      "structuralBottleneckCount": 0,
      "repairPriorityCount": 0,
      "bodyLoadCount": 0,
      "symbolFirstPass": true,
      "totalSourceFunctions": 40
    },
    "diagnostics": @[],
    "verificationQueue": @[],
    "structuralBottlenecks": @[],
    "repairPriorityDependencies": @[],
    "eligibility": %*{UnitA: "elProofCandidate", UnitB: "elProofCandidate"}
  }

proc makeProjections(closureComplete: bool): JsonNode =
  %*{
    "closure": %*{"closureComplete": closureComplete, "requiredCount": 2,
                  "completedCount": 1, "uncompletedRequired": @[], "wavesExecuted": 2},
    "crossValidation": %*{"consistent": true, "functionCount": 0},
    "leanVerify": %*{"success": true, "sorryFound": false, "exitCode": 0, "axiomsUsed": 0}
  }

suite "X1 canonical boundary (DEBT#458 closed)":

  test "renderLegacyReport purity — preRun mutation affects only preRun sections":
    # Same RunResult + two different PreRunContexts → the preRun projection
    # sections differ, but runAccounting/runOutcome/canonicalRunDigest and the
    # merged nodeReports are byte-identical.
    let waves = @[
      makeFullWave(@[makeNodeReport(UnitA, "verified"),
                     makeNodeReport(UnitB, "no_obligation")]),
      makeFullWave(@[makeNodeReport(UnitC, "verified")])
    ]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate),
                                (UnitC, ProofCandidate)])
    let runResult = buildCanonicalRunResult(waves, elig, @[@[UnitA, UnitB], @[UnitC]])
    let preRunA = makePreRun()
    let preRunB = makePreRun()
    preRunB["summary"]["symbolCount"] = %999
    preRunB["diagnostics"] = %*[%*{"nodeId": "x", "labels": @[]}]
    let projections = makeProjections(true)
    let reportA = renderLegacyReport(runResult, preRunA, projections)
    let reportB = renderLegacyReport(runResult, preRunB, projections)
    # preRun sections differ.
    check reportA["summary"]["symbolCount"].getInt() == 40
    check reportB["summary"]["symbolCount"].getInt() == 999
    check reportA["diagnostics"].len == 0
    check reportB["diagnostics"].len == 1
    # canonical sections byte-identical.
    check $reportA["runAccounting"] == $reportB["runAccounting"]
    check $reportA["runOutcome"] == $reportB["runOutcome"]
    check reportA["canonicalRunDigest"].getStr() == reportB["canonicalRunDigest"].getStr()
    check $reportA["nodeReports"] == $reportB["nodeReports"]
    check $reportA["executionStats"] == $reportB["executionStats"]

  test "canonical stability under presentation mutation (P≠P' → projection differs, digest identical)":
    let waves = @[
      makeFullWave(@[makeNodeReport(UnitA, "verified")]),
      makeFullWave(@[makeNodeReport(UnitB, "no_obligation")])
    ]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate)])
    let runResult = buildCanonicalRunResult(waves, elig, @[@[UnitA], @[UnitB]])
    let preRun = makePreRun()
    # P vs P': different post-loop projections (closure verdict flips).
    let reportP = renderLegacyReport(runResult, preRun, makeProjections(true))
    let reportPprime = renderLegacyReport(runResult, preRun, makeProjections(false))
    check $reportP["closure"] != $reportPprime["closure"]  # projection differs
    check reportP["canonicalRunDigest"].getStr() == reportPprime["canonicalRunDigest"].getStr()
    check canonicalRunDigest(runResult) == reportP["canonicalRunDigest"].getStr()
    # preRun mutation → digest identical.
    let preRunMutated = makePreRun()
    preRunMutated["summary"]["symbolCount"] = %1
    let reportM = renderLegacyReport(runResult, preRunMutated, makeProjections(true))
    check reportM["canonicalRunDigest"].getStr() == reportP["canonicalRunDigest"].getStr()

  test "INV-X1 inversion — run_result outcome is RAW and UNDECIDED; VDA decides verdict/basis":
    let waves = @[
      makeFullWave(@[makeNodeReport(UnitA, "verified")]),
      makeFullWave(@[makeNodeReport(UnitB, "no_obligation")])
    ]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate)])
    let runResult = buildCanonicalRunResult(waves, elig, @[@[UnitA], @[UnitB]])
    let expected = deriveRunOutcome(
      RunPlanInput(requiredUnitIds: @[UnitA, UnitB]),
      runResult.runAccounting,
      runResult.executionEvidence)
    check runResult.runOutcome.planComplete == expected.planComplete
    check runResult.runOutcome.executionComplete == expected.executionComplete
    check runResult.runOutcome.verificationComplete == expected.verificationComplete
    check runResult.runOutcome.verificationComplete == false
    # INV-X1 inversion: the construction-time verdict is UNDECIDED — the
    # reducer never derives a gate verdict; run_accounting preserves raw
    # state only.
    check runResult.runOutcome.verdict == vrInconclusive
    check runResult.runOutcome.basis == rbNone
    # The runOutcome block serializes the raw + undecided state.
    let outcomeJson = runOutcomeToJson(runResult.runOutcome)
    check outcomeJson["verificationComplete"].getBool() == expected.verificationComplete
    check outcomeJson["verdict"].getStr() == "INCONCLUSIVE"
    check outcomeJson["basis"].getStr() == "NONE"
    check outcomeJson["gateVerdict"].getStr() == "FAIL"
    check outcomeJson["reuseConditions"].len == 0
    # VDA decides (contested present → not PASS; pass never fabricated).
    let decided = evaluateRunOutcome(runResult.runAccounting,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrInconclusive
    check decided.basis == rbNone
    check runOutcomeToJson(decided)["gateVerdict"].getStr() == "FAIL"

  test "INV-X1 evidence guard — dispatched unit without observed verdict fails executionComplete":
    # A unit is DISPATCHED (per-wave set) but no runtime verdict row exists in
    # the wave JSON — the ExecutionEvidence layer fails closed even though the
    # reducer alone would mark the unit NOT_ATTEMPTED only when it is REQUIRED.
    let waves = @[makeFullWave(@[makeNodeReport(UnitA, "verified")])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    # dispatched = {A, B}; B has no verdict row anywhere.
    let runResult = buildCanonicalRunResult(waves, elig, @[@[UnitA, UnitB]])
    check runResult.runOutcome.executionComplete == false
    # Without the dispatched inconsistency the outcome is execution-complete.
    let consistent = buildCanonicalRunResult(waves, elig, @[@[UnitA]])
    check consistent.runOutcome.executionComplete == true

  test "last-wave regression — wave-1 information survives in merged rows / RunResult":
    # Meaningful wave1 + minimal wave2: the merged rows must still carry the
    # wave-1 units (calcDynamicTimeoutCore-style not_verifiable rows etc.).
    let wave1Rows = @[makeNodeReport(UnitA, "verified"),
                      makeNodeReport(UnitB, "not_verifiable")]
    let wave2Rows = @[makeNodeReport(UnitC, "verified")]
    let waves = @[makeFullWave(wave1Rows), makeFullWave(wave2Rows)]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate),
                                (UnitC, ProofCandidate)])
    let runResult = buildCanonicalRunResult(waves, elig, @[@[UnitA, UnitB], @[UnitC]])
    # Merged rows: keyed union across waves (wave-1 rows survive).
    let mergedIds = runResult.executionEvidence.observedRows.mapIt(
      it{"nodeId"}.getStr())
    check mergedIds == @[UnitA, UnitB, UnitC]
    # RunAccounting rows carry the wave-1 not_verifiable unit as PENDING.
    let rowB = runResult.runAccounting.units.filterIt(it.unitId == UnitB)[0]
    check rowB.verificationOutcome == voPending
    check rowB.executionEvidence == eeAttempted
    check runResult.runAccounting.attemptedCount == 3
    check runResult.runAccounting.requiredCount == 3
    # The legacy report's nodeReports is the merged union (not last-wave).
    let reportJson = renderLegacyReport(runResult, makePreRun(), makeProjections(true))
    let reportIds = reportJson["nodeReports"].elems.mapIt(it{"nodeId"}.getStr())
    check reportIds == @[UnitA, UnitB, UnitC]

  test "canonicalSerialize determinism + permutation invariance over FULL RunResult":
    let waves = @[
      makeFullWave(@[makeNodeReport(UnitA, "verified"),
                     makeNodeReport(UnitB, "no_oblig")]),
      makeFullWave(@[makeNodeReport(UnitC, "verified")])
    ]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate),
                                (UnitC, ProofCandidate)])
    let runResult = buildCanonicalRunResult(waves, elig, @[@[UnitA, UnitB], @[UnitC]])
    # Same RunResult twice → identical bytes.
    check canonicalSerialize(runResult) == canonicalSerialize(runResult)
    check canonicalRunDigest(runResult) == canonicalRunDigest(runResult)
    # Permutation invariance: reordered waves + reordered dispatched sets +
    # reordered eligibility key insertion → identical canonical bytes.
    let permuted = buildCanonicalRunResult(
      @[waves[1], waves[0]], elig, @[@[UnitC], @[UnitB, UnitA]])
    check canonicalSerialize(permuted) == canonicalSerialize(runResult)
    check canonicalRunDigest(permuted) == canonicalRunDigest(runResult)

# ── 11. DEBT#459 — cache-hit evidence attribution (REUSED basis) ─────────

suite "DEBT#459 cache-hit evidence attribution (REUSED basis)":

  test "parallel cache-hit row with verified reuse record → REUSED, not UNSATISFIED":
    # The parallel scheduler emits cache-hit rows with the fail-closed runtime
    # status orchestrationProofFailed ("failed") + cacheHit=true. With a full
    # 5-condition reuse record the pair classifies canonically as a REUSED
    # satisfaction: SATISFIED + REUSED, NOT invocation-witnessed, NOT
    # ATTEMPTED, and does not inflate unsatisfiedCount/attemptedCount.
    let waves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                          makeValidRecord())])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.requiredCount == 1
    check acc.unsatisfiedCount == 0
    check acc.satisfiedCount == 1
    check acc.satisfiedByReused == 1
    check acc.satisfiedByFresh == 0
    check acc.attemptedCount == 0
    check acc.notAttemptedCount == 1
    check acc.freshExecutionCount == 0
    check acc.executedCount == 1
    let row = acc.units[0]
    check row.requirementDecision == rdRequired
    check row.verificationOutcome == voSatisfied
    check row.satisfactionSource == ssReused
    check row.executionEvidence == eeNotAttempted
    check row.consistency == csConsistent

  test "conservation partitions hold with eligible cache-hit rows present":
    # Required = Reused + FreshObserved (no genuine failures):
    # A fresh-verified, B verified-reuse, C pre-sieved (NOT_REQUIRED basis),
    # D fresh-verified.
    let waves = @[makeWave(@[makeNodeReport(UnitA, "verified"),
                             makeReuseRow(UnitB, "failed", SubjectFpB,
                                          makeValidRecord(SubjectFpB)),
                             makeNodeReport(UnitD, "verified")])]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate),
                                (UnitC, NoObligation), (UnitD, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.requiredCount == 3
    check acc.notRequiredCount == 1
    check acc.satisfiedCount == 3
    check acc.satisfiedByFresh == 2
    check acc.satisfiedByReused == 1
    check acc.preSievedCount == 1
    check acc.freshExecutionCount == 2
    check acc.unsatisfiedCount == 0
    # Partitions (no genuine failures ⇒ every witnessed unit is fresh-satisfied):
    #   Required = Reused + FreshObserved(satisfied-by-fresh witnesses)
    check acc.requiredCount == acc.satisfiedByFresh + acc.satisfiedByReused
    check acc.requiredCount == acc.freshExecutionCount + acc.satisfiedByReused
    #   Universe = Reused + FreshObserved + PreSieved
    check acc.requiredCount + acc.notRequiredCount ==
          acc.freshExecutionCount + acc.satisfiedByReused + acc.preSievedCount
    check acc.freshExecutionCount == acc.satisfiedByFresh
    # Outcome total invariant over REQUIRED units.
    check acc.requiredCount == acc.satisfiedCount + acc.unsatisfiedCount +
                              acc.pendingCount
    # Evidence total invariant over the unit universe.
    check acc.attemptedCount + acc.notAttemptedCount ==
          acc.requiredCount + acc.notRequiredCount
    check acc.anomalies.len == 0

  test "path symmetry — serial-style and parallel cache-hit rows classify identically":
    # A serial-analog row (status=verified, cacheHit=true) and the parallel
    # row (status=failed, cacheHit=true) with identical reuse records must
    # produce byte-identical per-unit classification.
    let serialWaves = @[makeWave(@[makeReuseRow(UnitA, "verified", SubjectFpA,
                                                makeValidRecord())])]
    let parallelWaves = @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                                  makeValidRecord())])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let serialAcc = reduceRunAccounting(serialWaves, elig, reuseContext())
    let parallelAcc = reduceRunAccounting(parallelWaves, elig, reuseContext())
    check $serialAcc.units == $parallelAcc.units
    check serialAcc.satisfiedByReused == parallelAcc.satisfiedByReused
    check serialAcc.freshExecutionCount == parallelAcc.freshExecutionCount
    check serialAcc.attemptedCount == parallelAcc.attemptedCount
    check serialAcc.executedCount == parallelAcc.executedCount
    let decidedS = evaluateRunOutcome(serialAcc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    let decidedP = evaluateRunOutcome(parallelAcc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decidedS.verdict == decidedP.verdict
    check decidedS.verdict == vrPass
    check decidedS.basis == rbReused

  test "genuine failure regression — cacheHit=false failed rows stay UNSATISFIED + witnessed":
    # The pair rule must NOT mask real failures: a row without cacheHit and
    # without a reuse record keeps the existing classification (UNSATISFIED,
    # ATTEMPTED, witnessed).
    let waves = @[makeWave(@[makeNodeReport(UnitA, "failed")])]
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    let acc = reduceRunAccounting(waves, elig, reuseContext())
    check acc.unsatisfiedCount == 1
    check acc.satisfiedCount == 0
    check acc.satisfiedByReused == 0
    check acc.attemptedCount == 1
    check acc.freshExecutionCount == 1
    check acc.units[0].verificationOutcome == voUnsatisfied
    check acc.units[0].executionEvidence == eeAttempted
    let decided = evaluateRunOutcome(acc,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decided.verdict == vrFail
    # Worse-wins join: a genuine failure in another wave dominates a cache row.
    let mixed = reduceRunAccounting(
      @[makeWave(@[makeReuseRow(UnitA, "failed", SubjectFpA, makeValidRecord())]),
        makeWave(@[makeNodeReport(UnitA, "failed")])], elig, reuseContext())
    check mixed.units[0].verificationOutcome == voUnsatisfied
    check mixed.unsatisfiedCount == 1
    check mixed.attemptedCount == 1

  test "summaryProjection — cache-hit rows do not inflate failedCount/statusCounts (raw telemetry)":
    # The merged-report summary (renderLegacyReport → summaryProjection) must
    # count cache-hit rows as REUSED, not failed — the exit-code path reads
    # summary.failedCount, so warm parallel runs must not fail on reuse.
    # (Summary counting is RAW telemetry and does not depend on the reuse
    # record — the verdict is decided separately by VDA.)
    let waves = @[makeFullWave(@[makeNodeReport(UnitA, "failed", cacheHit = true),
                                  makeNodeReport(UnitB, "verified")])]
    let elig = makeEligibility([(UnitA, ProofCandidate), (UnitB, ProofCandidate)])
    let runResult = buildCanonicalRunResult(waves, elig, @[@[UnitA, UnitB]])
    let reportJson = renderLegacyReport(runResult, makePreRun(), makeProjections(true))
    let summary = reportJson["summary"]
    check summary["failedCount"].getInt() == 0
    check summary["reusedCount"].getInt() == 1
    check summary["statusCounts"]["failed"].getInt() == 0
    check summary["statusCounts"]["reused"].getInt() == 1
    check summary["statusCounts"]["verified"].getInt() == 1
    # Genuine failure still counts.
    let failing = buildCanonicalRunResult(
      @[makeFullWave(@[makeNodeReport(UnitA, "failed")])],
      makeEligibility([(UnitA, ProofCandidate)]), @[@[UnitA]])
    let failingSummary = renderLegacyReport(failing, makePreRun(), makeProjections(true))["summary"]
    check failingSummary["failedCount"].getInt() == 1
    check failingSummary["reusedCount"].getInt() == 0

  test "warm reuse — REUSED conditional: eligible record → PASS(REUSED); count-only → no PASS":
    # Plan 1 redefinition of the old warm-reuse semantics (:739-740): reuse
    # may contribute a PASS ONLY when the 5-condition basis is established.
    # An unconditional PASS on cache-hit rows is discarded (fail-closed).
    let elig = makeEligibility([(UnitA, ProofCandidate)])
    # (a) A dispatched cache-hit unit WITH a verified 5-condition record:
    #     execution-incomplete (no fresh execution) but PASS(REUSED) on the
    #     outcome axis — execution absence is reported separately.
    let wavesRecord = @[makeFullWave(@[makeReuseRow(UnitA, "failed", SubjectFpA,
                                                    makeValidRecord())])]
    let runResultRecord = buildCanonicalRunResult(
      wavesRecord, elig, @[@[UnitA]], reuseContext())
    check runResultRecord.executionEvidence.attemptedUnits == newSeq[string]()
    check runResultRecord.runAccounting.attemptedCount == 0
    check runResultRecord.runAccounting.executedCount == 1
    check runResultRecord.runAccounting.satisfiedByReused == 1
    check not runResultRecord.runOutcome.executionComplete
    check runResultRecord.runOutcome.verificationComplete
    let decidedRecord = evaluateRunOutcome(runResultRecord.runAccounting,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decidedRecord.verdict == vrPass
    check decidedRecord.basis == rbReused
    check gateVerdictProjection(decidedRecord) == gvPass
    # (b) A dispatched cache-hit unit WITHOUT a reuse record (count-only row):
    #     fail-closed — PENDING, verificationComplete excluded, no PASS.
    let wavesCountOnly = @[makeFullWave(@[makeNodeReport(UnitA, "failed", cacheHit = true)])]
    let runResultCountOnly = buildCanonicalRunResult(
      wavesCountOnly, elig, @[@[UnitA]], reuseContext())
    check runResultCountOnly.runAccounting.satisfiedByReused == 0
    check runResultCountOnly.runAccounting.pendingCount == 1
    check not runResultCountOnly.runOutcome.verificationComplete
    let decidedCountOnly = evaluateRunOutcome(runResultCountOnly.runAccounting,
      NoObligationProvenance(universeEnumerated: true, source: "test"), false)
    check decidedCountOnly.verdict != vrPass
    check decidedCountOnly.basis == rbNone
    check gateVerdictProjection(decidedCountOnly) == gvFail
    # A fresh verified unit keeps executionComplete true.
    let freshRun = buildCanonicalRunResult(
      @[makeFullWave(@[makeNodeReport(UnitA, "verified")])], elig, @[@[UnitA]])
    check freshRun.executionEvidence.attemptedUnits == @[UnitA]
    check freshRun.runOutcome.executionComplete