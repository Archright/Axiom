import std/json
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/claim_authority
import core/trusted/cert_v2
import core/trusted/claim_projection

proc spec(origin: SpecOrigin): SpecificationArtifact =
  SpecificationArtifact(canonicalSpecIR: @[">= result x"], origin: origin,
                        ruleId: "s", ruleVersion: "v1")

proc provedClaim(): VerifiedClaim =
  let s = spec(soCanonicalDerived)
  var ctx = ClaimContext(
    subjectId: "foo", sourceIdentity: "h", specification: s,
    semanticProfileId: "SPV1", obligationGenerated: true, supported: true,
    dependenciesSatisfied: true, proofSignal: psUnsat, policyId: "apV1")
  ctx.evidenceBundle.specificationArtifact = s
  ctx.evidenceBundle.facts.solver.solverIdentity = "z3"
  deriveClaim(ctx, apV1)

proc disprovedClaim(): VerifiedClaim =
  let s = spec(soCanonicalDerived)
  var ctx = ClaimContext(
    subjectId: "foo", sourceIdentity: "h", specification: s,
    semanticProfileId: "SPV1", obligationGenerated: true, supported: true,
    dependenciesSatisfied: true, proofSignal: psCounterexample, policyId: "apV1")
  ctx.evidenceBundle.specificationArtifact = s
  ctx.evidenceBundle.facts.solver.solverIdentity = "z3"
  deriveClaim(ctx, apV1)

proc kernelCheckedProvedClaim(): VerifiedClaim =
  let s = spec(soCanonicalDerived)
  var ctx = ClaimContext(
    subjectId: "foo", sourceIdentity: "h", specification: s,
    semanticProfileId: "SPV1", obligationGenerated: true, supported: true,
    dependenciesSatisfied: true, proofSignal: psUnsat, policyId: "apV1")
  ctx.evidenceBundle.specificationArtifact = s
  ctx.evidenceBundle.facts.solver.solverIdentity = "z3"
  result = deriveClaim(ctx, apV1)
  result.assurance.kernelChecking = true

proc main() =
  echo "=== Phase-4a Claim Projection ==="

  # --- PROVED claim: certZ3Verified (no kernel checking) ---
  block:
    let claim = provedClaim()
    doAssert claim.outcome == clProved
    let legacy = legacyProjection(claim)
    doAssert legacy["status"].getStr() == "certZ3Verified"
    let v2 = v2Projection(claim, "SPV1")
    doAssert v2["outcome"].getStr() == "clProved"
    doAssert projectionInvariant(claim, "SPV1") == true

  # --- PROVED claim with kernelChecking: certGreen ---
  block:
    let claim = kernelCheckedProvedClaim()
    doAssert claim.outcome == clProved
    doAssert claim.assurance.kernelChecking == true
    let legacy = legacyProjection(claim)
    doAssert legacy["status"].getStr() == "certGreen"
    doAssert projectionInvariant(claim, "SPV1") == true

  # --- DISPROVED claim: certRed ---
  block:
    let claim = disprovedClaim()
    doAssert claim.outcome == clDisproved
    let legacy = legacyProjection(claim)
    doAssert legacy["status"].getStr() == "certRed"
    doAssert projectionInvariant(claim, "SPV1") == true

  # --- legacy status is NEVER certGreen unless kernelChecking ---
  block:
    let claim = provedClaim()
    doAssert claim.assurance.kernelChecking == false
    let legacy = legacyProjection(claim)
    doAssert legacy["status"].getStr() != "certGreen"

  # --- tamper-independence: projection never mutates the claim ---
  block:
    let claim1 = provedClaim()
    let _ = legacyProjection(claim1)
    let s = spec(soCanonicalDerived)
    var ctx = ClaimContext(
      subjectId: "foo", sourceIdentity: "h", specification: s,
      semanticProfileId: "SPV1", obligationGenerated: true, supported: true,
      dependenciesSatisfied: true, proofSignal: psUnsat, policyId: "apV1")
    ctx.evidenceBundle.specificationArtifact = s
    ctx.evidenceBundle.facts.solver.solverIdentity = "z3"
    let claim2 = deriveClaim(ctx, apV1)
    doAssert claim1 == claim2

  echo "=== Phase-4a Claim Projection OK ==="

main()