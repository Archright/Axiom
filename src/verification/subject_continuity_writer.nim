import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Subject-Continuity Certificate writer (certification-continuity Phase 4 —
## §4.1 "Certificate mint"). EXTENSION of the existing v3 certificate writer
## machinery, NOT a fork and NOT a parallel store: the same canonical JSON
## serializer (canonical_certificate_payload), the same v3 identity
## projection (certificate_identity), the same journal-first TrustCommit
## binding (trust_commit) and the same Ed25519 attestation block
## (infrastructure/certificate_attestation) used by cert_writer.nim's UAP
## path. The new cert kind "subject-continuity" carries the subject identity
## (candidate OID, tree digest, base), chain provenance, and the bound digest
## set of a successful trusted attestation run.
##
## This writer is invoked ONLY by the attestation orchestrator after the full
## Verify(E, M) chain passed — it never decides a verdict, it serializes an
## attested one. Fail-closed: every invariant violation rejects the mint.

import std/[json, os, strutils]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/proof/source_fingerprint
import core/results
import core/trusted/fingerprint_generator
import core/trusted/trust_commit
import infrastructure/certificate_attestation
import verification/canonical_certificate_payload
import verification/canonical_json
import verification/certificate_identity
import verification/verification_subject

when fileExists("src/generated/build_env.nim"):
  import generated/build_env
else:
  const BuildEnvZ3Version = "unavailable"

axiomIoBoundary()

type
  SubjectCertificateInput* = object
    subject*: VerificationSubject
    modulePath*: string          ## evidence.funcPath — where funcSource came from
    sourceCode*: string          ## evidence.funcSource (whole module file content)
    funcName*: string
    leanSource*: string          ## kernel re-executed Lean artifact (INV-6)
    smtlib2*: string             ## kernel re-executed Z3 query (INV-10)
    leanProposition*: string     ## proposition text when derivable ("" = unbound)
    prHeadSha*: string
    prNumber*: int
    envDigest*: string
    policyDigest*: string
    scopeDigest*: string
    toolchainIdentity*: string   ## D2 pinned "nim-<v>|lean-<v>|z3-<v>" identity
    evidenceDigest*: string      ## sha256 over the evidence bundle wire
    irHash*: string              ## agreed-IR digest of the extraction differential
    createdAt*: string           ## ISO8601 UTC mint time
    certTree*: string            ## merge-candidate tree OID (tree of the test
                                 ## merge ref) — the identity chain's cert-side
                                 ## link (testedTree == mergeTree == certTree,
                                 ## ADR-0025 §11); "" only on legacy full-attest
                                 ## surfaces without merge context
    axiomVersion*: string

  SubjectCertificateMintResult* = object
    path*: string
    commitId*: string

func subjectCertEvidenceId*(evidenceDigest: string): string {.raises: [].} =
  ## Content identity of the bound evidence bundle: the digest doubles as the
  ## v3 evidenceId so the 13-field identity projection covers the evidence.
  if evidenceDigest.len > 0:
    "sha256:" & evidenceDigest
  else:
    ""

func subjectCertDigestSet*(input: SubjectCertificateInput): tuple[
    sourceHash, claimJson, inputHash, solverInputDigest, solverResultDigest: string] {.raises: [].} =
  ## The digest family shared by the payload, the identity projection and the
  ## attestation block — computed once so writer and attestation cannot drift.
  let sourceHash = computeStableSourceFingerprint(input.sourceCode)
  let claimJson = canonical_json.canonicalJsonString(%*{
    "type": "subject-continuity",
    "status": "certGreen",
    "modulePath": input.modulePath,
    "functionName": input.funcName
  })
  let inputHashRaw = join([
    "modulePath", input.modulePath,
    "functionName", input.funcName,
    "sourceHash", sourceHash,
    "irHash", input.irHash
  ], "\x1f")
  let solverInputRaw = if input.smtlib2.len > 0:
    input.smtlib2
  elif input.leanProposition.len > 0:
    input.leanProposition
  else:
    ""
  let solverResultRaw = join([
    "solverStatus", "unsat",
    "z3Executed", "true",
    "solverInputBytes", $input.smtlib2.len,
    "tier", "certGreen"
  ], "\n")
  (sourceHash: sourceHash,
   claimJson: claimJson,
   inputHash: "sha256:" & sha256Hex(inputHashRaw),
   solverInputDigest: "sha256:" & sha256Hex(solverInputRaw),
   solverResultDigest: "sha256:" & sha256Hex(solverResultRaw))

func subjectCertIdentity*(input: SubjectCertificateInput; digests: tuple[
    sourceHash, claimJson, inputHash, solverInputDigest, solverResultDigest: string]): string {.raises: [].} =
  ## The v3 identity projection — the field set/order is the single source of
  ## truth shared with the structural verifier (certificate_identity.nim).
  compV3Identity(V3IdentityState(
    schemaVersion: CanonicalCertificateSchemaVersion,
    modulePath: input.modulePath,
    functionName: input.funcName,
    sourceHash: digests.sourceHash,
    irHash: input.irHash,
    leanProposition: input.leanProposition,
    solverStatus: "unsat",
    status: "certGreen",
    winningStrategy: "lean-replay",
    inputHash: digests.inputHash,
    solverInputDigest: digests.solverInputDigest,
    solverResultDigest: digests.solverResultDigest,
    evidenceId: subjectCertEvidenceId(input.evidenceDigest)
  ))

func subjectCertCoreFields*(input: SubjectCertificateInput; digests: tuple[
    sourceHash, claimJson, inputHash, solverInputDigest, solverResultDigest: string]): JsonNode {.raises: [].} =
  ## All payload fields EXCEPT the journal/attestation additions — the exact
  ## record the TrustCommit journal is bound to.
  let s = input.subject
  result = newJObject()
  result["kind"] = %"subject-continuity"
  result["schemaVersion"] = %CanonicalCertificateSchemaVersion
  result["modulePath"] = %input.modulePath
  result["functionName"] = %input.funcName
  result["fingerprint"] = %computeVerificationFingerprint(input.irHash, input.leanProposition)
  result["sourceHash"] = %digests.sourceHash
  result["trusted"] = %true
  result["kernel"] = %true
  result["status"] = %"certGreen"
  result["reason"] = %"dual-verified"
  result["solverStatus"] = %"unsat"
  result["winningStrategy"] = %"lean-replay"
  result["solverMeta"] = %*{
    "leanCompilerVerified": true,
    "negativeTestResult": false,
    "vacuityChecked": false,
    "vacuityProven": false,
    "solverVersion": BuildEnvZ3Version,
    "solverProvenance": "spZ3SAT",
    "z3Executed": true
  }
  result["verificationTier"] = %"dual-verified"
  result["leanProposition"] = %input.leanProposition
  result["smtlib2"] = %input.smtlib2
  result["leanSource"] = %input.leanSource
  result["leanSourceHash"] = %sha256Hex(input.leanSource)
  result["evidenceId"] = %subjectCertEvidenceId(input.evidenceDigest)
  result["irHash"] = %input.irHash
  result["translationVersion"] = %"axiom-ir-smt-v1"
  result["claim"] = %*{
    "type": "subject-continuity",
    "status": "certGreen",
    "modulePath": input.modulePath,
    "functionName": input.funcName
  }
  result["inputHash"] = %digests.inputHash
  result["solverInputDigest"] = %digests.solverInputDigest
  result["solverResultDigest"] = %digests.solverResultDigest
  result["identityDigest"] = %subjectCertIdentity(input, digests)

func subjectCertBindingFields*(input: SubjectCertificateInput): JsonNode {.raises: [].} =
  ## The subject binding block — attested fields: covered by the Ed25519
  ## payload signature, so ANY post-mint tamper fails structural verify.
  ## certTree (the merge-candidate tree OID) is recorded ONLY when the mint
  ## had merge context — the legacy full-attest surface without --merge-tree
  ## keeps its legacy byte shape; the mint path (witness→sign) always carries
  ## it and the mint workflow fail-closes on its absence.
  let s = input.subject
  result = newJObject()
  result["subjectId"] = %s.subjectId
  result["baseSha"] = %s.baseSha
  result["headSha"] = %s.headSha
  result["headTreeDigest"] = %s.headTreeDigest
  if input.certTree.len > 0:
    result["certTree"] = %input.certTree
  result["policyDigest"] = %s.policyDigest
  result["scopeDigest"] = %s.scopeDigest
  result["evidenceDigest"] = %s.evidenceDigest
  result["envDigest"] = %input.envDigest
  result["toolchainIdentity"] = %input.toolchainIdentity
  result["prNumber"] = %input.prNumber
  result["createdAt"] = %input.createdAt

proc subjectCertValidate*(input: SubjectCertificateInput): string {.raises: [].} =
  ## "" = mintable; otherwise the rejection reason (fail-closed on every
  ## invariant violation, mirroring the UAP writer's guard discipline).
  let subjectProblem = validateSubject(input.subject)
  if subjectProblem.len > 0:
    return "subject_continuity_writer: " & subjectProblem
  if input.modulePath.len == 0 or input.funcName.len == 0 or input.sourceCode.len == 0:
    return "subject_continuity_writer: module path/function/source required (fail-closed)"
  if input.leanSource.len == 0 or input.smtlib2.len == 0:
    return "subject_continuity_writer: leanSource and smtlib2 required (fail-closed)"
  if input.evidenceDigest.len != 64 or input.irHash.len == 0:
    return "subject_continuity_writer: evidence digest must be 64 hex and irHash required (fail-closed)"
  if not isHexOfLen(input.envDigest, 64) or not isHexOfLen(input.policyDigest, 64) or
     not isHexOfLen(input.scopeDigest, 64):
    return "subject_continuity_writer: env/policy/scope digests must be 64 hex (fail-closed)"
  if not isHexOfLen(input.prHeadSha, 40):
    return "subject_continuity_writer: prHeadSha must be 40 hex (fail-closed)"
  if input.prHeadSha != input.subject.headSha:
    return "subject_continuity_writer: prHeadSha must equal subject.headSha (fail-closed)"
  if input.certTree.len > 0 and not isHexOfLen(input.certTree, 40):
    return "subject_continuity_writer: certTree must be 40 lowercase hex — the merge-candidate tree OID (fail-closed)"
  if input.toolchainIdentity.len == 0 or not isValidIso8601Zulu(input.createdAt):
    return "subject_continuity_writer: toolchain identity and ISO createdAt required (fail-closed)"
  ""

proc subjectCertJournalBind*(certDir: string; node: JsonNode; input: SubjectCertificateInput): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Journal-first binding: the SAME trust-commit machinery as the UAP path.
  ## The claim is the cert payload AT THIS POINT (before provenance/attestation
  ## fields), so cert↔journal replay equality holds by construction.
  commitCertificateVerification(certDir, node, input.modulePath, input.funcName,
    "unsat", input.irHash, input.leanProposition, "")

proc subjectCertSignAndWrite*(certPath: string; node: JsonNode; claimJson, commitId: string): Result[void, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Provenance + Ed25519 attestation over the FINAL deterministic payload
  ## (attestation block itself excluded by signCertificatePayload), then the
  ## canonical RFC 8785 write. Sign failure is a hard error — never emit an
  ## unattested certificate.
  node["trustCommitId"] = %commitId
  node["provenance"] = %*{
    "journalCommitId": commitId,
    "certificateDigest": node["identityDigest"].getStr(),
    "scheme": "axiom.subject-cert.v1"
  }
  let attSig = signCertificatePayload(node)
  if attSig.isErr:
    return err("subject_continuity_writer: attestation signing failed: " & attSig.error)
  node["attestation"] = %*{
    "authority": "axiom",
    "policyVersion": CanonicalCertificateSchemaVersion,
    "claimDigest": "sha256:" & sha256Hex(claimJson),
    "journalRef": commitId,
    "algorithm": AxiomAttestationAlgorithm,
    "publicKeyId": attSig.get.publicKeyId,
    "signature": attSig.get.signature
  }
  writeFile(certPath, canonicalCertificateString(node))
  Result[void, string](ok: true)

proc writeSubjectContinuityCertificate*(certDir: string;
                                        input: SubjectCertificateInput): Result[SubjectCertificateMintResult, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Mint ONE subject-continuity certificate. Append-only: an existing file
  ## for the same subjectId is refused (a subject is certified once per mint).
  let problem = subjectCertValidate(input)
  if problem.len > 0:
    return err(problem)
  if not dirExists(certDir):
    createDir(certDir)
  let certPath = joinPath(certDir, input.subject.subjectId & ".json")
  if fileExists(certPath):
    return err("subject_continuity_writer: certificate already exists — append-only, overwrite refused (fail-closed): " & certPath)
  let digests = subjectCertDigestSet(input)
  var node = subjectCertCoreFields(input, digests)
  let binding = subjectCertBindingFields(input)
  for key, value in binding.pairs:
    node[key] = value
  let commitRes = subjectCertJournalBind(certDir, node, input)
  if commitRes.isErr:
    return err("subject_continuity_writer: TrustCommit journal write rejected: " & commitRes.error)
  let written = subjectCertSignAndWrite(certPath, node, digests.claimJson, commitRes.get)
  if written.isErr:
    return err("subject_continuity_writer: " & written.error)
  ok(SubjectCertificateMintResult(path: certPath, commitId: commitRes.get))

{.pop.}
