import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/[tables, json, os, strutils, sequtils, algorithm]
import core/results
import core/sync/sync_utils_process
import core/trusted/trust_commit
import core/proof/source_fingerprint
import core/proof/proof_integrity
import core/types/certificate_types
import core/trusted/semantic_profile
import core/trusted/axiom_pragmas
import core/trusted/stdlib_shield
import core/crypto/hash_kernel
import core/json/json_utils
import core/utils/repo_root
import verification/cert_vault_role
import verification/canonical_certificate_payload
import verification/canonical_json
import verification/attestation_orchestrator
import infrastructure/certificate_attestation
import verification/certificate_verifier

## ─────────────────────────────────────────────────────────────────────────
## Deterministic Reference-Vault Materializer (WP4-g)
##
## Projects a failable, pure canonical reference vault from (Journal,
## SourceSnapshot).  The existing reference vault is NOT an input — the
## projection is computed purely from journal records and the current
## source snapshot.  This ensures purity: empty vault / R1 vault / R2
## vault all yield identical --check output for the same journal+source.
##
## SelectionPolicy is pluggable at the type level; RejectMultiple is
## the only implemented policy (Open Issue #1).
## ─────────────────────────────────────────────────────────────────────────

# ---------------------------------------------------------------------------
# Selection policy (pluggable concept; RejectMultiple is the only impl)
# ---------------------------------------------------------------------------

type
  SelectionPolicy* = enum
    spRejectMultiple  ## variants.size > 1 → AMBIGUOUS (sole implemented policy)

# ---------------------------------------------------------------------------
# Projection outcome and result types
# ---------------------------------------------------------------------------

type
  ProjectionOutcome* = enum
    poNoCurrentEvidence  ## 0 variants for this definition
    poResolved           ## 1 variant — deterministic projection
    poAmbiguous          ## >1 variants — contract boundary, not a bug

  CanonicalReferenceProjection* = object
    case outcome*: ProjectionOutcome
    of poNoCurrentEvidence:
      discard
    of poResolved:
      certificateIdentity*: string     ## irHash of the chosen variant
      bytes*: seq[byte]                ## canonical RFC 8785 bytes
      journalCommitId*: string         ## commit id in the trust journal
    of poAmbiguous:
      variantCount*: int               ## number of conflicting variants

  ProjectionError* = object
    message*: string

  ClaimBucketEntry* = object
    commit*: TrustCommit
    commitId*: string

  ClaimBuckets* = ref object
    byClaimIdentity*: Table[string, seq[ClaimBucketEntry]]

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func stripAttestationNode*(certNode: JsonNode): JsonNode {.raises: [].} =
  ## The attested payload: every certificate field EXCEPT the attestation
  ## block.  Mirrors the private `stripAttestation` in
  ## infrastructure/certificate_attestation.nim (which cannot be imported
  ## from the verification layer due to layer enforcement).
  result = newJObject()
  if certNode.isNil or certNode.kind != JObject:
    return
  for k, v in certNode.pairs:
    if k != "attestation":
      result[k] = v

func bytesToString*(b: seq[byte]): string {.raises: [].} =
  ## Convert a byte sequence to a string (binary-safe).
  result = newString(b.len)
  for i in 0 ..< b.len:
    result[i] = char(b[i])

proc groupByFingerprint*(
  records: seq[TrustCommit];
  sourceSnapshot: Table[string, string]
): Table[string, seq[tuple[certId: string; bytes: seq[byte]; commitId: string]]] {.raises: [CatchableError].} =
  ## Group journal records by their source fingerprint key.
  ## Each record yields one variant (certId, canonicalBytes, commitId).
  ## Handles both v1 (flat claim with top-level modulePath/irHash) and
  ## v2 (claim with entries[] array, each entry carrying modulePath/irHash).
  for commit in records:
    var claim: JsonNode
    try:
      claim = parseJson(commit.claim)
    except CatchableError:
      continue
    if claim.kind != JObject:
      continue

    # v2 claims nest function data in claim{"entries"}[];
    # v1 claims are flat objects with top-level modulePath/irHash.
    let entries = claim{"entries"}
    if entries != nil and entries.kind == JArray and entries.len > 0:
      for entry in entries:
        if entry.kind != JObject:
          continue
        let modulePath = entry{"modulePath"}.getStr("")
        if modulePath.len == 0:
          continue
        let sourceCode = sourceSnapshot.getOrDefault(modulePath)
        if sourceCode.len == 0:
          continue
        let fp = computeStableSourceFingerprint(sourceCode)
        let irHash = entry{"irHash"}.getStr("")
        let certId = if irHash.len > 0: irHash else: commit.evidenceId
        # Pass the individual entry node: each v2 entry is a
        # self-contained function-level record used for variant identity.
        let cbytes = canonicalCertificateBytes(entry)
        result.mgetOrPut(fp, @[]).add (certId, cbytes, commit.evidenceId)
    else:
      # v1 flat claim shape
      let modulePath = claim{"modulePath"}.getStr("")
      if modulePath.len == 0:
        continue
      let sourceCode = sourceSnapshot.getOrDefault(modulePath)
      if sourceCode.len == 0:
        continue
      let fp = computeStableSourceFingerprint(sourceCode)
      let irHash = claim{"irHash"}.getStr("")
      let certId = if irHash.len > 0: irHash else: commit.evidenceId
      let cbytes = canonicalCertificateBytes(claim)
      result.mgetOrPut(fp, @[]).add (certId, cbytes, commit.evidenceId)

# ---------------------------------------------------------------------------
# Failable projection — F(Journal, SourceSnapshot) → Result<CanonicalReferenceProjection, ProjectionError>
# ---------------------------------------------------------------------------

proc projectDefinition*(
  fingerprint: string;
  journalRecords: seq[TrustCommit];
  sourceSnapshot: Table[string, string];
  policy: SelectionPolicy = spRejectMultiple
): Result[CanonicalReferenceProjection, ProjectionError] {.
    axiomDecision(id = "DECISION-0664", reason = "Failable pure projection of a single definition from journal+source; policy selects ambiguity handling", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Project a single definition (identified by its source fingerprint)
  ## from the journal records.  The function is pure — no I/O, no side
  ## effects.  The existing reference vault is NOT consulted.
  let grouped = groupByFingerprint(journalRecords, sourceSnapshot)
  let variants = grouped.getOrDefault(fingerprint)

  if variants.len == 0:
    return ok(CanonicalReferenceProjection(outcome: poNoCurrentEvidence))

  if variants.len == 1:
    let v = variants[0]
    return ok(CanonicalReferenceProjection(
      outcome: poResolved,
      certificateIdentity: v.certId,
      bytes: v.bytes,
      journalCommitId: v.commitId))

  # >1 variants → ambiguous under RejectMultiple policy
  case policy
  of spRejectMultiple:
    ok(CanonicalReferenceProjection(
      outcome: poAmbiguous,
      variantCount: variants.len))

# ---------------------------------------------------------------------------
# Single-pass claim-bucket builder (O(J) index by claim identity)
# ---------------------------------------------------------------------------

proc buildClaimBuckets*(
  journalBaseDir: string
): Result[ClaimBuckets, ProjectionError] {.
    axiomDecision(id = "DECISION-0669", reason = "Single-pass O(J) index of the trust journal by claim identity (modulePath::functionName); each tracked certificate then looks up its own bucket in O(1)", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33"), axiomDebt: "DEBT#448".} =
  ## Single-pass O(J) index of the trust journal by claim identity
  ## (modulePath::functionName). Build ONCE, then each tracked certificate
  ## looks up its own bucket in O(1). Handles v1 flat claims and v2
  ## claims with entries[] arrays, mirroring the existing scanner logic
  ## currently at projectReferenceCertificate (lines 512-543).
  ## Returns Err only if listCommitIds fails; readCommit parse failures
  ## are skipped (continue) exactly like the legacy scanner.
  let idsRes = listCommitIds(journalBaseDir)
  if idsRes.isErr():
    return err(ProjectionError(message: "buildClaimBuckets: cannot list journal: " & idsRes.error))

  let buckets = ClaimBuckets()
  buckets.byClaimIdentity = initTable[string, seq[ClaimBucketEntry]]()

  for cid in idsRes.value:
    let rc = readCommit(journalBaseDir, cid)
    if not rc.ok: continue
    var claim: JsonNode
    try:
      claim = parseJson(rc.value.claim)
    except CatchableError:
      continue
    if claim.kind != JObject: continue

    let entries = claim{"entries"}
    if entries != nil and entries.kind == JArray and entries.len > 0:
      for entry in entries:
        if entry.kind != JObject: continue
        let ep = entry{"modulePath"}.getStr("")
        let efn = entry{"functionName"}.getStr("")
        if ep.len == 0 or efn.len == 0: continue
        let key = ep & "::" & efn
        buckets.byClaimIdentity.mgetOrPut(key, @[]).add(
          ClaimBucketEntry(commit: rc.value, commitId: cid))
    else:
      let v1mp = claim{"modulePath"}.getStr("")
      let v1fn = claim{"functionName"}.getStr("")
      if v1mp.len == 0 or v1fn.len == 0: continue
      let key = v1mp & "::" & v1fn
      buckets.byClaimIdentity.mgetOrPut(key, @[]).add(
        ClaimBucketEntry(commit: rc.value, commitId: cid))

  ok(buckets)

# ---------------------------------------------------------------------------
# Reconstruction recipe — rebuild canonical bytes from a journal record
# ---------------------------------------------------------------------------

proc reconstructCanonicalBytes*(
  commit: TrustCommit;
  commitId: string
): Result[seq[byte], ProjectionError] {.
    axiomDecision(id = "DECISION-0665", reason = "Reconstruct canonical certificate bytes from a TrustCommit journal record via claim normalization, deterministic re-sign, and RFC 8785 serialization", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## 1. Parse the claim JSON from the journal record.
  # Kernel normalization boundary rule (WP4-g.2):
  #   kernel := solverMeta.leanCompilerVerified
  #            ∧ status ∈ {certLeanVerified, certGreen, certDualVerified}
  # This rule canonicalizes legacy metadata; it does NOT redefine kernel
  # semantics.  leanCompilerVerified + a kernel-capable status remain the
  # sole authority; registry-derived kernel flags are legacy artifacts.
  var certNode: JsonNode
  try:
    certNode = parseJson(commit.claim)
  except CatchableError as e:
    return err(ProjectionError(message: "reconstruct: claim parse failed: " & e.msg))

  if certNode.isNil or certNode.kind != JObject:
    return err(ProjectionError(message: "reconstruct: claim is not a JSON object"))

  ## 2. Normalize: strip stray trustCommitId / provenance / attestation fields.
  if certNode.hasKey("trustCommitId"):
    certNode.delete("trustCommitId")
  if certNode.hasKey("provenance"):
    certNode.delete("provenance")
  if certNode.hasKey("attestation"):
    certNode.delete("attestation")

  ## Kernel normalization (WP4-g.2): canonicalize legacy registry
  ## kernel flags — kernel := solverMeta.leanCompilerVerified ∧
  ## status ∈ {certLeanVerified, certGreen, certDualVerified}.
  ## Legacy certs carrying kernel: true from the old registry writer
  ## but a non-kernel-capable status (e.g. certZ3Candidate) lose it.
  let statusStr = certNode.getOrDefault("status").getStr("")
  let kernelCapable = statusStr in ["certLeanVerified", "certGreen", "certDualVerified"]
  let solverMetaNode = certNode.getOrDefault("solverMeta")
  let leanCompilerVerified = (if solverMetaNode != nil and solverMetaNode.kind == JObject:
    solverMetaNode.getOrDefault("leanCompilerVerified").getBool(false)
  else:
    false)
  certNode["kernel"] = newJBool(leanCompilerVerified and kernelCapable)

  ## 3. Re-add trustCommitId + provenance.
  certNode["trustCommitId"] = newJString(commitId)
  let identityDigest = certNode{"identityDigest"}.getStr("")
  certNode["provenance"] = %*{
    "journalCommitId": commitId,
    "certificateDigest": identityDigest
  }

  ## 4. Ed25519 deterministic re-sign with constant seed.
  let attSig = signCertificatePayload(certNode)
  if attSig.isErr:
    return err(ProjectionError(message: "reconstruct: attestation signing failed: " & attSig.error))
  certNode["attestation"] = %*{
    "authority": "axiom",
    "policyVersion": CanonicalCertificateSchemaVersion,
    "claimDigest": "sha256:" & sha256Hex(canonical_json.canonicalJsonString(stripAttestationNode(certNode))),
    "journalRef": commitId,
    "algorithm": AxiomAttestationAlgorithm,
    "publicKeyId": attSig.get.publicKeyId,
    "signature": attSig.get.signature
  }

  ## 5. RFC 8785 canonical bytes.
  let canonicalBytes = canonicalCertificateBytes(certNode)

  ## 6. Re-verify via verifyCertificateClosure; accept only on PASS.
  let tmpPath = getTempDir() / ("axiom_reconcile_" & commitId & ".json")
  try:
    writeFile(tmpPath, canonicalCertificateString(certNode))
    let closure = verifyCertificateClosure(tmpPath)
    if closure.status != ccsPass:
      return err(ProjectionError(message: "reconstruct: verification closure failed: " & $closure.status & " " & closure.detail))
  finally:
    if fileExists(tmpPath):
      try: removeFile(tmpPath)
      except CatchableError: discard  # axiom:best-effort(temp file cleanup is best-effort; canonical outcome already decided)

  ok(canonicalBytes)

# ---------------------------------------------------------------------------
# renameat2 atomic replacement (Linux; fail-closed)
# The renameat2 syscall primitive lives in core/sync/sync_utils_process
# (the architecture policy's canonical importc site); this layer owns the
# fail-closed Result wrapping.
# ---------------------------------------------------------------------------

when defined(linux):
  proc atomicReplaceFile*(stagingPath, targetPath: string): Result[void, ProjectionError] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    ## Atomic namespace transition via renameat2(RENAME_EXCHANGE).
    ## Swaps stagingPath ↔ targetPath in a single syscall.
    ## If the syscall is unsupported or fails → fail-closed.
    let ret = renameat2Exchange(stagingPath.cstring, targetPath.cstring)
    if ret != 0:
      return err(ProjectionError(
        message: "renameat2(RENAME_EXCHANGE) failed for " &
                 stagingPath & " ↔ " & targetPath))
    Result[void, ProjectionError](ok: true)
else:
  proc atomicReplaceFile*(stagingPath, targetPath: string): Result[void, ProjectionError] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    return err(ProjectionError(message: "renameat2 unsupported on this platform"))

# ---------------------------------------------------------------------------
# Whole-vault atomic materialization
# ---------------------------------------------------------------------------

proc materializeReferenceVault*(
  journalBaseDir: string;
  sourceSnapshot: Table[string, string];
  referenceVaultDir: string = resolveCertificate(cvCanonicalRead);
  projectRoot: string = ""
): Result[void, ProjectionError] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
    axiomDecision(id = "DECISION-0666", reason = "Atomic whole-vault materialization via renameat2(RENAME_EXCHANGE); fail-closed on any ambiguity or verification failure", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Preconditions for apply:
  ##   • every tracked definition is resolvable (no AMBIGUOUS)
  ##   • all verification pass (verifyCertificateClosure → ccsPass)
  ##   • no NoCurrentEvidence where evidence is required
  ## Any ambiguity → NO write at all, fail closed. No partial application.
  ##
  ## Replacement of a cert file uses renameat2(RENAME_EXCHANGE).
  ## Single syscall, atomic namespace transition.  No non-atomic fallback.

  # 1. Enumerate journal records deterministically.
  let ids = listCommitIds(journalBaseDir)
  if not ids.ok:
    return err(ProjectionError(
      message: "materialize: cannot list journal: " & ids.error))

  var records: seq[TrustCommit]
  for cid in ids.value:
    let rc = readCommit(journalBaseDir, cid)
    if not rc.ok:
      return err(ProjectionError(
        message: "materialize: cannot read commit " & cid & ": " & rc.error))
    records.add rc.value

  # 2. Group records by source fingerprint.
  let grouped = groupByFingerprint(records, sourceSnapshot)
  if grouped.len == 0:
    return Result[void, ProjectionError](ok: true)

  # 3. Check preconditions per definition; collect replacements.
  var replacements: seq[(string, string)]  ## (targetPath, canonicalString)

  for fp, _ in grouped.pairs:
    let proj = projectDefinition(fp, records, sourceSnapshot, spRejectMultiple)
    if not proj.ok:
      return err(ProjectionError(
        message: "materialize: projection failed for " & fp & ": " & proj.error.message))

    case proj.value.outcome
    of poNoCurrentEvidence:
      return err(ProjectionError(
        message: "materialize: no current evidence for definition " & fp))
    of poAmbiguous:
      return err(ProjectionError(
        message: "materialize: ambiguous definition " & fp &
                 " (" & $proj.value.variantCount & " variants)"))
    of poResolved:
      # 4. Verify the canonical bytes via verifyCertificateClosure.
      let tmpPath = getTempDir() / ("axiom_reconcile_verify_" & fp & ".json")
      let canonicalStr = canonicalCertificateString(parseJson(bytesToString(proj.value.bytes)))
      try:
        writeFile(tmpPath, canonicalStr)
        let closure = verifyCertificateClosure(tmpPath, projectRoot)
        if closure.status != ccsPass:
          return err(ProjectionError(
            message: "materialize: verification closure failed for " & fp &
                     ": " & closure.detail))
      finally:
        if fileExists(tmpPath):
          try: removeFile(tmpPath)
          except CatchableError: discard  # axiom:best-effort(temp file cleanup is best-effort; canonical outcome already decided)

      let targetPath = referenceVaultDir / (proj.value.certificateIdentity & ".json")
      replacements.add (targetPath, canonicalStr)

  # 5. Atomic replacement of all cert files via renameat2(RENAME_EXCHANGE).
  #    Write new content to a staging file, then exchange it with the
  #    target.  Fail-closed: any single renameat2 failure aborts the
  #    entire materialization with no writes.
  for (targetPath, content) in replacements:
    let stagingPath = targetPath & ".new"
    try:
      writeFile(stagingPath, content)
    except CatchableError as e:
      return err(ProjectionError(
        message: "materialize: cannot write staging file " & stagingPath & ": " & e.msg))
    let exch = atomicReplaceFile(stagingPath, targetPath)
    if exch.isErr:
      if fileExists(stagingPath):
        try: removeFile(stagingPath)
        except CatchableError: discard  # axiom:best-effort(temp file cleanup is best-effort; canonical outcome already decided)
      return err(exch.error)
    # After exchange: stagingPath holds the old target content,
    # targetPath holds the new canonical bytes.  Remove the old content.
    if fileExists(stagingPath):
      try: removeFile(stagingPath)
      except CatchableError: discard  # axiom:best-effort(temp file cleanup is best-effort; canonical outcome already decided)

  Result[void, ProjectionError](ok: true)

# ---------------------------------------------------------------------------
# Diagnostics — per-definition outcomes
# ---------------------------------------------------------------------------

type
  DefinitionOutcome* = object
    definitionKey*: string
    case outcome*: ProjectionOutcome
    of poResolved:
      journalCommitId*: string
      oldCertId*: string    ## existing cert id in the reference vault (diagnostics only)
      action*: string       ## always "REPLACE"
    of poAmbiguous:
      variantCount*: int
    of poNoCurrentEvidence:
      discard

proc listDefinitionOutcomes*(
  journalBaseDir: string;
  sourceSnapshot: Table[string, string];
  referenceVaultDir: string = resolveCertificate(cvCanonicalRead)
): Result[seq[DefinitionOutcome], ProjectionError] {.
    axiomDecision(id = "DECISION-0667", reason = "Pure diagnostics listing per-definition outcomes; existing vault read only for old cert IDs in reporting, never as projection input", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Enumerate journal records deterministically, project each definition,
  ## and report outcomes suitable for Phase 5 output.  The existing
  ## reference vault is consulted ONLY for old cert IDs (diagnostics).
  let ids = listCommitIds(journalBaseDir)
  if not ids.ok:
    return err(ProjectionError(
      message: "diagnostics: cannot list journal: " & ids.error))

  var records: seq[TrustCommit]
  for cid in ids.value:
    let rc = readCommit(journalBaseDir, cid)
    if not rc.ok:
      return err(ProjectionError(
        message: "diagnostics: cannot read commit " & cid & ": " & rc.error))
    records.add rc.value

  let grouped = groupByFingerprint(records, sourceSnapshot)
  var outcomes: seq[DefinitionOutcome]

  for fp, _ in grouped.pairs:
    let proj = projectDefinition(fp, records, sourceSnapshot, spRejectMultiple)
    if not proj.ok:
      return err(ProjectionError(
        message: "diagnostics: projection failed for " & fp & ": " & proj.error.message))

    case proj.value.outcome
    of poResolved:
      let oldCertPath = referenceVaultDir / (proj.value.certificateIdentity & ".json")
      let oldCertId = if fileExists(oldCertPath): proj.value.certificateIdentity else: ""
      outcomes.add DefinitionOutcome(
        definitionKey: fp,
        outcome: poResolved,
        journalCommitId: proj.value.journalCommitId,
        oldCertId: oldCertId,
        action: "REPLACE")
    of poAmbiguous:
      outcomes.add DefinitionOutcome(
        definitionKey: fp,
        outcome: poAmbiguous,
        variantCount: proj.value.variantCount)
    of poNoCurrentEvidence:
      outcomes.add DefinitionOutcome(
        definitionKey: fp,
        outcome: poNoCurrentEvidence)

  ok(outcomes)

# ---------------------------------------------------------------------------
# Artifact-local reference projection (per-tracked-cert, not journal-wide)
# ---------------------------------------------------------------------------

type
  ReferenceProjectionOutcome* = enum
    rpoResolved               ## NC1 ∧ NC2 ∧ NC3 all satisfied → deterministic projection
    rpoNoCurrentEvidence      ## no bound current evidence record exists for the tracked cert's claim
    rpoAmbiguousEvidence      ## >1 candidate matches the tracked cert's claim identity
    rpoBindingMismatch        ## NC1 (sourceHash vs current staged source) or NC3 (claim identity/digest) mismatch
    rpoInvalidCurrentCertificate  ## NC2 verifyCertificateClosure != ccsPass for the candidate

  ReferenceCertProjection* = object
    trackedCertId*: string        ## cert identity (irHash) of the tracked reference certificate (never content source)
    trackedCertName*: string      ## on-disk basename (no .json) of the tracked reference cert being replaced — the
                                  ## replacement TARGET. Reconciliation replaces the tracked file in place; the target
                                  ## must be the actual on-disk filename, NOT trackedCertId, because a genuine source
                                  ## mutation legitimately changes the content irHash while the tracked filename stays
                                  ## the stable reference identity.
    claimIdentity*: string        ## modulePath::functionName (same namespace comparison string)
    case outcome*: ReferenceProjectionOutcome
    of rpoResolved:
      bytes*: seq[byte]           ## canonical RFC 8785 bytes of the NEW canonical certificate
      journalCommitId*: string    ## RecordLocator — the journal commit backing the current evidence
      certificateDigest*: string  ## identityDigest of the new certificate
    of rpoAmbiguousEvidence:
      variantCount*: int
    else:
      discard

func referenceClaimIdentity*(certNode: JsonNode): string {.raises: [].} =
  ## Returns the claim identity string (modulePath::functionName) for a cert JSON node.
  certNode.getOrDefault("modulePath").getStr("") & "::" & certNode.getOrDefault("functionName").getStr("")

func isEligibleReferenceCert*(json: JsonNode): bool {.raises: [].} =
  ## A cert JSON node is eligible for reference projection if it
  ## carries at least one of modulePath or functionName (i.e. it is
  ## not a manifest / banner file without claim identity).
  if json == nil or json.kind != JObject: return false
  let mp = json.getOrDefault("modulePath").getStr("")
  let fn = json.getOrDefault("functionName").getStr("")
  mp.len > 0 or fn.len > 0

func certScopedMatch*(filename, irHash, value: string): bool {.raises: [].} =
  ## Return true when the cert's basename (no .json extension)
  ## or its irHash equals the --cert scope value.
  let base = splitFile(filename).name
  base == value or irHash == value

proc allResolved*(projections: seq[ReferenceCertProjection]): bool {.raises: [].} =
  ## Return true only when every projection is rpoResolved
  ## (used by the all-or-nothing --apply gate).
  for proj in projections:
    if proj.outcome != rpoResolved: return false
  result = true

proc projectReferenceCertificate*(
  trackedCertPath: string;
  journalBaseDir: string;
  sourceSnapshot: Table[string, string];
  projectRoot: string = "";
  buckets: ClaimBuckets = nil
): Result[ReferenceCertProjection, ProjectionError] {.
    axiomDecision(id = "DECISION-0668", reason = "Artifact-local per-tracked-cert projection: reads tracked cert and journal, matches tracked cert by claim identity (modulePath::functionName); irHash is not a content-match key, checks NC1-NC3 binding chain, returns deterministic projection or failure classification", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Project a single tracked reference certificate from the journal and current source snapshot.
  ## Pure: reads only, no solver execution, no mutation of source/journal/vault.
  ## verifyCertificateClosure is structural/signature/binding verification (zero solver calls).
  ## Fail-closed: unreadable/non-object tracked cert → err.

  # 1. Read/parse the tracked cert JSON (fail-closed).
  if not fileExists(trackedCertPath):
    return err(ProjectionError(message: "projectReferenceCertificate: tracked cert not found: " & trackedCertPath))
  var certNode: JsonNode
  try:
    certNode = parseJson(readFile(trackedCertPath))
  except CatchableError as e:
    return err(ProjectionError(message: "projectReferenceCertificate: tracked cert parse failed: " & e.msg))
  if certNode.isNil or certNode.kind != JObject:
    return err(ProjectionError(message: "projectReferenceCertificate: tracked cert is not a JSON object"))

  # 2. Extract claim identity and source identity of the tracked artifact.
  let modulePath = certNode.getOrDefault("modulePath").getStr("")
  let functionName = certNode.getOrDefault("functionName").getStr("")
  let trackedIrHash = certNode.getOrDefault("irHash").getStr("")
  let trackedCertName = splitFile(trackedCertPath).name
  let claimIdentity = referenceClaimIdentity(certNode)

  if modulePath.len == 0 or functionName.len == 0:
    return err(ProjectionError(message: "projectReferenceCertificate: tracked cert missing modulePath or functionName"))

  # 3. Search the journal for records matching the tracked cert's CLAIM IDENTITY
  #    (modulePath::functionName). The old tracked irHash is NOT a content-match
  #    key: the tracked cert is a replacement TARGET identity only, and a genuine
  #    source mutation legitimately changes the evidence irHash. Locating current
  #    evidence by the stale irHash would guarantee rpoNoCurrentEvidence for every
  #    reconcilable drift, which defeats the reconciliation. (WP4-g.1 — claim
  #    identity namespace, 4-way identity separation.)
  let claimCommits = if buckets != nil:
    var cc: seq[tuple[commit: TrustCommit, commitId: string]]
    for entry in buckets.byClaimIdentity.getOrDefault(claimIdentity):
      cc.add (commit: entry.commit, commitId: entry.commitId)
    cc
  else:
    let idsRes = listCommitIds(journalBaseDir)
    if idsRes.isErr():
      return err(ProjectionError(message: "projectReferenceCertificate: cannot list journal: " & idsRes.error))
    var cc: seq[tuple[commit: TrustCommit, commitId: string]]
    for cid in idsRes.value:
      let rc = readCommit(journalBaseDir, cid)
      if not rc.ok: continue
      var claim: JsonNode
      try:
        claim = parseJson(rc.value.claim)
      except CatchableError:
        continue
      if claim.kind != JObject: continue
      # Check v2 (entries[]) claim shape.
      let entries = claim{"entries"}
      if entries != nil and entries.kind == JArray and entries.len > 0:
        for entry in entries:
          if entry.kind != JObject: continue
          let ep = entry{"modulePath"}.getStr("")
          let efn = entry{"functionName"}.getStr("")
          if ep == modulePath and efn == functionName:
            cc.add (rc.value, cid)
            break
      else:
        # v1 flat claim shape.
        let v1mp = claim{"modulePath"}.getStr("")
        let v1fn = claim{"functionName"}.getStr("")
        if v1mp == modulePath and v1fn == functionName:
          cc.add (rc.value, cid)
    cc

  # 4. No journal record for this claim identity at all → no current evidence.
  if claimCommits.len == 0:
    return ok(ReferenceCertProjection(
      trackedCertId: trackedIrHash,
      trackedCertName: trackedCertName,
      claimIdentity: claimIdentity,
      outcome: rpoNoCurrentEvidence))

  # 5. NC1 SourceIdentity: among claim commits, select those bound to the
  #    CURRENT staged source (candidate.sourceHash == fingerprint(current source)).
  #    The stale tracked cert's own sourceHash is irrelevant here — it is stale by
  #    definition, which is exactly why we are reconciling.
  let currentSource = sourceSnapshot.getOrDefault(modulePath)
  let currentStagedHash = if currentSource.len > 0:
      computeStableSourceFingerprint(currentSource)
    else:
      ""
  var boundCommits: seq[tuple[commit: TrustCommit; commitId: string]]
  for (cand, cid) in claimCommits:
    var candClaim: JsonNode
    try:
      candClaim = parseJson(cand.claim)
    except CatchableError:
      continue
    if candClaim.isNil or candClaim.kind != JObject: continue
    let candSourceHash = candClaim.getOrDefault("sourceHash").getStr("")
    if currentStagedHash.len > 0 and candSourceHash == currentStagedHash:
      boundCommits.add (cand, cid)

  # 6. No journal record for this claim is bound to the current staged source →
  #    current evidence for the current source does not exist → needs re-verification.
  if boundCommits.len == 0:
    return ok(ReferenceCertProjection(
      trackedCertId: trackedIrHash,
      trackedCertName: trackedCertName,
      claimIdentity: claimIdentity,
      outcome: rpoNoCurrentEvidence))

  if boundCommits.len > 1:
    return ok(ReferenceCertProjection(
      trackedCertId: trackedIrHash,
      trackedCertName: trackedCertName,
      claimIdentity: claimIdentity,
      outcome: rpoAmbiguousEvidence,
      variantCount: boundCommits.len))

  # Exactly 1 BoundCurrentEvidenceCandidate (bound to current staged source).
  let candidate = boundCommits[0].commit
  let commitId = boundCommits[0].commitId

  # Parse the candidate claim for field access.
  var candidateClaim: JsonNode
  try:
    candidateClaim = parseJson(candidate.claim)
  except CatchableError:
    return ok(ReferenceCertProjection(
      trackedCertId: trackedIrHash,
      trackedCertName: trackedCertName,
      claimIdentity: claimIdentity,
      outcome: rpoBindingMismatch))
  if candidateClaim.isNil or candidateClaim.kind != JObject:
    return ok(ReferenceCertProjection(
      trackedCertId: trackedIrHash,
      trackedCertName: trackedCertName,
      claimIdentity: claimIdentity,
      outcome: rpoBindingMismatch))

  # 7. NC1 re-check: candidate.sourceHash must match current source snapshot.
  let candidateSourceHash = candidateClaim.getOrDefault("sourceHash").getStr("")
  if currentSource.len == 0 or candidateSourceHash.len == 0:
    return ok(ReferenceCertProjection(
      trackedCertId: trackedIrHash,
      trackedCertName: trackedCertName,
      claimIdentity: claimIdentity,
      outcome: rpoBindingMismatch))
  if computeStableSourceFingerprint(currentSource) != candidateSourceHash:
    return ok(ReferenceCertProjection(
      trackedCertId: trackedIrHash,
      trackedCertName: trackedCertName,
      claimIdentity: claimIdentity,
      outcome: rpoBindingMismatch))

  # 8. NC3 Binding Chain: the candidate's recorded RecordLocator (trustCommitId)
  #    must resolve to the journal commit we are projecting from. If the claim
  #    records a different commit id than the one that actually carries it, the
  #    binding chain is inconsistent → rpoBindingMismatch. Empty is tolerated
  #    (some v1/v2 records carry no explicit trustCommitId; the found commit is
  #    the de-facto RecordLocator).
  let recordedTrustCommitId = candidateClaim.getOrDefault("trustCommitId").getStr("")
  if recordedTrustCommitId.len > 0 and recordedTrustCommitId != commitId:
    return ok(ReferenceCertProjection(
      trackedCertId: trackedIrHash,
      trackedCertName: trackedCertName,
      claimIdentity: claimIdentity,
      outcome: rpoBindingMismatch))

  # 9. NC2 Closure: verifyCertificateClosure on the candidate must pass.
  #    Add trustCommitId to a projection-time copy so verifyCertificateClosure
  #    can resolve the journal binding (mirrors reconstructCanonicalBytes).
  candidateClaim["trustCommitId"] = newJString(commitId)
  let tmpPath = getTempDir() / ("axiom_refproj_" & commitId & ".json")
  try:
    writeFile(tmpPath, canonicalCertificateString(candidateClaim))
    let closure = verifyCertificateClosure(tmpPath, projectRoot)
    if closure.status != ccsPass:
      return ok(ReferenceCertProjection(
        trackedCertId: trackedIrHash,
        trackedCertName: trackedCertName,
        claimIdentity: claimIdentity,
        outcome: rpoInvalidCurrentCertificate))
  finally:
    if fileExists(tmpPath):
      try: removeFile(tmpPath)
      except CatchableError: discard  # axiom:best-effort(temp file cleanup is best-effort; canonical outcome already decided)

  # 10. All checks passed → rpoResolved. Rebuild canonical bytes via reconstructCanonicalBytes.
  let reconRes = reconstructCanonicalBytes(candidate, commitId)
  if reconRes.isErr():
    return err(ProjectionError(message: "projectReferenceCertificate: reconstruction failed: " & reconRes.error.message))

  ok(ReferenceCertProjection(
    trackedCertId: trackedIrHash,
    trackedCertName: trackedCertName,
    claimIdentity: claimIdentity,
    outcome: rpoResolved,
    bytes: reconRes.value,
    journalCommitId: commitId,
    certificateDigest: candidateClaim.getOrDefault("identityDigest").getStr("")))

# ---------------------------------------------------------------------------
# Journal-driven VKD admission (TrustCommit journal authority, I2/I3)
#
# VKD numerator evidence is computed from the TrustCommit journal ONLY.
# The reference vault (src/verification/certificates) and the L1 cache
# (logs/ax_proof_state.json) are NOT consulted. Admission uses v1 flat
# full-cert claims exclusively; v2 `entries[]` records are compact
# checkpoints (catalog only) and never admit.
# ---------------------------------------------------------------------------

when fileExists("src/generated/build_env.nim"):
  import generated/build_env
else:
  const BuildEnvZ3Version = "unavailable"

import std/options
import core/trusted/env_types
import core/trusted/completeness_binding
import verification/certificate_identity
import infrastructure/evidence_artifact_io
import verification/obligation/canonical_verification
import verification/obligation/lean_kernel_boundary

type
  JournalVkdSymbolOutcome* = enum
    jvCounted             ## exactly one distinct eligible full-cert claim
    jvAmbiguous           ## >1 distinct eligible full-cert claims → UNKNOWN
    jvNoCurrentEvidence   ## no eligible full-cert claim in the current context

  JournalVkdSymbolVerdict* = object
    symbol*: string                     ## modulePath::functionName
    case outcome*: JournalVkdSymbolOutcome
    of jvCounted:
      commitId*: string                 ## journal commit backing the count
      identityDigest*: string           ## certificate identity counted
    of jvAmbiguous:
      variantCount*: int                ## distinct eligible full-cert claims
      identityDigests*: seq[string]     ## conflicting identities (sorted)
    of jvNoCurrentEvidence:
      discard

  JournalVkdAdmission* = object
    counted*: int                       ## |symbols with exactly one distinct eligible claim|
    verdicts*: seq[JournalVkdSymbolVerdict]  ## one per journaled full-cert identity (sorted)
    journalSnapshotSize*: int           ## fixed-snapshot commit count (diagnostics)

func currentJournalToolchainPin*(): JsonNode {.raises: [].} =
  ## The current pinned toolchain identity, in the certificate
  ## `toolchainIdentity` object form. Phase 1B: this is the SAME measured
  ## composition the writer emits (verifierToolchainIdentityJson) — compiling
  ## Nim version, repo lean-toolchain pin, hermetic Z3 build-env version, and
  ## the content-based verifier build identity (`engineBuild`, NOT the repo
  ## commit). `toolchainIdentityMatchesPin` iterates every pin key, so a claim
  ## produced before this cutover (no engineBuild) or under a different
  ## verifier build drops — fail-closed; the kernels are re-proved on cutover.

  verifierToolchainIdentityJson()

func toolchainIdentityMatchesPin*(claimToolchain: JsonNode): bool {.raises: [].} =
  ## A claim's recorded toolchainIdentity matches the current pin when every
  ## pinned component is present and equal. Missing/unmeasurable components
  ## fail closed (stale evidence never matches an absent pin).
  let pin = currentJournalToolchainPin()
  # An unmeasured engine identity is not a pin. Without this guard a claim that
  # literally carries "unmeasured" would compare equal to the "unmeasured" pin
  # value and be admitted — self-consistent theater. Fail closed instead.
  if verifierEngineBuildId() == "unmeasured":
    return false
  if claimToolchain.isNil or claimToolchain.kind != JObject:
    return false
  for key, value in pin.pairs:
    if claimToolchain{key}.getStr("") != value.getStr(""):
      return false
  true

func isStrictContractClaim*(claim: JsonNode): bool {.raises: [].} =
  ## True when the claim belongs to the strict-completeness generation
  ## (`completenessContract == "strict-v1"`). The marker is written only when
  ## the evidence carried the full strict anchor set; legacy claims (no
  ## marker) keep the legacy admission path.
  if claim.isNil or claim.kind != JObject:
    return false
  claim.getOrDefault("completenessContract").getStr("") == CompletenessContractStrictV1

func isFullCertClaim*(claim: JsonNode): bool {.raises: [].} =
  ## v1 flat full-cert claim: has a claim identity and carries the full
  ## context binding (sourceHash + toolchainIdentity + semanticProfileId).
  ## v2 compact `entries[]` checkpoints are NOT full certs.
  ## Phase 1B additions:
  ##   - the v3-identity-bound required fields must be non-empty
  ##     (solverStatus/solverInputDigest/solverResultDigest, plus
  ##     winningStrategy for certGreen) — the 13-field identity binds them, so
  ##     a claim missing any cannot be identity-verified;
  ##   - a strict-contract claim (`completenessContract == "strict-v1"`) must
  ##     additionally carry the full completeness binding anchor set
  ##     (completenessEvidenceKey/completenessBindingDigest/
  ##     completenessPayloadDigest); legacy claims (no marker) keep exactly the
  ##     legacy required fields.
  if claim.isNil or claim.kind != JObject:
    return false
  if claim.hasKey("entries"):
    return false
  claim.getOrDefault("modulePath").getStr("").len > 0 and
    claim.getOrDefault("functionName").getStr("").len > 0 and
    claim.getOrDefault("sourceHash").getStr("").len > 0 and
    claim.getOrDefault("irHash").getStr("").len > 0 and
    claim.hasKey("toolchainIdentity") and
    claim.getOrDefault("semanticProfileId").getStr("").len > 0 and
    claim.getOrDefault("solverStatus").getStr("").len > 0 and
    claim.getOrDefault("solverInputDigest").getStr("").len > 0 and
    claim.getOrDefault("solverResultDigest").getStr("").len > 0 and
    not (claim.getOrDefault("status").getStr("") == "certGreen" and
         claim.getOrDefault("winningStrategy").getStr("").len == 0) and
    not (isStrictContractClaim(claim) and
         (claim.getOrDefault("completenessEvidenceKey").getStr("").len == 0 or
          claim.getOrDefault("completenessBindingDigest").getStr("").len == 0 or
          claim.getOrDefault("completenessPayloadDigest").getStr("").len == 0))

func evidenceStrictModeActive*(): bool {.raises: [].} =
  ## AXIOM_EVIDENCE_STRICT=1: legacy-generation claims (no strict marker) are
  ## excluded from VKD admission entirely. The env only tightens (excludes
  ## legacy); it can never relax the strict-contract requirements.
  getEnv("AXIOM_EVIDENCE_STRICT", "") == "1"

type StrictCompletenessContext* = object
  ## The CURRENT admission context a strict binding must match (measured, not
  ## taken from the claim). Consumed by loadCompletenessBinding.
  sourceIdentity*: string
  subjectModuleSha256*: string
  toolchainFingerprint*: string

proc measureStrictCompletenessContext*(projectRoot: string;
                                       modulePath: string;
                                       moduleSource: string): StrictCompletenessContext {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Measure the CURRENT strict-admission context for a subject module:
  ##   - subjectModuleSha256: raw sha256 of the CURRENT module bytes;
  ##   - sourceIdentity: canonical composite of the subject git ref, the
  ##     subject tree merkle root (module + first-party import closure), and
  ##     the module sha256 — the producer-side capture composition
  ##     (external_ir_materializer must compose the SAME value at capture
  ##     time; the composite contract is integration-locked by the strict
  ##     admission tests);
  ##   - toolchainFingerprint: the measured lean/lake bundle digest — the SAME
  ##     computeBundleDigest composition the kernel receipt records at capture
  ##     (same resolution, same canonical 120_000 ms timeout contract).
  ## Every component fails closed to "" when unmeasurable.
  let moduleSha256 = if moduleSource.len > 0: sha256Hex(moduleSource) else: ""
  let gitRef = measureSubjectGitRef(projectRoot)
  let treeMerkle = measureSubjectTreeMerkleRoot(projectRoot, modulePath, moduleSource)
  result.sourceIdentity =
    if gitRef.len > 0 and treeMerkle.len > 0 and moduleSha256.len > 0:
      # THE single source-identity composition — the producer sites record the
      # same versioned, domain-separated composite (composeCompletenessSourceIdentity).
      # Composing a raw join here would make every strict binding unloadable.
      composeCompletenessSourceIdentity(gitRef, treeMerkle, moduleSha256)
    else:
      ""
  result.subjectModuleSha256 = moduleSha256
  let leanCmd = getAxiomEnv(evLeanCmd, "")
  let resolvedCmd = if leanCmd.len > 0: leanCmd else: "lake env lean"
  let leanExePath = resolveLeanBinaryPath()
  let lakePath = findExe("lake")
  if leanExePath.len == 0 or lakePath.len == 0:
    result.toolchainFingerprint = ""
  else:
    try:
      result.toolchainFingerprint =
        computeBundleDigest(leanExePath, lakePath, 120_000, resolvedCmd)
    except CatchableError:
      result.toolchainFingerprint = ""

proc strictCompletenessAdmits*(claim: JsonNode;
                               ctx: StrictCompletenessContext): bool {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The strict-contract admission seal (Phase 1B). Every check is fail-closed:
  ##   1. the claim carries the full anchor set (guarded by isFullCertClaim);
  ##   2. loadCompletenessBinding must return SOME — the strict binding
  ##      artifact exists at the claim's key, parses strictly, its
  ##      evidenceDigest recomputes, AND its sourceIdentity /
  ##      subjectModuleSha256 / semanticProfileId / toolchainFingerprint equal
  ##      the CURRENT measured context (missing/corrupt/stale → none);
  ##   3. the binding's evidenceDigest equals the claim's recorded
  ##      completenessBindingDigest (claim ↔ artifact binding);
  ##   4. the binding payload's legacy 5-field digest equals the claim's
  ##      completenessPayloadDigest (the legacy completeness commitment);
  ##   5. the binding's flavor-③ CAS anchor equals the claim's recorded
  ##      completenessEvidenceKey. The binding is keyed by the producer's
  ##      PRE-SYNTHESIS IR; the certified post-synthesis `irHash` is bound by
  ##      the proof and the certificate identity, not by this anchor —
  ##      comparing `irDigestCanonical` to `irHash` would reject every
  ##      legitimate pre-synthesis binding.
  ## Any failure → false: the claim is never counted.
  let key = claim.getOrDefault("completenessEvidenceKey").getStr("")
  let claimBindingDigest = claim.getOrDefault("completenessBindingDigest").getStr("")
  let claimPayloadDigest = claim.getOrDefault("completenessPayloadDigest").getStr("")
  if key.len == 0 or claimBindingDigest.len == 0 or claimPayloadDigest.len == 0:
    return false
  let loaded = loadCompletenessBinding(key, ctx.sourceIdentity,
    ctx.subjectModuleSha256, SemanticProfileV1Hash, ctx.toolchainFingerprint)
  if loaded.isNone:
    return false
  let b = loaded.get
  if b.evidenceDigest != claimBindingDigest:
    return false
  if sha256Hex($evidenceToJson(b.payload)) != claimPayloadDigest:
    return false
  if b.irDigest != key:
    return false
  true

func journalEvidenceKey*(claim: JsonNode): string {.raises: [].} =
  ## Function-level evidence identity: the v3 identity fields that say WHAT was
  ## proved about WHICH subject bytes, excluding `evidenceId`. The stored v3
  ## identity also binds the whole-repo subject tree merkle root, so an
  ## unrelated commit changes every identity without changing this symbol's
  ## evidence. VKD ambiguity is decided on THIS key: two keys = two genuinely
  ## different claims; one key = the same claim re-attested on a different tree
  ## snapshot (count once, never UNKNOWN).
  if claim.isNil or claim.kind != JObject:
    return ""
  sha256Hex([
    claim.getOrDefault("schemaVersion").getStr(""),
    claim.getOrDefault("modulePath").getStr(""),
    claim.getOrDefault("functionName").getStr(""),
    claim.getOrDefault("sourceHash").getStr(""),
    claim.getOrDefault("irHash").getStr(""),
    claim.getOrDefault("leanProposition").getStr(""),
    claim.getOrDefault("solverStatus").getStr(""),
    claim.getOrDefault("status").getStr(""),
    claim.getOrDefault("winningStrategy").getStr(""),
    claim.getOrDefault("inputHash").getStr(""),
    claim.getOrDefault("solverInputDigest").getStr(""),
    claim.getOrDefault("solverResultDigest").getStr("")
  ].join("\x1f"))

func journalEvidenceKeyStrict*(claim: JsonNode): string {.raises: [].} =
  ## Admission-ambiguity key: the function-level evidence key PLUS, for a
  ## strict-generation claim, its completeness binding anchor. Two strict
  ## claims that differ only in the anchor are different evidence (the
  ## artifact can be present for one and absent/corrupt for the other) and
  ## must not collapse into one entry; a strict and a legacy claim for the
  ## same function-level evidence are likewise NOT silently merged.
  ##
  ## This key is deliberately NOT used by canonical promotion replacement:
  ## `journalEvidenceKey` stays byte-compatible there so a strict candidate
  ## can supersede an older legacy projection for the same irHash.
  let base = journalEvidenceKey(claim)
  if base.len == 0 or not isStrictContractClaim(claim):
    base
  else:
    base & "|" & claim.getOrDefault("completenessBindingDigest").getStr("")

proc verifyJournalClaimClosure*(
  claim: JsonNode; commitId: string; projectRoot: string
): bool {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
    axiomDecision(id = "DECISION-0672", reason = "verifyCertificateClosure over the journal claim reconstructed with its trustCommitId; only closure-PASS evidence is VKD-admissible", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Reconstruct the journal claim as a certificate (claim + trustCommitId —
  ## the claim cannot carry its own commit id) and run the v1 trust closure
  ## on it in memory: verifyCertificateClosureNode consumes the JsonNode
  ## directly (same closure implementation as `ax cert verify`, no disk
  ## round-trip). Fail-closed: any closure outcome other than ccsPass
  ## rejects the record.
  var certNode = claim
  certNode["trustCommitId"] = newJString(commitId)
  let closure = verifyCertificateClosureNode(
    certNode, "journal:" & commitId, projectRoot)
  result = closure.status == ccsPass

proc computeJournalVkdAdmission*(
  journalBaseDir: string;
  scope: KernelScopeInfo;
  projectRoot: string = ""
): Result[JournalVkdAdmission, string] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
    axiomDecision(id = "DECISION-0671", reason = "VKD numerator admission computed from the TrustCommit journal snapshot only: v1 full-cert claims filtered to the current context (source/toolchain/profile/status certGreen), quarantine-excluded, verifyCertificateClosure- and isVkdAdmissible-gated, identityDigest-deduplicated; ambiguous symbols yield UNKNOWN and are never counted", adr = "docs/adr/0012-ax-vkd-sync.md", introduced = "v33").} =
  ## Compute the current VKD numerator evidence from the TrustCommit journal.
  ##
  ## Pipeline (per symbol identity found in the journal):
  ##   1. fixed snapshot: listCommitIds once, then read each record — journal
  ##      files created after the enumeration are invisible to this run;
  ##   2. v1 flat full-cert claims only (isFullCertClaim); v2 compact
  ##      `entries[]` checkpoints are catalog, never admission;
  ##   3. context filter: status == certGreen, sourceHash == fingerprint of
  ##      the CURRENT module bytes, toolchainIdentity == current pin
  ##      (engineBuild included), semanticProfileId == SemanticProfileV1Hash;
  ##   3b. strict-contract claims (completenessContract == "strict-v1") must
  ##      additionally admit through strictCompletenessAdmits — the strict
  ##      binding artifact is loaded by key and re-verified against the
  ##      CURRENT measured context; legacy claims are excluded entirely when
  ##      AXIOM_EVIDENCE_STRICT=1;
  ##   4. tcQuarantine exclusion: a quarantine record matching the claim
  ##      identity AND sourceHash demotes the evidence;
  ##   5. verifyCertificateClosure must PASS (reconstructed cert, in-memory);
  ##   6. proof_integrity.isVkdAdmissible must admit (kernel entry);
  ##   7. dedup identical eligible records by identityDigest; >1 distinct
  ##      eligible full claim for a symbol → jvAmbiguous (UNKNOWN), never a
  ##      count.
  ##
  ## The reference vault and the L1 cache are never read. `journalBaseDir`
  ## follows the trust_commit convention: the base dir whose
  ## `data/trusted/journal` subtree is the journal (i.e. the repo root).
  ## `projectRoot`
  ## anchors source-byte reads and the closure's source-staleness stage; the
  ## closure's journal-binding stage resolves the journal via the process
  ## repo root (AXIOM_ROOT / CWD), which callers must keep consistent with
  ## `journalBaseDir` (the product path derives both from the same root).
  let idsRes = listCommitIds(journalBaseDir)
  if idsRes.isErr():
    return err("computeJournalVkdAdmission: cannot list journal: " & idsRes.error)
  let snapshotIds = idsRes.value

  # ── Single pass over the fixed snapshot: collect full-cert claims and
  #    quarantine bindings.
  type
    Candidate = tuple[commitId: string; claim: JsonNode]
  var candidatesBySymbol = initTable[string, seq[Candidate]]()
  var quarantineSourceHashes = initTable[string, seq[string]]()

  for cid in snapshotIds:
    let rc = readCommit(journalBaseDir, cid)
    if not rc.isErr():
      let commit = rc.value
      var claim: JsonNode
      try:
        claim = parseJson(commit.claim)
      except CatchableError:
        continue
      if claim.isNil or claim.kind != JObject:
        continue
      case commit.kind
      of tcQuarantine:
        # Quarantine binding: (modulePath::functionName) → demoted sourceHashes.
        let mp = claim.getOrDefault("modulePath").getStr("")
        let fn = claim.getOrDefault("functionName").getStr("")
        let sh = claim.getOrDefault("sourceHash").getStr("")
        if mp.len > 0 and fn.len > 0 and sh.len > 0:
          quarantineSourceHashes.mgetOrPut(mp & "::" & fn, @[]).add(sh)
      of tcVerifiedProof:
        if not isFullCertClaim(claim):
          continue
        let symbol = claim.getOrDefault("modulePath").getStr("") & "::" &
                     claim.getOrDefault("functionName").getStr("")
        candidatesBySymbol.mgetOrPut(symbol, @[]).add((cid, claim))

  # ── Current context: pinned toolchain, current semantic profile, and the
  #    current source fingerprint per module (read once per module).
  let currentProfile = SemanticProfileV1Hash
  var moduleContents = initTable[string, string]()

  proc currentModuleContent(modulePath: string): string {.
      axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    if moduleContents.hasKey(modulePath):
      return moduleContents.getOrDefault(modulePath)
    var content = ""
    try:
      let sourcePath = (if projectRoot.len > 0: projectRoot else: resolveRepoRoot()) / modulePath
      if fileExists(sourcePath):
        content = readFile(sourcePath)
    except CatchableError:
      content = ""
    moduleContents[modulePath] = content
    content

  var sourceFingerprints = initTable[string, string]()

  proc currentSourceFingerprint(modulePath: string): string =
    if sourceFingerprints.hasKey(modulePath):
      return sourceFingerprints.getOrDefault(modulePath)
    let content = currentModuleContent(modulePath)
    var fp = ""
    if content.len > 0:
      try:
        fp = computeStableSourceFingerprint(content)
      except CatchableError:
        fp = ""
    sourceFingerprints[modulePath] = fp
    fp

  proc isQuarantined(symbol: string; sourceHash: string): bool =
    if not quarantineSourceHashes.hasKey(symbol):
      return false
    for sh in quarantineSourceHashes.getOrDefault(symbol):
      if sh == sourceHash:
        return true
    false

  var admission = JournalVkdAdmission(journalSnapshotSize: snapshotIds.len)

  # Deterministic symbol order independent of journal/lock ordering.
  var symbols = toSeq(candidatesBySymbol.keys)
  symbols.sort()

  for symbol in symbols:
    let allCandidates = candidatesBySymbol.getOrDefault(symbol)
    if allCandidates.len == 0:
      continue

    # Context filter (step 3+4). Status/toolchain/profile are per-claim;
    # sourceHash needs the CURRENT module bytes. Phase 1B: strict-contract
    # claims must additionally admit through the strict completeness seal;
    # under AXIOM_EVIDENCE_STRICT=1 legacy-generation claims are excluded.
    let modulePath = allCandidates[0].claim.getOrDefault("modulePath").getStr("")
    let currentFp = currentSourceFingerprint(modulePath)
    let strictMode = evidenceStrictModeActive()
    # Generation cutover: once a symbol has a strict-generation claim in this
    # fixed snapshot, an older legacy claim for the SAME symbol is never a
    # valid fallback — not even with the env flag unset. This closes the
    # "remove the strict binding and let legacy resurrect the symbol" path.
    var symbolHasStrictGeneration = false
    for (_, candidateClaim) in allCandidates:
      if isStrictContractClaim(candidateClaim):
        symbolHasStrictGeneration = true
        break
    var strictCtx: StrictCompletenessContext
    var strictCtxMeasured = false
    var eligible: seq[Candidate]
    for (cid, claim) in allCandidates:
      let strict = isStrictContractClaim(claim)
      if not strict and (strictMode or symbolHasStrictGeneration):
        continue
      if claim.getOrDefault("status").getStr("") != "certGreen":
        continue
      let sourceHash = claim.getOrDefault("sourceHash").getStr("")
      if currentFp.len == 0 or sourceHash != currentFp:
        continue
      if not toolchainIdentityMatchesPin(claim.getOrDefault("toolchainIdentity")):
        continue
      if claim.getOrDefault("semanticProfileId").getStr("") != currentProfile:
        continue
      if isQuarantined(symbol, sourceHash):
        continue
      if strict:
        if not strictCtxMeasured:
          strictCtx = measureStrictCompletenessContext(
            (if projectRoot.len > 0: projectRoot else: resolveRepoRoot()),
            modulePath, currentModuleContent(modulePath))
          strictCtxMeasured = true
        if not strictCompletenessAdmits(claim, strictCtx):
          continue
      eligible.add((cid, claim))

    if eligible.len == 0:
      admission.verdicts.add(JournalVkdSymbolVerdict(
        symbol: symbol, outcome: jvNoCurrentEvidence))
      continue

    # Dedup eligible records by FUNCTION-LEVEL evidence key (step 7). The
    # stored v3 identity binds the whole-repo subject tree merkle root, so a
    # re-verification after an unrelated commit yields the same evidence under
    # a different identityDigest. Ambiguity means different EVIDENCE, not
    # different tree snapshots: keys > 1 → UNKNOWN; one key → count once.
    var uniqueCandidates: seq[Candidate]
    var seenKeys: seq[string]
    var seenIdentities: seq[string]
    for cand in eligible:
      let identity = cand.claim.getOrDefault("identityDigest").getStr("")
      if identity.len == 0:
        continue  # a full-cert claim without identityDigest cannot be trusted
      let key = journalEvidenceKeyStrict(cand.claim)
      if key.len == 0:
        continue
      # Keep EVERY record for admission: the same evidence may be recorded by
      # a verification commit and a promotion commit, and only one of them is
      # signed for its own commit id. Distinct keys decide ambiguity.
      uniqueCandidates.add(cand)
      if key notin seenKeys:
        seenKeys.add(key)
        seenIdentities.add(identity)

    if seenKeys.len > 1:
      admission.verdicts.add(JournalVkdSymbolVerdict(
        symbol: symbol, outcome: jvAmbiguous,
        variantCount: seenKeys.len, identityDigests: seenIdentities.sorted()))
      continue
    if seenKeys.len == 0:
      # Every eligible claim lacked identityDigest/semantic key — no
      # deduplicatable, trustworthy identity → not current evidence.
      admission.verdicts.add(JournalVkdSymbolVerdict(
        symbol: symbol, outcome: jvNoCurrentEvidence))
      continue

    # One distinct EVIDENCE key may have several journal records: the
    # verification commit and the promotion commit carrying the same claim.
    # Closure reconstructs a claim under the RECORD's commit id, so only the
    # record the claim was signed for validates (a promotion record's claim
    # still names the verification commit). Count the symbol when ANY record
    # for this evidence passes the v1 closure AND the canonical VKD admission
    # predicate; if none does, the evidence is not current (fail-closed).
    let first = uniqueCandidates[0]
    let entry = RuntimeAxiomEntry(
      name: first.claim.getOrDefault("functionName").getStr(""),
      sourcePath: first.claim.getOrDefault("modulePath").getStr(""),
      isKernel: true,
      irHash: first.claim.getOrDefault("irHash").getStr(""))
    var admitted = false
    for cand in uniqueCandidates:
      var certNode = cand.claim
      if verifyJournalClaimClosure(certNode, cand.commitId, projectRoot) and
         proof_integrity.isVkdAdmissible(certNode, entry, scope, certificate_verifier.isDeepVerified) == proof_integrity.varAdmit:
        admission.counted += 1
        admission.verdicts.add(JournalVkdSymbolVerdict(
          symbol: symbol, outcome: jvCounted,
          commitId: cand.commitId,
          identityDigest: cand.claim.getOrDefault("identityDigest").getStr("")))
        admitted = true
        break
    if not admitted:
      admission.verdicts.add(JournalVkdSymbolVerdict(
        symbol: symbol, outcome: jvNoCurrentEvidence))

  ok(admission)

{.pop.}
