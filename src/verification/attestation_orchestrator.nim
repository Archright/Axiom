import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Attestation Orchestrator (certification-continuity Phase 4 — Trusted
## Attestation, contract §4.1 "Trusted attest — Verify(E, M)").
##
## attest() runs the trusted verifier chain IN ORDER over one subject M and
## its evidence bundle E, fail-closed at every step. Only an ALL-PASS run
## mints the subject-continuity certificate (the v3 writer extension in
## cert_writer.nim). run.conclusion / workflow-run census are NOT evidence
## here (INV-5) — every stage below is re-executed fresh in this process.
##
## Chain order (each step gated; any failure → its verdict, no further steps):
##   a. subject match   — reload the subject from the append-only store by
##                        ref and require exact equality (verifySubjectMatch;
##                        empty inputs are NEVER equal, INV-1)
##   b. extraction      — per-run differential (Phase 3.75 module); eaAgree
##                        required. EA_UNSUPPORTED is a FAIL here: the
##                        certified subset is MANDATORY for certification
##   c. kernel          — reexecuteLean + reexecuteZ3 (Phase 3) on the
##                        recorded evidence; both must be krPassed (INV-6/INV-10)
##   d. policy digest   — sha256(config/policy/merge_admission.json bytes)
##                        must equal the recorded policyDigest
##   e. toolchain       — recorded toolchainIdentity must equal the pinned
##                        D2 identity "nim-<v>|lean-<v>|z3-<v>|modelprofile=…"
##                        "|charon-pin-<40hex>|charon-<ver>" (the extraction
##                        pin segment is sourced from the Aeneas-side SSOT,
##                        verification/extraction_provenance.nim)
##   f. scope           — sha256(data/verification_scope.lock bytes) must
##                        equal the recorded scopeDigest
##   g. mint            — ALL PASS → subject-continuity certificate minted
##                        through the v3 writer extension (journal-bound,
##                        Ed25519-attested)

import std/[json, os, strutils, times]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/release/version_derive
import verification/canonical_json
import verification/cert_vault_role
import verification/evidence_cas
import verification/evidence_ledger
import verification/extraction_agreement
import verification/extraction_provenance
import verification/kernel_reexecution
import verification/ledger_side_ref
import verification/obligation/identity
import verification/subject_continuity_writer
import verification/subject_store
import verification/verification_subject

# fileSha256Hex moved to its single home (extraction_provenance, nimtry
# dry-duplicates dedup); re-exported so this module's public surface keeps
# resolving the digest for policy/scope recomputes and external consumers.
export extraction_provenance.fileSha256Hex

axiomIoBoundary()

type
  AttestationVerdict* = enum
    atPassed                 ## every chain stage passed → certificate minted
    atSubjectMismatch        ## store reload missing/ambiguous/unequal (fail-closed)
    atExtractionMismatch     ## extractors disagree or the agreement run failed
    atExtractionUnsupported  ## AST node outside the certified-subset wire set
    atKernelLeanFail         ## Lean re-execution verdict != krPassed
    atKernelZ3Fail           ## Z3 re-execution verdict != krPassed
    atPolicyDigestMismatch   ## recorded policy digest != sha256(policy file bytes)
    atToolchainMismatch      ## recorded toolchain identity != pinned D2 identity
    atScopeMismatch          ## recorded scope digest != sha256(scope lock bytes)
    atInternalError          ## evidence malformed / I/O failure — fail-closed

  AttestationInputs* = object
    ## The evidence bundle E a candidate attestation re-runs (schema
    ## "axiom.attestation.evidence.v2" — the untrusted-tier verification
    ## record; v2 is a COHERENT GENERATION CUTOVER from v1: the strict parser
    ## accepts ONLY the v2 schemaVersion, and v2 folds the Rust extraction
    ## binding into the evidence identity — v1 records are never silently
    ## reinterpreted). All fields except prNumber must be non-empty
    ## (fail-closed), except the Rust extraction binding pair which is
    ## all-or-nothing (both empty = a lane that consumed no LLBC; both
    ## well-formed = a lane whose evidenceDigest binds the LLBC bytes).
    schemaVersion*: string
    subjectId*: string
    prNumber*: int
    prHeadSha*: string
    leanSource*: string      ## kernel re-execution input (INV-6)
    smtlib2*: string         ## kernel re-execution input (INV-10)
    funcSource*: string      ## extraction-agreement input (Tier 2)
    funcPath*: string        ## module path the funcSource was read from
    funcName*: string
    policyDigest*: string    ## recorded sha256(config/policy/merge_admission.json)
    scopeDigest*: string     ## recorded sha256(data/verification_scope.lock)
    envDigest*: string       ## recorded RunnerPoolSpecDigest-class env identity
    toolchainIdentity*: string  ## recorded pinned identity (stage-e compares)
    llbcDigest*: string = ""            ## v2: raw-byte sha256 of the consumed
                                        ## Charon LLBC ("" = lane consumed no
                                        ## LLBC); wired into evidenceDigest
    rustToolchainIdentity*: string = "" ## v2: recorded measured Rust toolchain
                                        ## identity token
                                        ## (extraction_provenance
                                        ## .rustToolchainIdentityToken form);
                                        ## wired into evidenceDigest

  AttestationResult* = object
    verdict*: AttestationVerdict
    reason*: string
    certPath*: string        ## populated iff verdict == atPassed
    commitId*: string        ## journal commit of the minted certificate

  AttestationOptions* = object
    subjectsDir*: string
    certDir*: string
    policyPath*: string
    scopeLockPath*: string
    leanExe*: string
    z3Path*: string
    ircheckExe*: string
    leanTimeoutMs*: int
    z3TimeoutMs*: int
    extractionTimeoutMs*: int

const
  EvidenceScheme* = "axiom.attestation.evidence.v2"
    ## Coherent generation cutover from v1 (AGENTS §2.5): v2 adds the Rust
    ## extraction binding (llbcDigest + rustToolchainIdentity) to the record
    ## AND to the evidence bundle wire, so evidenceDigest → certificate
    ## evidenceId binds the consumed LLBC bytes. The strict parser rejects
    ## every other schemaVersion — v1 records stay in the v1 generation
    ## (fail-closed), matching the subject-store v1→v2 precedent. The two new
    ## record fields are OPTIONAL-IN-PRESENCE (the witness bundle embeds the
    ## record and lanes without an LLBC carry ""), strictly typed and
    ## validated when present.
  AttestationPolicyPath* = "config/policy/merge_admission.json"
  AttestationScopeLockPath* = "data/verification_scope.lock"
  PinnedLeanToolchainVersion* = "4.33.0"  ## lean-toolchain pin (repo SSOT)

when fileExists("src/generated/build_env.nim"):
  import generated/build_env
else:
  const BuildEnvZ3Version = "unavailable"

func isCanonicalVerifierBuildId(s: string): bool {.raises: [].} =
  if s.len != 64:
    return false
  for ch in s:
    if ch notin {'0'..'9', 'a'..'f'}:
      return false
  true

func admissibleVerifierBuildId*(id, idSourceHash, liveSourceHash: string): string {.
    raises: [].} =
  ## Pure admissibility cross-check (exported for the negative-control test):
  ## the measured id is usable ONLY when it is a canonical 64-hex identity AND
  ## the source-tree hash it was measured for equals the live compiled
  ## `BuildSourceHash`. Any other value is "unmeasured" — never a
  ## stale-but-plausible identity.
  if not isCanonicalVerifierBuildId(id):
    "unmeasured"
  elif idSourceHash.len == 0 or idSourceHash != liveSourceHash:
    "unmeasured"
  else:
    id

func verifierEngineBuildId*(): string {.raises: [].} =
  ## The content-based verifier build identity (Phase 1B `engineBuild`),
  ## generated by tools/hermetic_build.nim into src/generated/build_env.nim as
  ## `VerifierBuildId`: a SHA-256 over the verifier's build-input manifest
  ## (src/**/*.nim minus src/generated/, config.nims compiler flags,
  ## axiom.nimble + axiom.lock dependency pins — docs/tests excluded). It is
  ## deliberately NOT the repo commit (BuildEnvGitHash): a docs-only commit or
  ## a topic-vs-merge tree change must NOT move the engine identity.
  ##
  ## The id is bound to the source tree it was measured for:
  ## `VerifierBuildSourceHash` (hermetic_build) must equal the live
  ## `BuildSourceHash` (filled by config.nims at compile time). A plain
  ## `nim c` after an edit without bin/hermetic_build therefore yields
  ## "unmeasured" instead of a stale-but-plausible id. Every failure mode —
  ## missing constants, placeholder, non-64-hex, tree mismatch — is
  ## "unmeasured", and `toolchainIdentityMatchesPin` never matches it.
  when declared(VerifierBuildId) and declared(VerifierBuildSourceHash) and
      declared(BuildSourceHash):
    admissibleVerifierBuildId(VerifierBuildId, VerifierBuildSourceHash,
      BuildSourceHash)
  else:
    "unmeasured"

func verifierToolchainIdentityJson*(): JsonNode {.raises: [].} =
  ## THE measured toolchain-identity composition — the single proc shared by
  ## the certificate writer (toolchainIdentity) and the journal admission pin
  ## (currentJournalToolchainPin). Replaces the writer's hardcoded version
  ## literals: every component is measured — the compiling Nim version, the
  ## repo lean-toolchain pin (PinnedLeanToolchainVersion SSOT), the hermetic
  ## Z3 build-env version, and the content-based verifier build identity.
  ## `toolchainIdentityMatchesPin` iterates every pin key, so a missing or
  ## stale engineBuild drops the claim (fail-closed).
  %*{
    "nim": $NimVersion,
    "lean": PinnedLeanToolchainVersion,
    "z3": BuildEnvZ3Version,
    "engineBuild": verifierEngineBuildId()
  }

func pinnedToolchainIdentity*(): string {.raises: [].} =
  ## The pinned D2 toolchain identity — "nim-<v>|lean-<v>|z3-<v>" plus the
  ## shared modelprofile segment (verification/obligation/identity.nim) plus
  ## the charon extraction-pin segment (verification/extraction_provenance —
  ## the Aeneas-side ./charon-pin SSOT, quirk Q3) — the SAME pattern as
  ## canonical_verification.captureToolchainIdentity (D2) and the
  ## lean_kernel_boundary execution contract. One identity, no second form:
  ## stage (e) compares the recorded identity against this exact string, so
  ## the attested evidence cannot outrun the pinned extraction toolchain.
  ## The modelprofile suffix pins the VERIFIED semantic model (SemanticProfileV1
  ## hash), not Axiom's own compile profile — tool versions alone do not name
  ## the checked/wrap coincidence domain the evidence was sealed under. Since
  ## the 2026-10-07 weakening (DEBT#494) the profile declares that coincidence
  ## domain itself (spDivCoincidentNonnegative / spOverflowObligationDischarged).
  if BuildEnvZ3Version.len > 0:
    "nim-" & NimVersion & "|lean-" & PinnedLeanToolchainVersion & "|z3-" & BuildEnvZ3Version & "|" & modelProfileIdentitySegment & charonIdentitySegment()
  else:
    "nim-" & NimVersion & "|lean-" & PinnedLeanToolchainVersion & "|" & modelProfileIdentitySegment & charonIdentitySegment()

func defaultAttestationOptions*(): AttestationOptions {.raises: [].} =
  AttestationOptions(
    subjectsDir: SubjectStoreDir,
    certDir: resolveCertificate(cvRuntimeCanonical),
    policyPath: AttestationPolicyPath,
    scopeLockPath: AttestationScopeLockPath,
    leanExe: "",
    z3Path: "",
    ircheckExe: "",
    leanTimeoutMs: defaultLeanReexecTimeoutMs,
    z3TimeoutMs: defaultZ3ReexecTimeoutMs,
    extractionTimeoutMs: 60_000)

# ---------------------------------------------------------------------------
# Evidence bundle — canonical wire + digest (pure)
# ---------------------------------------------------------------------------

func evidenceBundleWire*(inputs: AttestationInputs): string {.raises: [].} =
  ## Canonical evidence-bundle wire (v2): the exact inputs the attest chain
  ## re-executes (extraction inputs + both kernel inputs) PLUS the recorded
  ## toolchain identity and the Rust extraction binding. evidenceDigest =
  ## sha256 over this wire; tampering ANY re-executed input — or swapping the
  ## consumed LLBC (llbcDigest) or the measured Rust toolchain — changes the
  ## digest bound by the certificate. The v1→v2 member-set widening IS the
  ## schema cutover (EvidenceScheme); the member set is closed and fixed.
  canonicalJsonString(%*{
    "funcSource": inputs.funcSource,
    "funcName": inputs.funcName,
    "leanSource": inputs.leanSource,
    "smtlib2": inputs.smtlib2,
    "toolchainIdentity": inputs.toolchainIdentity,
    "llbcDigest": inputs.llbcDigest,
    "rustToolchainIdentity": inputs.rustToolchainIdentity
  })

func evidenceBundleDigest*(inputs: AttestationInputs): string {.raises: [].} =
  sha256Hex(evidenceBundleWire(inputs))

# ---------------------------------------------------------------------------
# Evidence-record codec (fail-closed parse/validate)
# ---------------------------------------------------------------------------

func validateAttestationInputs*(inputs: AttestationInputs): string {.raises: [].} =
  ## "" = well-formed; otherwise the rejection reason. Record-required fields
  ## are non-empty except prNumber (0 = "no PR context" is honest). policyDigest
  ## and scopeDigest are deliberately NOT record-level: an empty digest must
  ## surface at its own chain stage (d/f) with the stage verdict — "missing ≠
  ## valid-empty" is enforced where the digest is consumed, never masked by an
  ## earlier generic validation error.
  if inputs.schemaVersion != EvidenceScheme:
    return "attestation: unsupported evidence schemaVersion (fail-closed)"
  if not isHexOfLen(inputs.subjectId, 64):
    return "attestation: subjectId must be 64 lowercase hex chars (fail-closed)"
  if not isHexOfLen(inputs.prHeadSha, 40):
    return "attestation: prHeadSha must be 40 lowercase hex chars (fail-closed)"
  if not isHexOfLen(inputs.envDigest, 64):
    return "attestation: envDigest must be 64 lowercase hex chars (fail-closed)"
  for (label, value) in [("leanSource", inputs.leanSource), ("smtlib2", inputs.smtlib2),
                         ("funcSource", inputs.funcSource), ("funcPath", inputs.funcPath),
                         ("funcName", inputs.funcName),
                         ("toolchainIdentity", inputs.toolchainIdentity)]:
    if value.len == 0:
      return "attestation: empty evidence field '" & label & "' (fail-closed)"
  ## v2 Rust extraction binding — all-or-nothing coherence: BOTH empty = a
  ## lane that consumed no LLBC (honest absence); BOTH well-formed = a lane
  ## whose evidenceDigest binds the LLBC bytes and the measured Rust
  ## toolchain. Any half-bound record is malformed (fail-closed).
  if inputs.llbcDigest.len > 0 or inputs.rustToolchainIdentity.len > 0:
    if not isHexOfLen(inputs.llbcDigest, 64):
      return "attestation: llbcDigest must be 64 lowercase hex chars (fail-closed)"
    let tokenProblem = validateRustToolchainIdentityToken(inputs.rustToolchainIdentity)
    if tokenProblem.len > 0:
      return "attestation: " & tokenProblem
  ""

func inputsFromJson*(node: JsonNode): Result[AttestationInputs, string] {.raises: [].} =
  ## Strict record decode: missing/mistyped fields → err (never defaults).
  if node.isNil or node.kind != JObject:
    return err("attestation: evidence record must be a JSON object")
  template need(key: string): string =
    block:
      let v = node{key}
      if v.isNil or v.kind != JString:
        return err("attestation: evidence field '" & key & "' missing or not a string")
      v.getStr()
  let numberField = block:
    let v = node{"prNumber"}
    if v.isNil or v.kind != JInt:
      return err("attestation: evidence field 'prNumber' missing or not an int")
    v.getInt()
  # v2 fields — OPTIONAL-IN-PRESENCE (lanes/witness embeddings without a Rust
  # extraction binding omit them), strictly typed when present: a present
  # field that is not a string is malformed; an ABSENT field folds to "" (the
  # honest no-LLBC lane). The schemaVersion gate above is what makes this
  # optional-presence safe: v1 records are rejected wholesale, never
  # reinterpreted with implicit empty bindings.
  template opt(key: string): string =
    block:
      let v = node{key}
      if v.isNil:
        ""
      elif v.kind != JString:
        return err("attestation: evidence field '" & key & "' present but not a string")
      else:
        v.getStr()
  let inputs = AttestationInputs(
    schemaVersion: need("schemaVersion"),
    subjectId: need("subjectId"),
    prNumber: numberField,
    prHeadSha: need("prHeadSha"),
    leanSource: need("leanSource"),
    smtlib2: need("smtlib2"),
    funcSource: need("funcSource"),
    funcPath: need("funcPath"),
    funcName: need("funcName"),
    policyDigest: need("policyDigest"),
    scopeDigest: need("scopeDigest"),
    envDigest: need("envDigest"),
    toolchainIdentity: need("toolchainIdentity"),
    llbcDigest: opt("llbcDigest"),
    rustToolchainIdentity: opt("rustToolchainIdentity"))
  let problem = validateAttestationInputs(inputs)
  if problem.len > 0:
    return err(problem)
  ok(inputs)

proc parseAttestationEvidenceText*(text: string): Result[AttestationInputs, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Text → validated evidence record (parseJson lives at the I/O boundary;
  ## validation stays pure).
  if text.len == 0:
    return err("attestation: evidence text is empty (fail-closed)")
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError:
    return err("attestation: malformed evidence JSON (fail-closed)")
  inputsFromJson(node)

# ---------------------------------------------------------------------------
# Pure verdict helpers
# ---------------------------------------------------------------------------

func extractionVerdictFor*(verdict: ExtractionAgreementVerdict): AttestationVerdict {.raises: [].} =
  ## Tier-2 stage mapping. eaAgree is the ONLY evidence-carrying outcome;
  ## every other verdict is a FAIL here (the certified subset is mandatory
  ## for certification — EA_UNSUPPORTED is not a skip).
  case verdict
  of eaAgree: atPassed
  of eaUnsupported: atExtractionUnsupported
  of eaMismatch, eaReferenceError, eaInternalError: atExtractionMismatch

func kernelLeanVerdictFor*(v: KernelVerdict): AttestationVerdict {.raises: [].} =
  if v == krPassed: atPassed else: atKernelLeanFail

func kernelZ3VerdictFor*(v: KernelVerdict): AttestationVerdict {.raises: [].} =
  if v == krPassed: atPassed else: atKernelZ3Fail

# ---------------------------------------------------------------------------
# I/O helpers (single-threaded orchestration; fresh processes only)
# ---------------------------------------------------------------------------

proc currentUtcTimestamp*(): string {.raises: [].} =
  ## ISO8601 UTC ("yyyy-MM-dd'T'HH:mm:ss'Z'") — same canonical form as the
  ## subject store's createdAt (verification_subject.isValidIso8601Zulu).
  format(now().utc, "yyyy-MM-dd'T'HH:mm:ss'Z'")

proc reloadStoredSubject(subject: VerificationSubject; subjectsDir: string): Result[VerificationSubject, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage (a) reload: the authoritative subject is the append-only store
  ## record. Ref → exactly one record required: none = unknown subject
  ## (fail-closed), several = store integrity violation (fail-closed).
  let listing = listSubjects(subjectsDir)
  if listing.isErr:
    return err("subject store unreadable: " & listing.error)
  var matches: seq[VerificationSubject] = @[]
  for id in listing.get:
    let loaded = loadSubject(id, subjectsDir)
    if loaded.isErr:
      return err("subject store record unreadable: " & loaded.error)
    if loaded.get.headSha == subject.headSha:
      matches.add(loaded.get)
  if matches.len == 0:
    return err("no stored subject for headSha " & subject.headSha & " (fail-closed)")
  if matches.len > 1:
    return err("multiple stored subjects for headSha " & subject.headSha &
      " — store integrity violation (fail-closed)")
  ok(matches[0])

# ---------------------------------------------------------------------------
# Evidence CAS — HIT/MISS plan + the sanctioned kernel-chain skip (§15.3)
# ---------------------------------------------------------------------------

## The Evidence CAS reuse surface of the witness chain. When
## AXIOM_EVIDENCE_CAS_ENABLED=1 the witness production first re-derives the
## EvidenceKey from the CURRENT workspace (verifier identity + evidence draft
## + tree OIDs + policy set + scope lock — collectEvidenceKeyInputs), consults
## the durable evidence side-ref ledger READ-ONLY, and:
##
##   MISS (key absent) — run the trusted chain a-f EXACTLY as today (INV-4
##     extraction differential + INV-6 kernel re-execution all fresh), then
##     emit the canonical evidence record for the trusted mint to append.
##   HIT (key present) — fetch + re-verify the stored record (payloadSha256
##     recomputed over the re-read bytes, full record validation, key ==
##     requested) and SKIP stages (b)+(c) — the ONLY sanctioned skip, valid
##     solely under the §15.3 reuse conditions: fresh key re-derivation from
##     the full semantic input set, ledger membership + byte re-read +
##     sha256 recompute (fetchEvidenceRecord), stored outcome all-pass with
##     bundle fields byte-equal to this run's evidence record, and stages
##     (a)+(d)(e)(f) — subject binding plus policy/toolchain/scope
##     actual-equivalence — still executed fresh below. Fresh witness/
##     subjectId/certTree derivation continues exactly as today; ONLY the
##     semantic evidence facts (irHash + verdicts) are reused, and the run is
##     honestly marked via the AXIOM_EVIDENCE_CAS log lines.
##
## Any enabled-but-unverifiable state (missing env, unreadable input, corrupt
## ledger record, unreadable ledger) is casError → atInternalError —
## fail-closed: reuse is never guessed, and an unverifiable ledger is never
## reported as a MISS. Env unset/zero → casOff → byte-identical legacy chain,
## no new reads, no new files.

type
  EvidenceCasMode* = enum
    casOff     ## AXIOM_EVIDENCE_CAS_ENABLED unset/"0" — legacy path, zero delta
    casHit     ## ledger record verified — kernel chain skipped (§15.3 reuse)
    casMiss    ## key absent — full chain runs, evidence record produced
    casError   ## enabled but a precondition/ledger read failed — fail closed

  EvidenceCasPlan* = object
    mode*: EvidenceCasMode
    reason*: string                ## populated on casError (the fail-closed reason)
    evidenceKey*: string           ## 64-hex key (hit/miss)
    payloadSha256*: string         ## hit: the re-verified payload digest
    payload*: string               ## hit: the re-verified canonical evidence bytes
    verifierArtifactDigests*: JsonNode ## metadata for the emitted record (NOT identity)
    recordPath*: string            ## enabled: path the evidence record file is written to
    repo*: string                  ## ledger repo (resolved)
    refName*: string               ## ledger side ref (EvidenceCasRefName)

func disabledEvidenceCasPlan*(): EvidenceCasPlan {.raises: [].} =
  ## The env-unset plan — the caller passes this when CAS is off; the chain
  ## then behaves byte-identically to the legacy attestChain.
  EvidenceCasPlan(mode: casOff)

func evidenceCasReuseLogLine*(plan: EvidenceCasPlan): string {.raises: [].} =
  ## The greppable runtime log line for the resolved CAS branch — the single
  ## source of the exact wire text (the CLI echoes it verbatim; HIT/MISS only:
  ## casOff is silent in-process, the engine step prints the NO-FIRE line).
  case plan.mode
  of casHit:
    "AXIOM_EVIDENCE_CAS: HIT — reused + rebound record " &
      plan.evidenceKey[0 ..< min(plan.evidenceKey.len, 12)] &
      " (evidence bytes re-verified)"
  of casMiss:
    "AXIOM_EVIDENCE_CAS: MISS — produced + stored record " &
      plan.evidenceKey[0 ..< min(plan.evidenceKey.len, 12)]
  of casOff, casError:
    ""

func evidenceCasDisabled*(value: string): bool {.raises: [].} =
  ## The env-off contract: unset ("") or explicit "0" — anything else must be
  ## exactly "1" (an unexpected value fails closed later, it never silently
  ## disables the reuse gate).
  value.len == 0 or value == "0"

proc planEvidenceCasWithTransport*(repoRoot: string; transport: LedgerTransport): EvidenceCasPlan
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Resolve the CAS plan for this run: env contract → fail-closed input
  ## collection → EvidenceKey derivation → read-only ledger consult. The
  ## transport is injectable (tests); planEvidenceCas is the live wrapper.
  let enabled = getEnv("AXIOM_EVIDENCE_CAS_ENABLED", "")
  if evidenceCasDisabled(enabled):
    return disabledEvidenceCasPlan()
  if enabled != "1":
    return EvidenceCasPlan(mode: casError,
      reason: "AXIOM_EVIDENCE_CAS_ENABLED='" & enabled & "' is not '1' (fail-closed)")
  let baseTreeOid = getEnv("AXIOM_EVIDENCE_CAS_BASE_TREE_OID", "")
  let headTreeOid = getEnv("AXIOM_EVIDENCE_CAS_HEAD_TREE_OID", "")
  let mergeTreeOid = getEnv("AXIOM_EVIDENCE_CAS_MERGE_TREE_OID", "")
  for (label, oid) in [("BASE", baseTreeOid), ("HEAD", headTreeOid), ("MERGE", mergeTreeOid)]:
    if not isHexOfLen(oid, 40):
      return EvidenceCasPlan(mode: casError,
        reason: "AXIOM_EVIDENCE_CAS_" & label & "_TREE_OID must be a 40-hex git tree OID (fail-closed)")
  let recordPath = getEnv("AXIOM_EVIDENCE_CAS_RECORD_PATH", "")
  if recordPath.len == 0:
    return EvidenceCasPlan(mode: casError,
      reason: "AXIOM_EVIDENCE_CAS_RECORD_PATH is not set — the evidence record has no store path (fail-closed)")
  # Read-only input collection — every digest fail-closed, then the key.
  let inputsRes = collectEvidenceKeyInputs(repoRoot, baseTreeOid, headTreeOid, mergeTreeOid)
  if inputsRes.isErr:
    return EvidenceCasPlan(mode: casError, reason: inputsRes.error)
  let key = deriveEvidenceKey(inputsRes.get)
  # Record metadata (provenance/informational — NEVER part of the identity).
  var digests = newJObject()
  let verifierRes = collectVerifierIdentityInputs(repoRoot, baseTreeOid)
  if verifierRes.isErr:
    return EvidenceCasPlan(mode: casError, reason: verifierRes.error)
  for a in verifierRes.get.artifactDigests:
    digests[a.name] = %a.digest
  var plan = EvidenceCasPlan(
    mode: casMiss,
    evidenceKey: $key,
    verifierArtifactDigests: digests,
    recordPath: recordPath,
    repo: resolveEvidenceCasRepo(),
    refName: EvidenceCasRefName)
  # Read-only ledger consult. An unverifiable ledger is NEVER a MISS:
  # hasEvidence fails closed on any listing anomaly, and a HIT is only
  # claimed after the full record re-verification (byte re-read + sha256
  # recompute + key binding) inside fetchEvidenceRecord.
  let has = hasEvidence(transport, plan.repo, plan.evidenceKey, plan.refName)
  if has.isErr:
    return EvidenceCasPlan(mode: casError,
      reason: "evidence ledger membership read failed: " & has.error & " (fail-closed)")
  if not has.get:
    return plan
  let record = fetchEvidenceRecord(transport, plan.repo, plan.evidenceKey, plan.refName)
  if record.isErr:
    return EvidenceCasPlan(mode: casError,
      reason: "evidence ledger record fetch/verify failed: " & record.error & " (fail-closed)")
  plan.mode = casHit
  plan.payloadSha256 = record.get.payloadSha256
  plan.payload = record.get.payload
  plan

proc planEvidenceCas*(repoRoot: string): EvidenceCasPlan
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Live plan — GITHUB_TOKEN fail-closed (no token = no ledger read = no
  ## reuse claim), transport = liveLedgerTransport against EvidenceCasRefName.
  let enabled = getEnv("AXIOM_EVIDENCE_CAS_ENABLED", "")
  if evidenceCasDisabled(enabled):
    return disabledEvidenceCasPlan()
  let token = getEnv("GITHUB_TOKEN", "")
  if token.len == 0:
    return EvidenceCasPlan(mode: casError,
      reason: "GITHUB_TOKEN not set — evidence ledger read refused (fail-closed)")
  planEvidenceCasWithTransport(repoRoot, liveLedgerTransport(token, EvidenceCasRefName))

proc reuseIrHashFromPayload*(payload: string; evidence: AttestationInputs): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## HIT re-verification against THIS run's evidence record: the stored
  ## canonical evidence payload must (1) parse, (2) carry an ALL-PASS outcome
  ## (a stored non-pass record is corruption — never reusable), (3) carry a
  ## 64-hex irHash, and (4) have its four bundle fields BYTE-EQUAL to the
  ## local evidence record (a divergence means the key inputs under-determined
  ## the evidence — an identity anomaly, fail-closed). Returns the reused
  ## irHash — the extraction-agreement identity stage (b) would have produced.
  var node: JsonNode
  try:
    node = parseJson(payload)
  except CatchableError:
    return err("stored evidence payload is not valid JSON (fail-closed)")
  if node.isNil or node.kind != JObject:
    return err("stored evidence payload is not a JSON object (fail-closed)")
  template need(key: string): string =
    block:
      let v = node{key}
      if v.isNil or v.kind != JString or v.getStr().len == 0:
        return err("stored evidence payload field '" & key & "' missing/empty (fail-closed)")
      v.getStr()
  let extraction = need("extractionVerdict")
  let lean = need("leanVerdict")
  let z3 = need("z3Verdict")
  if extraction != $eaAgree or lean != $krPassed or z3 != $krPassed:
    return err("stored evidence payload is not an ALL-PASS outcome (" & extraction & "/" &
      lean & "/" & z3 & ") — never reusable (fail-closed)")
  let irHash = need("irHash")
  if not isHexOfLen(irHash, 64):
    return err("stored evidence payload irHash is not 64-hex (fail-closed)")
  for (label, stored, local) in [("funcSource", need("funcSource"), evidence.funcSource),
                                 ("funcName", need("funcName"), evidence.funcName),
                                 ("leanSource", need("leanSource"), evidence.leanSource),
                                 ("smtlib2", need("smtlib2"), evidence.smtlib2)]:
    if stored != local:
      return err("stored evidence payload field '" & label & "' diverges from this run's evidence record (identity anomaly, fail-closed)")
  ok(irHash)

proc normalizedEvidenceForRun*(evidence: AttestationInputs;
                               agreement: ExtractionAgreementResult): Result[NormalizedEvidence, string] {.raises: [].} =
  ## The MISS record's semantic kernel record from THIS run's fresh outcome.
  ## Only legal after attestWitnessChainCas returned atPassed on a casMiss
  ## plan: stage (b) proved extraction agreement (eaAgree) and stage (c)
  ## proved BOTH kernels krPassed — the verdicts here restate that proven
  ## outcome, they do not assert it.
  if agreement.verdict != eaAgree:
    return err("extraction verdict " & $agreement.verdict & " is not a reusable outcome (fail-closed)")
  let irHash = if agreement.nimDigest.len > 0: agreement.nimDigest
    else: evidenceBundleDigest(evidence)
  let ne = NormalizedEvidence(
    funcSource: evidence.funcSource,
    funcName: evidence.funcName,
    leanSource: evidence.leanSource,
    smtlib2: evidence.smtlib2,
    irHash: irHash,
    extractionVerdict: eaAgree,
    leanVerdict: krPassed,
    z3Verdict: krPassed)
  let problem = validateNormalizedEvidence(ne)
  if problem.len > 0:
    return err(problem)
  ok(ne)

proc buildEvidenceCasRecord*(plan: EvidenceCasPlan; payload: string;
                             evidence: AttestationInputs): Result[EvidenceCasRecord, string] {.
    raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The record for the emitted evidence: identity = plan.evidenceKey, payload
  ## = canonical normalized-evidence bytes, digest/timestamp = fresh audit
  ## metadata (NOT identity). The evidenceDigest is computed HERE — inside the
  ## single-definition module — from the attestation inputs
  ## (evidenceBundleDigest over the canonical 7-member evidenceBundleWire, the
  ## SAME authority the witness's .semantic.evidenceDigest carries), so no
  ## caller can inject an arbitrary digest, the value is never taken from the
  ## payload, and the record's binding digest cannot diverge from the witness:
  ## the mint COMPARES record.evidenceDigest == witness .semantic.evidenceDigest,
  ## never re-derives (ADR-0034). The trusted mint appends it idempotently — a
  ## HIT rebound record (same key + same payload bytes) lands as a no-op.
  makeEvidenceRecord(plan.evidenceKey, payload, plan.verifierArtifactDigests,
    currentUtcTimestamp(), evidenceBundleDigest(evidence))


# ---------------------------------------------------------------------------
# attest — the trusted chain, in order, fail-closed
# ---------------------------------------------------------------------------

proc attestSubjectStage(subject: VerificationSubject; evidence: AttestationInputs;
                        options: AttestationOptions): AttestationResult
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage (a): the authoritative subject is the append-only store record.
  ## Reload by ref (exactly one) and require EXACT equality — empty inputs
  ## are never equal (svEmptyInput, INV-1). The evidence binding must name
  ## the same subject.
  let stored = reloadStoredSubject(subject, options.subjectsDir)
  if stored.isErr:
    return AttestationResult(verdict: atSubjectMismatch, reason: "stage-a subject reload: " & stored.error)
  let storedVerdict = verifySubjectMatch(stored.get, subject)
  if not isSubjectMatch(storedVerdict):
    return AttestationResult(verdict: atSubjectMismatch,
      reason: "stage-a subject mismatch: " & $storedVerdict &
      " (store subject differs from the attestation subject)")
  if evidence.subjectId != subject.subjectId:
    return AttestationResult(verdict: atSubjectMismatch,
      reason: "stage-a subject mismatch: evidence subjectId differs from the store subject")
  if evidence.prHeadSha != subject.headSha:
    return AttestationResult(verdict: atSubjectMismatch,
      reason: "stage-a subject mismatch: evidence prHeadSha " & evidence.prHeadSha[0 ..< min(evidence.prHeadSha.len, 12)] &
      " != subject headSha " & subject.headSha[0 ..< min(subject.headSha.len, 12)] & " (fail-closed)")
  AttestationResult(verdict: atPassed)

proc attestExtractionStage(evidence: AttestationInputs; options: AttestationOptions;
                           agreement: var ExtractionAgreementResult): AttestationResult
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage (b): record validation + per-run extraction differential. eaAgree
  ## is the ONLY evidence-carrying outcome; EA_UNSUPPORTED is a FAIL here —
  ## the certified subset is MANDATORY for certification (contract §6).
  let problem = validateAttestationInputs(evidence)
  if problem.len > 0:
    return AttestationResult(verdict: atInternalError, reason: "stage-b evidence: " & problem)
  agreement = runExtractionAgreement(evidence.funcSource, evidence.funcName,
    options.ircheckExe, "", options.extractionTimeoutMs)
  let agreeVerdict = extractionVerdictFor(agreement.verdict)
  if agreeVerdict != atPassed:
    return AttestationResult(verdict: agreeVerdict,
      reason: "stage-b extraction agreement: " & agreement.reason &
      " (" & agreementReasonCode(agreement.verdict) & ")")
  AttestationResult(verdict: atPassed)

proc attestKernelStage(evidence: AttestationInputs; options: AttestationOptions): AttestationResult
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage (c): fresh kernel re-execution of the RECORDED evidence — Lean
  ## typecheck + INV-6 axiom allowlist, then Z3 fresh unsat under the INV-10
  ## checksum pin. Only krPassed continues; order: lean first, fail-closed.
  var certLike = newJObject()
  certLike["leanSource"] = %(evidence.leanSource)
  certLike["smtlib2"] = %(evidence.smtlib2)
  let leanVerdict = reexecuteLean(certLike, options.leanExe, options.leanTimeoutMs)
  let leanStage = kernelLeanVerdictFor(leanVerdict)
  if leanStage != atPassed:
    return AttestationResult(verdict: leanStage,
      reason: "stage-c lean re-execution: " & kernelVerdictReason(leanVerdict))
  let z3Verdict = reexecuteZ3(certLike, options.z3Path, options.z3TimeoutMs)
  let z3Stage = kernelZ3VerdictFor(z3Verdict)
  if z3Stage != atPassed:
    return AttestationResult(verdict: z3Stage,
      reason: "stage-c z3 re-execution: " & kernelVerdictReason(z3Verdict))
  AttestationResult(verdict: atPassed)

proc attestPolicyStage(evidence: AttestationInputs; options: AttestationOptions): AttestationResult
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stages (d)(e)(f): recorded digest set must equal the CURRENT state —
  ## policy file bytes, the pinned D2 toolchain identity, and the installed
  ## verification scope lock. Empty recorded digests are denied with the
  ## stage verdict (missing ≠ valid-empty).
  if evidence.policyDigest.len == 0:
    return AttestationResult(verdict: atPolicyDigestMismatch,
      reason: "stage-d policy digest empty (fail-closed: missing ≠ valid-empty)")
  let policyActual = fileSha256Hex(options.policyPath)
  if policyActual.isErr:
    return AttestationResult(verdict: atPolicyDigestMismatch,
      reason: "stage-d policy digest: " & policyActual.error)
  if policyActual.get != evidence.policyDigest:
    return AttestationResult(verdict: atPolicyDigestMismatch,
      reason: "stage-d policy digest mismatch: recorded " & evidence.policyDigest[0 ..< 12] &
      " != sha256(policy file) " & policyActual.get[0 ..< 12])
  let toolchainNow = pinnedToolchainIdentity()
  if evidence.toolchainIdentity.len == 0 or evidence.toolchainIdentity != toolchainNow:
    return AttestationResult(verdict: atToolchainMismatch,
      reason: "stage-e toolchain identity mismatch: recorded '" &
      evidence.toolchainIdentity & "' != pinned '" & toolchainNow & "'")
  if evidence.scopeDigest.len == 0:
    return AttestationResult(verdict: atScopeMismatch,
      reason: "stage-f scope digest empty (fail-closed: missing ≠ valid-empty)")
  let scopeActual = fileSha256Hex(options.scopeLockPath)
  if scopeActual.isErr:
    return AttestationResult(verdict: atScopeMismatch,
      reason: "stage-f scope digest: " & scopeActual.error)
  if scopeActual.get != evidence.scopeDigest:
    return AttestationResult(verdict: atScopeMismatch,
      reason: "stage-f scope digest mismatch: recorded " & evidence.scopeDigest[0 ..< 12] &
      " != sha256(scope lock) " & scopeActual.get[0 ..< 12])
  AttestationResult(verdict: atPassed)

proc attestMintStage(subject: VerificationSubject; evidence: AttestationInputs;
                     certDir: string; agreement: ExtractionAgreementResult;
                     createdAt: string; mergeTreeDigest: string = ""): AttestationResult
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Stage (g): ALL PASS → mint through the v3 writer extension (journal-bound,
  ## Ed25519-attested). Certificate fields bind the subject identity, the chain
  ## provenance and the digest set asserted by stages (a)-(f). createdAt is the
  ## mint timestamp: attest() passes the current time; the witness→sign surface
  ## (DEBT#464 S4 Phase 1a) passes the witness-recorded time so identical
  ## semantic inputs yield byte-identical certificate representations.
  ## mergeTreeDigest (the merge-candidate tree OID) is forwarded into the
  ## certificate's certTree binding field — the legacy full-attest surface may
  ## leave it empty (no merge context); the witness→sign surface always carries
  ## it (provenance.mergeTreeDigest, validated 40-hex).
  let evidenceDigest = evidenceBundleDigest(evidence)
  let certInput = SubjectCertificateInput(
    subject: subject,
    modulePath: evidence.funcPath,
    sourceCode: evidence.funcSource,
    funcName: evidence.funcName,
    leanSource: evidence.leanSource,
    smtlib2: evidence.smtlib2,
    leanProposition: firstDeclaredName(evidence.leanSource),
    prHeadSha: evidence.prHeadSha,
    prNumber: evidence.prNumber,
    envDigest: evidence.envDigest,
    policyDigest: evidence.policyDigest,
    scopeDigest: evidence.scopeDigest,
    toolchainIdentity: evidence.toolchainIdentity,
    evidenceDigest: evidenceDigest,
    irHash: (if agreement.nimDigest.len > 0: agreement.nimDigest else: evidenceDigest),
    createdAt: createdAt,
    certTree: mergeTreeDigest,
    axiomVersion: axiomVersionWithPrefix)
  let minted = writeSubjectContinuityCertificate(certDir, certInput)
  if minted.isErr:
    return AttestationResult(verdict: atInternalError,
      reason: "stage-g certificate mint failed: " & minted.error)
  AttestationResult(verdict: atPassed,
    reason: "trusted attestation chain passed (a-f) — subject-continuity certificate minted",
    certPath: minted.get.path, commitId: minted.get.commitId)

proc attestChain*(subject: VerificationSubject; evidence: AttestationInputs;
                  options: AttestationOptions; agreement: var ExtractionAgreementResult): AttestationResult
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The trusted Verify(E, M) chain (contract §4.1) — stages (a)-(f) gated IN
  ## ORDER, fail-closed at every step. NO mint: witness-only (DEBT#464 S4
  ## Phase 1a) reuses these exact gates to produce an unsigned witness bundle.
  ## run.conclusion / step census are NOT evidence (INV-5): every stage below
  ## is re-executed fresh in this process.
  let stageA = attestSubjectStage(subject, evidence, options)
  if stageA.verdict != atPassed: return stageA
  let stageB = attestExtractionStage(evidence, options, agreement)
  if stageB.verdict != atPassed: return stageB
  let stageC = attestKernelStage(evidence, options)
  if stageC.verdict != atPassed: return stageC
  let stageDF = attestPolicyStage(evidence, options)
  if stageDF.verdict != atPassed: return stageDF
  AttestationResult(verdict: atPassed)

proc attestWitnessChainCas*(subject: VerificationSubject; evidence: AttestationInputs;
                            options: AttestationOptions; agreement: var ExtractionAgreementResult;
                            cas: EvidenceCasPlan; reusedIrHash: var string): AttestationResult
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The witness-production chain with the Evidence CAS branch:
  ##   casOff / casMiss — stages (a)-(f) EXACTLY as attestChain (byte-identical
  ##     legacy path; MISS merely carries the plan for the record emission).
  ##   casHit — stage (a), then the §15.3 SANCTIONED SKIP of stages (b)+(c)
  ##     (INV-4 extraction differential + INV-6 kernel re-execution): the
  ##     stored record's semantic facts are reused after full re-verification
  ##     (payload re-read + payloadSha256 recompute happened in the plan's
  ##     fetchEvidenceRecord; bundle-field byte-equality + ALL-PASS outcome +
  ##     64-hex irHash are re-checked here against THIS run's evidence
  ##     record), and `reusedIrHash` carries the reused extraction identity.
  ##     Stages (d)(e)(f) still run — policy/toolchain/scope must equal the
  ##     CURRENT state (the toolchain actual-equivalence condition). Fresh
  ##     witness/subjectId/certTree derivation continues in the caller
  ##     exactly as today.
  ##   casError — atInternalError: an enabled-but-unverifiable CAS state never
  ##     degrades into a chain run, and a corrupt ledger record never PASSes.
  let stageA = attestSubjectStage(subject, evidence, options)
  if stageA.verdict != atPassed: return stageA
  case cas.mode
  of casError:
    return AttestationResult(verdict: atInternalError,
      reason: "evidence CAS enabled: " & cas.reason)
  of casHit:
    let reuse = reuseIrHashFromPayload(cas.payload, evidence)
    if reuse.isErr:
      return AttestationResult(verdict: atInternalError,
        reason: "evidence CAS HIT re-verification: " & reuse.error)
    reusedIrHash = reuse.get
  of casOff, casMiss:
    let stageB = attestExtractionStage(evidence, options, agreement)
    if stageB.verdict != atPassed: return stageB
    let stageC = attestKernelStage(evidence, options)
    if stageC.verdict != atPassed: return stageC
  let stageDF = attestPolicyStage(evidence, options)
  if stageDF.verdict != atPassed: return stageDF
  AttestationResult(verdict: atPassed)

proc attest*(subject: VerificationSubject; evidence: AttestationInputs;
             options: AttestationOptions = defaultAttestationOptions();
             mergeTreeDigest: string = ""): AttestationResult
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The trusted Verify(E, M) chain (contract §4.1) — stages (a)-(f) gated IN
  ## ORDER, fail-closed at every step; ALL PASS → (g) mint at the current
  ## timestamp. Any failure returns its verdict with the precise reason; no
  ## certificate is written on a non-PASS run. run.conclusion / step census are
  ## NOT evidence (INV-5): every stage below is re-executed fresh in this process.
  ## mergeTreeDigest (optional, legacy full-attest surface) forwards the
  ## merge-candidate tree OID into the certificate's certTree binding.
  var agreement: ExtractionAgreementResult
  let chain = attestChain(subject, evidence, options, agreement)
  if chain.verdict != atPassed: return chain
  attestMintStage(subject, evidence, options.certDir, agreement, currentUtcTimestamp(), mergeTreeDigest)

{.pop.}
