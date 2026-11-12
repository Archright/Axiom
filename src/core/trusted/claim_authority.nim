import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/strutils
import std/sequtils
import core/crypto/hash_kernel
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/dependency_snapshot
import core/trusted/assurance_profile

## Phase 3 — Claim Authority.
##
## The single and pure answer to "who decides the verification result":
##
##   EvidenceBundle -> deriveClaim(context, policy) -> VerifiedClaim
##
## Certificate / VerifiedSet / VKD / CI are projections of a Claim and NEVER
## determine one. A certificate status/label is NOT an input to deriveClaim.

type
  EvidenceValidity* = enum
    evValid       ## required artifacts consistent & complete enough to judge
    evIncomplete  ## valid but insufficient info for proof judgment -> UNKNOWN
    evInvalid     ## internal invariant violated / identity-content mismatch -> INVALID_EVIDENCE

  InputClassification* = enum
    icEvidenceInvalid
    icDependencyBlocked
    icUnsupported
    icNoSpecification
    icInconclusive
    icCounterexample
    icProofSuccess

  ClaimSignal* = enum
    psUnsat
    psCounterexample
    psUnknown
    psNotEncodable

  ClaimContext* = object
    subjectId*: string
    sourceIdentity*: string
    specification*: SpecificationArtifact
    semanticProfileId*: string
    obligationGenerated*: bool
    supported*: bool
    dependenciesSatisfied*: bool
    proofSignal*: ClaimSignal
    evidenceBundle*: EvidenceBundle
    policyId*: string

  VerifiedClaim* = object
    subjectId*: string
    outcome*: VerificationOutcomeRef
    assurance*: AssuranceProfile
    specificationId*: SpecID
    semanticProfileId*: string
    obligationId*: string
    evidenceId*: string
    dependencySnapshotId*: string
    policyId*: string
    claimId*: string

func validateEvidence*(bundle: EvidenceBundle): EvidenceValidity {.raises: [].} =
  ## Pure gate BEFORE outcome derivation. NEVER reads a certificate label.
  let spec = bundle.specificationArtifact
  if spec.canonicalSpecIR.len == 0:
    return evInvalid          # corrupt/missing spec identity -> INVALID_EVIDENCE
  if bundle.facts.solver.solverIdentity.len == 0 and bundle.facts.solver.smtHash.len == 0:
    return evIncomplete       # valid but insufficient (no solver identity) -> UNKNOWN
  evValid

func deriveAssurance*(ctx: ClaimContext): AssuranceProfile {.raises: [].} =
  AssuranceProfile(
    specificationAuthority: isAuthorizedForVerification(ctx.specification.origin),
    translationTrust: ctx.supported,
    solverEvidence: ctx.proofSignal in {psUnsat, psCounterexample},
    replayability: false,        # T0/Replay is Phase 6
    kernelChecking: false        # T2/kernel is a later phase
  )

func deriveClaim*(ctx: ClaimContext; policy: AssurancePolicy): VerifiedClaim {.raises: [].} =
  ## The single semantic authority. NEVER reads a certificate label/metric.
  let v = validateEvidence(ctx.evidenceBundle)

  result.subjectId = ctx.subjectId
  result.policyId = ctx.policyId

  # --- outcome (condition-based; mutually exclusive by construction) ---
  if v == evInvalid:
    result.outcome = clInvalidEvidence
  elif not isAuthorizedForVerification(ctx.specification.origin):
    result.outcome = clNoSpecification       # MINED / LLM spec -> NOT PROVED
  elif not ctx.supported:
    result.outcome = clUnsupported
  elif not ctx.dependenciesSatisfied:
    result.outcome = clDependencyBlocked
  elif v == evIncomplete:
    result.outcome = clUnknown               # valid-but-insufficient -> inconclusive
  else:
    case ctx.proofSignal
    of psUnsat:
      result.outcome = clProved
    of psCounterexample:
      result.outcome = clDisproved
    of psUnknown:
      result.outcome = clUnknown
    of psNotEncodable:
      result.outcome = clUnsupported

  # PROVED additionally requires an actual (non-vacuous) obligation.
  if result.outcome == clProved and not ctx.obligationGenerated:
    result.outcome = clUnknown

  result.assurance = deriveAssurance(ctx)
  result.specificationId = ctx.specification.specIdentity
  result.semanticProfileId = ctx.semanticProfileId
  result.obligationId = (if ctx.obligationGenerated: "obl:" & ctx.semanticProfileId else: "none")
  result.dependencySnapshotId = ctx.evidenceBundle.dependencySnapshot.snapshotHash
  result.evidenceId = sha256Hex(
    string(ctx.evidenceBundle.facts.solver.solverIdentity) & "|" &
    ctx.evidenceBundle.facts.solver.smtHash)

  result.claimId = sha256Hex(
    result.subjectId & "|" & $result.outcome &
    "|" & $result.assurance.specificationAuthority & $result.assurance.translationTrust &
        $result.assurance.solverEvidence & $result.assurance.replayability & $result.assurance.kernelChecking &
    "|" & result.specificationId & "|" & result.semanticProfileId &
    "|" & result.obligationId & "|" & result.evidenceId &
    "|" & result.dependencySnapshotId & "|" & result.policyId)

{.pop.}
