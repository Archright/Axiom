import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Evidence CAS — content-addressed evidence reuse for the landing flow.
##
## Axiom's landing flow mints a certificate for the subject
## (baseSha, headSha, headTreeDigest, policyDigest, scopeDigest, evidenceDigest).
## This module defines the SEMANTIC IDENTITY under which produced evidence may
## be stored once and reused: evidence is a durable FACT keyed by its semantic
## identity, and execution (Lean/Z3 re-execution, extraction agreement) is the
## production MECHANISM that mints the fact. When the identity is unchanged,
## the mechanism has already run and its verdict is reusable; when anything
## semantic changes, the key changes and the fact must be produced again.
##
## EvidenceKey = H(verifierIdentity, evidenceDraftDigest, headTreeDigest,
## mergeTreeDigest, policyDigest, scopeDigest). The key includes EVERY semantic
## input and NO provenance: runId, runAttempt, job name, runner image labels,
## BuildEnv BuildDate/GitHash/CommitCount build stamps, ciEpochId label
## strings, lock/mode/maxJobs, nimcache contents, ledger state and timestamps
## have NO field to travel through. Built-binary byte hashes are NOT a sound
## verifier identity either: tools/hermetic_build.nim embeds
## BuildEnvBuildDate/BuildEnvGitHash/BuildEnvCommitCount into the compiled
## artifacts, so a same-tree rebuild produces different bytes with identical
## verification semantics — hashing them would make the key differ on every
## CI run (permanent false MISS). The verifier identity is therefore a
## semantic digest (composeVerifierIdentity) over the base-tree OID, the
## build recipe, the toolchain pins, the Z3 checksum policy and the solver
## option set — nothing else. Artifact digests are RECORD-LEVEL integrity
## metadata of the stored evidence and never enter the key, and the collected
## set covers ONLY the binaries a verification path EXECUTES
## (ExecutedArtifactPaths) — their bytes shape the fresh verdict. Build-only
## binaries are executed by no verification path, and their workspace
## presence depends on runner cache state: demanding them fail-closed made
## the same tree+policy pass or fail nondeterministically (2026-10-06
## admission incident, untracked bin/gate_hook).
##
## All hashing reuses the house kernel (sha256Hex) and the house canonical
## serializer (canonicalJsonString, RFC 8785): fixed member set, canonical
## key order, explicit separators, UTF-8 bytes. Digest collection lives at
## explicit I/O boundaries and is FAIL-CLOSED — a missing or unreadable input
## is an error, never an empty/zero digest.
##
## Naming caution: EvidenceKeyInputs.policyDigest is the CAS's chained digest
## over the whole runtime-read policy SET — a wider identity than the attest
## chain's single-file sha256(config/policy/merge_admission.json)
## (AttestationInputs.policyDigest). Same name, different contracts: the CAS
## key binds every policy byte the landing verdict reads, not only the
## admission policy file.

import std/[algorithm, json, os, strutils]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/trusted/solver_invocation
import verification/canonical_json
import verification/extraction_agreement
import verification/kernel_reexecution
import verification/verification_subject

when fileExists("src/generated/build_env.nim"):
  import generated/build_env
else:
  const BuildEnvZ3Version = ""

axiomIoBoundary()

# ---------------------------------------------------------------------------
# Canonical inputs (consts — the enumerated semantic channels)
# ---------------------------------------------------------------------------

const
  EvidenceKeyScheme* = "axiom.evidence.cas.key.v1"
    ## Domain separator for the EvidenceKey wire — keys of different eras can
    ## never collide across scheme revisions.
  LeanToolchainPinPath* = "proofs/lean-toolchain"
    ## The Lean pin SSOT — the digest comes from this file's CONTENT, never a
    ## version literal duplicated from another module.
  EvidenceDraftPath* = "data/certification/evidence-draft.json"
    ## The base-tree (B) evidence draft — the mandatory base→evidence channel
    ## (admission-check.yml Stage D9 reads this exact path @B).
  Z3ChecksumPolicyPath* = "data/policy/z3_binary_checksums.json"
    ## The INV-10 checksum policy the runtime z3 verdict is pinned against
    ## (kernel_reexecution.z3BinaryChecksumAccepted).
  ScopeLockPath* = "data/verification_scope.lock"
    ## The installed verification scope (stage-f digest source).
  RecipeDigestInputPaths*: array[4, string] = [
    "Makefile",
    "config.nims",
    "config/effects.nims",
    "src/gate/config.nims"]
    ## The build-recipe set — the SAME recipe set the B-cache key uses
    ## (.github/actions/setup-axiom-toolchain/action.yml "Build-script
    ## identity": Makefile, config.nims, config/effects.nims,
    ## src/gate/config.nims chained sha256).
  PolicyDigestInputPaths*: array[5, string] = [
    "config/decision_binding.waiver.json",
    "config/policy/epoch_manifest.json",
    "config/policy/landing_required_gateway_tests.json",
    "config/policy/merge_admission.json",
    "config/trusted_writer_set.json"]
    ## The runtime-read policy file set, fixed sorted order. Sources: the
    ## merge predicate reads config/policy/merge_admission.json (policy SSOT,
    ## merge_cli.nim currentPolicyDigest) and config/trusted_writer_set.json
    ## (pin@B rotation closure, merge_cli.nim RotationPinBPath); the required-
    ## validations policy config/policy/landing_required_gateway_tests.json
    ## is a rotation companion of the same predicate (merge_cli.nim A2
    ## amendment); the engine execution scope comes from
    ## config/policy/epoch_manifest.json @B (admission-check.yml slice-engine
    ## step); the decision-binding exemption state is
    ## config/decision_binding.waiver.json (decision_binding_gate.nim).
  ExecutedArtifactPaths*: array[1, (string, string)] = [
    ("ircheck", "proofs/.lake/build/bin/ircheck")]
    ## The EXECUTED artifact set — canonical name → workspace path. Only
    ## binaries a verification path actually runs are collected as record
    ## provenance: ircheck is the attest chain's stage-(b) reference
    ## extractor (extraction_agreement.runReferenceExtractorOnWire resolves
    ## its default worker to this exact path and executes it). The former
    ## build-only members (bin/ax, bin/core_purity_gate, bin/gate_hook,
    ## bin/install_ax_cas, bin/precompile_gates) are executed by NO
    ## verification path — their workspace presence is runner cache state,
    ## and collecting their bytes fail-closed made the same tree+policy pass
    ## or fail nondeterministically (2026-10-06 admission incident,
    ## untracked bin/gate_hook).

# ---------------------------------------------------------------------------
# Normalized evidence — the semantic kernel record (pure)
# ---------------------------------------------------------------------------

type
  NormalizedEvidence* = object
    ## The semantic kernel record: the 4-field evidence bundle wire
    ## (attestation_orchestrator.evidenceBundleWire) plus the extraction IR
    ## identity (irHash) and the three verdicts the trusted chain produced.
    ## NO provenance fields: no runId, no runAttempt, no createdAt, no
    ## mergeSha, no prNumber, no timestamps.
    ##
    ## D6 ruling (certification_continuity_contract.md): witness digests are
    ## run-scoped, and comparing them across runs is INVALID. Cross-run
    ## identity is established ONLY through this normalized record and its
    ## EvidenceKey — never by comparing witness/certificate digests between
    ## runs.
    funcSource*: string
    funcName*: string
    leanSource*: string
    smtlib2*: string
    irHash*: string                          ## extraction-agreement IR identity
    extractionVerdict*: ExtractionAgreementVerdict
    leanVerdict*: KernelVerdict
    z3Verdict*: KernelVerdict

export extraction_agreement.ExtractionAgreementVerdict
export kernel_reexecution.KernelVerdict

func normalizedEvidenceWire*(e: NormalizedEvidence): string {.raises: [].} =
  ## Canonical serialization of the normalized record: fixed member set,
  ## RFC 8785 key order, explicit separators, UTF-8 bytes. The member set is
  ## closed — provenance cannot enter without changing this wire and the key
  ## contract with it.
  canonicalJsonString(%*{
    "funcSource": e.funcSource,
    "funcName": e.funcName,
    "leanSource": e.leanSource,
    "smtlib2": e.smtlib2,
    "irHash": e.irHash,
    "extractionVerdict": $e.extractionVerdict,
    "leanVerdict": $e.leanVerdict,
    "z3Verdict": $e.z3Verdict})

func normalizedEvidenceDigest*(e: NormalizedEvidence): string {.raises: [].} =
  ## sha256 over normalizedEvidenceWire — the content address of the record.
  sha256Hex(normalizedEvidenceWire(e))

func validateNormalizedEvidence*(e: NormalizedEvidence): string {.raises: [].} =
  ## "" = well-formed; otherwise the rejection reason. Bundle fields are
  ## non-empty (fail-closed) and irHash is a 64-hex digest.
  for (label, value) in [("funcSource", e.funcSource), ("funcName", e.funcName),
                         ("leanSource", e.leanSource), ("smtlib2", e.smtlib2),
                         ("irHash", e.irHash)]:
    if value.len == 0:
      return "evidence_cas: empty normalized-evidence field '" & label & "' (fail-closed)"
  if not isHexOfLen(e.irHash, 64):
    return "evidence_cas: irHash must be 64 lowercase hex chars (fail-closed)"
  ""

func isReusableOutcome*(e: NormalizedEvidence): bool {.raises: [].} =
  ## Only an ALL-PASS run is evidence worth storing: extraction agreement,
  ## Lean kernel pass, Z3 kernel pass. Any other outcome is not a reusable
  ## fact — caching it would let a failure travel as evidence.
  e.extractionVerdict == eaAgree and
  e.leanVerdict == krPassed and
  e.z3Verdict == krPassed

# ---------------------------------------------------------------------------
# Verifier identity (pure composition)
# ---------------------------------------------------------------------------

type
  ArtifactDigest* = object
    ## Record-level integrity metadata of the stored evidence — NEVER hashed
    ## into the EvidenceKey: built-binary bytes drift across rebuilds without
    ## semantic change (tools/hermetic_build.nim embeds
    ## BuildEnvBuildDate/BuildEnvGitHash/BuildEnvCommitCount into them).
    name*: string    ## canonical artifact name (ExecutedArtifactPaths member)
    digest*: string  ## sha256 of the artifact's bytes

  VerifierIdentityInputs* = object
    ## The semantic parts of the executing verifier. baseTreeOid is supplied
    ## by the caller (CI derives tree OIDs via git; this module performs no
    ## git); everything else is collectible at the I/O boundary below.
    baseTreeOid*: string             ## git tree OID of the verifier build tree B
    recipeDigest*: string            ## chained sha256 over RecipeDigestInputPaths
    nimPin*: string                  ## Nim the verifier executes under (NimVersion)
    leanPin*: string                 ## sha256 of the trimmed proofs/lean-toolchain content
    z3Pin*: string                   ## pinned Z3 version (generated BuildEnvZ3Version)
    z3ChecksumPolicyDigest*: string  ## sha256 of Z3ChecksumPolicyPath bytes
    solverOptionsDigest*: string     ## digest of the deterministic Z3 option set
    artifactDigests*: seq[ArtifactDigest]
    ## Integrity metadata of the stored record (validation requires the
    ## complete canonical executed set) — deliberately EXCLUDED from the
    ## identity hash: same-tree rebuilds change these bytes with no semantic
    ## change.

  EvidenceKeyInputs* = object
    ## The declared member set of EvidenceKey. This object is the whole
    ## derivation surface: a caller CANNOT feed provenance without widening
    ## this type, and the type is the contract.
    verifierIdentity*: string     ## composeVerifierIdentity over VerifierIdentityInputs
    evidenceDraftDigest*: string  ## sha256 of EvidenceDraftPath bytes @B
    headTreeDigest*: string       ## subject head tree OID (H)
    mergeTreeDigest*: string      ## merge-candidate tree OID
    policyDigest*: string         ## collectPolicyDigest over PolicyDigestInputPaths
    scopeDigest*: string          ## sha256 of ScopeLockPath bytes

  EvidenceKey* = distinct string
    ## The content address of reusable evidence — 64 lowercase hex chars.

func `==`*(a, b: EvidenceKey): bool {.borrow.}

func `$`*(k: EvidenceKey): string {.inline, raises: [].} =
  ## The key's 64-hex canonical text form.
  string(k)

func verifierIdentityWire*(inputs: VerifierIdentityInputs): string {.raises: [].} =
  ## Canonical verifier-identity serialization — the SEMANTIC members only.
  ## artifactDigests are deliberately absent: built-binary bytes drift across
  ## same-tree rebuilds (tools/hermetic_build.nim embeds
  ## BuildEnvBuildDate/BuildEnvGitHash/BuildEnvCommitCount), so hashing them
  ## would invalidate the cache on every CI run. They travel as record-level
  ## integrity metadata instead. RFC 8785 fixes the member order.
  canonicalJsonString(%*{
    "baseTreeOid": inputs.baseTreeOid,
    "recipeDigest": inputs.recipeDigest,
    "nimPin": inputs.nimPin,
    "leanPin": inputs.leanPin,
    "z3Pin": inputs.z3Pin,
    "z3ChecksumPolicyDigest": inputs.z3ChecksumPolicyDigest,
    "solverOptionsDigest": inputs.solverOptionsDigest})

func composeVerifierIdentity*(inputs: VerifierIdentityInputs): string {.raises: [].} =
  ## verifierIdentity = H(treeOID(B), recipeDigest, nimPin, leanPin, z3Pin,
  ## z3ChecksumPolicyDigest, solverOptionsDigest). Pure: consumes the declared
  ## semantic parts and nothing else — artifactDigests are record-level
  ## integrity metadata and never enter the identity.
  sha256Hex(verifierIdentityWire(inputs))

func validateVerifierIdentityInputs*(inputs: VerifierIdentityInputs): string {.raises: [].} =
  ## "" = well-formed; otherwise the rejection reason. The artifact set must
  ## be exactly the canonical executed set — a stored record that cannot name
  ## every EXECUTING artifact is incomplete (fail-closed). This is RECORD
  ## integrity: the artifact digests never enter the identity hash.
  if not isHexOfLen(inputs.baseTreeOid, 40):
    return "evidence_cas: verifier baseTreeOid must be a 40-hex git tree OID (fail-closed)"
  if inputs.nimPin.len == 0:
    return "evidence_cas: empty verifier identity field 'nimPin' (fail-closed)"
  if inputs.leanPin.len == 0:
    return "evidence_cas: empty verifier identity field 'leanPin' (fail-closed)"
  if inputs.z3Pin.len == 0:
    return "evidence_cas: empty verifier identity field 'z3Pin' (fail-closed)"
  if not isHexOfLen(inputs.recipeDigest, 64):
    return "evidence_cas: verifier recipeDigest must be 64 lowercase hex chars (fail-closed)"
  if not isHexOfLen(inputs.leanPin, 64):
    return "evidence_cas: verifier leanPin must be 64 lowercase hex chars (fail-closed)"
  if not isHexOfLen(inputs.z3ChecksumPolicyDigest, 64):
    return "evidence_cas: verifier z3ChecksumPolicyDigest must be 64 lowercase hex chars (fail-closed)"
  if not isHexOfLen(inputs.solverOptionsDigest, 64):
    return "evidence_cas: verifier solverOptionsDigest must be 64 lowercase hex chars (fail-closed)"
  var names: seq[string] = @[]
  for a in inputs.artifactDigests:
    if a.name.len == 0:
      return "evidence_cas: artifact digest with empty name (fail-closed)"
    if not isHexOfLen(a.digest, 64):
      return "evidence_cas: artifact '" & a.name & "' digest must be 64 lowercase hex chars (fail-closed)"
    names.add(a.name)
  names.sort()
  var canonical: seq[string] = @[]
  for (name, _) in ExecutedArtifactPaths:
    canonical.add(name)
  if names != canonical:
    return "evidence_cas: artifact set must be exactly the canonical executed set (fail-closed)"
  ""

# ---------------------------------------------------------------------------
# EvidenceKey derivation (pure)
# ---------------------------------------------------------------------------

func evidenceKeyWire*(inputs: EvidenceKeyInputs): string {.raises: [].} =
  ## Canonical EvidenceKey serialization — the fixed member set, RFC 8785 key
  ## order, explicit separators, UTF-8 bytes. Consumes NOTHING beyond the
  ## declared members; the schema constant domain-separates the key space.
  canonicalJsonString(%*{
    "schema": EvidenceKeyScheme,
    "verifierIdentity": inputs.verifierIdentity,
    "evidenceDraftDigest": inputs.evidenceDraftDigest,
    "headTreeDigest": inputs.headTreeDigest,
    "mergeTreeDigest": inputs.mergeTreeDigest,
    "policyDigest": inputs.policyDigest,
    "scopeDigest": inputs.scopeDigest})

func deriveEvidenceKey*(inputs: EvidenceKeyInputs): EvidenceKey {.raises: [].} =
  ## EvidenceKey = H(canonical serialization of inputs). Pure: consumes the
  ## declared inputs and nothing else — the signature is the proof that
  ## run-scoped provenance cannot affect the key. Callers obtain inputs from
  ## the fail-closed collectors below (validateEvidenceKeyInputs is the
  ## well-formedness gate; collectors never emit empty digests).
  sha256Hex(evidenceKeyWire(inputs)).EvidenceKey

func validateEvidenceKeyInputs*(inputs: EvidenceKeyInputs): string {.raises: [].} =
  ## "" = well-formed; otherwise the rejection reason. Digest members are
  ## 64-hex; tree members are 40-hex git OIDs. Empty is never valid — a
  ## missing input surfaces here instead of degenerating the key.
  if not isHexOfLen(inputs.verifierIdentity, 64):
    return "evidence_cas: verifierIdentity must be 64 lowercase hex chars (fail-closed)"
  if not isHexOfLen(inputs.evidenceDraftDigest, 64):
    return "evidence_cas: evidenceDraftDigest must be 64 lowercase hex chars (fail-closed)"
  if not isHexOfLen(inputs.headTreeDigest, 40):
    return "evidence_cas: headTreeDigest must be a 40-hex git tree OID (fail-closed)"
  if not isHexOfLen(inputs.mergeTreeDigest, 40):
    return "evidence_cas: mergeTreeDigest must be a 40-hex git tree OID (fail-closed)"
  if not isHexOfLen(inputs.policyDigest, 64):
    return "evidence_cas: policyDigest must be 64 lowercase hex chars (fail-closed)"
  if not isHexOfLen(inputs.scopeDigest, 64):
    return "evidence_cas: scopeDigest must be 64 lowercase hex chars (fail-closed)"
  ""

# ---------------------------------------------------------------------------
# I/O boundary — fail-closed digest collection (never empty digests)
# ---------------------------------------------------------------------------

proc fileDigestHex(path: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 over the raw bytes of ONE file — missing/unreadable/empty file →
  ## err (fail-closed). Empty digests are never substituted for missing data.
  if not fileExists(path):
    return err("evidence_cas: file not found (fail-closed): " & path)
  let bytes =
    try: readFile(path)
    except CatchableError as e:
      return err("evidence_cas: file unreadable (fail-closed): " & path & ": " & e.msg)
  if bytes.len == 0:
    return err("evidence_cas: file is empty (fail-closed): " & path)
  ok(sha256Hex(bytes))

proc collectChainedFileDigest*(repoRoot: string; paths: openArray[string]): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Chained content digest over a FIXED path set in the given order, in the
  ## scope_cli.computeScopeHash pattern (`<rel>:<bytes>\n` per member) — but
  ## FAIL-CLOSED per member: a missing or unreadable member is an error, never
  ## a skipped entry.
  var content = ""
  for rel in paths:
    let p = repoRoot / rel
    if not fileExists(p):
      return err("evidence_cas: chained digest input missing (fail-closed): " & rel)
    let bytes =
      try: readFile(p)
      except CatchableError as e:
        return err("evidence_cas: chained digest input unreadable (fail-closed): " & rel & ": " & e.msg)
    content.add(rel & ":" & bytes & "\n")
  ok(sha256Hex(content))

func nimPin*(): string {.raises: [].} =
  ## The Nim pin — the compiler version the verifier executes under. Pure
  ## (compile-time constant of the executing binary itself).
  NimVersion

func collectZ3Pin*(): Result[string, string] {.raises: [].} =
  ## The executing-toolchain Z3 pin: the semantic version the verifier binary
  ## was built against (generated BuildEnvZ3Version). Deliberately NOT a
  ## binary hash — build_env.nim embeds GitHash/BuildDate/CommitCount, so
  ## verifier bytes drift across rebuilds while the semantic pin does not.
  ## Pure (no filesystem): the pin travels inside the executing binary — the
  ## same pattern as attestation_orchestrator.pinnedToolchainIdentity. The
  ## generated module is absent or carries no pin → err (fail-closed); an
  ## identity that cannot name its Z3 pin is never derived.
  let pin = BuildEnvZ3Version
  if pin.len == 0:
    err("evidence_cas: Z3 pin unavailable in build metadata (fail-closed)")
  else:
    ok(pin)

proc collectLeanPin*(repoRoot: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 of the TRIMMED proofs/lean-toolchain content — the Lean pin SSOT.
  ## The version literal is read from the file, never hardcoded.
  let path = repoRoot / LeanToolchainPinPath
  if not fileExists(path):
    return err("evidence_cas: Lean pin file not found (fail-closed): " & LeanToolchainPinPath)
  let text =
    try: readFile(path)
    except CatchableError as e:
      return err("evidence_cas: Lean pin file unreadable (fail-closed): " & LeanToolchainPinPath & ": " & e.msg)
  let trimmed = text.strip()
  if trimmed.len == 0:
    return err("evidence_cas: Lean pin file is empty (fail-closed): " & LeanToolchainPinPath)
  ok(sha256Hex(trimmed))

proc collectRecipeDigest*(repoRoot: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Chained digest over the build-recipe set (RecipeDigestInputPaths) — the
  ## SAME recipe identity the B-cache key uses. Fail-closed per member.
  collectChainedFileDigest(repoRoot, RecipeDigestInputPaths)

proc collectZ3ChecksumPolicyDigest*(repoRoot: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 of the Z3 binary checksum policy (Z3ChecksumPolicyPath).
  fileDigestHex(repoRoot / Z3ChecksumPolicyPath)

proc collectEvidenceDraftDigest*(repoRoot: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 of the base-tree evidence draft (EvidenceDraftPath @B) — the
  ## mandatory base→evidence channel a naive 4-tuple missed.
  fileDigestHex(repoRoot / EvidenceDraftPath)

proc collectScopeDigest*(repoRoot: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 of the installed verification scope lock (ScopeLockPath) — the
  ## same canonical digest the attest chain's stage (f) compares.
  fileDigestHex(repoRoot / ScopeLockPath)

proc collectPolicyDigest*(repoRoot: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Chained digest over the runtime-read policy file set
  ## (PolicyDigestInputPaths, fixed sorted order). The verdict reads all of
  ## these at landing time, so all of them are semantic inputs of the key.
  ## Fail-closed per member.
  collectChainedFileDigest(repoRoot, PolicyDigestInputPaths)

proc collectArtifactDigests*(repoRoot: string): Result[seq[ArtifactDigest], string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Digests of the EXECUTED artifact set (ExecutedArtifactPaths): every
  ## member is run by a verification path, so its bytes shape the fresh
  ## verdict and a missing/unreadable member is an err (fail-closed).
  ## Record-level integrity metadata of the stored evidence — never hashed
  ## into the EvidenceKey.
  var digests: seq[ArtifactDigest] = @[]
  for (name, rel) in ExecutedArtifactPaths:
    let digest = fileDigestHex(repoRoot / rel)
    if digest.isErr:
      return err(digest.error)
    digests.add(ArtifactDigest(name: name, digest: digest.get))
  ok(digests)

proc collectVerifierIdentityInputs*(repoRoot: string; baseTreeOid: string): Result[VerifierIdentityInputs, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Assemble the full verifier-identity input set: every part collected
  ## fail-closed, then validated as a whole. baseTreeOid is caller-supplied
  ## (tree OIDs come from git; this module performs no git).
  var inputs = VerifierIdentityInputs(
    baseTreeOid: baseTreeOid,
    recipeDigest: "",
    nimPin: nimPin(),
    leanPin: "",
    z3Pin: "",
    z3ChecksumPolicyDigest: "",
    solverOptionsDigest: deterministicSolverOptionsDigest(),
    artifactDigests: @[])
  let recipe = collectRecipeDigest(repoRoot)
  if recipe.isErr: return err(recipe.error)
  inputs.recipeDigest = recipe.get
  let lean = collectLeanPin(repoRoot)
  if lean.isErr: return err(lean.error)
  inputs.leanPin = lean.get
  let z3 = collectZ3Pin()
  if z3.isErr: return err(z3.error)
  inputs.z3Pin = z3.get
  let z3Policy = collectZ3ChecksumPolicyDigest(repoRoot)
  if z3Policy.isErr: return err(z3Policy.error)
  inputs.z3ChecksumPolicyDigest = z3Policy.get
  let artifacts = collectArtifactDigests(repoRoot)
  if artifacts.isErr: return err(artifacts.error)
  inputs.artifactDigests = artifacts.get
  let problem = validateVerifierIdentityInputs(inputs)
  if problem.len > 0:
    return err(problem)
  ok(inputs)

proc collectEvidenceKeyInputs*(repoRoot: string; baseTreeOid: string;
                               headTreeDigest: string; mergeTreeDigest: string): Result[EvidenceKeyInputs, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Assemble the complete EvidenceKey input set from the workspace: verifier
  ## identity + draft/policy/scope digests fail-closed, plus the caller-supplied
  ## tree OIDs (head H and merge candidate). Whole-set validated before ok.
  let verifier = collectVerifierIdentityInputs(repoRoot, baseTreeOid)
  if verifier.isErr: return err(verifier.error)
  let draft = collectEvidenceDraftDigest(repoRoot)
  if draft.isErr: return err(draft.error)
  let policy = collectPolicyDigest(repoRoot)
  if policy.isErr: return err(policy.error)
  let scope = collectScopeDigest(repoRoot)
  if scope.isErr: return err(scope.error)
  let inputs = EvidenceKeyInputs(
    verifierIdentity: composeVerifierIdentity(verifier.get),
    evidenceDraftDigest: draft.get,
    headTreeDigest: headTreeDigest,
    mergeTreeDigest: mergeTreeDigest,
    policyDigest: policy.get,
    scopeDigest: scope.get)
  let problem = validateEvidenceKeyInputs(inputs)
  if problem.len > 0:
    return err(problem)
  ok(inputs)

{.pop.}
