import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/json
import std/strutils
import core/trusted/assurance_profile
import core/trusted/claim_authority
import core/trusted/cert_v2

func legacyStatus(outcome: VerificationOutcomeRef; kernelChecking: bool): string {.raises: [].} =
  case outcome
  of clProved:
    if kernelChecking: "certGreen"
    else: "certZ3Verified"
  of clDisproved: "certRed"
  of clNoSpecification: "certNoObligation"
  of clUnsupported, clUnknown, clDependencyBlocked: "certPending"
  of clInvalidEvidence: "certRed"

func legacyProjection*(claim: VerifiedClaim): JsonNode {.raises: [].} =
  let parts = claim.subjectId.split("::")
  let modulePath = if parts.len > 0: parts[0] else: ""
  let functionName = if parts.len > 1: parts[1] else: ""
  let status = legacyStatus(claim.outcome, claim.assurance.kernelChecking)
  %*{
    "modulePath": modulePath,
    "functionName": functionName,
    "status": status,
    "schemaVersion": "1",
    "sourceHash": "",
    "specificationId": claim.specificationId,
    "semanticProfileId": claim.semanticProfileId,
    "policyId": claim.policyId,
    "claimId": claim.claimId
  }

func v2Projection*(claim: VerifiedClaim; semanticProfileId: string): JsonNode {.raises: [].} =
  cert_v2.serialize(cert_v2.persist(claim, semanticProfileId))

func projectionInvariant*(claim: VerifiedClaim; semanticProfileId: string): bool {.raises: [].} =
  let legacy = legacyProjection(claim)
  let v2 = v2Projection(claim, semanticProfileId)
  let expectedStatus = legacyStatus(claim.outcome, claim.assurance.kernelChecking)
  if legacy.getOrDefault("status").getStr() != expectedStatus:
    return false
  if v2.getOrDefault("outcome").getStr() != $claim.outcome:
    return false
  if legacy.getOrDefault("specificationId").getStr() != v2.getOrDefault("specificationId").getStr():
    return false
  if legacy.getOrDefault("policyId").getStr() != v2.getOrDefault("policyId").getStr():
    return false
  if legacy.getOrDefault("claimId").getStr() != claim.claimId:
    return false
  true

{.pop.}