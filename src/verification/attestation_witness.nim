import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Witness bundle codec for the two-tier certificate mint path (DEBT#464 S4
## Phase 1a — plan v12 §identity separation).
##
## A witness is an UNSIGNED bundle produced by `ax cert attest --witness-only`
## (the unprivileged tier) and consumed by `ax cert attest --sign <witness>`
## (the publication tier). It carries EXACTLY the semantic inputs needed to
## deterministically reconstruct the canonical subject-continuity certificate
## representation, plus a provenance block for attribution/traceability:
##
##   semantic  = D9 evidence record (schema axiom.attestation.evidence.v1 —
##               UNCHANGED) + the subject binding (6-field identity wire +
##               prNumber + registration createdAt) + evidenceDigest + irHash +
##               mint createdAt + the OPTIONAL s1a judgment binding
##               ({basis, evidenceKey, projection, projectionSha256} — present
##               only when the judgment CAS is armed; absent = the pre-CAS
##               byte-identical wire, E-A golden preserved)
##   provenance = mergeSha(M) · mergeTreeDigest(tree of M — the merge-candidate
##               tree OID, 40 hex) · toolCommit(B) · prHeadSha(H) · prNumber(PR) ·
##               runId · runAttempt · artifact identity ("witness-{attempt}")
##
## Certificate semantic identity = (B,H) + the attest binding fields; M, runId
## and runAttempt NEVER enter the certificate representation (provenance stays
## in the witness + ledger commit metadata) — that is what makes the
## full-attest ≡ witness→sign byte-equality golden (E-A) well-formed: identical
## semantic inputs → identical canonical certificate bytes, including the
## deterministic Ed25519 signature.
##
## Integrity is fail-closed: every recorded value is re-derived at parse time
## (evidence digest, subjectId wire, witness digest over the whole bundle
## minus itself) and any mismatch rejects the bundle with a WITNESS_* reason.

import std/[json, os, strutils]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/release/version_derive
import verification/attestation_orchestrator
import verification/canonical_json
import verification/judgment_cas
import verification/kernel_reexecution
import verification/subject_continuity_writer
import verification/verification_subject

axiomIoBoundary()

const
  WitnessScheme* = "axiom.witness.v1"
    ## schemaVersion of the unsigned witness bundle (distinct from the
    ## evidence record and the certificate — the witness is a transport
    ## artifact, never a certificate).
  WitnessArtifactPrefix = "witness-"
    ## deterministic artifact name prefix — artifact identity = "witness-{run_attempt}".

type
  WitnessProvenance* = object
    mergeSha*: string       ## M — the merge-ref commit (witness job: github.sha of the PR run)
    mergeTreeDigest*: string ## tree OID of mergeSha — the merge-candidate tree the
                             ## gateway tested (the identity chain's middle link:
                             ## testedTree == mergeTree == certTree, ADR-0025 §11)
    toolCommit*: string     ## B — the commit the ax binary that ran the chain was built from (= M.parent1)
    prHeadSha*: string      ## H — PR head commit the certificate attributes to
    prNumber*: int          ## PR number (0 = "no PR context" is honest, as in the evidence record)
    runId*: string          ## GitHub Actions run id (run instance identity)
    runAttempt*: string     ## GitHub Actions run attempt
    artifact*: string       ## artifact identity — deterministic "witness-{run_attempt}"

  WitnessSemantic* = object
    evidence*: AttestationInputs  ## D9 evidence record (axiom.attestation.evidence.v1 — unchanged)
    subject*: VerificationSubject ## the attest binding — 6-field identity wire + prNumber + createdAt
    evidenceDigest*: string       ## sha256 over the canonical evidence bundle wire (binding digest)
    irHash*: string               ## agreed-IR digest of the extraction differential (stage-b outcome)
    createdAt*: string            ## ISO8601 Z mint timestamp used for the certificate's createdAt
    judgment*: JsonNode           ## OPTIONAL s1a judgment binding ({basis, evidenceKey,
                                  ## projection, projectionSha256} — judgment_cas.judgmentWitnessNode);
                                  ## nil = absent (unarmed legacy path, byte-identical wire)
    judgments*: JsonNode = nil    ## OPTIONAL extension-subject judgment bindings — an ARRAY of
                                  ## {subject, basis, evidenceKey, projection, projectionSha256}
                                  ## nodes (judgment_cas.judgmentWitnessNodeFor); nil = absent.
                                  ## The mint pairs each element to its per-subject record file.

  WitnessBundle* = object
    schema*: string
    semantic*: WitnessSemantic
    provenance*: WitnessProvenance
    witnessDigest*: string  ## sha256 over the canonical bundle minus this field

# ---------------------------------------------------------------------------
# Pure wire builders (RFC 8785 canonical — the digest source of truth)
# ---------------------------------------------------------------------------

func evidenceRecordNode*(inputs: AttestationInputs): JsonNode {.raises: [].} =
  ## The FULL evidence record as the on-disk evidence file serializes it
  ## (13 fields — the evidenceDigest is computed over the 4-field bundle wire,
  ## not this record object; that mirrors the evidence FILE vs bundle digest
  ## relationship so the certificate binding matches exactly).
  %*{
    "schemaVersion": inputs.schemaVersion,
    "subjectId": inputs.subjectId,
    "prNumber": inputs.prNumber,
    "prHeadSha": inputs.prHeadSha,
    "leanSource": inputs.leanSource,
    "smtlib2": inputs.smtlib2,
    "funcSource": inputs.funcSource,
    "funcPath": inputs.funcPath,
    "funcName": inputs.funcName,
    "policyDigest": inputs.policyDigest,
    "scopeDigest": inputs.scopeDigest,
    "envDigest": inputs.envDigest,
    "toolchainIdentity": inputs.toolchainIdentity
  }

func subjectRecordNode*(subject: VerificationSubject): JsonNode {.raises: [].} =
  ## The canonical subject store record (11 fields) — the same wire
  ## toCanonicalJson emits, so subjectFromJson round-trips it strictly.
  %*{
    "schemaVersion": SubjectScheme,
    "subjectId": subject.subjectId,
    "baseSha": subject.baseSha,
    "headSha": subject.headSha,
    "headTreeDigest": subject.headTreeDigest,
    "policyDigest": subject.policyDigest,
    "scopeDigest": subject.scopeDigest,
    "evidenceDigest": subject.evidenceDigest,
    "prNumber": subject.prNumber,
    "createdAt": subject.createdAt,
    "provenance": {
      "source": subject.provenance.source,
      "scheme": subject.provenance.scheme
    }
  }

func witnessSemanticNode*(s: WitnessSemantic): JsonNode {.raises: [].} =
  result = %*{
    "evidence": evidenceRecordNode(s.evidence),
    "subject": subjectRecordNode(s.subject),
    "evidenceDigest": s.evidenceDigest,
    "irHash": s.irHash,
    "createdAt": s.createdAt
  }
  if not s.judgment.isNil:
    result["judgment"] = s.judgment
  if not s.judgments.isNil:
    result["judgments"] = s.judgments

func witnessProvenanceNode*(p: WitnessProvenance): JsonNode {.raises: [].} =
  %*{
    "mergeSha": p.mergeSha,
    "mergeTreeDigest": p.mergeTreeDigest,
    "toolCommit": p.toolCommit,
    "prHeadSha": p.prHeadSha,
    "prNumber": p.prNumber,
    "runId": p.runId,
    "runAttempt": p.runAttempt,
    "artifact": p.artifact
  }

func witnessBundleNode*(b: WitnessBundle): JsonNode {.raises: [].} =
  %*{
    "schema": b.schema,
    "semantic": witnessSemanticNode(b.semantic),
    "provenance": witnessProvenanceNode(b.provenance),
    "witnessDigest": b.witnessDigest
  }

func witnessBundleDigest*(b: WitnessBundle): string {.raises: [].} =
  ## sha256 over the canonical bundle wire EXCLUDING the witnessDigest field
  ## (a bundle cannot bind its own bytes through a field it contains). Any
  ## mutation — semantic or provenance — changes the digest (fail-closed).
  var node = witnessBundleNode(b)
  node["witnessDigest"] = %""
  sha256Hex(canonicalJsonString(node))

func provenanceValidationError*(p: WitnessProvenance): string {.raises: [].} =
  ## "" = well-formed; otherwise the rejection reason (WITNESS_PROVENANCE).
  if not isHexOfLen(p.mergeSha, 40):
    return "witness: mergeSha must be 40 lowercase hex (WITNESS_PROVENANCE)"
  if not isHexOfLen(p.mergeTreeDigest, 40):
    return "witness: mergeTreeDigest must be 40 lowercase hex — the tree OID of the merge-candidate commit (WITNESS_PROVENANCE)"
  if not isHexOfLen(p.toolCommit, 40):
    return "witness: toolCommit must be 40 lowercase hex (WITNESS_PROVENANCE)"
  if not isHexOfLen(p.prHeadSha, 40):
    return "witness: prHeadSha must be 40 lowercase hex (WITNESS_PROVENANCE)"
  if p.prNumber < 0:
    return "witness: prNumber must be non-negative (WITNESS_PROVENANCE)"
  if p.runId.len == 0 or not allCharsInSet(p.runId, {'0'..'9'}):
    return "witness: runId must be a decimal run id (WITNESS_PROVENANCE)"
  if p.runAttempt.len == 0 or not allCharsInSet(p.runAttempt, {'0'..'9'}):
    return "witness: runAttempt must be a decimal run attempt (WITNESS_PROVENANCE)"
  if p.artifact != WitnessArtifactPrefix & p.runAttempt:
    return "witness: artifact must be '" & WitnessArtifactPrefix & "{run_attempt}' — deterministic name contract (WITNESS_PROVENANCE)"
  ""

func semanticValidationError*(s: WitnessSemantic): string {.raises: [].} =
  ## "" = well-formed; otherwise the rejection reason (fail-closed on every
  ## invariant the publisher tier relies on).
  if s.evidenceDigest.len != 64 or not isHexOfLen(s.evidenceDigest, 64):
    return "witness: evidenceDigest must be 64 lowercase hex (WITNESS_EVIDENCE_BINDING)"
  if s.irHash.len == 0 or not isHexOfLen(s.irHash, 64):
    return "witness: irHash must be 64 lowercase hex (WITNESS_IRHASH)"
  if not isValidIso8601Zulu(s.createdAt):
    return "witness: createdAt must be ISO8601 'yyyy-MM-ddTHH:mm:ssZ' (WITNESS_CREATED_AT)"
  if not s.judgment.isNil:
    let judgmentProblem = validateJudgmentWitnessNode(s.judgment)
    if judgmentProblem.len > 0:
      return judgmentProblem
  if not s.judgments.isNil:
    if s.judgments.kind != JArray:
      return "witness: judgments must be an array of judgment bindings (fail-closed)"
    for el in s.judgments.items:
      let elProblem = validateJudgmentWitnessNode(el)
      if elProblem.len > 0:
        return elProblem
      let subjectNode = el{"subject"}
      if subjectNode.isNil or subjectNode.kind != JString or subjectNode.getStr().len == 0:
        return "witness: judgments[] element must name its subject (fail-closed)"
  ""

# ---------------------------------------------------------------------------
# Creation (witness-only surface)
# ---------------------------------------------------------------------------

proc createWitnessBundle*(subject: VerificationSubject; evidence: AttestationInputs;
                          irHash, createdAt: string; provenance: WitnessProvenance;
                          judgment: JsonNode = nil;
                          judgments: JsonNode = nil): Result[WitnessBundle, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Assemble ONE unsigned witness bundle. Fail-closed: the binding digest is
  ## RE-DERIVED here (never accepted from a caller-supplied value) and must
  ## equal the subject's recorded evidenceDigest; the evidence record must
  ## name the same subject/head. provenance is validated; createdAt/irHash
  ## must be well-formed. judgment (optional) must be a well-formed judgment
  ## witness binding when present.
  let evidenceProblem = validateAttestationInputs(evidence)
  if evidenceProblem.len > 0:
    return err("witness: " & evidenceProblem)
  let digest = evidenceBundleDigest(evidence)
  if digest != subject.evidenceDigest:
    return err("witness: evidence bundle digest " & digest[0 ..< 12] &
      " != subject evidenceDigest " & subject.evidenceDigest[0 ..< 12] &
      " (WITNESS_EVIDENCE_BINDING)")
  if evidence.subjectId != subject.subjectId or evidence.prHeadSha != subject.headSha:
    return err("witness: evidence record names a different subject/head than the store subject (WITNESS_SUBJECT_CROSSCHECK)")
  let semanticProblem = semanticValidationError(WitnessSemantic(
    evidence: evidence, subject: subject, evidenceDigest: digest,
    irHash: irHash, createdAt: createdAt, judgment: judgment,
    judgments: judgments))
  if semanticProblem.len > 0:
    return err(semanticProblem)
  let provProblem = provenanceValidationError(provenance)
  if provProblem.len > 0:
    return err(provProblem)
  if provenance.prHeadSha != subject.headSha:
    return err("witness: provenance prHeadSha " & provenance.prHeadSha[0 ..< 12] &
      " != subject headSha " & subject.headSha[0 ..< 12] & " (WITNESS_PROVENANCE)")
  if provenance.prNumber != evidence.prNumber:
    return err("witness: provenance prNumber " & $provenance.prNumber &
      " != evidence prNumber " & $evidence.prNumber & " (WITNESS_PROVENANCE)")
  var bundle = WitnessBundle(
    schema: WitnessScheme,
    semantic: WitnessSemantic(evidence: evidence, subject: subject,
      evidenceDigest: digest, irHash: irHash, createdAt: createdAt,
      judgment: judgment, judgments: judgments),
    provenance: provenance)
  bundle.witnessDigest = witnessBundleDigest(bundle)
  ok(bundle)

proc witnessBundleJson*(b: WitnessBundle): string {.raises: [].} =
  ## Canonical JSON serialization of the full bundle (all fields — the bytes
  ## written by the witness-only surface).
  canonicalJsonString(witnessBundleNode(b))

# ---------------------------------------------------------------------------
# Parsing + verification (sign surface — fail-closed)
# ---------------------------------------------------------------------------

type WitnessSemanticDecoded = object
  evidence: AttestationInputs
  subject: VerificationSubject
  evidenceDigest: string
  irHash: string
  createdAt: string
  judgment: JsonNode
  judgments: JsonNode

func toWitnessSemantic*(decoded: WitnessSemanticDecoded): WitnessSemantic {.raises: [].} =
  WitnessSemantic(evidence: decoded.evidence, subject: decoded.subject,
    evidenceDigest: decoded.evidenceDigest, irHash: decoded.irHash,
    createdAt: decoded.createdAt, judgment: decoded.judgment,
    judgments: decoded.judgments)

func witnessJsonObject(node: JsonNode; key: string; what: string): Result[JsonNode, string] {.raises: [].} =
  ## Strict JSON object-block accessor shared by the parse helpers below.
  let v = node{key}
  if v.isNil or v.kind != JObject:
    return err("witness: " & what & " missing (fail-closed)")
  ok(v)

func witnessJsonString(node: JsonNode; key, what: string): Result[string, string] {.raises: [].} =
  let v = node{key}
  if v.isNil or v.kind != JString:
    return err("witness: " & what & " missing or not a string (fail-closed)")
  ok(v.getStr())

proc decodeWitnessSemantic(semanticNode: JsonNode): Result[WitnessSemanticDecoded, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Re-derive the semantic block: evidence record, subject binding, binding
  ## digest and the reconstruction inputs — every recorded value cross-checked
  ## against the re-derived canonical forms (fail-closed).
  let evidenceNodeRes = witnessJsonObject(semanticNode, "evidence", "semantic evidence record")
  if evidenceNodeRes.isErr: return evidenceNodeRes.error.err
  let evidenceRes = inputsFromJson(evidenceNodeRes.get)
  if evidenceRes.isErr: return err("witness: " & evidenceRes.error)
  let subjectNodeRes = witnessJsonObject(semanticNode, "subject", "semantic subject binding")
  if subjectNodeRes.isErr: return subjectNodeRes.error.err
  let subjectRes = subjectFromJson(subjectNodeRes.get)
  if subjectRes.isErr: return err("witness: " & subjectRes.error)
  let evidence = evidenceRes.get
  let subject = subjectRes.get
  let evidenceDigest = evidenceBundleDigest(evidence)
  let recordedDigestRes = witnessJsonString(semanticNode, "evidenceDigest", "semantic evidenceDigest")
  if recordedDigestRes.isErr: return recordedDigestRes.error.err
  let recordedDigest = recordedDigestRes.get
  if recordedDigest != evidenceDigest:
    return err("witness: evidence digest mismatch — recorded " & recordedDigest[0 ..< 12] &
      " != recomputed " & evidenceDigest[0 ..< 12] & " (WITNESS_EVIDENCE_BINDING)")
  if recordedDigest != subject.evidenceDigest:
    return err("witness: evidence digest " & recordedDigest[0 ..< 12] &
      " != subject evidenceDigest " & subject.evidenceDigest[0 ..< 12] & " (WITNESS_SUBJECT_CROSSCHECK)")
  if evidence.subjectId != subject.subjectId:
    return err("witness: evidence subjectId differs from the subject binding (WITNESS_SUBJECT_CROSSCHECK)")
  if evidence.prHeadSha != subject.headSha:
    return err("witness: evidence prHeadSha differs from the subject headSha (WITNESS_SUBJECT_CROSSCHECK)")
  let irHashRes = witnessJsonString(semanticNode, "irHash", "semantic irHash")
  if irHashRes.isErr: return irHashRes.error.err
  let createdAtRes = witnessJsonString(semanticNode, "createdAt", "semantic createdAt")
  if createdAtRes.isErr: return createdAtRes.error.err
  ## The judgment binding is OPTIONAL (nil = the unarmed legacy wire). When
  ## present it must be a well-formed judgment witness node — the byte-level
  ## projection↔record binding is the mint's P7c, not the parser's.
  var judgment: JsonNode = nil
  let judgmentNode = semanticNode{"judgment"}
  if not judgmentNode.isNil:
    let judgmentProblem = validateJudgmentWitnessNode(judgmentNode)
    if judgmentProblem.len > 0:
      return err(judgmentProblem)
    judgment = judgmentNode
  var judgments: JsonNode = nil
  let judgmentsNode = semanticNode{"judgments"}
  if not judgmentsNode.isNil:
    if judgmentsNode.kind != JArray:
      return err("witness: judgments must be an array of judgment bindings (fail-closed)")
    for el in judgmentsNode.items:
      let elProblem = validateJudgmentWitnessNode(el)
      if elProblem.len > 0:
        return err(elProblem)
      let subjectNode = el{"subject"}
      if subjectNode.isNil or subjectNode.kind != JString or subjectNode.getStr().len == 0:
        return err("witness: judgments[] element must name its subject (fail-closed)")
    judgments = judgmentsNode
  let semantic = WitnessSemantic(evidence: evidence, subject: subject,
    evidenceDigest: recordedDigest, irHash: irHashRes.get, createdAt: createdAtRes.get,
    judgment: judgment, judgments: judgments)
  let semanticProblem = semanticValidationError(semantic)
  if semanticProblem.len > 0:
    return err(semanticProblem)
  ok(WitnessSemanticDecoded(evidence: evidence, subject: subject,
    evidenceDigest: recordedDigest, irHash: irHashRes.get, createdAt: createdAtRes.get,
    judgment: judgment, judgments: judgments))

proc decodeWitnessProvenance(provNode: JsonNode; subject: VerificationSubject;
                             evidence: AttestationInputs): Result[WitnessProvenance, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Re-derive the provenance block (M · B · H · PR · run identity) and
  ## cross-check it against the semantic subject/evidence bindings.
  if provNode.isNil or provNode.kind != JObject:
    return err("witness: provenance block missing (fail-closed)")
  template needStr(key: string): string =
    block:
      let v = provNode{key}
      if v.isNil or v.kind != JString:
        return err("witness: provenance field '" & key & "' missing or not a string (fail-closed)")
      v.getStr()
  let prNumberNode = provNode{"prNumber"}
  if prNumberNode.isNil or prNumberNode.kind != JInt:
    return err("witness: provenance prNumber missing or not an int (fail-closed)")
  let provenance = WitnessProvenance(
    mergeSha: needStr("mergeSha"),
    mergeTreeDigest: needStr("mergeTreeDigest"),
    toolCommit: needStr("toolCommit"),
    prHeadSha: needStr("prHeadSha"),
    prNumber: prNumberNode.getInt(),
    runId: needStr("runId"),
    runAttempt: needStr("runAttempt"),
    artifact: needStr("artifact"))
  let provProblem = provenanceValidationError(provenance)
  if provProblem.len > 0:
    return err(provProblem)
  if provenance.prHeadSha != subject.headSha:
    return err("witness: provenance prHeadSha " & provenance.prHeadSha[0 ..< 12] &
      " != subject headSha " & subject.headSha[0 ..< 12] & " (WITNESS_PROVENANCE)")
  if provenance.prNumber != evidence.prNumber:
    return err("witness: provenance prNumber " & $provenance.prNumber &
      " != evidence prNumber " & $evidence.prNumber & " (WITNESS_PROVENANCE)")
  ok(provenance)

proc verifyWitnessDigest(root: JsonNode; semantic: WitnessSemantic;
                         provenance: WitnessProvenance): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Recompute the whole-bundle digest over the parsed semantic/provenance and
  ## compare it against the recorded witnessDigest (the tamper gate).
  let recordedRes = witnessJsonString(root, "witnessDigest", "witnessDigest")
  if recordedRes.isErr: return recordedRes.error.err
  let recorded = recordedRes.get
  if recorded.len != 64 or not isHexOfLen(recorded, 64):
    return err("witness: witnessDigest must be 64 lowercase hex (fail-closed)")
  var bundle = WitnessBundle(schema: WitnessScheme, semantic: semantic,
    provenance: provenance, witnessDigest: recorded)
  let recomputed = witnessBundleDigest(bundle)
  if recomputed != recorded:
    return err("witness: bundle digest mismatch — recorded " & recorded[0 ..< 12] &
      " != recomputed " & recomputed[0 ..< 12] & " (WITNESS_DIGEST_MISMATCH)")
  ok(recorded)

proc parseWitnessBundleText*(text: string): Result[WitnessBundle, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Text → strictly validated witness bundle. Every recorded value is
  ## re-derived and cross-checked; ANY mismatch rejects the bundle (never a
  ## silent acceptance — WITNESS_* reason). This is the tamper-verification
  ## gate of the --sign surface.
  if text.len == 0:
    return err("witness: bundle text is empty (fail-closed)")
  var root: JsonNode
  try:
    root = parseJson(text)
  except CatchableError:
    return err("witness: malformed bundle JSON (fail-closed)")
  if root.isNil or root.kind != JObject:
    return err("witness: bundle must be a JSON object (fail-closed)")
  if root{"schema"}.isNil or root{"schema"}.kind != JString or root{"schema"}.getStr() != WitnessScheme:
    return err("witness: unsupported schema — expected '" & WitnessScheme & "' (WITNESS_SCHEMA)")
  let semanticNodeRes = witnessJsonObject(root, "semantic", "semantic block")
  if semanticNodeRes.isErr: return semanticNodeRes.error.err
  let semanticRes = decodeWitnessSemantic(semanticNodeRes.get)
  if semanticRes.isErr: return semanticRes.error.err
  let decoded = semanticRes.get
  let provRes = decodeWitnessProvenance(root{"provenance"}, decoded.subject, decoded.evidence)
  if provRes.isErr: return provRes.error.err
  let provenance = provRes.get
  let digestRes = verifyWitnessDigest(root, decoded.toWitnessSemantic, provenance)
  if digestRes.isErr: return digestRes.error.err
  ok(WitnessBundle(schema: WitnessScheme, semantic: decoded.toWitnessSemantic,
    provenance: provenance, witnessDigest: digestRes.get))

# ---------------------------------------------------------------------------
# Certificate reconstruction (sign surface)
# ---------------------------------------------------------------------------

func subjectCertInputFromWitness*(subject: VerificationSubject;
    evidence: AttestationInputs; irHash, createdAt, mergeTreeDigest: string): SubjectCertificateInput {.raises: [].} =
  ## Reconstruct the canonical SubjectCertificateInput from the witness
  ## semantic inputs — the EXACT field set attestMintStage builds (so the
  ## full-attest and witness→sign certificate representations coincide).
  ## No runId/runAttempt/M enter this representation (identity separation);
  ## certTree (the merge-candidate tree OID) is the provenance-observed
  ## identity link — carry it into the binding block.
  SubjectCertificateInput(
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
    evidenceDigest: evidenceBundleDigest(evidence),
    irHash: irHash,
    createdAt: createdAt,
    certTree: mergeTreeDigest,
    axiomVersion: axiomVersionWithPrefix)

proc signWitness*(bundle: WitnessBundle; certDir: string): Result[SubjectCertificateMintResult, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify → normalize → reconstruct → journal → sign the canonical
  ## certificate representation. NO kernel execution, NO network: the witness
  ## is the sole input. Reuses the v3 writer exactly (append-only, journal
  ## binding, deterministic Ed25519 attestation).
  let input = subjectCertInputFromWitness(bundle.semantic.subject, bundle.semantic.evidence,
    bundle.semantic.irHash, bundle.semantic.createdAt, bundle.provenance.mergeTreeDigest)
  writeSubjectContinuityCertificate(certDir, input)

{.pop.}
