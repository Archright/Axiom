import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/os
import std/options
import std/sets
import std/strutils
import std/tables

when fileExists("src/generated/build_env.nim"):
  import generated/build_env
else:
  const BuildEnvZ3Version = "unavailable"

import core/asset_collector
import core/axiom_pragmas
import core/heal_types
import core/json/json_utils
import core/json/std_redirect
import core/judge/smart_search
import core/proof/source_fingerprint
import core/results
import core/release/version_derive
import core/trusted/fingerprint_generator
import core/trusted/claim_authority
import core/trusted/scope_identity
import core/trusted/semantic_profile
import core/trusted/trust_commit
import core/crypto/hash_kernel
import core/provenance_guard
import core/types/certificate_types
import core/types/verification_tier
import core/utils/io_utils
import core/trusted/claim_projection
import core/trusted/assurance_profile  ## S2: VerificationOutcomeRef (clProved consistency gate)

import verification/certificate_identity
import verification/certificate_manager
import verification/cert_vault_role
import verification/obligation/obligation_ir
import verification/obligation/kernel_acceptance_authority
import verification/canonical_certificate_payload
import verification/canonical_json
import verification/rust_obligation_render
import verification/attestation_orchestrator  # verifierToolchainIdentityJson — measured writer/pin composition (Phase 1B)
import infrastructure/certificate_attestation

proc lookupIsKernel*(functionName: string): bool {.raises: [].} =
  if registryLookup.contains(functionName):
    try:
      return registryLookup[functionName].isKernel
    except KeyError:
      return false
  false

func solverHasExecuted(solverStatus, smtlib2: string): bool {.raises: [].} =
  ## True ONLY when a real solver interaction produced the recorded result:
  ## a non-empty solver status (not "skipped") AND an actual solver input
  ## payload. A non-empty status with empty smtlib2 is the structural/heuristic
  ## path (no solver execution) — recording z3Executed=true there would fabricate
  ## solver evidence (Step-④ evidence: sha256("") input digest with z3Executed).
  solverStatus.len > 0 and solverStatus != "skipped" and smtlib2.len > 0

func stripInjectedCommentBlock(sourceCode: string): string {.raises: [].} =
  ## S2 fix: request_builder prepends a "## CEGAR-derived invariants:" comment
  ## block to the module source for downstream personas. The certificate's
  ## sourceHash must identify the REAL on-disk module, not the enriched copy —
  ## otherwise the stale-cert gate (and any external verifier) sees a hash of
  ## content that exists nowhere in the repository. Strip the injected block
  ## before fingerprinting; pass-through when absent.
  if not sourceCode.startsWith("## CEGAR-derived invariants:"):
    return sourceCode
  var inBlock = true
  var lines: seq[string]
  for line in sourceCode.splitLines():
    if inBlock and (line.len == 0 or line.startsWith("##")):
      continue  # still inside the injected comment block
    inBlock = false
    lines.add(line)
  return lines.join("\n") & (if sourceCode.endsWith("\n"): "\n" else: "")

proc canonicalInputSource(modulePath, sourceCode: string): string {.raises: [].} =
  ## Truthful source identity (S2 fix): the pipeline mutates the in-memory
  ## module copy (CEGAR comment-block prepending, extracted-pure body
  ## injection). The certificate's sourceHash must identify the REAL
  ## repository module — the canonical input that the stale-cert gate and
  ## external verifiers check against — not an analysis-mutated copy.
  ## Prefer the on-disk module; fall back to the in-memory copy only when the
  ## module file is not readable (e.g. synthetic test inputs).
  try:
    if modulePath.len > 0 and fileExists(modulePath):
      return readFile(modulePath)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch) — fallback to in-memory copy
  stripInjectedCommentBlock(sourceCode)

# ─── Phase 1B: strict completeness contract fields ──────────────────────────
## Integration seam with the producer branch: CanonicalLeanEvidence carries the
## strict completeness binding anchor set (completenessEvidenceKey /
## completenessBindingDigest / completenessPayloadDigest) with the producer
## that dual-writes the strict binding artifacts. The accessors below resolve
## the merged spelling at COMPILE time (`when compiles` probes both the plain
## accessor and the cle-prefixed accessor convention of this module); until the
## producer branch merges they return "" and the writer honestly emits a legacy
## certificate (no strict marker) — the admission side fail-closes on strict
## claims, so nothing is silently admitted.
func evidenceCompletenessEvidenceKey(e: CanonicalLeanEvidence): string {.raises: [].} =
  when compiles(e.completenessEvidenceKey): e.completenessEvidenceKey
  elif compiles(e.cleCompletenessEvidenceKey): e.cleCompletenessEvidenceKey
  else: ""
func evidenceCompletenessBindingDigest(e: CanonicalLeanEvidence): string {.raises: [].} =
  when compiles(e.completenessBindingDigest): e.completenessBindingDigest
  elif compiles(e.cleCompletenessBindingDigest): e.cleCompletenessBindingDigest
  else: ""
func evidenceCompletenessPayloadDigest(e: CanonicalLeanEvidence): string {.raises: [].} =
  when compiles(e.completenessPayloadDigest): e.completenessPayloadDigest
  elif compiles(e.cleCompletenessPayloadDigest): e.cleCompletenessPayloadDigest
  else: ""

func uapScopeDigest(modulePath, functionName, sourceCode, irHash: string): string {.raises: [].} =
  hash_kernel.sha256Hex([modulePath, functionName, sourceCode, irHash].join("|"))

func uapConfigDigest(
  modulePath, functionName, leanProposition, solverStatus, semanticProfileId, irHash: string
): string {.raises: [].} =
  let profileIdentity = if semanticProfileId.len > 0: semanticProfileId else: "SPV1"
  let scopeLockHash = hash_kernel.sha256Hex([
    modulePath,
    functionName,
    solverStatus,
    irHash,
    leanProposition,
    profileIdentity
  ].join("|"))
  configIdentityDigest(profileIdentity, scopeLockHash)

func z3outClaimJson(
  solverStatus: string;
  leanKernelVerified, negativeTestResult, vacuityProven: bool;
  solverVersion, solverProvenance, smtlib2, irHash, leanProposition: string
): string {.raises: [].} =
  canonical_json.canonicalJsonString(%*{
    "kind": "z3out",
    "solverStatus": solverStatus,
    "leanCompilerVerified": leanKernelVerified,
    "negativeTestResult": negativeTestResult,
    "vacuityChecked": true,
    "vacuityProven": vacuityProven,
    "solverVersion": solverVersion,
    "solverProvenance": solverProvenance,
    "z3Executed": solverHasExecuted(solverStatus, smtlib2),
    "irHash": irHash,
    "leanProposition": leanProposition,
    "smtlib2": smtlib2
  })

func z3outTrustCommit*(
  modulePath, functionName, solverStatus, leanProposition, semanticProfileId: string;
  leanKernelVerified, negativeTestResult, vacuityProven: bool;
  smtlib2, irHash: string
): TrustCommit {.raises: [].} =
  let claim = z3outClaimJson(
    solverStatus, leanKernelVerified, negativeTestResult, vacuityProven,
    BuildEnvZ3Version, (if solverStatus == "unsat": "spZ3SAT" else: "spHeuristic"),
    smtlib2, irHash, leanProposition)
  let certificateDigest = hash_kernel.sha256Hex(claim)
  TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: computeEvidenceId(claim, "z3out", certificateDigest),
    claim: claim,
    solverInvocation: "z3out",
    attestation: "Z3 solver result payload captured in TrustCommit journal",
    certificateDigest: certificateDigest,
    scopeDigest: certificateScopeDigestForPair(modulePath, functionName),
    configDigest: certificateConfigDigestForPair(
      modulePath, functionName, solverStatus, irHash, leanProposition, semanticProfileId),
    parentCommit: none(string)
  )

func v2ClaimJson(claim: VerifiedClaim; semanticProfileId: string): string {.raises: [].} =
  canonical_json.canonicalJsonString(v2Projection(claim, semanticProfileId))

func v2VerifiedTrustCommit*(
  claim: VerifiedClaim; semanticProfileId, modulePath, functionName, solverStatus, irHash: string
): TrustCommit {.raises: [].} =
  let claimStr = v2ClaimJson(claim, semanticProfileId)
  let certificateDigest = hash_kernel.sha256Hex(claimStr)
  TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: computeEvidenceId(claimStr, "v2-verified", certificateDigest),
    claim: claimStr,
    solverInvocation: "v2-verified",
    attestation: "CertificateV2 claim projection captured in TrustCommit journal",
    certificateDigest: certificateDigest,
    scopeDigest: certificateScopeDigestForPair(modulePath, functionName),
    configDigest: certificateConfigDigestForPair(
      modulePath, functionName, solverStatus, irHash, claim.semanticProfileId, semanticProfileId),
    parentCommit: none(string)
  )

proc commitTrustCommitRecord(logLines: var seq[string]; baseDir: string; c: TrustCommit): bool {.raises: [CatchableError].} =
  let res = commitVerification(baseDir, c)
  if res.ok:
    logLines.add("  -> TrustCommit committed: " & c.solverInvocation)
    true
  else:
    logLines.add("  -> [Warning] TrustCommit rejected for " & c.solverInvocation & ": " & res.error)
    false

type
  ExistingCertificateState = object
    verifiedStatus: string
    leanArtifactHash: string
    solverProvenance: SolverProvenance
func canOverwriteProvenance(existing, incoming: SolverProvenance): bool {.used.} =
  ## Provenance vault guard: never downgrade solver confidence.
  ## Z3SAT > SpacerCHC > Heuristic.
  existing <= incoming

# ─── Phase 4A: VerificationTier → CertificateStatus bridge ──────────────
## The 1-arg `tierToCertStatus` / `tierToStatusString` are canonical in
## core/types/certificate_types.nim (B2 mapping: Z3-only/K-induction →
## certZ3Candidate, never verified). Do NOT redefine them here — a second
## definition creates ambiguous-call breakage for every module importing
## both. Only the well-formed/safety-aware 3-arg overload lives here.

func tierToCertStatus*(tier: VerificationTier,
                        isWellFormed: bool,
                        isSafetyVerified: bool): CertificateStatus =
  if isSafetyVerified:
    certSafetyVerified
  elif isWellFormed:
    certWellFormed
  else:
    tierToCertStatus(tier)

proc writeCertificateFromUapResult*(
  certDir: string;
  modulePath: string;
  functionName: string;
  sourceCode: string;
  leanKernelVerified: bool;
  smtlib2: string;
  solverStatus: string;
  logLines: var seq[string];
  vacuityProven: bool = false;
  irHash: string;
  leanProposition: string = "";
  negativeTestResult: bool = false;
  verifiedClaim: Option[VerifiedClaim] = none(VerifiedClaim);
  semanticProfileId: string = "";
  axiomVersion: string = axiomVersionWithPrefix;
  obligationVerdict: Option[ObligationGenerationResultKind] = none(ObligationGenerationResultKind);
  kaa: Option[KernelAcceptanceAttestation] = none(KernelAcceptanceAttestation);
  evidence: Option[CanonicalLeanEvidence] = none(CanonicalLeanEvidence);
  rustBoundedClaim: Option[RustBoundedClaim] = none(RustBoundedClaim)
): bool {.axiomDecision(id = "DECISION-0628", reason = "Write guard for canonical path enforced before UAP certificate writing", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32"), raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect], axiomDebt: "DEBT#447".} =
  doAssert irHash.len > 0, "CAVA Integrity Violation: irHash cannot be empty"
  let canonicalDir = resolveCertificate(cvCanonicalRead)
  let runtimeCanonicalDir = resolveCertificate(cvRuntimeCanonical)
  if (certDir.startsWith(canonicalDir) or certDir.startsWith(runtimeCanonicalDir)) and not promotionActive:
    raise newException(CatchableError, "DIRECT CANONICAL WRITE FORBIDDEN — must go through explicit promotion context (set promotionActive=true or use --promote flag)")
  try:
    # ─── S2 rev.4: CanonicalLeanEvidence fail-closed guards ─────────────────
    # The writer is a serializer + consistency gate — NEVER a verdict authority.
    # Any invariant violation here REJECTS the write (fail-closed); already-
    # verified evidence is never silently demoted or repaired. The evidence's
    # hash bindings were self-validated at factory time; we recompute them here
    # so a corrupted in-memory object can never reach durable storage.
    var ev = none(CanonicalLeanEvidence)
    if evidence.isSome:
      let e = evidence.get()
      if sha256Hex(e.cleLeanSource) != e.cleLeanSourceHash:
        raise newException(CatchableError, "S2 evidence invariant violated: leanSourceHash != H(leanSource)")
      if sha256Hex(e.cleProposition) != e.clePropositionHash:
        raise newException(CatchableError, "S2 evidence invariant violated: propositionHash != H(proposition)")
      if sha256Hex(e.cleCanonicalKaaJson) != e.cleKaaDigest:
        raise newException(CatchableError, "S2 evidence invariant violated: kaaDigest != H(canonicalKaa)")
      if e.kaa.kaaSorryScan.len > 0:
        raise newException(CatchableError, "S2 evidence invariant violated: sorry present in accepted artifact")
      ev = evidence
    # ─── Phase 2-E: Rust extraction-bounded claim gate (plan 정정 14) ───────
    # A RUST success certificate may only carry extraction-bounded claims:
    # (i) the accepted artifact must be a member of the closed renderer
    #     template family (skeleton allowlist) — a free/unrecognized
    #     proposition is refused at mint, never written;
    # (ii) proposition ↔ obligation ↔ RustCanonical digests must co-bind —
    #     the persisted proposition must be byte-identical to the accepted
    #     source's own proposition, the claim's canonical digest must equal
    #     this certificate's irHash, and the obligation digest must recompute
    #     (the Rust mirror of the S2 propositionHash guard above and the
    #     lean_evidence mismatch rejections);
    # (iii) the extractor identity recorded at extraction time must equal the
    #     CURRENT pinned reference extractor (kernel_acceptance_authority's
    #     mint-time fingerprint refusal pattern).
    # The gate is Rust-specific BY CONSTRUCTION: it arms only when the caller
    # passes a claim (the Rust lane) — the Nim lane never does, so its
    # behavior is byte-identical to before. No canonical evidence behind the
    # claim (no accepted artifact) refuses too — an accepted artifact is the
    # only thing the claim is allowed to bind.
    if rustBoundedClaim.isSome:
      let claim = rustBoundedClaim.get()
      let gateLeanSource = if ev.isSome: ev.get().cleLeanSource else: ""
      var gateRefusal = rustBoundedClaimRefusal(claim, irHash,
                                                leanProposition,
                                                gateLeanSource)
      if gateRefusal.len == 0:
        gateRefusal = rustExtractorIdentityRefusal(claim.extractorIdentity)
      if gateRefusal.len > 0:
        raise newException(CatchableError,
          "Rust bounded-claim gate refused issuance: " & gateRefusal)
    # Consistency gate (no verdict synthesis): a claim-derived certProved
    # outcome REQUIRES canonical evidence backing this run. Mismatch = reject.
    if verifiedClaim.isSome and verifiedClaim.get().outcome == clProved and ev.isNone:
      raise newException(CatchableError, "S2 consistency gate: clProved claim without CanonicalLeanEvidence")
    # Effective KAA: explicit param wins; evidence carries the same KAA.
    let kaaEff = if kaa.isSome: kaa elif ev.isSome: some(ev.get().kaa)
                 else: none(KernelAcceptanceAttestation)
    if not dirExists(certDir):
      discard existsOrCreateDirOpt(certDir)
    var certJson = newJObject()
    certJson["modulePath"] = newJString(modulePath)
    certJson["functionName"] = newJString(functionName)
    certJson["fingerprint"] = newJString(computeVerificationFingerprint(irHash, leanProposition))
    certJson["sourceHash"] = newJString(computeStableSourceFingerprint(canonicalInputSource(modulePath, sourceCode)))
    certJson["trusted"] = newJBool(true)
    # Honest solver-execution binding: z3Executed is true ONLY when a real
    # solver run produced this result (non-empty status + non-empty input).
    # A non-empty status with empty smtlib2 is the heuristic/structural path —
    # it must never be recorded as a z3 execution (certificate would fabricate
    # solver evidence; see solverHasExecuted).
    let z3Executed = solverHasExecuted(solverStatus, smtlib2)
    let z3Passed = z3Executed and solverStatus == "unsat"
    # When a genuine KAA is present, derive kernel=true and leanKernelVerified=true
    # from the observed receipt. The KAA can only be produced by
    # canonicalLeanKernelCheck → bindReceipt, so this is the ONLY
    # forge-proof path to kernel=true on a persisted certificate.
    # The static registry has NO authority over kernel truth (see below).
    let effectiveLeanKernelVerified = kaaEff.isSome() or leanKernelVerified
    # S2 rev.4: leanProposition is the PURE proposition string (what was proved).
    # The old theorem-name fallback conflated proposition with source identity —
    # removed. A naked kernel flag without a bound proposition stays recorded in
    # solverMeta but can never promote the tier (leanEvidenceBound gate below).
    let effectiveLeanProposition = leanProposition
    # A2 Lean-evidence binding — PROMOTION GATE ONLY (winningStrategy +
    # verificationTier): effectiveLeanKernelVerified may promote the TIER to a
    # Lean-verified value ONLY when a real non-empty Lean proposition is bound
    # to this certificate. The Lean replay boundary (runLeanKernelCheck)
    # rejects empty source, so a naked flag with effectiveLeanProposition.len == 0
    # means no accepted Lean artifact backs the flag. The raw flag is still
    # recorded truthfully in solverMeta. The persisted `status` is NOT decided
    # by this gate: it follows the canonical evidence contract (DECISION-0630)
    # — the P0 statusConsistentWithEvidence demotion below (and its claim-path
    # mirror) is the sole status authority, so a naked/unbound flag can never
    # yield certLeanVerified/certGreen regardless of tier promotion.
    # Empty-digest structural-path semantics (verifier UAP intent) are unaffected.
    let leanEvidenceBound = effectiveLeanProposition.len > 0
    let leanVerified = effectiveLeanKernelVerified and leanEvidenceBound
    let tier = tierFromResults(z3Passed, leanVerified)
    if verifiedClaim.isSome:
      let claim = verifiedClaim.get()
      let legacy = legacyProjection(claim)
      certJson["status"] = newJString(legacy.getOrDefault("status").getStr("certPending"))
      certJson["reason"] = newJString("claim-derived")
      certJson["claimId"] = newJString(claim.claimId)
      certJson["specificationId"] = newJString(claim.specificationId)
      certJson["policyId"] = newJString(claim.policyId)
      certJson["schemaVersion"] = newJString("1")
      # P0 (verification_density.md): a claim-derived status must not overclaim
      # certGreen without dual evidence. If the claim maps to certGreen but the
      # stored evidence is not dual (z3Passed ∧ leanVerified), fall back to the
      # canonical tier status so Z3-only evidence can never be labeled certGreen.
      if certJson["status"].getStr() == "certGreen" and
          not statusConsistentWithEvidence(certJson):
        certJson["status"] = newJString(tierToStatusString(tier))
        certJson["reason"] = newJString("claim-derived-evidence-corrected")
    else:
      let certStatus = tierToStatusString(tier)
      let certReason = if tier == vtDual: "dual-verified"
                       elif tier == vtLeanOnly: "uap-lean-verified"
                       elif tier == vtZ3Only: "z3-verified"
                       elif leanKernelVerified: "lean-evidence-unbound"
                       else: "unverified"
      certJson["status"] = newJString(certStatus)
      certJson["reason"] = newJString(certReason)
    # kernel is true ONLY when a genuine KAA backs this run (real Lean kernel
    # acceptance observed via canonicalLeanKernelCheck → bindReceipt, carried by
    # the CanonicalLeanEvidence). The static registry is DEMOTED to compatibility
    # metadata (solverMeta.registryIsKernel) — it can never manufacture kernel=true;
    # registry state has no authority over persisted verification truth.
    let kernelFromKaa = kaaEff.isSome()
    certJson["kernel"] = newJBool(kernelFromKaa)
    certJson["solverStatus"] = newJString(solverStatus)
    certJson["winningStrategy"] = newJString(if leanVerified: "lean-replay" else: "none")
    certJson["solverMeta"] = %*{
      "leanCompilerVerified": effectiveLeanKernelVerified,
      "registryIsKernel": lookupIsKernel(functionName),
      "negativeTestResult": negativeTestResult,
      "vacuityChecked": true,
      "vacuityProven": effectiveLeanKernelVerified and vacuityProven,

      "solverVersion": BuildEnvZ3Version,
      "solverProvenance": (if z3Passed: "spZ3SAT" else: "spHeuristic"),
      "z3Executed": z3Executed
    }
    # P5: Write obligation verdict to solverMeta for cert re-play.
    if obligationVerdict.isSome:
      let ov = obligationVerdict.get()
      case ov
      of ogrGenerated:
        certJson["solverMeta"]["obligationVerdict"] = newJString("generated")
      of ogrNoApplicableObligation:
        certJson["solverMeta"]["obligationVerdict"] = newJString("no_applicable")
      of ogrUnsupported:
        certJson["solverMeta"]["obligationVerdict"] = newJString("unsupported")
      of ogrIllFormed:
        certJson["solverMeta"]["obligationVerdict"] = newJString("ill_formed")
    certJson["verificationTier"] = newJString($tier)
    certJson["solverMeta"]["vacuityProven"] = newJBool(effectiveLeanKernelVerified and vacuityProven)
    certJson["leanProposition"] = %(effectiveLeanProposition)
    # ─── S2 rev.4: durable canonical evidence fields ────────────────────────
    # Self-contained identity-bearing evidence: the certificate independently
    # establishes WHICH obligation, WHICH proposition, WHICH Lean source, and
    # WHICH execution/toolchain contract the kernel accepted — bound together
    # by evidenceId. canonicalKaa is the identity-bearing KAA projection
    # (volatile provenance excluded); its digest is the kaaDigest preimage.
    if ev.isSome:
      let e = ev.get()
      certJson["evidenceId"] = newJString(e.evidenceId)
      certJson["obligationId"] = newJString(e.cleObligationId)
      certJson["propositionHash"] = newJString(e.clePropositionHash)
      certJson["leanSource"] = newJString(e.cleLeanSource)
      certJson["leanSourceHash"] = newJString(e.cleLeanSourceHash)
      certJson["canonicalKaa"] = newJString(e.cleCanonicalKaaJson)
      certJson["kaaDigest"] = newJString(e.cleKaaDigest)
      certJson["toolchainFingerprint"] = newJString(e.cleToolchainFingerprint)
      certJson["executionBundleFingerprint"] = newJString(e.cleToolchainFingerprint)
      certJson["executionContractDigest"] = newJString(e.cleExecutionContractDigest)
      # ─── Phase 1B: strict completeness contract binding ──────────────────
      # Written ONLY when the evidence carries the full strict anchor set;
      # legacy evidence never gets the marker (isFullCertClaim and the v3
      # identity extension both branch on it).
      let cKey = evidenceCompletenessEvidenceKey(e)
      let cBindingDigest = evidenceCompletenessBindingDigest(e)
      let cPayloadDigest = evidenceCompletenessPayloadDigest(e)
      if cKey.len > 0 and cBindingDigest.len > 0 and cPayloadDigest.len > 0:
        certJson["completenessContract"] = newJString(CompletenessContractStrictV1)
        certJson["completenessEvidenceKey"] = newJString(cKey)
        certJson["completenessBindingDigest"] = newJString(cBindingDigest)
        certJson["completenessPayloadDigest"] = newJString(cPayloadDigest)
      # ─── axiomsUsed: KAA-observed axiom set for Lean-only deep verification ──
      # Honest serialization of the actual axiom/sorry-scan outcome from
      # the canonical Lean kernel acceptance (#print axioms probe bound into
      # the KAA's observedAxiomSet). This is what isDeepVerified's lean sorry
      # gate consumes: it must be non-empty and allowlisted for a pure-Lean
      # cert to be deep-verified (an empty/missing list → dvcLeanNotVerified,
      # fail-closed per docs/spec/lean_sorry_gate.md). We serialize exactly
      # what the kernel reported — nothing fabricated.
      let axSet = e.kaa.kaaAxiomSet()
      var axArr = newJArray()
      for ax in axSet:
        axArr.add(%ax)
      certJson["axiomsUsed"] = axArr
    if smtlib2.len > 0:
      certJson["smtlib2"] = newJString(smtlib2)
    certJson["irHash"] = %irHash
    certJson["translationVersion"] = newJString("axiom-ir-smt-v1")
    # P5 semantic binding: record the exact semantics contract (Nim semantics
    # profile) under which this claim is verified. This is the canonical
    # semanticContractHash (SemanticProfileV1Hash / core/trusted/semantic_profile).
    # Since the 2026-10-07 weakening (DEBT#494) the profile names the VERIFIED
    # semantics: division/modulo coincide with Lean floor/emod on the
    # nonnegative domain, overflow reachability discharged via no-overflow
    # obligations (docs/spec/semantic_profile_verified_semantics.md).
    # A specific profile id (from a claim) is honored when bound; otherwise the
    # v1 canonical profile hash is used — v1 has exactly one semantics contract,
    # so every certificate carries its real semantics hash rather than an empty
    # or sentinel value. The field is a top-level cert field, so it is covered
    # by the Ed25519 attestation signature over the deterministic payload: a
    # claim verified under a different semantics contract carries a different
    # signed artifact and cannot be passed off as identical.
    certJson["semanticProfileId"] = newJString(
      if semanticProfileId.len > 0: semanticProfileId else: SemanticProfileV1Hash)
    # ─── Certificate v3 fields ──────────────────────────────────────────────
    const CertificateV3SchemaVersion = "axiom.certificate.v3"
    certJson["schemaVersion"] = newJString(CertificateV3SchemaVersion)
    let sourceHash = computeStableSourceFingerprint(canonicalInputSource(modulePath, sourceCode))
    let winningStrategy = if leanVerified: "lean-replay" else: "none"
    # claim: verification claim object mapping tier status to module/function
    certJson["claim"] = %*{
      "type": "verification",
      "status": tierToStatusString(tier),
      "modulePath": modulePath,
      "functionName": functionName
    }
    # claimJsonStr: canonical (RFC 8785) JSON string for claimDigest computation
    let claimJsonStr = canonical_json.canonicalJsonString(%*{
      "type": "verification",
      "status": tierToStatusString(tier),
      "modulePath": modulePath,
      "functionName": functionName
    })
    # inputHash: strictly TO ed string concatenation of key-value pairs
    let inputHashRaw = join([
      "modulePath", modulePath,
      "functionName", functionName,
      "sourceHash", sourceHash,
      "irHash", irHash
    ], "\x1f")
    certJson["inputHash"] = newJString("sha256:" & hash_kernel.sha256Hex(inputHashRaw))
    # toolchainIdentity: measured runtime toolchain composition (Phase 1B) —
    # the SAME proc the journal admission pin uses
    # (verifierToolchainIdentityJson): compiling Nim version, repo lean
    # pin, hermetic Z3 version, and the content-based verifier build identity
    # (engineBuild — NOT the repo commit). axiomVersion is a PRODUCT LABEL
    # appended by the writer only: it is not a pin component and never
    # participates in admission matching.
    certJson["toolchainIdentity"] = verifierToolchainIdentityJson()
    certJson["toolchainIdentity"]["axiomVersion"] = %(axiomVersion)
    # solverInvocation: engine, version, strategy, and mode derived from solverMeta.
    # engine is derived from the honest z3Executed binding above — the structural
    # path (no solver input) can never claim a z3 engine here.
    certJson["solverInvocation"] = %*{
      "engine": if z3Executed: "z3" elif leanVerified: "lean" else: "none",
      "version": BuildEnvZ3Version,
      "strategy": winningStrategy,
      "mode": winningStrategy
    }
    # solverInputDigest: hash of the actual solver input (smtlib2 or leanProposition).
    # Empty solver input (structural/leSucceeded path) is a canonical empty input:
    # digest of "" keeps the field REQUIRED and deterministic per contract.
    let solverInputDigestRaw = if smtlib2.len > 0:
      smtlib2
    elif effectiveLeanProposition.len > 0:
      effectiveLeanProposition
    else:
      ""
    certJson["solverInputDigest"] = newJString("sha256:" & hash_kernel.sha256Hex(solverInputDigestRaw))
    # solverResultDigest: fallback derivation from solver evidence (stdout not
    # persisted; runtime .z3out exists in state dirs). Honest binding — the raw
    # records the solver status, whether a solver actually executed, the solver
    # input size (0 for the structural path), and the derived tier. sha256("")
    # is impossible here: the digest always covers the descriptive rows, so an
    # empty-input "unsat" yields a truthful (distinct) digest instead of
    # H(empty). The verifier's identityDigest recompute (START-D) binds this
    # digest, so any tamper breaks the closure check.
    let solverResultDigestRaw = join([
      "solverStatus", solverStatus,
      "z3Executed", $z3Executed,
      "solverInputBytes", $smtlib2.len,
      "tier", tierToStatusString(tier)
    ], "\n")
    certJson["solverResultDigest"] = newJString("sha256:" & hash_kernel.sha256Hex(solverResultDigestRaw))
    # provenance: journal commit reference and certificate digest (populated after commit)
    # NOTE: journalCommitId and certificateDigest are set below after commit resolves
    # ─── End Certificate v3 fields ──────────────────────────────────────────
    # P0 evidence-consistency guard (general path — C2 closure). Now that
    # solverStatus/solverMeta/winningStrategy are populated, verify the derived
    # status is no stronger than the stored evidence supports; if not, demote to
    # the evidence-derived tier (mirror of the claim-path guard at :221-224).
    if not statusConsistentWithEvidence(certJson):
      certJson["status"] = newJString(tierToStatusString(tierFromEvidence(
        certificateEvidenceFromJson(certJson))))
      certJson["reason"] = newJString("evidence-corrected")
    # Compute identityDigest from the FINAL v3 semantic state (AFTER any status
    # demotion above so the stored digest is self-consistent with the emitted
    # status field). Shared with the verifier via compV3Identity/V3IdentityState
    # (certificate_identity.nim) — the field set/order is a single source of
    # truth (START-D), so writer and verifier can never drift.
    let sourceHashVal = computeStableSourceFingerprint(canonicalInputSource(modulePath, sourceCode))
    let v3InputHashVal = "sha256:" & hash_kernel.sha256Hex(inputHashRaw)
    let v3SolverInputDigestVal = if smtlib2.len > 0:
      "sha256:" & hash_kernel.sha256Hex(smtlib2)
    elif effectiveLeanProposition.len > 0:
      "sha256:" & hash_kernel.sha256Hex(effectiveLeanProposition)
    else:
      "sha256:" & hash_kernel.sha256Hex("")
    let v3SolverResultDigestVal = "sha256:" & hash_kernel.sha256Hex(solverResultDigestRaw)
    certJson["identityDigest"] = newJString(compV3Identity(V3IdentityState(
      schemaVersion: CertificateV3SchemaVersion,
      modulePath: modulePath,
      functionName: functionName,
      sourceHash: sourceHashVal,
      irHash: irHash,
      leanProposition: effectiveLeanProposition,
      solverStatus: solverStatus,
      status: certJson["status"].getStr(),
      winningStrategy: winningStrategy,
      inputHash: v3InputHashVal,
      solverInputDigest: v3SolverInputDigestVal,
      solverResultDigest: v3SolverResultDigestVal,
      evidenceId: (if ev.isSome: ev.get().evidenceId else: ""),
      completenessContract: certJson{"completenessContract"}.getStr(""),
      completenessEvidenceKey: certJson{"completenessEvidenceKey"}.getStr(""),
      completenessBindingDigest: certJson{"completenessBindingDigest"}.getStr("")
    )))
    let commitRes = commitCertificateVerification(certDir, certJson, modulePath, functionName, solverStatus, irHash, effectiveLeanProposition, semanticProfileId)
    if commitRes.isOk:
      # R4 trust closure: bind this certificate to the authoritative TrustCommit
      # journal record. trustCommitId is the ONLY new certificate field in v1 —
      # every other provenance concept maps to existing fields (contract §7a).
      # Journal-first lookup on verify reads this id and cross-checks replay inputs.
      certJson["trustCommitId"] = newJString(commitRes.get())
      logLines.add("UAP certificate committed to TrustCommit journal (commitId=" & commitRes.get() & ")")
    else:
      logLines.add("  -> [Warning] UAP certificate TrustCommit write rejected: " & commitRes.err)
      result = false
      return
    # Populate provenance after commit resolves (journalCommitId depends on commitRes)
    certJson["provenance"] = %*{
      "journalCommitId": commitRes.get(),
      "certificateDigest": certJson["identityDigest"].getStr()
    }

    # attestation: Ed25519 signature over the DETERMINISTIC certificate payload.
    # The payload is the RFC 8785 canonical JSON of the fully-populated
    # certificate (trustCommitId + provenance + identityDigest included) MINUS
    # the attestation block itself — the verifier strips the "attestation" key
    # and re-signs to check (signCertificatePayload/verifyCertificateAttestation).
    # Sign failure is a hard error: a certificate must never claim an attestation
    # it could not produce (degrading to un-attested is NOT allowed once the
    # journal binding exists).
    let attSig = signCertificatePayload(certJson)
    if attSig.isErr:
      logLines.add("  -> [Warning] Attestation signing failed: " & attSig.error)
      result = false
      return
    certJson["attestation"] = %*{
      "authority": "axiom",
      "policyVersion": CertificateV3SchemaVersion,
      "claimDigest": "sha256:" & hash_kernel.sha256Hex(claimJsonStr),
      "journalRef": commitRes.get(),
      "algorithm": AxiomAttestationAlgorithm,
      "publicKeyId": attSig.get.publicKeyId,
      "signature": attSig.get.signature
    }

    if verifiedClaim.isSome:
      if not commitTrustCommitRecord(logLines, certDir, z3outTrustCommit(
          modulePath, functionName, solverStatus, effectiveLeanProposition, semanticProfileId,
          effectiveLeanKernelVerified, negativeTestResult, vacuityProven, smtlib2, irHash)):
        result = false
        return

      if not commitTrustCommitRecord(logLines, certDir,
          v2VerifiedTrustCommit(verifiedClaim.get(), semanticProfileId, modulePath, functionName, solverStatus, irHash)):
        result = false
        return
    else:
      if not commitTrustCommitRecord(logLines, certDir, z3outTrustCommit(
          modulePath, functionName, solverStatus, effectiveLeanProposition, semanticProfileId,
          effectiveLeanKernelVerified, negativeTestResult, vacuityProven, smtlib2, irHash)):
        result = false
        return

    # v3 persistence: portable self-describing projection file. The TrustCommit
    # journal remains the authoritative SSOT; this file is the canonical
    # certificate projection emitted per contract (provenance_contract_v3.md
    # §"Journal = ledger, Certificate = projection"). Emitted via the single
    # canonical RFC 8785 serializer (no trailing newline) so the candidate bytes
    # are byte-identical to the canonical vault write in promoteToCanonical.
    let certFileName = if irHash.len > 0: irHash & ".json" else: functionName & ".json"
    writeFile(joinPath(certDir, certFileName), canonicalCertificateString(certJson))

    result = true
  except CatchableError as e:
    logLines.add("  -> [Warning] Failed to write UAP certificate: " & e.msg)
    result = false
proc cleanOrphanCertificates*(certDir: string; expectedIrHashes: seq[string]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var keepSet = initHashSet[string]()
  for h in expectedIrHashes:
    if h.len > 0:
      keepSet.incl(h)
  for path in walkPattern(joinPath(certDir, "*.json")):
    try:
      let fileName = extractFilename(path)
      if fileName == "manifest.json":
        continue
      let basename = splitFile(fileName).name
      if basename in keepSet:
        continue
      if not isProvenanceProtected(path):
        discard removeFileOpt(path)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
proc writeCertificateWithFingerprint*(certPath: string; fn: FunctionRef; fingerprint, body: string; graphFingerprint: string): bool {.axiomDecision(id = "DECISION-0629", reason = "Write guard for canonical path enforced before fingerprint certificate writing", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32"), raises: [CatchableError].} =
  let canonicalDir = resolveCertificate(cvCanonicalRead)
  let runtimeCanonicalDir = resolveCertificate(cvRuntimeCanonical)
  if (certPath.startsWith(canonicalDir) or certPath.startsWith(runtimeCanonicalDir)) and not promotionActive:
    raise newException(CatchableError, "DIRECT CANONICAL WRITE FORBIDDEN — must go through explicit promotion context (set promotionActive=true or use --promote flag)")
  var theorem: string
  try:
    theorem = buildTheoremName(fn)
  except CatchableError:
    return false
  let node = %*{
    "theorem": theorem,
    "functionName": fn.name,
    "modulePath": fn.modulePath,
    "fingerprint": fingerprint,
    "currentFingerprint": fingerprint,
    "sourceHash": computeStableSourceFingerprint(body),
    "status": "certRed",
    "reason": "awaiting-leanstral-proof-synthesis",
    "trusted": true,
    "kernel": lookupIsKernel(fn.name),
    "retryCount": 0,
    "tactics": ["-- awaiting leanstral synthesis --"],
    "refinement_applied": [],
    "calls": ["axiom.external.noop"],
    "accessedResources": [splitFile(fn.modulePath).name & "." & fn.name],
    "mutatedResources": [],
    "imports": [],
    "constraints": [],
    "selfHealingAsserts": [],
    "recoveredDefects": [],
    "winningStrategy": "none",
    "provenance": "rebuild-assets",
    "globalGraphFingerprint": graphFingerprint
  }
  try:
    result = writeCertificate(certPath, node)
  except CatchableError:
    result = false
{.pop.}

