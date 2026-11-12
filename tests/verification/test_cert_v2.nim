# Phase-4: CertificateV2 = projection(persist(claim)); outcome copied, not writable;
# schemaVersion=2; identityDigest content-addressed (anti-stale).

import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/claim_authority
import core/trusted/cert_v2

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

proc main() =
  echo "=== Phase-4 CertV2 ==="
  let claim = provedClaim()
  doAssert claim.outcome == clProved
  let cert = persist(claim, "SPV1")
  doAssert cert.schemaVersion == "2"
  doAssert cert.outcome == claim.outcome          # projection: copied, not re-chosen
  doAssert cert.identityDigest.len > 0
  let cert2 = persist(claim, "SPV2")
  doAssert cert2.identityDigest != cert.identityDigest   # anti-stale on profile change
  echo "=== Phase-4 CertV2 OK ==="
