# Phase-4b: writeCertificateFromUapResult is projection-only when a VerifiedClaim
# is present — status comes from the CLAIM, never recomputed from Z3.

import std/json
import std/os
import std/options
import std/strutils
import core/crypto/hash_kernel
import core/trusted/layer_declaration
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/claim_authority
import core/trusted/claim_projection
import core/trusted/trust_commit
import core/utils/io_utils
import verification/cert_writer

proc noSpecClaim(): VerifiedClaim =
  ## A claim whose outcome is clNoSpecification (MINED spec => no authorized spec).
  ## legacyProjection renders it as "certNoObligation" (a legacy-write-gate-allowed status).
  let s = SpecificationArtifact(canonicalSpecIR: @["(>= result x)"], origin: soMined,
                                ruleId: "s", ruleVersion: "v1")
  var ctx = ClaimContext(
    subjectId: "src/mod.nim::f", sourceIdentity: "h", specification: s,
    semanticProfileId: "SPV1", obligationGenerated: true, supported: true,
    dependenciesSatisfied: true, proofSignal: psUnsat, policyId: "apV1")
  ctx.evidenceBundle.specificationArtifact = s
  ctx.evidenceBundle.facts.solver.solverIdentity = "z3"
  deriveClaim(ctx, apV1)

proc main() =
  echo "=== Phase-4b claim-authoritative writer ==="
  let tmp = getTempDir() / "ax_writer_claim" & $getCurrentProcessId()
  try:
    removeDir(tmp)
  except CatchableError:
    # axiom:best-effort(temp dir pre-cleanup is non-fatal; test asserts on writeCertificate output)
    discard
  discard existsOrCreateDirOpt(tmp)
  let claim = noSpecClaim()
  doAssert claim.outcome == clNoSpecification
  var logLines: seq[string] = @[]
  # solverStatus="unsat" would (without a claim) yield a verified tier — but the claim
  # (clNoSpecification) must WIN and render as certNoObligation (projection only).
  let ok = writeCertificateFromUapResult(
    certDir = tmp,
    modulePath = "src/mod.nim",
    functionName = "f",
    sourceCode = "func f(x:int):int = x",
    leanKernelVerified = false,
    smtlib2 = "(set-logic QF_BV)",
    solverStatus = "unsat",
    logLines = logLines,
    irHash = "irhash123",
    verifiedClaim = some(claim),
    semanticProfileId = "SPV1")
  doAssert ok, "writeCertificateFromUapResult(claim) must succeed, logs: " & logLines.join("; ")

  let idsRes = listCommitIds(tmp)
  doAssert idsRes.ok, "journal ids available"
  var solverInvocations: seq[string] = @[]
  var foundUapCommit = false
  var foundV2Commit = false
  for id in idsRes.value:
    let c = readCommit(tmp, id)
    doAssert c.ok, "journal commit reads: " & id
    doAssert validateCommit(c.value).ok, "journal commit validates: " & id
    solverInvocations.add(c.value.solverInvocation)
    if c.value.solverInvocation == "batch-uap-loop" and c.value.claim.len > 0:
      let commitNode = parseJson(commitToJson(c.value))
      let claimNode = parseJson(c.value.claim)
      doAssert commitNode["kind"].getStr == "tcVerifiedProof"
      doAssert claimNode["status"].getStr == "certNoObligation",
        "status must come from claim projection (not Z3), got: " & claimNode["status"].getStr
      doAssert claimNode["reason"].getStr == "claim-derived"
      doAssert claimNode["claimId"].getStr == claim.claimId
      doAssert c.value.claim.len > 0
      doAssert c.value.solverInvocation == "batch-uap-loop"
      doAssert c.value.certificateDigest == hash_kernel.sha256Hex(c.value.claim)
      doAssert c.value.evidenceId == computeEvidenceId(c.value.claim, c.value.solverInvocation, c.value.certificateDigest)
      doAssert c.value.scopeDigest.len > 0
      doAssert c.value.configDigest.len > 0
      foundUapCommit = true
    elif c.value.solverInvocation == "v2-verified" and c.value.claim.len > 0:
      let v2Node = parseJson(c.value.claim)
      doAssert v2Node["schemaVersion"].getStr == "2"
      doAssert v2Node["outcome"].getStr == "clNoSpecification"
      foundV2Commit = true
  doAssert solverInvocations.len >= 3, "journal contains z3out + batch-uap-loop + v2 commits"
  doAssert "z3out" in solverInvocations, "journal includes z3out solverInvocation"
  doAssert "batch-uap-loop" in solverInvocations, "journal includes batch-uap-loop solverInvocation"
  doAssert "v2-verified" in solverInvocations, "journal includes v2-verified solverInvocation"
  doAssert not fileExists(tmp / "irhash123.z3out"), "legacy .z3out sidecar removed"
  doAssert not fileExists(tmp / "irhash123.v2.json"), "legacy .v2.json sidecar removed"
  # v3 provenance contract: the writer emits the canonical certificate projection
  # file (provenance_contract_v3.md — journal = ledger, certificate = projection);
  # the TrustCommit journal above remains the authoritative SSOT.
  doAssert fileExists(tmp / "irhash123.json"), "v3 canonical certificate projection emitted"
  doAssert foundUapCommit, "journal includes batch-uap-loop commit"
  doAssert foundV2Commit, "journal includes v2-verified commit"
  echo "  OK: claim-authoritative status + TrustCommit journal"
  try:
    removeDir(tmp)
  except CatchableError:
    # axiom:best-effort(temp dir teardown is cleanup; test outcome already asserted above)
    discard
  echo "=== Phase-4b claim-authoritative writer OK ==="
main()
