import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/json
import std/os
import std/strutils
import std/algorithm
import core/crypto/hash_kernel
import core/results
import core/types/certificate_types
import core/types/verification_tier
import core/trusted/axiom_pragmas
import core/trusted/fingerprint_generator
import core/trusted/trust_commit
import core/proof/source_fingerprint
import core/utils/repo_root
import core/io/file_utils
import core/judge/lean_replay
import verification/canonical_json
import verification/certificate_identity
import verification/kernel_reexecution
import infrastructure/certificate_attestation
{.push raises: [].}

## Builtin axiom allowlist for kernel cert deep verification. THE canonical
## definition lives in core/judge/lean_replay.nim (a core-layer module, so the
## verification layer may import it): Lean 4.33.0 exposes three primitive
## axioms, and `funext` is a theorem over `Quot.sound`, not an axiom. Any
## recorded axiom outside this set (notably sorryAx/Lean.sorryAx)
## → fail-closed. docs/spec/lean_sorry_gate.md.
const leanCertBuiltinAxiomAllowlist* = canonicalAxiomAllowlist

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
  # Nim's `/` (joinPath) does not discard the head for an absolute tail — it
  # concatenates ("usr/" / "/lib" == "usr/lib"). An absolute cert modulePath
  # already identifies the subject's module bytes and must not be re-rooted.
  let sourcePath =
    if isAbsolute(certModulePath): certModulePath
    else: repo / certModulePath
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
    let leanSource = cert.getOrDefault("leanSource").getStr("")
    if not leanVerified and smtlib2.len == 0:
      return dvcSmtMissing
    # Fail-closed sorry gate. VS-188 Phase 1: enforce the allowlist whenever a
    # leanSource is bound — previously this gate ran only for pure-Lean certs
    # (smtlib2.len == 0), so subject-continuity certs (leanSource + smtlib2)
    # never reached INV-6. An empty recorded set is legitimate ONLY when the
    # cert carries an observation that proves the kernel observed it (the
    # observation is validated below and in the closure gate); a legacy
    # pure-Lean cert with no recorded set stays dvcNotCurrent.
    if leanSource.len > 0:
      var names: seq[string] = @[]
      let axiomsNode = cert.getOrDefault("axiomsUsed")
      if axiomsNode != nil and axiomsNode.kind == JArray:
        for ax in axiomsNode.items:
          let name = ax.getStr("")
          if name.len > 0 and name notin names:
            names.add(name)
      for ax in names:
        if ax == "sorryAx" or ax == "Lean.sorryAx":
          return dvcLeanNotVerified
        if not isCanonicalAxiom(ax):
          return dvcLeanNotVerified
      if names.len == 0 and cert{"observation"}.isNil and
          leanVerified and smtlib2.len == 0:
        # Legacy pure-Lean artifact: the producing toolchain did not record
        # the observed axiom set. Structurally valid but not current product
        # truth — dvcNotCurrent, never a green claim.
        return dvcNotCurrent
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
  # VS-188 Phase 1: a subject-continuity certGreen/dual-verified claim is a
  # claim about a FRESH kernel observation. Without a recorded, self-consistent,
  # dual-passing observation bound to the cert's own leanSource/smtlib2, the
  # status is stronger than its evidence → tampered (existing result value).
  # Scope: the subject-continuity contract only — legacy UAP certs (no `kind`)
  # keep their pre-VS-188 deep-verification semantics, and are never upgraded
  # to a fresh-verification claim (their legacy shape is classified elsewhere).
  if parsedStatus in {certGreen, certDualVerified} and
      cert.getOrDefault("kind").getStr("") == "subject-continuity":
    let observationNode = cert{"observation"}
    if observationNode.isNil or observationNode.kind != JObject:
      return dvcTamperedStatus
    let parsedObservation = parseKernelObservation(observationNode)
    if parsedObservation.isErr:
      return dvcTamperedStatus
    if not isPassingKernelObservation(parsedObservation.get,
        cert.getOrDefault("leanSource").getStr(""),
        cert.getOrDefault("smtlib2").getStr("")):
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
    # #246: the replay identity must cover the CLAIMED SEMANTICS, not only the
    # hashes of its inputs. Without these, an attestation-less certificate whose
    # `leanProposition` / `leanSource` was swapped (with sourceHash/irHash
    # recomputed) still projected identically to its journal claim and replayed
    # PASS. theoremName is included for the same reason: the theorem the proof
    # establishes is part of what was certified.
    node.getOrDefault("leanProposition").getStr(""),
    node.getOrDefault("propositionHash").getStr(""),
    node.getOrDefault("leanSource").getStr(""),
    node.getOrDefault("leanSourceHash").getStr(""),
    node.getOrDefault("theoremName").getStr(""),
    solverMetaProjection(node)
  ]
  sha256Hex(fields.join("|"))

func observationProjection(node: JsonNode): string {.raises: [].} =
  ## Canonical projection of the signed observation block: key order cannot
  ## affect the comparison, but any value change does. Absent projects to "".
  let observation = node{"observation"}
  if observation.isNil:
    return ""
  canonical_json.canonicalJsonString(observation)

func sameReplayInputs(certNode, journalClaim: JsonNode): bool {.raises: [].} =
  ## Replay input identity consistency (R4 §4): the inputs used for replay —
  ## sourceHash, irHash, solverStatus, policyId — must be identical between the
  ## certificate and the journal claim it points at. A mismatch means the cert
  ## was re-bound to a foreign journal (cert A + journal B) or the journal was
  ## replayed with different inputs. VS-188 Phase 1: the observation block and
  ## its digest are replay inputs too — a cert whose observation was altered
  ## after minting can never replay against the journaled claim.
  # #246: the proposition/source digests are replay inputs too. A cert whose
  # claimed semantics differ from the journaled claim is a DIFFERENT subject,
  # not a replay of the same one.
  for key in ["sourceHash", "irHash", "solverStatus", "policyId",
              "propositionHash", "leanSourceHash"]:
    if certNode.getOrDefault(key).getStr("") != journalClaim.getOrDefault(key).getStr(""):
      return false
  if observationProjection(certNode) != observationProjection(journalClaim):
    return false
  if certNode.getOrDefault("observationDigest").getStr("") !=
      journalClaim.getOrDefault("observationDigest").getStr(""):
    return false
  true

func subjectObservationProblem(node: JsonNode): string {.raises: [].} =
  ## "" = the subject-continuity observation block is self-consistent AND the
  ## recorded derived facts are exactly what that observation implies. Any
  ## mismatch — absent block, tampered axiom set, digest that does not bind the
  ## block, or a kernel/status claim the observation does not support — is a
  ## fail-closed reason. Non-subject certs return "" (their gates are the
  ## legacy deep-verification stages).
  if node.getOrDefault("kind").getStr("") != "subject-continuity":
    return ""
  let observationNode = node{"observation"}
  if observationNode.isNil or observationNode.kind != JObject:
    return "subject-continuity certificate carries no observation (fail-closed)"
  let parsed = parseKernelObservation(observationNode)
  if parsed.isErr:
    return "observation block: " & parsed.error
  let observation = parsed.get
  let leanSource = node.getOrDefault("leanSource").getStr("")
  let smtlib2 = node.getOrDefault("smtlib2").getStr("")
  if leanSource.len == 0 or smtlib2.len == 0:
    return "subject-continuity certificate lacks leanSource/smtlib2 (fail-closed)"
  let problem = kernelObservationValidationError(observation, leanSource, smtlib2)
  if problem.len > 0:
    return "observation: " & problem
  if not isPassingKernelObservation(observation, leanSource, smtlib2):
    return "observation is not a dual-kernel pass (fail-closed)"
  let storedDigest = node.getOrDefault("observationDigest").getStr("")
  if storedDigest.len == 0 or storedDigest != kernelObservationDigest(observation):
    return "observationDigest does not bind the recorded observation (fail-closed)"
  # Derived facts, all signed: they must be exactly the observation's
  # implications, so a post-mint edit of one without the other is rejected.
  if not node.getOrDefault("trusted").getBool(false):
    return "trusted=false contradicts a provenance-anchored mint (fail-closed)"
  if not node.getOrDefault("verified").getBool(false):
    return "verified=false contradicts a dual-passing observation (fail-closed)"
  if not node.getOrDefault("kernel").getBool(false):
    return "kernel=false contradicts a passing Lean observation (fail-closed)"
  if node.getOrDefault("status").getStr("") != "certGreen":
    return "status is not the observation-derived certGreen (fail-closed)"
  if node.getOrDefault("solverStatus").getStr("") != "unsat":
    return "solverStatus is not the observation-derived unsat (fail-closed)"
  if node.getOrDefault("reason").getStr("") != "dual-verified":
    return "reason is not the observation-derived dual-verified (fail-closed)"
  if node.getOrDefault("verificationTier").getStr("") != "dual-verified":
    return "verificationTier is not the observation-derived dual-verified (fail-closed)"
  if node.getOrDefault("winningStrategy").getStr("") != "lean-replay":
    return "winningStrategy is not the observation-derived lean-replay (fail-closed)"
  if node.getOrDefault("theoremName").getStr("") != observation.lean.theoremName:
    return "theoremName does not match the observation (fail-closed)"
  if node.getOrDefault("leanSourceDigest").getStr("") != observation.lean.leanSourceDigest:
    return "leanSourceDigest does not match the observation (fail-closed)"
  if node.getOrDefault("smtlib2Digest").getStr("") != sha256Hex(smtlib2):
    return "smtlib2Digest does not bind the certificate's smtlib2 (fail-closed)"
  if node.getOrDefault("z3QueryDigest").getStr("") != observation.z3.queryDigest:
    return "z3QueryDigest does not match the observation (fail-closed)"
  if node.getOrDefault("z3OptionsDigest").getStr("") != observation.z3.optionsDigest:
    return "z3OptionsDigest does not match the observation (fail-closed)"
  if node.getOrDefault("z3BinaryDigest").getStr("") != observation.z3.binaryDigest:
    return "z3BinaryDigest does not match the observation (fail-closed)"
  if node.getOrDefault("verificationMode").getStr("") != observation.verificationMode:
    return "verificationMode does not match the observation (fail-closed)"
  var recordedAxioms: seq[string] = @[]
  let axiomsNode = node.getOrDefault("axiomsUsed")
  if axiomsNode.isNil or axiomsNode.kind != JArray:
    return "axiomsUsed missing (fail-closed)"
  for axiom in axiomsNode.items:
    if axiom.kind != JString:
      return "axiomsUsed element is not a string (fail-closed)"
    recordedAxioms.add axiom.getStr()
  if normalizeAxiomSet(recordedAxioms) != normalizeAxiomSet(observation.lean.axiomSet):
    return "axiomsUsed does not match the observed axiom set (fail-closed)"
  if node.getOrDefault("leanProposition").getStr("") != observation.lean.theoremName:
    return "leanProposition does not name the observed theorem (fail-closed)"
  ## Provenance axis: `trusted=true` is an assertion about a run/artifact
  ## anchor. The anchor itself must be recorded. Two shapes exist and both are
  ## validated for what they actually claim:
  ##   * admission anchor — carries GitHub run identity (any of the seven
  ##     fields below). Then ALL seven fields + prNumber must be complete and
  ##     prHeadSha must equal the certified headSha.
  ##   * chain-local anchor — the legacy full-attest CLI surface. It carries
  ##     no run identity, so it cannot support an admission claim; it is
  ##     validated as a presence-only marker (source/scheme). Requiring the
  ##     admission shape here would reject legitimate local mints, and
  ##     accepting the marker as run identity would over-claim — the capsule
  ##     verifier is the authority that requires the full admission anchor.
  let anchor = node{"provenanceAnchor"}
  if anchor.isNil or anchor.kind != JObject or anchor.len == 0:
    return "trusted=true but provenanceAnchor is absent (fail-closed)"
  var admissionFields = 0
  for key in ["mergeSha", "mergeTreeDigest", "toolCommit", "prHeadSha",
              "runId", "runAttempt", "artifact"]:
    let v = anchor.getOrDefault(key)
    if v.isNil:
      continue
    if v.kind != JString or v.getStr("").len == 0:
      return "provenanceAnchor." & key & " present but not a non-empty string (fail-closed)"
    admissionFields.inc
  if admissionFields > 0:
    for key in ["mergeSha", "mergeTreeDigest", "toolCommit", "prHeadSha",
                "runId", "runAttempt", "artifact"]:
      let v = anchor.getOrDefault(key)
      if v.isNil or v.kind != JString or v.getStr("").len == 0:
        return "provenanceAnchor." & key & " missing (fail-closed)"
    if anchor.getOrDefault("prNumber").kind != JInt:
      return "provenanceAnchor.prNumber missing (fail-closed)"
    if anchor.getOrDefault("prHeadSha").getStr("") !=
        node.getOrDefault("headSha").getStr(""):
      return "provenanceAnchor.prHeadSha does not match the certified headSha (fail-closed)"
  else:
    if anchor.getOrDefault("source").getStr("").len == 0 or
        anchor.getOrDefault("scheme").getStr("").len == 0:
      return "chain-local provenanceAnchor lacks source/scheme (fail-closed)"
  ""

proc verifyCertificateClosureNode*(
  certNode: JsonNode; certPath: string; projectRoot: string
): CertClosureResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [IOEffect, RootEffect, AxiomIOEffect].} =
  ## v1 certificate trust closure over an in-memory certificate node — the
  ## single shared implementation behind two thin adapters: the file adapter
  ## `verifyCertificateClosure` (`ax cert verify`) and the in-memory
  ## journal-claim adapter (cert_reconcile.verifyJournalClaimClosure).
  ## Fail-closed: any absent/mismatched element fails verification.
  ## `certPath` is the certificate origin identifier (real path from the file
  ## adapter, "journal:<commitId>" from the journal adapter); it is forwarded
  ## to isDeepVerified, whose certPath parameter is never read, so both
  ## adapters see identical closure semantics.
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

  # VS-188 Phase 1: a subject-continuity certificate must carry an observation
  # that is self-consistent, dual-passing, and the exact basis of every
  # recorded kernel/status claim. Missing or altered facts fail closed with
  # the EXISTING result value (no new verdict member).
  let observationProblem = subjectObservationProblem(certNode)
  if observationProblem.len > 0:
    return CertClosureResult(status: ccsNotDeepVerified,
      detail: "observation gate: " & observationProblem)

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

proc verifyCertificateClosure*(
  certPath: string;
  projectRoot: string = ""
): CertClosureResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [IOEffect, RootEffect, AxiomIOEffect].} =
  ## v1 certificate trust closure — the single entry point for `ax cert verify`.
  ## File adapter: reads and parses the certificate, then delegates to
  ## verifyCertificateClosureNode.
  if not fileExists(certPath):
    return CertClosureResult(status: ccsMalformed, detail: "certificate file not found")
  var certNode: JsonNode
  try:
    certNode = parseJson(readFile(certPath))
  except CatchableError as e:
    return CertClosureResult(status: ccsMalformed, detail: "malformed certificate JSON: " & e.msg)
  if certNode.isNil or certNode.kind != JObject:
    return CertClosureResult(status: ccsMalformed, detail: "certificate is not a JSON object")
  verifyCertificateClosureNode(certNode, certPath, projectRoot)

{.pop.}
{.pop.}
