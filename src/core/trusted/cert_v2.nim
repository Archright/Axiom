import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}
import std/json
import core/crypto/hash_kernel
import core/trusted/specification_artifact
import core/trusted/assurance_profile
import core/trusted/claim_authority

## Phase-4 — CertificateV2 = a PROJECTION of a VerifiedClaim.
##
## A certificate is persist(claim). The writer NEVER decides the outcome (it is
## copied from the Claim); the only inputs are identity + optional evidence that
## the AssuranceProfile allows (smtHash / proofArtifactDigest are optional).

type
  CertificateV2* = object
    subjectId*: string
    outcome*: VerificationOutcomeRef     ## derived from Claim only — non-writable
    assurance*: AssuranceProfile
    specificationId*: SpecID
    semanticProfileId*: string
    obligationId*: string
    evidenceId*: string
    dependencySnapshotId*: string
    policyId*: string
    smtHash*: string              ## optional (assurance-driven, NOT mandatory)
    proofArtifactDigest*: string  ## optional (assurance-driven, NOT mandatory)
    schemaVersion*: string        ## "2"
    identityDigest*: string       ## anti-stale: H(specId|semanticProfileId|policyId)

func persist*(claim: VerifiedClaim; semanticProfileId: string): CertificateV2 {.raises: [].} =
  ## PROJECT the Claim into a certificate. outcome is copied (never chosen here).
  result.schemaVersion = "2"
  result.subjectId = claim.subjectId
  result.outcome = claim.outcome
  result.assurance = claim.assurance
  result.specificationId = claim.specificationId
  result.semanticProfileId = semanticProfileId
  result.obligationId = claim.obligationId
  result.evidenceId = claim.evidenceId
  result.dependencySnapshotId = claim.dependencySnapshotId
  result.policyId = claim.policyId
  # content-addressed anti-stale identity: any spec/profile/policy change -> new digest
  result.identityDigest = sha256Hex(
    claim.specificationId & "|" & semanticProfileId & "|" & claim.policyId)

func serialize*(c: CertificateV2): JsonNode {.raises: [].} =
  ## CertificateV2 -> JSON (schemaVersion=2). NOTE: outcomme is a stored projection,
  ## but the WRITER path must never accept a cert whose outcome disagrees with
  ## persist(claim). This serializer is a pure projection of the strongly-typed object.
  %*{
    "schemaVersion": c.schemaVersion,
    "subjectId": c.subjectId,
    "outcome": $c.outcome,
    "specificationId": c.specificationId,
    "semanticProfileId": c.semanticProfileId,
    "obligationId": c.obligationId,
    "evidenceId": c.evidenceId,
    "dependencySnapshotId": c.dependencySnapshotId,
    "policyId": c.policyId,
    "smtHash": c.smtHash,
    "proofArtifactDigest": c.proofArtifactDigest,
    "identityDigest": c.identityDigest,
    "assurance": %*{
      "specificationAuthority": c.assurance.specificationAuthority,
      "translationTrust": c.assurance.translationTrust,
      "solverEvidence": c.assurance.solverEvidence,
      "replayability": c.assurance.replayability,
      "kernelChecking": c.assurance.kernelChecking
    }
  }

{.pop.}
