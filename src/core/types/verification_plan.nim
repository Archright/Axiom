import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## VerificationPlan — pure, deterministic plan for verification scope.
##
## Produced by computeVerificationPlan. Contains no execution state,
## no cache reads, no solver calls — it is a pure function of
## (universe, analysis, kernelScope, seedSet, policy).

type
  RequirementDecisionKind* = enum
    rdRequired      ## unit must be verified: scope-eligible, has obligation, policy allows
    rdNotRequired   ## unit is not required: fails one of the Required predicates
    rdUnresolved    ## unit's requirement cannot be determined (fail-closed)

  PlanState* = enum
    psComplete      ## every unit is REQUIRED or NOT_REQUIRED (no UNRESOLVED)
    psUnresolved    ## at least one unit is UNRESOLVED (fail-closed, NOT COMPLETE)
    psFailed        ## fail-closed: a required request cannot be resolved

  RequirementDecision* = object
    unitId*: string
    decision*: RequirementDecisionKind
    reason*: string

  VerificationPlan* = object
    subjectDigest*: string
    semanticPolicyDigest*: string
    universeDigest*: string
    affectedUnitIds*: seq[string]
    requiredUnitIds*: seq[string]
    perUnitRequirement*: seq[RequirementDecision]
    planState*: PlanState
    semanticModelVersion*: string

{.pop.}