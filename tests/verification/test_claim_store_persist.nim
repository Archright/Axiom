# Phase-5a ClaimStore Persistence — round-trip, determinism, tamper-resistance tests.

import std/json
import std/options
import std/strutils
import std/tables
import core/trusted/layer_declaration
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/assurance_profile
import core/trusted/dependency_snapshot
import core/trusted/claim_authority
import core/trusted/claim_store
import core/trusted/claim_store_persist

proc makeSpec(origin: SpecOrigin; corrupt = false): SpecificationArtifact =
  if corrupt:
    SpecificationArtifact(canonicalSpecIR: @[], origin: origin, ruleId: "s", ruleVersion: "v1")
  else:
    SpecificationArtifact(
      canonicalSpecIR: @["(>= result x)"],
      origin: origin, ruleId: "synthesizeContracts", ruleVersion: "v1")

proc makeBundle(spec: SpecificationArtifact; solverIdentity = "z3"; smtHash = "abc123"): EvidenceBundle =
  result.specificationArtifact = spec
  result.facts.solver.solverIdentity = solverIdentity
  result.facts.solver.smtHash = smtHash

proc ctx(subjectId: string; bundle: EvidenceBundle; spec: SpecificationArtifact;
         signal: ClaimSignal; supported = true; depsOk = true; obligation = true): ClaimContext =
  ClaimContext(
    subjectId: subjectId, sourceIdentity: "h", specification: spec,
    semanticProfileId: spec.specIdentity, obligationGenerated: obligation,
    supported: supported, dependenciesSatisfied: depsOk, proofSignal: signal,
    evidenceBundle: bundle, policyId: "policy-001")

proc makeClaim(subjectId: string; outcome: VerificationOutcomeRef;
               spec: SpecificationArtifact; bundle: EvidenceBundle): VerifiedClaim =
  deriveClaim(ctx(subjectId, bundle, spec, psUnsat), apV1)

proc storeWithClaims(): ClaimStore =
  let spec = makeSpec(soCanonicalDerived)
  let bundle = makeBundle(spec)
  let c1 = makeClaim("subject-1", clProved, spec, bundle)
  let c2 = makeClaim("subject-2", clUnknown, spec, bundle)
  result.add(c1)
  result.add(c2)

proc claimsEqual(a, b: VerifiedClaim): bool =
  a.subjectId == b.subjectId and
  a.outcome == b.outcome and
  a.assurance.specificationAuthority == b.assurance.specificationAuthority and
  a.assurance.translationTrust == b.assurance.translationTrust and
  a.assurance.solverEvidence == b.assurance.solverEvidence and
  a.assurance.replayability == b.assurance.replayability and
  a.assurance.kernelChecking == b.assurance.kernelChecking and
  a.specificationId == b.specificationId and
  a.semanticProfileId == b.semanticProfileId and
  a.obligationId == b.obligationId and
  a.evidenceId == b.evidenceId and
  a.dependencySnapshotId == b.dependencySnapshotId and
  a.policyId == b.policyId and
  a.claimId == b.claimId

proc main() =
  # --- round-trip ---
  let original = storeWithClaims()
  let jsonNode = serializeClaims(original)
  let restored = deserializeClaims(jsonNode)
  doAssert restored.claims.len == original.claims.len,
    "Round-trip: store size must match"
  for subjectId, claim in original.claims:
    doAssert restored.claims.hasKey(subjectId),
      "Round-trip: subjectId " & subjectId & " must be preserved"
    doAssert claimsEqual(claim, restored.claims[subjectId]),
      "Round-trip: claim for " & subjectId & " must be identical"

  # --- determinism ---
  let json1 = serializeClaims(original)
  let json2 = serializeClaims(original)
  doAssert $json1 == $json2,
    "Determinism: two serializations of the same store must produce identical JSON"

  # --- tamper-resistance ---
  let jsonStr = $jsonNode
  let tamperedStr = jsonStr.replace("clProved", "clInvalidEvidence")
  let tamperedNode = parseJson(tamperedStr)
  let tamperedResult = deserializeClaims(tamperedNode)
  doAssert tamperedResult.claims.len < original.claims.len,
    "Tamper-resistance: tampered claim must be rejected (claimId integrity mismatch)"

  echo "=== ClaimStore Persistence Tests OK ==="

main()