import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import core/axiom_pragmas

import std/json
import std/options
import std/strutils
import std/tables
import core/crypto/hash_kernel
import core/trusted/assurance_profile
import core/trusted/claim_store
import core/trusted/claim_authority

const ClaimsDirName* = "claims"

func claimsSidecarPath*(baseDir: string): string =
  baseDir & "/" & ClaimsDirName & "/claims.json"

func serializeClaims*(store: ClaimStore): JsonNode =
  result = newJObject()
  for subjectId, claim in pairs(store.claims):
    let claimObj = newJObject()
    claimObj.add("claimId", %claim.claimId)
    claimObj.add("dependencySnapshotId", %claim.dependencySnapshotId)
    claimObj.add("evidenceId", %claim.evidenceId)
    claimObj.add("obligationId", %claim.obligationId)
    claimObj.add("outcome", %($claim.outcome))
    claimObj.add("policyId", %claim.policyId)
    claimObj.add("semanticProfileId", %claim.semanticProfileId)
    claimObj.add("specificationId", %claim.specificationId)
    claimObj.add("subjectId", %claim.subjectId)
    let assuranceObj = newJObject()
    assuranceObj.add("kernelChecking", %claim.assurance.kernelChecking)
    assuranceObj.add("replayability", %claim.assurance.replayability)
    assuranceObj.add("solverEvidence", %claim.assurance.solverEvidence)
    assuranceObj.add("specificationAuthority", %claim.assurance.specificationAuthority)
    assuranceObj.add("translationTrust", %claim.assurance.translationTrust)
    claimObj.add("assurance", assuranceObj)
    result.add(subjectId, claimObj)

func parseClaim*(node: JsonNode): Option[VerifiedClaim] {.axiomDecision(id = "DECISION-0634", reason = "Parse VerifiedClaim from JSON node with Option return type", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  if node.kind != JObject:
    return none(VerifiedClaim)
  if not node.hasKey("subjectId") or not node.hasKey("outcome") or
      not node.hasKey("assurance") or not node.hasKey("specificationId") or
      not node.hasKey("semanticProfileId") or not node.hasKey("obligationId") or
      not node.hasKey("evidenceId") or not node.hasKey("dependencySnapshotId") or
      not node.hasKey("policyId") or not node.hasKey("claimId"):
    return none(VerifiedClaim)
  let subjectId = node.getOrDefault("subjectId").getStr()
  let outcomeStr = node.getOrDefault("outcome").getStr()
  let outcome = case outcomeStr
    of "clProved": clProved
    of "clDisproved": clDisproved
    of "clUnknown": clUnknown
    of "clUnsupported": clUnsupported
    of "clNoSpecification": clNoSpecification
    of "clDependencyBlocked": clDependencyBlocked
    of "clInvalidEvidence": clInvalidEvidence
    else: return none(VerifiedClaim)
  let assuranceNode = node.getOrDefault("assurance")
  let assurance = AssuranceProfile(
    specificationAuthority: assuranceNode.getOrDefault("specificationAuthority").getBool(),
    translationTrust: assuranceNode.getOrDefault("translationTrust").getBool(),
    solverEvidence: assuranceNode.getOrDefault("solverEvidence").getBool(),
    replayability: assuranceNode.getOrDefault("replayability").getBool(),
    kernelChecking: assuranceNode.getOrDefault("kernelChecking").getBool()
  )
  let specificationId = node.getOrDefault("specificationId").getStr()
  let semanticProfileId = node.getOrDefault("semanticProfileId").getStr()
  let obligationId = node.getOrDefault("obligationId").getStr()
  let evidenceId = node.getOrDefault("evidenceId").getStr()
  let dependencySnapshotId = node.getOrDefault("dependencySnapshotId").getStr()
  let policyId = node.getOrDefault("policyId").getStr()
  let storedClaimId = node.getOrDefault("claimId").getStr()
  let claim = VerifiedClaim(
    subjectId: subjectId,
    outcome: outcome,
    assurance: assurance,
    specificationId: specificationId,
    semanticProfileId: semanticProfileId,
    obligationId: obligationId,
    evidenceId: evidenceId,
    dependencySnapshotId: dependencySnapshotId,
    policyId: policyId,
    claimId: storedClaimId
  )
  let recomputedId = sha256Hex(
    claim.subjectId & "|" & $claim.outcome &
    "|" & $claim.assurance.specificationAuthority & $claim.assurance.translationTrust &
        $claim.assurance.solverEvidence & $claim.assurance.replayability & $claim.assurance.kernelChecking &
    "|" & claim.specificationId & "|" & claim.semanticProfileId &
    "|" & claim.obligationId & "|" & claim.evidenceId &
    "|" & claim.dependencySnapshotId & "|" & claim.policyId)
  if recomputedId == storedClaimId:
    some(claim)
  else:
    none(VerifiedClaim)

func deserializeClaims*(node: JsonNode): ClaimStore =
  result = ClaimStore()
  if node.kind != JObject:
    return result
  for subjectId, claimNode in pairs(node.fields):
    let claim = parseClaim(claimNode)
    if claim.isSome():
      result.claims[subjectId] = claim.get()

{.pop.}