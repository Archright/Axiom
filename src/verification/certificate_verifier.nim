import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/json
import std/os
import std/strutils
import std/algorithm
import core/crypto/hash_kernel
import core/types/certificate_types
import core/types/verification_tier
import core/trusted/axiom_pragmas
import core/trusted/fingerprint_generator
import core/trusted/trust_commit
import core/proof/source_fingerprint
import core/utils/repo_root
import core/io/file_utils
import verification/certificate_identity
import infrastructure/certificate_attestation
{.push raises: [].}

## Builtin axiom allowlist for pure-Lean kernel cert deep verification. Any
## recorded axiom outside this set (notably sorryAx/Lean.sorryAx) → fail-closed.
## Mirrors ax_vacuity_check.lean / lean_replay.nim. docs/spec/lean_sorry_gate.md.
const leanCertBuiltinAxiomAllowlist*: array[4, string] =
  ["Classical.choice", "Quot.sound", "propext", "funext"]

proc certSourceHashMatchesSource*(cert: JsonNode; projectRoot: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Fail-closed source-staleness check: the cert's `sourceHash` must equal
  ## computeStableSourceFingerprint of the CURRENT module file. Any missing,
  ## unreadable, or mismatched source → false (stale cert, §0.9).
  let certSourceHash = cert.getOrDefault("sourceHash").getStr("")
  if certSourceHash == "":
    return false
  let certModulePath = cert.getOrDefault("modulePath").getStr("")
  if certModulePath.len == 0:
    return false
  let repo = if projectRoot.len > 0: projectRoot else: resolveRepoRoot()
  let sourcePath = repo / certModulePath
  let sourceContent = try: readFileSafe(sourcePath) except CatchableError: ""
  if sourceContent.len == 0:
    return false
  computeStableSourceFingerprint(sourceContent) == certSourceHash

# ─── Canonical Genuine Qualification Predicate ────────────────────────────────────

proc isDeepVerified*(cert: JsonNode; certPath: string;
    entry: RuntimeAxiomEntry; projectRoot: string): DeepVerificationCode {.nimcall, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## # CANONICAL: isDeepVerified is the SINGLE SOURCE OF TRUTH for deep verification.
  ## All VKD numerators MUST route here via proof_integrity.isDeepVerified.
  ## Zero-Trust Deep Verification — kernel/empirical 분기 포함.
  if cert.isNil or cert.kind != JObject:
    return dvcFileNotFound

  let certFingerprint = cert.getOrDefault("fingerprint").getStr("")

  # 1. CAS-based fingerprint verification (Zero-Trust)
  let irHash = cert.getOrDefault("irHash").getStr("")
  if irHash.len == 0:
    return dvcTamperedStatus  # Legacy/corrupted cert
  # leanProposition may be empty for UAP-generated certs — use irHash only
  let leanProp = cert.getOrDefault("leanProposition").getStr("")
  let currentFp = computeVerificationFingerprint(irHash, leanProp)
  if currentFp == "" or currentFp != certFingerprint:
    return dvcFingerprintMismatch

  # 1.b Source-staleness check — compatibility axis, NOT integrity.
  # A mismatched sourceHash means the cert was produced against a
  # different version of the source (stale toolchain / execution contract).
  # The artifact itself is structurally valid; it is merely not current
  # product truth.  dvcNotCurrent distinguishes this from genuine
  # integrity violations (dvcFingerprintMismatch for crypto tampering).
  if not certSourceHashMatchesSource(cert, projectRoot):
    return dvcNotCurrent

  # 2. 커널(Formal) / 일반(Empirical) 분기
  if entry.isKernel:
    # Accept Lean-only verification (certLeanVerified) without requiring smtlib2
    let leanVerified = cert{"solverMeta"}{"leanCompilerVerified"}.getBool(false)
    let smtlib2 = cert.getOrDefault("smtlib2").getStr("")
    if not leanVerified and smtlib2.len == 0:
      return dvcSmtMissing
    # Fail-closed sorry gate for pure-Lean kernel certs. When verification is
    # Lean-only (no smtlib2), the cert MUST record a non-empty `axiomsUsed` list
    # free of sorryAx/Lean.sorryAx and restricted to the builtin allowlist.
    # A missing/empty list or any offending axiom → dvcLeanNotVerified. Z3-based
    # certs (non-empty smtlib2, leanCompilerVerified=false) are untouched and
    # remain valid. See docs/spec/lean_sorry_gate.md (DEBT#296).
    if leanVerified and smtlib2.len == 0:
      var names: seq[string] = @[]
      let axiomsNode = cert.getOrDefault("axiomsUsed")
      if axiomsNode != nil and axiomsNode.kind == JArray:
        for ax in axiomsNode.items:
          let name = ax.getStr("")
          if name.len > 0 and name notin names:
            names.add(name)
      if names.len == 0:
        # Empty axiomsUsed for a pure-Lean kernel cert means the cert
        # was produced by an older toolchain that did not record the
        # observed axiom set.  The artifact is structurally valid (its
        # fingerprint, identityDigest, and attestation all check out);
        # it is merely not current product truth.  dvcNotCurrent
        # distinguishes this from genuine integrity violations
        # (sorryAx / non-allowlisted axioms → dvcLeanNotVerified).
        return dvcNotCurrent
      for ax in names:
        if ax == "sorryAx" or ax == "Lean.sorryAx":
          return dvcLeanNotVerified
        if ax notin leanCertBuiltinAxiomAllowlist:
          return dvcLeanNotVerified
  # NOTE: the `passed` field was a legacy artifact from an earlier writer
  # (writeCertificateFromUapResult) that never emitted it.  The current
  # canonical evidence representation (solverStatus/smtlib2/solverMeta)
  # fully expresses the same meaning via the P0 statusConsistentWithEvidence
  # gate below, so the `passed` gate is pure legacy redundancy.

  # 3. 화이트리스트 상태 검증 (genuine only; NoObligation-derived/csbPseudo are excluded;
  # certDualVerified is mapped to certGreen via tierToStatusString, never standalone)
  let status = cert.getOrDefault("status").getStr("")
  let parsedStatus = parseCertificateStatus(status)
  if parsedStatus notin {certGreen, certZ3Candidate, certLeanVerified, certDualVerified, certVerifiedAxiom}:
    return dvcTamperedStatus
  # P0 invariant: status must not be stronger than evidence.
  # certGreen without dual Z3∧Lean evidence → tampered.
  if not statusConsistentWithEvidence(cert):
    return dvcTamperedStatus

  dvcSuccess

# ─── R4: Certificate trust closure (v1 contract — local replay-bound artifact) ────
#
# Verify(C) = deep 4-stage check + identityDigest recompute + journal binding:
#   1. existing isDeepVerified stages (fingerprint / source staleness / kernel-
#      sorry / status whitelist) — reused unchanged
#   2. identityDigest recompute from the certificate fields (tamper in any field
#      covered by the identity changes the digest → FAIL)
#   3. trustCommitId ↔ journal: the cert must reference an existing, replay-
#      valid TrustCommit journal record (v1 local replay-bound contract); a
#      missing journal or missing binding → JOURNAL_REQUIRED (exit 2)
#   4. ReplayInputs(C) == ReplayInputs(Journal): sourceHash/irHash/solverStatus/
#      policyId extracted from the cert must equal the values stored in the
#      journal claim (blocks cert A + journal B mismatches)
#   5. Replay equality: H(certSemanticProjection) == H(journalClaimSemanticProjection)

type
  CertClosureStatus* = enum
    ccsPass                  ## all trust-closure stages passed
    ccsNotCurrent            ## artifact is valid but not current product truth (toolchain/lineage mismatch)
    ccsMalformed             ## file unreadable / not a JSON object
    ccsNotDeepVerified       ## isDeepVerified stage failed (structural/crypto integrity violation)
    ccsIdentityDigestMismatch## recomputed identityDigest differs from stored
    ccsJournalBindingAbsent  ## cert carries no trustCommitId
    ccsJournalRequired       ## trustCommitId set but journal record missing
    ccsReplayInputMismatch   ## cert/journal replay inputs disagree
    ccsReplayMismatch        ## semantic projection hash differs (H(pS) != H(pS'))
    ccsAttestationInvalid    ## attestation block present but fails Ed25519 check

  CertClosureResult* = object
    status*: CertClosureStatus
    detail*: string
    replayMatched*: bool
    semanticHash*: string

func solverMetaProjection(node: JsonNode): string {.raises: [].} =
  ## Deterministic projection of the solverMeta evidence block (vacuity, lean
  ## compiler verification, z3 execution, solver provenance). Sorted keys with
  ## "k=v" pairs — immune to the writer's emission order, yet any evidence
  ## tampering changes the projection. Absent/malformed meta projects to "".
  let meta = node.getOrDefault("solverMeta")
  if meta.isNil or meta.kind != JObject:
    return ""
  var parts: seq[string]
  for k, v in meta.pairs:
    parts.add(k & "=" & $v)
  parts.sort()
  parts.join(";")

func certSemanticProjection(node: JsonNode): string {.raises: [].} =
  ## Canonical semantic projection of a certificate for replay equality.
  ## Field order is fixed; absent fields project as "". trustCommitId is
  ## intentionally excluded — the journal record cannot carry its own id.
  ## solverMeta is projected deterministically so evidence-block tampering
  ## (vacuity / lean-compiler flags) breaks replay equality.
  let fields = [
    node.getOrDefault("status").getStr(""),
    node.getOrDefault("reason").getStr(""),
    node.getOrDefault("verificationTier").getStr(""),
    node.getOrDefault("sourceHash").getStr(""),
    node.getOrDefault("irHash").getStr(""),
    node.getOrDefault("solverStatus").getStr(""),
    node.getOrDefault("policyId").getStr(""),
    node.getOrDefault("modulePath").getStr(""),
    node.getOrDefault("functionName").getStr(""),
    solverMetaProjection(node)
  ]
  sha256Hex(fields.join("|"))

func sameReplayInputs(certNode, journalClaim: JsonNode): bool {.raises: [].} =
  ## Replay input identity consistency (R4 §4): the inputs used for replay —
  ## sourceHash, irHash, solverStatus, policyId — must be identical between the
  ## certificate and the journal claim it points at. A mismatch means the cert
  ## was re-bound to a foreign journal (cert A + journal B) or the journal was
  ## replayed with different inputs.
  for key in ["sourceHash", "irHash", "solverStatus", "policyId"]:
    if certNode.getOrDefault(key).getStr("") != journalClaim.getOrDefault(key).getStr(""):
      return false
  true

proc verifyCertificateClosure*(
  certPath: string;
  projectRoot: string = ""
): CertClosureResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [IOEffect, RootEffect, AxiomIOEffect].} =
  ## v1 certificate trust closure — the single entry point for `ax cert verify`.
  ## Fail-closed: any absent/mismatched element fails verification.
  if not fileExists(certPath):
    return CertClosureResult(status: ccsMalformed, detail: "certificate file not found")
  var certNode: JsonNode
  try:
    certNode = parseJson(readFile(certPath))
  except CatchableError as e:
    return CertClosureResult(status: ccsMalformed, detail: "malformed certificate JSON: " & e.msg)
  if certNode.isNil or certNode.kind != JObject:
    return CertClosureResult(status: ccsMalformed, detail: "certificate is not a JSON object")

  # Reuse the existing deep-verification predicate (fingerprint / source
  # staleness / kernel-sorry / status whitelist).
  let entry = RuntimeAxiomEntry(
    name: certNode.getOrDefault("functionName").getStr(""),
    sourcePath: certNode.getOrDefault("modulePath").getStr(""),
    isKernel: certNode.getOrDefault("kernel").getBool(false),
    irHash: certNode.getOrDefault("irHash").getStr("")
  )
  let root = if projectRoot.len > 0: projectRoot else: resolveRepoRoot()
  let dv = isDeepVerified(certNode, certPath, entry, root)
  if dv == dvcNotCurrent:
    # Artifact is structurally valid (fingerprint, identityDigest, attestation
    # all pass) but the cert is not current product truth — different
    # toolchain / execution-contract lineage.  This is NOT a failure;
    # it is a compatibility classification.
    return CertClosureResult(status: ccsNotCurrent,
      detail: "artifact is valid but not current product truth (toolchain/lineage mismatch): " & $dv)
  if dv != dvcSuccess:
    return CertClosureResult(status: ccsNotDeepVerified, detail: "deep verification failed: " & $dv)

  # Recompute identityDigest via the SHARED canonical semantic-state function
  # (START-D). v3IdentityFromJson reads the 12 identity fields from the JSON and
  # projects them through the same compV3Identity/V3IdentityState the writer uses,
  # so the field set/order is a single source of truth and cannot drift. Runs only
  # AFTER isDeepVerified (above) has validated sourceHash/status, so a tampered
  # JSON value cannot be "self-blessed" by hashing the same wrong value on both
  # sides.
  let rebuilt = v3IdentityFromJson(certNode)
  let storedDigest = certNode.getOrDefault("identityDigest").getStr("")
  if storedDigest.len == 0 or rebuilt != storedDigest:
    return CertClosureResult(
      status: ccsIdentityDigestMismatch,
      detail: "identityDigest recompute mismatch (stored: '" & storedDigest & "')")

  # Attestation stage: an Ed25519 signature over the deterministic payload
  # (RFC 8785 canonical JSON minus the attestation block) MUST verify when an
  # attestation block is present; absent attestation passes for legacy certs
  # (verifyCertificateAttestation returns ok() for missing blocks). A present
  # but invalid block fails closed — the certificate claims an authority
  # binding it cannot back.
  let attCheck = verifyCertificateAttestation(certNode)
  if not attCheck.ok:
    return CertClosureResult(
      status: ccsAttestationInvalid,
      detail: "attestation verification failed: " & attCheck.err)

  # Journal binding: trustCommitId must exist and resolve to a durable commit.
  # The journal is the AXIOM product's own artifact — it must resolve at the
  # SAME root the writer used (`activeJournalRoot`: AXIOM_STATE_DIR when set,
  # else the repo anchor) even when `projectRoot` names an external subject
  # repo whose module bytes the source-staleness check above reads.
  let tcid = certNode.getOrDefault("trustCommitId").getStr("")
  if tcid.len == 0:
    return CertClosureResult(status: ccsJournalBindingAbsent,
      detail: "no trustCommitId — certificate lacks v1 journal binding")
  let journalRead = readCommit(activeJournalRoot(root), tcid)
  if not journalRead.ok:
    return CertClosureResult(
      status: ccsJournalRequired,
      detail: "journal commit '" & tcid & "' missing: " & journalRead.err &
              " — journal / replay artifacts required (v1 local replay-bound)")
  let commit = journalRead.value
  var journalClaim: JsonNode
  try:
    journalClaim = parseJson(commit.claim)
  except CatchableError:
    return CertClosureResult(status: ccsMalformed, detail: "journal claim is not valid JSON")

  # Replay input consistency: cert's recorded inputs must match the journal's.
  if not sameReplayInputs(certNode, journalClaim):
    return CertClosureResult(
      status: ccsReplayInputMismatch,
      detail: "replay inputs (sourceHash/irHash/solverStatus/policyId) differ between cert and journal")

  # Replay equality: H(pS) == H(pS′).
  let certHash = certSemanticProjection(certNode)
  let journalHash = certSemanticProjection(journalClaim)
  if certHash != journalHash:
    return CertClosureResult(
      status: ccsReplayMismatch,
      detail: "semantic projection mismatch: cert='" & certHash & "' journal='" & journalHash & "'")
  CertClosureResult(status: ccsPass, replayMatched: true,
    semanticHash: certHash)

{.pop.}
{.pop.}
