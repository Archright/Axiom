import core/trusted/layer_declaration
axiomLayer "domain"
## Obligation-Driven Strategy Plan (WP4-j C2).
##
## Deterministic execution-strategy selection for refactoring/verification.
## The plan is a PURE function of two separated inputs:
##   (1) IR structural facts (hasLoop, hasRecursion, hasIndex, ...)
##   (2) obligation capability (obligationCount, obligationKinds)
## Retry is plan-index advance — never an attempt/maxAttempts counter.
##
## Locked principles (WP4-j B):
##   1. pattern mismatch = strategy failure ≠ candidate failure
##   2. retry = obligation-aware deterministic selection result
##   3. plan exhaustion = explicit accounting terminal (not silent pass)
##   5. obligation kind ↔ strategy 1:1 mapping is FORBIDDEN

import std/options
import core/trusted/axiom_pragmas_lite
import core/diagnostics/pattern_guard

type
  StrategyStep* = object
    ## One executable strategy in the plan.
    pattern*: PatternKind
    ## Which failure this step is designed to recover from. `paNone`
    ## means it is the primary (obligation-serving) strategy, not a
    ## recovery for a specific structural miss.
    recoveryFor*: FailureKind

  StrategyPlan* = object
    ## Immutable, canonical ordered execution plan.
    steps*: seq[StrategyStep]
    ## Structural facts (deterministic input, do not use as retry escape).
    hasLoop*: bool
    hasRecursion*: bool
    hasIndex*: bool
    hasDivision*: bool
    hasShift*: bool
    ## Obligation capability (deterministic input, not a counter).
    obligationCount*: int
    obligationKinds*: seq[string]

## Canonical ordering (locking WP4-j principle 5):
##   1. obligation-specific   — present only when obligationCount > 0
##   2. structural            — matches the strongest structural feature
##   3. generic               — fallback structural step
##   4. unsupported           — empty plan (seIncomplete / seReject decision upstream)
##
## The plan MUST be deterministic and independent of attempt/maxAttempts.

func computeStrategyPlan*(
    obligationCount: int;
    obligationKinds: seq[string];
    hasLoop: bool;
    hasRecursion: bool;
    hasIndex: bool;
    hasDivision: bool;
    hasShift: bool
): StrategyPlan {.raises: [].} =
  ## Pure deterministic function of the two separated inputs.
  ## Never reads attempt/maxAttempts/timestamps/RNG.
  ## Retry is plan-index advance over plan.steps (WP4-j: retry = plan-index
  ## advance, never an attempt counter — plan exhaustion is an explicit
  ## terminal, not a silent pass).
  ##
  ## hasStructuralObligation (capability query: does the obligation kind
  ## require a specific structural shape?) is inlined here — it is a
  ## private step of the plan computation, NOT a kind→strategy 1:1 mapping.
  func hasStructuralObligation(kinds: seq[string]): bool {.raises: [].} =
    result = false
    for k in kinds:
      if k in ["okSafetyDiv", "okSafetyIndex", "okSafetyShift",
               "okSafetyOverflow", "okSafetyBounds", "okSafetySlice"]:
        return true

  var steps: seq[StrategyStep] = @[]

  # 1. obligation-specific tier (only when real obligations exist)
  if obligationCount > 0 and hasStructuralObligation(obligationKinds):
    # The obligation itself demands safe arithmetic/indexing semantics.
    # We serve it via a pure-function extraction so the body can reach
    # intrinsic obligation → ProofIR → SMT lowering. This is a capability
    # choice, not a 1:1 kind→strategy mapping.
    steps.add(StrategyStep(pattern: pkExtractPureFunction, recoveryFor: paNone))

  # 2. structural tier — match the strongest structural feature
  if hasLoop:
    steps.add(StrategyStep(pattern: pkAddLoopInvariant, recoveryFor: paPreconditionMiss))
  if hasRecursion:
    steps.add(StrategyStep(pattern: pkAddDecreaseMeasure, recoveryFor: paPreconditionMiss))
  if hasShift or hasDivision or hasIndex:
    # arithmetic/index-heavy body benefits from pure-function isolation
    steps.add(StrategyStep(pattern: pkExtractPureFunction, recoveryFor: paPreconditionMiss))
  if hasIndex or hasDivision:
    steps.add(StrategyStep(pattern: pkLinearizeVariables, recoveryFor: paPreconditionMiss))
  # 3. generic fallback — always present so the plan cannot be empty for
  # a structurally representable routine (empty plan ⇒ seIncomplete/seReject,
  # not silent pass).
  steps.add(StrategyStep(pattern: pkInsertCompositionNode, recoveryFor: paPreconditionMiss))
  steps.add(StrategyStep(pattern: pkExtractPureFunction, recoveryFor: paPreconditionMiss))

  StrategyPlan(
    steps: steps,
    hasLoop: hasLoop,
    hasRecursion: hasRecursion,
    hasIndex: hasIndex,
    hasDivision: hasDivision,
    hasShift: hasShift,
    obligationCount: obligationCount,
    obligationKinds: obligationKinds
  )
