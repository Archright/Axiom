## AssuranceProfile — multidimensional assurance VECTOR (Phase-3 contract).
##
## The scalar TIER is a projection over this profile (computed in a later phase);
## deriveClaim NEVER computes a scalar tier or certGreen. Evidence validity is NOT
## part of this vector (it lives on EvidenceFact provenance/validity).

import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

## VerificationOutcomeRef — outcome enum paired with AssuranceProfile.
## This is a CONTRACT; the pipeline wires to it in Phase 3 (Claim Authority).
type
  VerificationOutcomeRef* = enum
    clProved             ## Solver proved the property
    clDisproved          ## Solver disproved the property
    clUnknown            ## Solver returned unknown/inconclusive
    clUnsupported        ## Property is outside the supported subset
    clNoSpecification    ## No authorized specification artifact is present
    clDependencyBlocked  ## A dependency blocks verification
    clInvalidEvidence    ## Evidence is present but invalid/inconsistent

## AssuranceProfile — five independent axes of assurance (no scalar tier).
type
  AssuranceProfile* = object
    specificationAuthority*: bool  ## EXPLICIT/CANONICAL_DERIVED authorized
    translationTrust*: bool        ## IR→SMT within the trusted supported-subset boundary
    solverEvidence*: bool          ## solver produced a definite outcome (PROVED/DISPROVED)
    replayability*: bool           ## T0 deterministic reproduction (Phase 6; false now)
    kernelChecking*: bool          ## kernel/Lean check performed (T2; false now)

func assuranceNoEvidence*(): AssuranceProfile {.inline.} =
  AssuranceProfile()

## assuranceSolverReplayable — canonical example: solver-backed, not kernel-checked.
func assuranceSolverReplayable*(): AssuranceProfile {.inline.} =
  AssuranceProfile(
    specificationAuthority: false,
    translationTrust: true,
    solverEvidence: true,
    replayability: true,
    kernelChecking: false
  )

## proofArtifactRequired — whether a proof object is required (T2/kernel only).
func proofArtifactRequired*(a: AssuranceProfile): bool {.inline.} =
  a.kernelChecking or a.replayability

{.pop.}
