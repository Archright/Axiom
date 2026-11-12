import std/json
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/dependency_snapshot
import core/trusted/claim_authority
import core/trusted/claim_projection
import core/trusted/legacy_cert_classifier

proc makeSpec(origin: SpecOrigin; corrupt = false): SpecificationArtifact =
  if corrupt:
    SpecificationArtifact(canonicalSpecIR: @[], origin: origin, ruleId: "s", ruleVersion: "v1")
  else:
    SpecificationArtifact(
      canonicalSpecIR: @[">= result x"],
      origin: origin, ruleId: "synthesizeContracts", ruleVersion: "v1")

proc makeBundle(spec: SpecificationArtifact; solverIdentity = "z3"; smtHash = "abc123"): EvidenceBundle =
  result.specificationArtifact = spec
  result.facts.solver.solverIdentity = solverIdentity
  result.facts.solver.smtHash = smtHash

proc ctx(bundle: EvidenceBundle; spec: SpecificationArtifact;
         signal: ClaimSignal; supported = true; depsOk = true; obligation = true): ClaimContext =
  ClaimContext(
    subjectId: "foo", sourceIdentity: "h", specification: spec,
    semanticProfileId: spec.specIdentity, obligationGenerated: obligation,
    supported: supported, dependenciesSatisfied: depsOk, proofSignal: signal,
    evidenceBundle: bundle, policyId: "apV1")

proc provedClaim(): VerifiedClaim =
  let s = makeSpec(soCanonicalDerived)
  let b = makeBundle(s)
  let c = ctx(b, s, psUnsat)
  deriveClaim(c, apV1)

proc main() =
  echo "=== Phase-8 Negative Trust Suite ==="

  # Block 1: Projection invariance
  block:
    let claim = provedClaim()
    doAssert claim.outcome == clProved, "claim must be PROVED"
    let legacy = legacyProjection(claim)
    let legacyStatus = legacy.getOrDefault("status").getStr()
    doAssert legacyStatus in @["certZ3Verified", "certGreen"],
      "legacy status must be certZ3Verified or certGreen, got: " & legacyStatus
    let v2 = v2Projection(claim, "SPV1")
    doAssert v2.getOrDefault("outcome").getStr() == "clProved",
      "v2 outcome must be clProved"
    doAssert projectionInvariant(claim, "SPV1") == true,
      "projectionInvariant must hold for PROVED claim"

  # Block 2: Claim independence — certificate tampering cannot affect the claim
  block:
    let s = makeSpec(soCanonicalDerived)
    let b = makeBundle(s)
    let claim1 = deriveClaim(ctx(b, s, psUnsat), apV1)
    doAssert claim1.outcome == clProved
    let legacyJson = legacyProjection(claim1)
    legacyJson["status"] = %"certGreen"
    let claim2 = deriveClaim(ctx(b, s, psUnsat), apV1)
    doAssert claim2.outcome == claim1.outcome,
      "claim outcome must be unchanged after certificate JSON tampering"

  # Block 3: Failure-state separability — none of these may ever be clProved
  block:
    # MINED spec → clNoSpecification
    let minedSpec = makeSpec(soMined)
    let bMined = makeBundle(minedSpec)
    doAssert deriveClaim(ctx(bMined, minedSpec, psUnsat), apV1).outcome == clNoSpecification
    doAssert deriveClaim(ctx(bMined, minedSpec, psUnsat), apV1).outcome != clProved

    # supported=false → clUnsupported
    let bSupported = makeBundle(makeSpec(soCanonicalDerived))
    doAssert deriveClaim(ctx(bSupported, makeSpec(soCanonicalDerived), psUnsat, supported = false), apV1).outcome == clUnsupported
    doAssert deriveClaim(ctx(bSupported, makeSpec(soCanonicalDerived), psUnsat, supported = false), apV1).outcome != clProved

    # psUnknown → clUnknown
    doAssert deriveClaim(ctx(bSupported, makeSpec(soCanonicalDerived), psUnknown), apV1).outcome == clUnknown
    doAssert deriveClaim(ctx(bSupported, makeSpec(soCanonicalDerived), psUnknown), apV1).outcome != clProved

    # depsOk=false → clDependencyBlocked
    doAssert deriveClaim(ctx(bSupported, makeSpec(soCanonicalDerived), psUnsat, depsOk = false), apV1).outcome == clDependencyBlocked
    doAssert deriveClaim(ctx(bSupported, makeSpec(soCanonicalDerived), psUnsat, depsOk = false), apV1).outcome != clProved

    # corrupt spec identity → clInvalidEvidence
    let corruptSpec = makeSpec(soCanonicalDerived, corrupt = true)
    let bCorrupt = makeBundle(corruptSpec)
    doAssert deriveClaim(ctx(bCorrupt, corruptSpec, psUnsat), apV1).outcome == clInvalidEvidence
    doAssert deriveClaim(ctx(bCorrupt, corruptSpec, psUnsat), apV1).outcome != clProved

  # Block 4: Legacy classification — schemaVersion "1" / no claimId → certNotCurrent
  block:
    let certV1 = parseJson("""{"schemaVersion":"1","status":"certZ3Verified"}""")
    doAssert classifyLegacyCert(certV1) == true, "schemaVersion 1 must be legacy"
    doAssert demoteStatus(certV1) == "certNotCurrent", "legacy cert must be demoted to certNotCurrent"

    let certNoClaimId = parseJson("""{"schemaVersion":"2","status":"certZ3Verified","specificationId":"spec-xyz"}""")
    doAssert classifyLegacyCert(certNoClaimId) == true, "missing claimId must be legacy"
    doAssert demoteStatus(certNoClaimId) == "certNotCurrent", "legacy cert must be demoted to certNotCurrent"

  echo "=== Phase-8 Negative Trust Suite OK ==="

main()