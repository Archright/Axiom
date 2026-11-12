# Wave 4: writer sidecar payloads now become TrustCommit journal records.

import std/json
import std/os
import std/options
import std/strutils
import std/tables

import core/crypto/hash_kernel
import core/results
import core/trusted/claim_authority
import core/trusted/claim_projection
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/scope_identity
import core/trusted/specification_artifact
import core/trusted/trust_commit
import verification/cert_writer

## Test suite for the Wave 4 cert_writer TrustCommit construction path.
## It mirrors the two durable payloads formerly written as sidecars:
##   * .z3out -> canonical JSON string "unsat" via solverInvocation "z3out"
##   * .v2.json -> canonical CertificateV2 JSON via solverInvocation "v2-verified"

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

proc tmpBase(): string =
  let d = getTempDir() / "ax_wave4_writer_tc" & $getCurrentProcessId()
  if dirExists(d):
    removeDir(d)
  createDir(d)
  d

proc wave4ScopeDigest(modulePath, functionName: string): string {.raises: [].} =
  canonicalScopeDigest(scopeInputFromSynthetic(
    @[modulePath & "::" & functionName], @[], 1, 0,
    "wave4-cert-writer", "axiom-wave4-cert-writer-v1"))

proc wave4ConfigDigest(modulePath, functionName, solverStatus, irHash: string): string {.raises: [].} =
  configIdentityDigest("wave4-cert-writer", modulePath & "::" & functionName & "|" & solverStatus & "|" & irHash)

proc mkZ3outCommit(modulePath, functionName, solverStatus, irHash: string): TrustCommit =
  let payload = "unsat"
  let claim = $newJString(payload)
  let certificateDigest = sha256Hex(payload)
  TrustCommit(kind: tcVerifiedProof,
    evidenceId: computeEvidenceId(claim, "z3out", certificateDigest),
    claim: claim,
    solverInvocation: "z3out",
    attestation: "Z3 result payload captured in TrustCommit journal",
    certificateDigest: certificateDigest,
    scopeDigest: wave4ScopeDigest(modulePath, functionName),
    configDigest: wave4ConfigDigest(modulePath, functionName, solverStatus, irHash),
    parentCommit: none(string))

proc mkV2VerifiedCommit(claim: VerifiedClaim; semanticProfileId, modulePath, functionName, solverStatus, irHash: string): TrustCommit =
  let v2 = v2Projection(claim, semanticProfileId)
  let claimStr = $v2
  let certificateDigest = sha256Hex(claimStr)
  TrustCommit(kind: tcVerifiedProof,
    evidenceId: computeEvidenceId(claimStr, "v2-verified", certificateDigest),
    claim: claimStr,
    solverInvocation: "v2-verified",
    attestation: "CertificateV2 claim projection captured in TrustCommit journal",
    certificateDigest: certificateDigest,
    scopeDigest: wave4ScopeDigest(modulePath, functionName),
    configDigest: wave4ConfigDigest(modulePath, functionName, solverStatus, irHash),
    parentCommit: none(string))

proc noSpecClaim(): VerifiedClaim =
  let s = SpecificationArtifact(canonicalSpecIR: @["(>= result x)"], origin: soMined,
                                ruleId: "s", ruleVersion: "v1")
  var ctx = ClaimContext(
    subjectId: "src/mod.nim::f", sourceIdentity: "h", specification: s,
    semanticProfileId: "SPV1", obligationGenerated: true, supported: true,
    dependenciesSatisfied: true, proofSignal: psUnsat, policyId: "apV1")
  ctx.evidenceBundle.specificationArtifact = s
  ctx.evidenceBundle.facts.solver.solverIdentity = "z3"
  deriveClaim(ctx, apV1)

proc hasSolverInvocation(commits: seq[TrustCommit]; solverInvocation: string): bool =
  for c in commits:
    if c.solverInvocation == solverInvocation:
      return true
  false

proc main() =
  echo "=== Wave 4 writer TrustCommit tests ==="

  let base = tmpBase()
  let z3Commit = mkZ3outCommit("src/mod.nim", "f", "unsat", "wave4ir")
  let claim = noSpecClaim()
  let v2Commit = mkV2VerifiedCommit(claim, "SPV1", "src/mod.nim", "f", "unsat", "wave4ir")

  expect(validateCommit(z3Commit).ok, "z3out TrustCommit validates")
  expect(validateCommit(v2Commit).ok, "v2-verified TrustCommit validates")

  expect(z3Commit.evidenceId == computeEvidenceId(z3Commit.claim, z3Commit.solverInvocation, z3Commit.certificateDigest),
         "z3out evidenceId binds claim/solver/certificateDigest")
  expect(v2Commit.evidenceId == computeEvidenceId(v2Commit.claim, v2Commit.solverInvocation, v2Commit.certificateDigest),
         "v2 evidenceId binds claim/solver/certificateDigest")

  expect(z3Commit.evidenceId != v2Commit.evidenceId, "z3out and v2 evidenceId differ")
  expect(z3Commit.evidenceId != computeEvidenceId(z3Commit.claim, "z3out", "changed-digest"),
         "z3out evidenceId sensitive to certificateDigest")
  expect(z3Commit.evidenceId != computeEvidenceId("sat", z3Commit.solverInvocation, z3Commit.certificateDigest),
         "z3out evidenceId sensitive to payload")

  let z3Res = commitVerification(base, z3Commit)
  let v2Res = commitVerification(base, v2Commit)
  expect(z3Res.ok, "commitVerification z3out ok: " & (if z3Res.isErr: z3Res.error else: ""))
  expect(v2Res.ok, "commitVerification v2 ok: " & (if v2Res.isErr: v2Res.error else: ""))

  let z3Back = readCommit(base, z3Res.value)
  let v2Back = readCommit(base, v2Res.value)
  expect(z3Back.ok, "z3out journal round-trip")
  expect(v2Back.ok, "v2 journal round-trip")
  expect(z3Back.value.claim == z3Commit.claim, "z3out claim round-trip")
  expect(z3Back.value.solverInvocation == "z3out", "z3out solverInvocation round-trip")
  expect(v2Back.value.claim == v2Commit.claim, "v2 claim round-trip")
  expect(v2Back.value.solverInvocation == "v2-verified", "v2 solverInvocation round-trip")
  expect(validateCommit(z3Back.value).ok, "z3out persisted commit revalidates")
  expect(validateCommit(v2Back.value).ok, "v2 persisted commit revalidates")

  let idsRes = listCommitIds(base)
  expect(idsRes.ok, "listCommitIds ok")
  expect(idsRes.value.len >= 2, "journal contains z3out and v2 commits")
  var replayRes = replayJournal(base)
  expect(replayRes.ok, "replayJournal reconstructs both Wave 4 commits")

  let tmp = tmpBase()
  let writerClaim = noSpecClaim()
  var logLines: seq[string] = @[]
  let ok = writeCertificateFromUapResult(
    certDir = tmp,
    modulePath = "src/mod.nim",
    functionName = "f",
    sourceCode = "func f(x:int):int = x",
    leanKernelVerified = false,
    smtlib2 = "(set-logic QF_BV)",
    solverStatus = "unsat",
    logLines = logLines,
    irHash = "wave4ir",
    verifiedClaim = some(writerClaim),
    semanticProfileId = "SPV1")
  expect(ok, "writer succeeds after sidecar migration: " & logLines.join("; "))
  expect(fileExists(tmp / "wave4ir.json"), "writer emits canonical JSON certificate payload")
  expect(not fileExists(tmp / "wave4ir.z3out"), "legacy .z3out sidecar removed")
  expect(not fileExists(tmp / "wave4ir.v2.json"), "legacy .v2.json sidecar removed")

  let writerIdsRes = listCommitIds(tmp)
  expect(writerIdsRes.ok, "writer journal ids available")
  var writerCommits: seq[TrustCommit] = @[]
  for id in writerIdsRes.value:
    let c = readCommit(tmp, id)
    expect(c.ok, "writer journal commit reads: " & id)
    writerCommits.add(c.value)
  expect(writerIdsRes.value.len >= 3, "writer journal contains at least batch-uap-loop + z3out + v2 commits")
  expect(hasSolverInvocation(writerCommits, "z3out"), "writer emits z3out TrustCommit")
  expect(hasSolverInvocation(writerCommits, "v2-verified"), "writer emits v2-verified TrustCommit")
  expect(hasSolverInvocation(writerCommits, "batch-uap-loop"), "writer preserves existing UAP TrustCommit")

  removeDir(tmp)
  removeDir(base)

  echo ""
  if failures == 0:
    echo "=== All Wave 4 writer TrustCommit tests PASSED ==="
  else:
    echo "=== " & $failures & " Wave 4 writer TrustCommit test(s) FAILED ==="
    quit(1)

main()
