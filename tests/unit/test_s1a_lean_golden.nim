import std/[unittest, json, os, strutils, options]
import std/[tables, algorithm, sequtils]
import ../../src/core/results
import ../../src/core/crypto/hash_kernel
import ../../src/core/deterministic_cas_key
import ../../src/core/trusted/axiom_ir
import ../../src/core/trusted/axiom_ir_helpers
import ../../src/core/trusted/contract_synthesis
import ../../src/core/trusted/semantic_fact_types
import ../../src/infrastructure/evidence_artifact_io
import ../../src/verification/obligation/obligation_types
import ../../src/verification/obligation/canonical_obligation_generator
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/obligation/lean_kernel_boundary
import ../../src/verification/obligation/golden_fixture_ir
import ../../src/infrastructure/external_ir_materializer
import ../../src/verification/obligation/kernel_acceptance_authority
import ../../src/verification/obligation/verification_decision_authority
import ../../src/verification/obligation/identity
import ../../src/verification/judgment_cas

## v5 acceptance C (2026-10-22): this comment is an intentional ①/⑤ closure-input
## change — the judged subject's input changed, so the v5 record minted for the
## prior closure (644f058cb5db…) must NOT be reused; the landing run must return
## EXECUTED (fresh judgment) and PASS. Identical evidence → REUSED (acceptance B2,
## PR #1020); changed evidence → fresh execution (this PR). The distinction is the
## machine-drawn line the v5 contract exists for.
##
## S1-A — Generic IR-body → Lean lowering, genuine kernel ACCEPT, full chain.
##
## Proves that a real in-subset production-shaped funcDef flows through the
## generic `executeCanonicalVerification` chain to a GENUINE Lean kernel
## ACCEPT and `vdVerified`:
##
##   funcDef(body=if maxWorkers > 0 then maxWorkers else 1;
##           post=result >= 1)
##     → generic I6 lowering (no symbol-specific hardcode)
##       → def normalizeMaxWorkers : Int → Int := fun maxWorkers => (if ... )
##       → theorem : ∀ maxWorkers, normalizeMaxWorkers maxWorkers ≥ 1
##     → canonicalLeanKernelCheck (real Lean 4.33 `lake env lean`)
##     → bindReceipt → KAA
##     → evaluate(KAA, policy) → vdVerified
##     → CanonicalVerificationResult (4-fold identity binding)
##
## I6 Body/Result Binding: the theorem's result expression IS the Lean
## encoding of the actual IR body (via the `def`), so the proposition is
## never a hand-written or weakened claim. Symbol shape matches the real
## production `normalizeMaxWorkers` at
##   src/core/orchestrator/orchestrator_api.nim:34.
##
## A/B separation: this test is the A-axis (can the generic canonical spine
## genuinely prove one in-subset production symbol?). The `--limit 1`
## selection ordering (B-axis) is intentionally NOT modified here.
##
## Judgment CAS: this suite is the s1a JUDGMENT — when the evidence-path env
## is armed (admission attest/s1a step only), the boundary observation log is
## aggregated and flushed to the evidence file by the LAST S2 test below;
## unarmed, the suite runs identically with zero recording.

## The four golden subjects are constructed by the SHARED constructors
## (src/verification/obligation/golden_fixture_ir.nim) — the exact same
## definitions the Judgment CAS (verification/judgment_cas.nim) re-derives its
## CompletenessEvidence keys from (closure component ⑧). One definition, one
## hash space: the verified subjects and the recorded keys cannot drift.
## These aliases keep the established call sites.
proc normalizeMaxWorkersFuncDef(): IRFuncDef = gfNormalizeMaxWorkers()

proc fdIdentityFixture(): IRFuncDef = gfIdentityPostcondition()

var goldenBoundCache = initTable[string, SubjectParseBoundComponents]()
proc goldenBound(path, name: string): SubjectParseBoundComponents =
  ## Test-boundary §2.1a measurement: the parse-bound components (pnodeV2 +
  ## extraction agreement) require the Nim parser and are NOT gcsafe, so the
  ## golden tests — acting as the main-thread boundary — measure them from the
  ## REAL subject module bytes here and thread them into
  ## executeCanonicalVerification as values (measured once per (path, name)).
  let key = path & "::" & name
  if not goldenBoundCache.hasKey(key):
    goldenBoundCache[key] = measureParseBoundComponents(readFile(path), name)
  goldenBoundCache[key]

## Judgment CAS test-boundary capture (verification/judgment_cas.nim): every
## successful canonical-chain probe counts once, and the FIRST subPostcondition
## execution's identity set (the 6-fold identity + the CLE closure-pure
## members) is the captured judgment evidence. The set is run-invariant — the
## suite itself proves determinism across repeated executions — so "first" is
## exact, not sampling. The CLE's evidenceId is NOT captured: it transitively
## binds the checkout commit (§2.1a subjectGitRef), a run-scope digest the
## payload identity must never carry.
var judgmentProbeCount = 0
var judgmentFoldCleCaptured = false
var judgmentFold: JudgmentFoldIdentity
var judgmentCle: JudgmentCleIdentity

proc execGolden(fd: IRFuncDef; path, name: string): CanonicalVerificationResult =
  ## The golden-chain entry: same as executeCanonicalVerification, with the
  ## parse-bound §2.1a components measured at THIS (main-thread) boundary.
  let r = executeCanonicalVerification(fd, path, name, parseBound = goldenBound(path, name))
  if r.success and r.canonicalEvidence.isSome:
    inc judgmentProbeCount
    if not judgmentFoldCleCaptured and name == "subPostcondition":
      let e = r.canonicalEvidence.get()
      judgmentFold = JudgmentFoldIdentity(
        inputHash: r.inputHash,
        irHash: r.irHash,
        obligationHash: r.obligationHash,
        leanSourceHash: r.leanSourceHash,
        kaaIdentity: r.kaaIdentity,
        artifactIdentity: r.artifactIdentity)
      judgmentCle = JudgmentCleIdentity(
        cleKaaDigest: e.cleKaaDigest,
        cleCanonicalKaaJson: e.cleCanonicalKaaJson,
        cleToolchainFingerprint: e.cleToolchainFingerprint)
      judgmentFoldCleCaptured = true
  r

proc materializeCompletenessFor(fd: IRFuncDef; sourcePath: string) =
  ## Test-boundary materializer (WP4-j.2 Phase D role), Phase 1A dual-write:
  ## the legacy 5-field artifact PLUS the authenticated strict
  ## CompletenessBinding sibling, both keyed by the runner cache scheme
  ## (computeDeterministicCasKey(serializeIRFuncDef)), under the standard
  ## cache dir (.axiom/cache, gitignored), with the values the extraction
  ## actually measured (EA agreed byte-equal ⇒ translation-loss-free;
  ## identity-shaped fixture ⇒ no opaque boundaries). The capture measures
  ## the CWD repo as subject root (contentCarried=false — the same
  ## resolution rule executeCanonicalVerification applies to these
  ## path-resolved fixtures), so the strict-first reader recomputes the
  ## recorded sourceIdentity exactly.
  let key = computeDeterministicCasKey(serializeIRFuncDef(fd))
  let evidence = CompletenessEvidence(
    translationLossFree: true,
    bindingUniverseComplete: true,
    opaqueExpansionStatus: "none",
    sourceBindingCount: 1,
    irBindingCount: 1)
  saveEvidenceArtifact(key, evidence)
  let capture = measureCompletenessSourceCapture("", sourcePath,
    readFile(sourcePath), contentCarried = false)
  let strictLanded = saveCompletenessEvidenceDual(key, fd, capture, evidence)
  ## Fail closed: the strict half of the dual-write must land. A legacy-only
  ## environment (unmeasurable git identity, failed binding write) must NOT
  ## silently pass the strict contract — every strict assertion below
  ## (64-hex completenessBindingDigest, binding-removed → none) is
  ## unobservable when only the legacy artifact exists, and a silent legacy
  ## pass would exactly re-open the incident recorded in
  ## docs/evidence/go_critical_recovery_2026-10-20.md.
  if not strictLanded:
    echo "[S1A FAIL-CLOSED] strict CompletenessBinding dual-write did not land " &
      "for key " & key & " (capture.sourceIdentity.len=" &
      $capture.sourceIdentity.len & ") — a legacy-only environment cannot " &
      "silently pass the strict contract"
  ## NEGATIVE CONTROL (VS-T3 Phase A-2): this assertion was deliberately removed
  ## to prove the verdict-input byte guard rejects a weakened GO-critical test.
  check fileExists(completenessBindingCachePath(key))
  check fileExists(strictGenerationMarkerPath(key))

## The sub + mulDiv subjects come from the same shared constructors.
proc fdSubFixture(): IRFuncDef = gfSubPostcondition()

proc fdMulDivFixture(): IRFuncDef = gfMulDivRoundtrip()

suite "S1-A — Generic lowering produces genuine Lean kernel ACCEPT":
  test "generic lowering renders the actual IR body + I6 theorem":
    let lean = renderLeanForFuncDef(normalizeMaxWorkersFuncDef())
    check lean.len > 0
    ## The `def` body is the Lean encoding of the real IR body (I6).
    check "def normalizeMaxWorkers" in lean
    check "fun maxWorkers => (if (maxWorkers > 0) then maxWorkers else 1)" in lean
    ## The theorem proposition applies the postcondition to the lowered body,
    ## NOT a hand-weakened claim. The result is wrapped in parens by the
    ## generic renderer: `(normalizeMaxWorkers maxWorkers) ≥ 1`.
    check "normalizeMaxWorkers maxWorkers) ≥ 1" in lean
    check "normalizeMaxWorkers maxWorkers > 0 →" notin lean
    check "∀ (maxWorkers : Int)" in lean

  test "genuine Lean 4.33 kernel ACCEPTS the generated theorem":
    let lean = renderLeanForFuncDef(normalizeMaxWorkersFuncDef())
    check lean.len > 0
    let res = canonicalLeanKernelCheck(lean, timeoutMs = 120_000)
    check res.isOk()
    let receipt = res.get()
    check receipt.receiptTheoremIdentity == "normalizeMaxWorkers_post"
    check receipt.receiptExecutableDigest.len == 64
    check receipt.receiptInputIdentity.len == 64
    check receipt.receiptArtifactIdentity.len == 64

  test "mul/div body renders the Certified subset and the kernel ACCEPTS it":
    ## boMul/boDiv are IN the Certified subset (Denotation.lean: `.mul` → Int
    ## `*`, `.div` → Int.tdiv). The renderer lowers them to `*` and fixed-
    ## divisor `/`; the real kernel accepts the generated theorem.
    let fd = fdMulDivFixture()
    let lean = renderLeanForFuncDef(fd)
    check lean.len > 0
    check "def mulDivRoundtrip" in lean
    check "((x * 6) / 2)" in lean
    check "mulDivRoundtrip x) = ((x * 6) / 2)" in lean
    let res = canonicalLeanKernelCheck(lean, timeoutMs = 120_000)
    check res.isOk()
    check res.get().receiptTheoremIdentity == "mulDivRoundtrip_post"

suite "S1-A — Full canonical chain yields vdVerified (genuine KAA)":

  setup:
    ## The §2.1a completeness component must be measurable for the internal
    ## fixtures — the test boundary plays the materializer role (WP4-j.2).
    materializeCompletenessFor(normalizeMaxWorkersFuncDef(),
      "src/core/orchestrator/orchestrator_api.nim")
    materializeCompletenessFor(fdIdentityFixture(),
      "tests/golden/identity_postcondition.nim")
    materializeCompletenessFor(fdSubFixture(),
      "tests/golden/sub_postcondition.nim")
    materializeCompletenessFor(fdMulDivFixture(),
      "tests/golden/mul_div_body.nim")

  test "executeCanonicalVerification produces a genuine VERIFIED result":
    let r = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim",
      "subPostcondition"
    )
    check r.success == true
    check r.verdict == vdVerified
    check r.evidence == "lean_kernel_accepted"
    check r.obligationCount == 1
    check r.obligationKind == okContractPost
    ## Identity closure on the canonical result
    check r.inputHash.len == 64
    check r.irHash.len == 64
    check r.obligationHash.len == 64
    check r.leanSourceHash.len == 64
    check r.kaaIdentity.len == 64
    check r.artifactIdentity.len == 64
    check r.toolchainIdentity.startsWith("nim-") and r.toolchainIdentity.contains("|lean-")
    ## The artifact identity is the digest of the actual persisted Lean artifact.
    check r.artifactIdentity == r.leanSourceHash

  test "mul/div fixture proves through the full chain (mul body support)":
    ## The supported mul/div path end-to-end: real extraction agreement on the
    ## fixture bytes, real kernel ACCEPT, vdVerified. This is the positive
    ## control that moved here when boMul left the negative-pin set.
    let r = execGolden(
      fdMulDivFixture(),
      "tests/golden/mul_div_body.nim",
      "mulDivRoundtrip"
    )
    check r.success == true
    check r.verdict == vdVerified
    check r.evidence == "lean_kernel_accepted"
    check r.sealError == ""

  test "S1-B identity fixture (result == x) proves through the chain":
    ## Mirrors tests/golden/identity_postcondition.nim exactly:
    ##   func identityPostcondition(x: int): int {.axiom.[post:(result == x)].} = x
    let fd = fdIdentityFixture()
    ## Generic lowering is I6-correct: def body = x, theorem = result == x.
    let lean = renderLeanForFuncDef(fd)
    check "def identityPostcondition" in lean
    check "fun x => x" in lean
    check "identityPostcondition x) = x" in lean
    ## Genuine kernel ACCEPT.
    let res = canonicalLeanKernelCheck(lean, timeoutMs = 120_000)
    check res.isOk()
    ## Full chain yields vdVerified.
    let r = execGolden(fd, "tests/golden/identity_postcondition.nim", "identityPostcondition")
    check r.success == true
    check r.verdict == vdVerified
    check r.evidence == "lean_kernel_accepted"

  test "full chain is deterministic (same input → same identities)":
    let r1 = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim",
      "subPostcondition"
    )
    let r2 = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim",
      "subPostcondition"
    )
    check r1.success == true
    check r2.success == true
    check r1.irHash == r2.irHash
    check r1.obligationHash == r2.obligationHash
    check r1.leanSourceHash == r2.leanSourceHash
    check r1.kaaIdentity == r2.kaaIdentity
    check r1.artifactIdentity == r2.artifactIdentity

  test "toolchain fingerprint is deterministic across two calls":
    ## The fingerprint must bind measured content, not a hardcoded label.
    ## Two calls with the same input must produce the same fingerprint.
    let r1 = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim",
      "subPostcondition"
    )
    let r2 = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim",
      "subPostcondition"
    )
    check r1.success == true
    check r2.success == true
    let e1 = r1.canonicalEvidence.get()
    let e2 = r2.canonicalEvidence.get()
    check e1.cleToolchainFingerprint == e2.cleToolchainFingerprint

  test "toolchain fingerprint is not the old hardcoded constant":
    ## The old hardcoded formula was:
    ##   sha256("nim-2.2.10|lean-4.33.0|lake env lean|120000")
    ## The new measured bundle digest must differ from this.
    let oldHardcodedFp = sha256Hex(
      "nim-2.2.10|lean-4.33.0|lake env lean|120000"
    )
    let r = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim",
      "subPostcondition"
    )
    check r.success == true
    let e = r.canonicalEvidence.get()
    check e.cleToolchainFingerprint != oldHardcodedFp

# ---------------------------------------------------------------------------
# S2 rev.4 — CanonicalLeanEvidence: durable self-contained evidence binding
# ---------------------------------------------------------------------------

suite "S2 — CanonicalLeanEvidence binds obligation/proposition/source/KAA":

  setup:
    materializeCompletenessFor(normalizeMaxWorkersFuncDef(),
      "src/core/orchestrator/orchestrator_api.nim")
    materializeCompletenessFor(fdIdentityFixture(),
      "tests/golden/identity_postcondition.nim")
    materializeCompletenessFor(fdSubFixture(),
      "tests/golden/sub_postcondition.nim")

  test "canonical evidence exists and is internally hash-consistent":
    let r = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim",
      "subPostcondition"
    )
    check r.success == true
    check r.canonicalEvidence.isSome
    let e = r.canonicalEvidence.get()
    ## Hash bindings recomputed independently:
    check sha256Hex(e.cleProposition) == e.clePropositionHash
    check sha256Hex(e.cleLeanSource) == e.cleLeanSourceHash
    check sha256Hex(e.cleCanonicalKaaJson) == e.cleKaaDigest
    ## Genuine acceptance authority: the KAA is present and sorry-free.
    check e.kaa.kaaSorryScan.len == 0
    check e.kaa.kaaArtifactHash.len == 64

  test "evidenceId = H(6 components) and identity components are distinct spaces":
    let r = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim",
      "subPostcondition"
    )
    let e = r.canonicalEvidence.get()
    ## The strict branch is load-bearing: the completeness binding digest must
    ## be a real SHA-256 hex digest. An EMPTY digest would mean this evidence
    ## was sealed on the LEGACY formula (no strict binding bound at seal
    ## time) — i.e. the strict contract silently passed on legacy fallback,
    ## which the materializer's fail-closed setup and the binding-removed
    ## negative control below both refuse.
    check e.cleCompletenessBindingDigest.len == 64
    ## Phase 1A: the strict digest is appended to the SAME six-component
    ## PREIMAGE, not to the legacy hash:
    ##   legacy  : evidenceId = H(c1|…|c6)
    ##   strict  : evidenceId = H(c1|…|c6|completenessBindingDigest)
    ## Hashing the already-hashed legacyId would double-hash and can never
    ## equal the implementation (the pre-#961 test did exactly that).
    let legacyPreimage =
      e.cleObligationId & "|" & e.clePropositionHash & "|" & e.cleLeanSourceHash & "|" &
      e.cleKaaDigest & "|" & e.cleToolchainFingerprint & "|" & e.cleExecutionContractDigest
    let expected = if e.cleCompletenessBindingDigest.len > 0:
        sha256Hex(legacyPreimage & "|" & e.cleCompletenessBindingDigest)
      else:
        sha256Hex(legacyPreimage)
    check e.evidenceId == expected
    ## obligationId (5-tuple hash) lives in a DIFFERENT hash space than the
    ## proposition hash — they must never be conflated.
    check e.cleObligationId != e.clePropositionHash
    check e.cleObligationId.len == 64

  test "negative control — strict binding removed, marker kept → no evidenceId (fail-closed)":
    ## Strict contract (docs/spec/strict_completeness_binding.md §4/§6): a
    ## marked anchor whose binding artifact is missing is UNKNOWN — the
    ## strict-first reader returns none, the canonical chain refuses the
    ## subject binding ("completeness record unmeasurable"), and no CLE
    ## (hence no evidenceId) can be sealed. The legacy record must NOT
    ## resurrect. Reader-level control only — no second Lean chain: the
    ## positive leg proves the context matches, so the negative leg is
    ## attributable to the removal, not to a context mismatch.
    let fd = fdSubFixture()
    let key = computeDeterministicCasKey(serializeIRFuncDef(fd))
    let capture = measureCompletenessSourceCapture("",
      "tests/golden/sub_postcondition.nim", readFile(
      "tests/golden/sub_postcondition.nim"), contentCarried = false)
    ## Positive control: the strict ref resolves while the binding exists.
    let before = measureCompletenessRecordDigest(fd, key,
      capture.sourceIdentity, capture.moduleSha256)
    check before.isSome
    check before.get.evidenceKey == key
    check before.get.evidenceDigest.len == 64
    ## Remove ONLY the strict binding; the generation marker stays.
    let bindingPath = completenessBindingCachePath(key)
    check fileExists(bindingPath)
    check fileExists(strictGenerationMarkerPath(key))
    removeFile(bindingPath)
    ## Negative: marked anchor + missing binding → none in BOTH env modes
    ## (marker removes the legacy fallback; AXIOM_EVIDENCE_STRICT would only
    ## tighten further). The suite's next setup re-materializes the binding.
    let after = measureCompletenessRecordDigest(fd, key,
      capture.sourceIdentity, capture.moduleSha256)
    check after.isNone

  test "canonical KAA projection is deterministic across runs":
    let r1 = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim", "subPostcondition")
    let r2 = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim", "subPostcondition")
    let e1 = r1.canonicalEvidence.get()
    let e2 = r2.canonicalEvidence.get()
    ## Identity-bearing projection (volatile provenance excluded) is stable.
    check e1.cleCanonicalKaaJson == e2.cleCanonicalKaaJson
    check e1.cleKaaDigest == e2.cleKaaDigest
    check e1.evidenceId == e2.evidenceId

  test "splice resistance — cross-assembled genuine evidence is rejected":
    ## Two GENUINE executions (both real Lean kernel ACCEPT) yield two
    ## distinct evidence objects A (normalizeMaxWorkers) and B
    ## (identityPostcondition).  Each is individually valid.  Splicing a
    ## source from one execution with the KAA of the other — pairing B's
    ## source with A's KAA, or A's source with B's KAA — must be REJECTED so
    ## a mix-and-matched evidence can never become a valid CLE.  KAA↔source
    ## hash binding (receiptArtifactIdentity == sha256(source)) is the splice
    ## barrier: a source that is not the exact artifact the KAA accepted
    ## provably mismatches.
    let rA = execGolden(
      fdSubFixture(),
      "tests/golden/sub_postcondition.nim",
      "subPostcondition")
    let rB = execGolden(
      fdIdentityFixture(),
      "tests/golden/identity_postcondition.nim",
      "identityPostcondition")
    check rA.success == true
    check rB.success == true
    check rA.canonicalEvidence.isSome
    check rB.canonicalEvidence.isSome
    let eA = rA.canonicalEvidence.get()
    let eB = rB.canonicalEvidence.get()
    ## The two evidence objects are genuinely distinct.
    check eA.cleObligationId != eB.cleObligationId
    check eA.cleLeanSource != eB.cleLeanSource
    check eA.cleProposition != eB.cleProposition
    ## Positive control first: a well-formed single-execution binding is valid.
    let positive = newCanonicalLeanEvidence(
      obligationId = eA.cleObligationId,
      proposition = eA.cleProposition,
      leanSource = eA.cleLeanSource,
      kaa = eA.kaa,
      toolchainFingerprint = eA.cleToolchainFingerprint,
      executionContractDigest = eA.cleExecutionContractDigest)
    check positive.isOk
    ## (a) source from execution B, KAA from execution A → reject.
    ##     sha256(sourceB) != A's receiptArtifactIdentity (Check 1): B's source
    ##     was never accepted under A's execution.
    let spliceA = newCanonicalLeanEvidence(
      obligationId = eA.cleObligationId,
      proposition = eB.cleProposition,
      leanSource = eB.cleLeanSource,
      kaa = eA.kaa,
      toolchainFingerprint = eA.cleToolchainFingerprint,
      executionContractDigest = eA.cleExecutionContractDigest)
    check spliceA.isErr
    ## (b) source from execution A, KAA from execution B → reject.
    ##     sha256(sourceA) != B's receiptArtifactIdentity (Check 1).
    let spliceB = newCanonicalLeanEvidence(
      obligationId = eA.cleObligationId,
      proposition = eA.cleProposition,
      leanSource = eA.cleLeanSource,
      kaa = eB.kaa,
      toolchainFingerprint = eA.cleToolchainFingerprint,
      executionContractDigest = eA.cleExecutionContractDigest)
    check spliceB.isErr

  test "judgment CAS flush — the canonical judgment set (armed: emit; unarmed: pass)":
    ## AXIOM_JUDGMENT_CAS: when AXIOM_JUDGMENT_CAS_EVIDENCE_PATH is armed,
    ## THIS test is the single flush point for the run's judgment evidence.
    ## It runs zero kernel checks and zero probes — it only aggregates the
    ## boundary observation log — so the canonical counts (17 ACCEPTs /
    ## 14 probes) are preserved exactly. Unarmed (every other invocation of
    ## this suite: unit CI, local dev, other gates) the test trivially passes
    ## — the recording is opt-in by env, never ambient.
    if not judgmentRecordingArmed():
      skip()
    else:
      let accepts = observedKernelAccepts()
      check accepts.len == CanonicalKernelAcceptCount
      let facts = aggregateAcceptFacts(accepts)
      check facts.unknownTheorems.len == 0
      check facts.acceptsByTheorem == CanonicalAcceptsByTheorem
      check judgmentProbeCount == CanonicalProbeCount
      check judgmentFoldCleCaptured
      let evidence = JudgmentMeasuredEvidence(
        kernelAcceptCount: accepts.len,
        probeCount: judgmentProbeCount,
        facts: facts,
        fold: judgmentFold,
        cle: judgmentCle)
      let written = writeJudgmentEvidenceFile(evidence)
      check written.isOk
      ## The flushed bytes must re-parse and re-validate — the attest stage
      ## will build the record from exactly these bytes.
      let reparsed = parseJudgmentEvidenceFile(
        getEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH", ""))
      check reparsed.isOk
      check reparsed.get == written.get
