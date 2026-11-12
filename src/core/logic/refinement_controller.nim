import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/math
import std/options

import core/integrity/integrity_refinement_types
import core/logic/refinement_predicate

## Counter Example Severity.
func counterExampleSeverity*(counterExample: CounterExample): float {.inline.} =
  case counterExample.violation
  of violationUnderflow:
    abs(counterExample.stackSize).float
  of violationInvalidPointer:
    (abs(counterExample.indexValue - counterExample.stackSize) + (if counterExample.topValid: 0 else: 1)).float
  of violationBoundExceeded:
    max(0, counterExample.stackSize - 512).float
  of violationNone:
    0.0

## Total Controller Reward.
func totalControllerReward*(stats: array[RefinementOperatorKind, ActionStats]): float {.inline.} =
  for item in stats:
    result += item.totalReward

## Unsat Core Signature.
func unsatCoreSignature*(ids: seq[string]): string {.inline.} =
  var sortedIds = ids
  var i = 0
  while i < sortedIds.len:
    var j = i + 1
    while j < sortedIds.len:
      if sortedIds[i] > sortedIds[j]:
        let tmp = sortedIds[i]
        sortedIds[i] = sortedIds[j]
        sortedIds[j] = tmp
      j += 1
    i += 1
  result = ""
  for id in sortedIds:
    if result.len > 0:
      result.add(",")
    result.add(id)

## Is Stagnating.
func isStagnating*(controller: LoopControllerState): bool {.inline.} =
  if controller.rewardHistoryCount < integrityStagnationWindow:
    return false
  let startIdx = controller.rewardHistoryCount - integrityStagnationWindow
  let oldest = controller.rewardHistory[startIdx]
  let newest = controller.rewardHistory[controller.rewardHistoryCount - 1]
  let rewardDelta = abs(newest - oldest)
  let baseline = max(abs(oldest), 1.0)
  if rewardDelta / baseline < 0.01:
    return true
  let signature = controller.unsatCoreHistory[startIdx]
  if signature.len == 0:
    return false
  var idx = startIdx + 1
  while idx < controller.rewardHistoryCount:
    if controller.unsatCoreHistory[idx] != signature:
      return false
    idx += 1
  true

## Contains Unsat Core Id.
func containsUnsatCoreId*(ids: seq[string]; targetId: string): bool {.inline.} =
  for item in ids:
    if item == targetId:
      return true
  false

## Invariant Relevant To Unsat Core.
func invariantRelevantToUnsatCore*(entry: TrackedInvariant; unsatCore: seq[string]): bool {.inline.} =
  if containsUnsatCoreId(unsatCore, entry.id):
    return true
  if entry.dsl.minSize != low(int) and containsUnsatCoreId(unsatCore, entry.id & ".min_size"):
    return true
  if entry.dsl.requireValidTop and containsUnsatCoreId(unsatCore, entry.id & ".predicate"):
    return true
  if entry.dsl.maxSize != high(int) and containsUnsatCoreId(unsatCore, entry.id & ".max_size"):
    return true
  for predicate in entry.dsl.predicates:
    if containsUnsatCoreId(unsatCore, predicate.id):
      return true
  for implication in entry.dsl.implications:
    if containsUnsatCoreId(unsatCore, implication.id):
      return true
  false

## Round Reward.
func roundReward*(value: float): float {.inline.} =
  round(value * integrityRewardPrecision) / integrityRewardPrecision

## Operator Score.
func operatorScore*(stats: ActionStats): float {.inline.} =
  stats.totalReward * 100.0 + stats.successes.float * 10.0 - stats.failures.float * 5.0 - stats.attempts.float

## Deterministic Percent.
func deterministicPercent*(seed: int; iteration: int; salt: int): int {.inline.} =
  (((seed * 31) + (iteration * 17) + (salt * 13)) mod 100 + 100) mod 100

## Deterministic Choice Index.
func deterministicChoiceIndex*(seed: int; iteration: int; salt: int; candidateCount: int): int {.inline.} =
  if candidateCount <= 1:
    return 0
  (((seed * 7) + (iteration * 11) + (salt * 5)) mod candidateCount + candidateCount) mod candidateCount

## Init Loop Controller State.
func initLoopControllerState*(
  registry: InvariantRegistry;
  fixedSeed: int
): LoopControllerState {.inline.} =
  LoopControllerState(
    registry: registry,
    actionStats: default(array[RefinementOperatorKind, ActionStats]),
    fixedSeed: fixedSeed,
    iteration: 0,
    previousFingerprint: "",
    pendingOperator: none(RefinementOperatorKind),
    pendingSeverity: 0.0,
    rewardHistoryCount: 0,
    rewardHistory: default(array[integrityMaxIterations, float]),
    unsatCoreHistory: default(array[integrityMaxIterations, string]),
    epsilonPercent: integrityOperatorEpsilonPercent
  )

## Make Operator For.
func makeOperatorFor*(
  kind: RefinementOperatorKind;
  counterExample: CounterExample;
  state: LoopControllerState
): RefinementOperator {.inline.} =
  case kind
  of opTightenLower:
    RefinementOperator(
      kind: kind,
      targetTag: invariantStackDiscipline,
      lowerBound: max(0, counterExample.stackSize + 1)
    )
  of opTightenUpper:
    RefinementOperator(
      kind: kind,
      targetTag: invariantBoundedGrowth,
      upperBound:
        if counterExample.fingerprint == state.previousFingerprint:
          512
        else:
          768
    )
  of opAddPredicate:
    RefinementOperator(
      kind: kind,
      targetTag: invariantTopValidity,
      predicate: predicateRule(predicateTopValidity, predicateIsTrue)
    )
  of opAddImplication:
    RefinementOperator(
      kind: kind,
      targetTag: invariantTopValidity,
      implication: topValidityImplicationRule()
    )
  of opAddRelational:
    RefinementOperator(
      kind: kind,
      targetTag: invariantTopValidity,
      predicate: relationalTopValidityPredicateRule().rule
    )

## Select Operator.
func selectOperator*(
  counterExample: CounterExample;
  state: LoopControllerState
): RefinementOperator {.raises: [].} =
  var candidates: seq[RefinementOperatorKind] = @[]
  case counterExample.violation
  of violationUnderflow:
    candidates = @[opTightenLower]
  of violationInvalidPointer:
    if isSpecialBitPattern(counterExample.observedValue):
      candidates = @[opAddRelational, opAddImplication, opAddPredicate]
    else:
      candidates = @[opAddImplication, opAddPredicate]
  of violationBoundExceeded:
    candidates = @[opTightenUpper]
  of violationNone:
    candidates = @[opAddPredicate]
  let roll = deterministicPercent(state.fixedSeed, state.iteration, ord(counterExample.violation))
  let shouldExplore = candidates.len > 1 and roll < state.epsilonPercent
  var selectedKind = candidates[0]
  if shouldExplore:
    selectedKind = candidates[deterministicChoiceIndex(state.fixedSeed, state.iteration, ord(counterExample.violation), candidates.len)]
  else:
    var bestScore = -1.0e18
    for kind in candidates:
      let score = operatorScore(state.actionStats[kind])
      if score > bestScore:
        bestScore = score
        selectedKind = kind
  makeOperatorFor(selectedKind, counterExample, state)

{.pop.}

{.pop.}
