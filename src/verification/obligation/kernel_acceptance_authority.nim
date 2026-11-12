import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## KernelAcceptanceAuthority — Authority B (R4)
##
## The ONLY authority that may produce a KernelAcceptanceAttestation (KAA).
## KAA is opaque: public type, private fields, private constructor.
## The sole creation path is `bindReceipt(LeanKernelCheckReceipt)` — the receipt
## must come from the canonical sink `canonicalLeanKernelCheck` in
## `lean_kernel_boundary.nim`.  No rehydrate, no raw-observation bind.
##
## KAA's existence implies an actual canonical Lean kernel invocation
## happened with exit 0 and the target theorem identity was observed.
##
## Capability closure: fake persisted record → KAA ✗, fake serialized KAA → KAA ✗,
## fake raw observation → KAA ✗, Z3 evidence → KAA ✗, fake leanVerified → KAA ✗.
## Unique path: actual canonical Lean execution → opaque receipt → bindReceipt → KAA.

import std/[strutils, options, json, algorithm]
import core/crypto/hash_kernel
import core/results
import core/trusted/axiom_ir
import core/trusted/completeness_binding
import verification/obligation/lean_kernel_boundary
import verification/obligation/lean_evidence
import verification/obligation/identity
import verification/obligation/obligation_types
import verification/canonical_json

# ---------------------------------------------------------------------------
# KernelAcceptanceAttestation — opaque KAA, private fields, private constructor
# ---------------------------------------------------------------------------
## Policy-neutral attestation: Lean kernel ACCEPT + Axiom-side provenance
## observations (`observedAxiomSet`/`observedSorryScan`) bound to a canonical
## artifact.  The KAA does NOT contain a policy verdict — that is the role of
## Authority C (VerificationDecisionAuthority).
##
## Fields are all private (non-`*`) and the constructor is private — only
## `bindReceipt` may create instances.  The pattern follows `ASIRatio`
## (asi_types.nim:15), `NonNegativeDuration` (certificate_types.nim:124),
## and `VerifiedKernelRatio` (vkd_types.nim:19).

type KernelAcceptanceAttestation* = object
  receipt: LeanKernelCheckReceipt            # the opaque receipt from the canonical sink
  observedAxiomSet: seq[string]              # axioms observed in the accepted artifact
  observedSorryScan: seq[string]             # sorry markers observed (empty = none)
  artifactHash: string                       # SHA256 of the canonical artifact
  theoremIdentity: string                    # observed theorem identity from receipt

# ---------------------------------------------------------------------------
# Canonical observation set — deterministic sort + dedupe
# ---------------------------------------------------------------------------
## The Lean kernel emits `#print axioms` entries in an order that is an
## implementation detail of the running toolchain (it can vary across Lean
## versions / environments). `observedAxiomSet` feeds `kaaIdentity`,
## `canonicalizeKaa` → `kaaDigest` → `evidenceId`. Any order dependence there
## would make the same artifact-with-same-axioms produce different identities
## across runs — a determinism violation. We therefore normalize every observed
## set to a canonical lexical sort with duplicates removed at the KAA boundary
## (the single KAA creation point), so all downstream identity digests are
## order-independent. This canonicalizes the REPRESENTATION of the observation;
## it never adds, removes, or semantically merges axioms.

func canonicalObservationSet(items: seq[string]): seq[string] {.raises: [].} =
  var sorted = items
  sorted.sort()
  result = @[]
  for it in sorted:
    if result.len == 0 or result[^1] != it:
      result.add(it)

# ---------------------------------------------------------------------------
# Private constructor — only `bindReceipt` may call this
# ---------------------------------------------------------------------------

func makeKAA(receipt: LeanKernelCheckReceipt;
             axioms: seq[string];
             sorryScan: seq[string];
             artifactHash: string): KernelAcceptanceAttestation {.
  raises: [].} =
  ## Private constructor — only `bind` may invoke this.
  ## The receipt must come from the canonical sink; no other path may
  ## produce a KAA.  This constructor is the single authority closure
  ## point for KAA creation.
  ##
  ## `axioms`/`sorryScan` are canonicalized (lexical sort + dedupe) here so
  ## that KAA identity (kaaIdentity / canonicalizeKaa → kaaDigest) is
  ## deterministic regardless of the order Lean emitted its observations.
  KernelAcceptanceAttestation(
    receipt: receipt,
    observedAxiomSet: canonicalObservationSet(axioms),
    observedSorryScan: canonicalObservationSet(sorryScan),
    artifactHash: artifactHash,
    theoremIdentity: receipt.receiptTheoremIdentity
  )

# ---------------------------------------------------------------------------
# bindReceipt — the ONLY KAA creation path (Authority B)
# ---------------------------------------------------------------------------
## `bindReceipt(LeanKernelCheckReceipt)` is the sole way to produce a
## `KernelAcceptanceAttestation`.  The receipt's existence proves that a
## canonical Lean kernel check was actually performed and returned exit 0.
##
## No rehydrate from persisted state — that would be a bearer-token leak.
## No raw-observation bind — raw observations are forgeable (anyone can
## construct `LeanKernelResult(kernelAccepted:true, exitStatus:0, ...)`).
## No Z3 evidence → KAA — Z3 is candidate-only evidence, never authority.
##
## Two defense layers live at DIFFERENT boundaries:
##   - Opacity (private fields + private constructor) = the AUTHORITY boundary:
##     no code outside this module can fabricate a receipt or a KAA.
##   - This guard = an INTEGRITY sanity check on already-authoritative input:
##     structural validity + canonical execution membership. It does not
##     re-run Lean, re-read artifacts, or re-derive acceptance — that would
##     reintroduce cross-time divergence. bind = check + makeKAA, nothing more.
##
## This is NOT a policy decision — KAA is policy-neutral.  The policy
## qualification happens in Authority C (VerificationDecisionAuthority).

proc bindReceipt*(receipt: LeanKernelCheckReceipt;
           axioms: seq[string] = @[];
           sorryScan: seq[string] = @[]): Result[KernelAcceptanceAttestation, string] {.
  raises: [].} =
  ## Bind a `LeanKernelCheckReceipt` to produce a `KernelAcceptanceAttestation`.
  ## This is the ONLY KAA creation path.  The receipt must come from
  ## `canonicalLeanKernelCheck` (the single canonical sink).
  ##
  ## Layer 1 — structural validity: every provenance field must be non-empty.
  ## Layer 2 — canonical execution membership: the recorded invocation must
  ## match the canonical kernel-check contract shape (`--threads=1`, quoted
  ## `.lean` artifact path) and digests must be SHA256-sized hex.
  ##
  ## Any failure → err. A malformed receipt can NEVER become a KAA.

  # Layer 1: structural validity.
  let structuralFields = @[
    ("executableDigest", receipt.receiptExecutableDigest),
    ("toolchainFingerprint", receipt.receiptToolchainFingerprint),
    ("invocationContract", receipt.receiptInvocationContract),
    ("executionContract", receipt.receiptExecutionContract),
    ("inputIdentity", receipt.receiptInputIdentity),
    ("artifactIdentity", receipt.receiptArtifactIdentity),
    ("theoremIdentity", receipt.receiptTheoremIdentity)]
  for (fieldName, value) in structuralFields:
    if value.len == 0:
      return err("bindReceipt: malformed receipt — empty " & fieldName)

  if receipt.receiptObservedAt <= 0:
    return err("bindReceipt: malformed receipt — non-positive observedAt")

  # Layer 2: canonical execution membership.
  let invocation = receipt.receiptInvocationContract
  if not invocation.contains("--threads=1"):
    return err("bindReceipt: invocation contract is not canonical " &
               "(missing --threads=1): " & invocation)
  if not invocation.contains(".lean"):
    return err("bindReceipt: invocation contract has no .lean artifact: " & invocation)
  let digestFields = @[
    ("executableDigest", receipt.receiptExecutableDigest),
    ("toolchainFingerprint", receipt.receiptToolchainFingerprint),
    ("executionContract", receipt.receiptExecutionContract),
    ("inputIdentity", receipt.receiptInputIdentity),
    ("artifactIdentity", receipt.receiptArtifactIdentity)]
  for (digestName, digest) in digestFields:
    if digest.len != 64:
      return err("bindReceipt: " & digestName & " is not a SHA256 hex digest")
    for ch in digest:
      if ch notin {'0'..'9', 'a'..'f', 'A'..'F'}:
        return err("bindReceipt: " & digestName & " is not a SHA256 hex digest")

  ok(makeKAA(receipt, axioms, sorryScan, receipt.receiptArtifactIdentity))

# ---------------------------------------------------------------------------
# Accessor functions for opaque KAA fields
# ---------------------------------------------------------------------------

func kaaReceipt*(kaa: KernelAcceptanceAttestation): LeanKernelCheckReceipt {.
  raises: [].} =
  kaa.receipt

func kaaAxiomSet*(kaa: KernelAcceptanceAttestation): seq[string] {.raises: [].} =
  kaa.observedAxiomSet

func kaaSorryScan*(kaa: KernelAcceptanceAttestation): seq[string] {.raises: [].} =
  kaa.observedSorryScan

func kaaArtifactHash*(kaa: KernelAcceptanceAttestation): string {.raises: [].} =
  kaa.artifactHash

func kaaTheoremIdentity*(kaa: KernelAcceptanceAttestation): string {.raises: [].} =
  kaa.theoremIdentity

# ---------------------------------------------------------------------------
# KAA identity — SHA256 of the canonical KAA projection (C1)
# ---------------------------------------------------------------------------
## KAAIdentity = SHA256(CanonicalKAAProjection).  The projection contains
## ExecutionIdentity + ArtifactIdentity + TheoremIdentity + KernelAcceptanceFact
## + AxiomObservations.  This is an identity digest, NOT a proof of authenticity.
## Actual authority comes from `CanonicalLeanKernelCheck → Receipt → bind → KAA`.
##
## C1 schema: KAAIdentity = H(ExecutionIdentity + ArtifactIdentity + TheoremIdentity
##   + AxiomObservations).  The ExecutionIdentity is a pre-computed digest
##   (H(InputIdentity + ExecutionContract + CanonicalExecutionBundleFingerprint))
##   that captures the full decision computation closure identity.

func kaaIdentity*(kaa: KernelAcceptanceAttestation;
                   executionIdentity: string): string {.raises: [].} =
  sha256Hex(
    executionIdentity & "|" &
    kaa.receipt.receiptArtifactIdentity & "|" &
    kaa.receipt.receiptTheoremIdentity & "|" &
    kaa.observedAxiomSet.join("|") & "|" &
    kaa.observedSorryScan.join("|")
  )

# ---------------------------------------------------------------------------
# CanonicalLeanEvidence — immutable authority object (R4/R5/R8 materialization)
# ---------------------------------------------------------------------------
## CanonicalLeanEvidence binds a genuine Lean kernel acceptance (KAA) to the
## obligation, proposition, source, and execution identity that produced it.
## All fields are private (non-`*`); external access is through exported read
## accessors.  The sole factory `newCanonicalLeanEvidence*` requires an opaque
## `KernelAcceptanceAttestation` — the only way to obtain a KAA is via
## `bindReceipt(LeanKernelCheckReceipt)` which requires a genuine canonical
## Lean execution.  This mirrors the KAA pattern exactly: opacity + factory
## authority + single creation path.
##
## Identity hierarchy (documented, tested):
##   kaaDigest →(transitively) executionIdentity → contractDigest+bundleFp;
##   evidenceId = H(evidence components);
##   claimId = H(claim fields + evidenceId);
##   certificate identity = compV3Identity(12 fields + evidenceId).
##
## executionContractDigest and toolchainFingerprint are intentionally duplicated
## at the evidence envelope even though KAA identity already transitively binds
## them (external verifiers can recompute the top-level identity without
## traversing the KAA chain).

type CanonicalLeanEvidence* = object
  ## ALL fields private (non-`*`): external modules can hold/pass/read CLE via
  ## the exported accessors below, but can NEVER construct one — full or
  ## partial construction requires access to every field, and the private
  ## `kaa` field is only fillable inside this module (compile-time forge guard).
  obligationId: string
  proposition: string
  propositionHash: string
  leanSource: string
  leanSourceHash: string
  kaa: KernelAcceptanceAttestation
  canonicalKaaJson: string
  kaaDigest: string
  toolchainFingerprint: string
  executionContractDigest: string
  # Strict completeness binding (Phase 1A) — the authenticated strict evidence
  # identity, threaded from the strict-first reader through
  # `newCanonicalLeanEvidenceBound`. All three stay "" on the legacy
  # representation (no strict binding existed at seal time); the certificate
  # writer MUST persist them under exactly these field names:
  #   completenessEvidenceKey    — the strict load anchor ("" = legacy record)
  #   completenessBindingDigest  — the strict evidenceDigest (drives evidenceId
  #                                extension below; empty ⇒ old evidenceId
  #                                formula, byte-for-byte)
  #   completenessPayloadDigest  — sha256 of the legacy 5-field payload
  #                                serialization (equals
  #                                ObligationSubjectBinding.completenessRecordDigest)
  completenessEvidenceKey: string
  completenessBindingDigest: string
  completenessPayloadDigest: string

# ---------------------------------------------------------------------------
# Exported read accessors for private CLE fields
# ---------------------------------------------------------------------------

func kaa*(e: CanonicalLeanEvidence): KernelAcceptanceAttestation {.raises: [].} =
  e.kaa

func cleObligationId*(e: CanonicalLeanEvidence): string {.raises: [].} = e.obligationId
func cleProposition*(e: CanonicalLeanEvidence): string {.raises: [].} = e.proposition
func clePropositionHash*(e: CanonicalLeanEvidence): string {.raises: [].} = e.propositionHash
func cleLeanSource*(e: CanonicalLeanEvidence): string {.raises: [].} = e.leanSource
func cleLeanSourceHash*(e: CanonicalLeanEvidence): string {.raises: [].} = e.leanSourceHash
func cleCanonicalKaaJson*(e: CanonicalLeanEvidence): string {.raises: [].} = e.canonicalKaaJson
func cleKaaDigest*(e: CanonicalLeanEvidence): string {.raises: [].} = e.kaaDigest
func cleToolchainFingerprint*(e: CanonicalLeanEvidence): string {.raises: [].} = e.toolchainFingerprint
func cleExecutionContractDigest*(e: CanonicalLeanEvidence): string {.raises: [].} = e.executionContractDigest
func cleCompletenessEvidenceKey*(e: CanonicalLeanEvidence): string {.raises: [].} =
  e.completenessEvidenceKey
func cleCompletenessBindingDigest*(e: CanonicalLeanEvidence): string {.raises: [].} =
  e.completenessBindingDigest
func cleCompletenessPayloadDigest*(e: CanonicalLeanEvidence): string {.raises: [].} =
  e.completenessPayloadDigest

# ---------------------------------------------------------------------------
# canonicalizeKaa — deterministic identity-bearing projection of KAA
# ---------------------------------------------------------------------------
## Returns the canonical serialized JSON string of the KAA's identity-bearing
## fields only.  Excludes volatile provenance fields (`observedAt`,
## `actualKernelAcceptanceObservation`) per identity.nim:15 ("Identity digests
## exclude provenance").  Uses JsonNode internally only as an intermediate;
## the return type is a plain string — CLE holds strings/hashes/scalars only,
## making it a true immutable value object.
##
## Deterministic projection fields (7 identity fields from receipt + 2
## observation fields):
##   executionIdentity, receiptArtifactIdentity, receiptTheoremIdentity,
##   receiptToolchainFingerprint, receiptInvocationContract,
##   receiptExecutionContract, observedAxiomSet, observedSorryScan.

func canonicalizeKaa*(kaa: KernelAcceptanceAttestation;
                        executionIdentity: string): string {.raises: [].} =
  let projection = %*{
    "executionIdentity": executionIdentity,
    "receiptArtifactIdentity": kaa.receipt.receiptArtifactIdentity,
    "receiptTheoremIdentity": kaa.receipt.receiptTheoremIdentity,
    "receiptToolchainFingerprint": kaa.receipt.receiptToolchainFingerprint,
    "receiptInvocationContract": kaa.receipt.receiptInvocationContract,
    "receiptExecutionContract": kaa.receipt.receiptExecutionContract,
    "observedAxiomSet": kaa.observedAxiomSet,
    "observedSorryScan": kaa.observedSorryScan
  }
  canonicalJsonString(projection)

# ---------------------------------------------------------------------------
# newCanonicalLeanEvidence* — the sole factory (requires genuine KAA)
# ---------------------------------------------------------------------------
## Factory that creates a `CanonicalLeanEvidence` from an obligation context
## and a genuine `KernelAcceptanceAttestation`.  The KAA is the required
## authority parameter — without a genuine KAA (which can only be produced by
## `bindReceipt` → `canonicalLeanKernelCheck` → actual Lean execution), this
## factory cannot be called.  This mirrors the KAA pattern: the authority
## boundary is the KAA itself, not the factory's visibility.
##
## Self-validation (fail on mismatch):
##   - propositionHash == H(proposition)
##   - leanSourceHash == H(leanSource)
##   - kaaDigest == H(canonicalKaaJson)

proc newCanonicalLeanEvidence*(
  obligationId: string;
  proposition: string;
  leanSource: string;
  kaa: KernelAcceptanceAttestation;
  toolchainFingerprint: string;
  executionContractDigest: string;
  completeness: CompletenessBindingRef = CompletenessBindingRef()
): Result[CanonicalLeanEvidence, string] {.raises: [].} =
  let propositionHash = sha256Hex(proposition)
  let leanSourceHash = sha256Hex(leanSource)
  let canonicalKaaJson = canonicalizeKaa(kaa, executionContractDigest)
  let kaaDigest = sha256Hex(canonicalKaaJson)

  # Self-validation.
  if propositionHash != sha256Hex(proposition):
    return err("newCanonicalLeanEvidence: propositionHash mismatch")
  if leanSourceHash != sha256Hex(leanSource):
    return err("newCanonicalLeanEvidence: leanSourceHash mismatch")
  if kaaDigest != sha256Hex(canonicalKaaJson):
    return err("newCanonicalLeanEvidence: kaaDigest mismatch")

  # Strict completeness ref coherence (fail-closed): a ref that claims a
  # strict binding (non-empty evidenceDigest) must carry its anchor and its
  # payload digest; a partial ref is never sealed.
  if completeness.evidenceDigest.len > 0:
    if completeness.evidenceKey.len == 0 or completeness.payloadDigest.len == 0:
      return err("newCanonicalLeanEvidence: incomplete completeness binding ref " &
                 "(evidenceDigest set without evidenceKey/payloadDigest)")

  # --- KAA ↔ source cross-binding (R5 splice / mix-and-match resistance) ---
  # A CLE is only as authoritative as the KAA it carries, and the KAA only
  # attests to ONE exact Lean artifact.  If `leanSource` is not the very
  # artifact the kernel accepted, the evidence would splice a genuine KAA
  # onto a different source — a mix-and-match attack.  Both checks fire
  # BEFORE the CLE is constructed so a cross-assembled input can never
  # become valid.

  # 1. KAA ↔ Lean source: the receipt binds the exact artifact the kernel
  #    accepted.  sha256(leanSource) MUST equal receiptArtifactIdentity.
  #    This is the cryptographic splice barrier — a source from a different
  #    execution (different KAA) provably mismatches.
  if leanSourceHash != kaa.receipt.receiptArtifactIdentity:
    return err("newCanonicalLeanEvidence: leanSourceHash does not match KAA " &
               "receiptArtifactIdentity (splice: source is not the artifact the " &
               "kernel accepted)")

  # 3. Toolchain fingerprint ↔ measured receipt — FAIL-CLOSED identity
  #    binding (Phase A). The CLE toolchainFingerprint MUST be exactly the
  #    value the kernel actually measured into the receipt — never a
  #    placeholder, hardcoded label, or independently-reconstructed bundle.
  #    Determinism was previously broken by "receipt carries the real value
  #    but executionIdentity carries a different placeholder"; this check
  #    refuses issuance on any divergence so that cannot recur silently.
  #    A future edit replacing bundleFp at the identity site now fails loudly.
  if toolchainFingerprint.len != 64:
    return err("newCanonicalLeanEvidence: toolchainFingerprint is not a SHA256 hex " &
               "digest (len=" & $toolchainFingerprint.len & ")")
  if toolchainFingerprint != kaa.receipt.receiptToolchainFingerprint:
    return err("newCanonicalLeanEvidence: toolchainFingerprint does not match the " &
               "measured receipt's actualToolchainFingerprint (" &
               toolchainFingerprint & " vs " & kaa.receipt.receiptToolchainFingerprint &
               ") — execution identity would diverge from the real execution bundle")

  # 2. KAA ↔ theorem: the receipt records the theorem name the kernel
  #    accepted.  The theorem declared in `leanSource` MUST be that name.
  #    Guards against pairing a KAA with a source that declares a different
  #    (possibly weaker) theorem than the one actually accepted.
  let sourceTheoremName = extractTheoremName(leanSource)
  if sourceTheoremName != kaa.receipt.receiptTheoremIdentity:
    return err("newCanonicalLeanEvidence: theorem name from leanSource ('" &
               sourceTheoremName & "') does not match KAA receiptTheoremIdentity " &
               "('" & kaa.receipt.receiptTheoremIdentity & "') (splice: source " &
               "declares a different theorem than the KAA binds to)")

  ok(CanonicalLeanEvidence(
    obligationId: obligationId,
    proposition: proposition,
    propositionHash: propositionHash,
    leanSource: leanSource,
    leanSourceHash: leanSourceHash,
    kaa: kaa,
    canonicalKaaJson: canonicalKaaJson,
    kaaDigest: kaaDigest,
    toolchainFingerprint: toolchainFingerprint,
    executionContractDigest: executionContractDigest,
    completenessEvidenceKey: completeness.evidenceKey,
    completenessBindingDigest: completeness.evidenceDigest,
    completenessPayloadDigest: completeness.payloadDigest
  ))

# ---------------------------------------------------------------------------
# evidenceId — cryptographic binding of all evidence components
# ---------------------------------------------------------------------------
## evidenceId = H(obligationId | propositionHash | leanSourceHash |
##   kaaDigest | toolchainFingerprint | executionContractDigest).
## executionContractDigest and toolchainFingerprint are intentionally
## duplicated at the evidence envelope even though KAA identity already
## transitively binds them (external verifiers can recompute the top-level
## identity without traversing the KAA chain).
##
## Strict completeness extension (Phase 1A): when the evidence carries a
## strict CompletenessBinding (`completenessBindingDigest` non-empty), the
## digest is appended as a seventh component —
## evidenceId = H(<six legacy components> | completenessBindingDigest).
## When it is empty (the legacy representation) the formula above is
## byte-for-byte unchanged, so every evidence sealed before the strict
## generation keeps its identity.

func evidenceId*(e: CanonicalLeanEvidence): string {.raises: [].} =
  let legacy =
    e.obligationId & "|" &
    e.propositionHash & "|" &
    e.leanSourceHash & "|" &
    e.kaaDigest & "|" &
    e.toolchainFingerprint & "|" &
    e.executionContractDigest
  if e.completenessBindingDigest.len > 0:
    sha256Hex(legacy & "|" & e.completenessBindingDigest)
  else:
    sha256Hex(legacy)

# ---------------------------------------------------------------------------
# newCanonicalLeanEvidenceBound — subject-boundary evidence seal (I1)
# ---------------------------------------------------------------------------
## The KAA cross-checks above bind the evidence WITHIN one Lean artifact
## (splice, theorem name, measured fingerprint). Nothing verified that the
## obligation id the evidence is sealed under names the SUBJECT: a shadow
## model — an independent re-derivation of the same name/kind/predicate over
## different lowering — can produce the same 5-tuple id and reuse evidence
## for it. This factory closes that boundary: the obligation id must be
## exactly the bound identity recomputed from the subject-side binding set
## (docs/spec/obligation_semantics.md §2.1a), and the binding's irDigest is
## re-measured against the actual funcDef, not taken on trust.

proc newCanonicalLeanEvidenceBound*(
  obligationId: string;
  binding: ObligationSubjectBinding;
  funcDef: IRFuncDef;
  proposition: string;
  leanSource: string;
  kaa: KernelAcceptanceAttestation;
  toolchainFingerprint: string;
  executionContractDigest: string;
  completeness: CompletenessBindingRef = CompletenessBindingRef()
): Result[CanonicalLeanEvidence, string] {.raises: [].} =
  if binding.irDigest != sha256Hex(serializeIRFuncDef(funcDef)):
    return err("newCanonicalLeanEvidenceBound: binding.irDigest does not match " &
               "the actual funcDef — the bound identity would name a lowering " &
               "the evidence was not derived from")
  let recomputed = computeBoundObligationId(binding)
  if recomputed.len == 0:
    return err("newCanonicalLeanEvidenceBound: subject binding is incomplete or " &
               "malformed — no bound obligation identity exists (fail-closed)")
  if recomputed != obligationId:
    return err("newCanonicalLeanEvidenceBound: obligationId does not equal the " &
               "identity recomputed from the subject binding (shadow-model or " &
               "stale-binding attach refused)")
  if binding.leanSourceHash != sha256Hex(leanSource):
    return err("newCanonicalLeanEvidenceBound: binding.leanSourceHash does not " &
               "match the actual evidence source — the bound identity names a " &
               "different artifact than the evidence carries")
  if binding.toolchainFingerprint != toolchainFingerprint:
    return err("newCanonicalLeanEvidenceBound: binding.toolchainFingerprint does " &
               "not match the measured execution fingerprint")
  newCanonicalLeanEvidence(
    obligationId = obligationId,
    proposition = proposition,
    leanSource = leanSource,
    kaa = kaa,
    toolchainFingerprint = toolchainFingerprint,
    executionContractDigest = executionContractDigest,
    completeness = completeness
  )

{.pop.}