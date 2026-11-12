import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/options

import core/solver/types
import core/integrity/integrity_refinement_types
export integrity_refinement_types
import core/logic/refinement_string
export refinement_string
import core/logic/refinement_invariant
export refinement_invariant
import core/logic/refinement_predicate
export refinement_predicate
import core/logic/refinement_query
export refinement_query
import core/logic/refinement_controller
export refinement_controller
import core/profiles/bitcoin_script_profile
import ../../core/trusted/axiom_pragmas

## Upsert Invariant.
func upsertInvariant*(registry: var InvariantRegistry; candidate: TrackedInvariant) {.raises: [], axiom: ["(assert (and (>= depth 0) (>= existing 0) (= lruIdx idx) (>= lruIdx 0)))", "depth >= 0 ∧ existing ≥ 0 ∧ lruIdx = idx ∧ (lruIdx ≥ 0)"].} =
  let existing = findInvariantIndex(registry, candidate.tag)
  if existing >= 0:
    registry.entries[existing] = candidate
    return
  if registry.count < integrityMaxInvariants:
    registry.entries[registry.count] = candidate
    inc registry.count
    return
  var lruIdx = 0
  for idx in 1 ..< registry.count:
    if registry.entries[idx].lastTouchedIteration < registry.entries[lruIdx].lastTouchedIteration:
      lruIdx = idx
  registry.entries[lruIdx] = candidate

func pushDecision(
  loop: var IntegrityLoopResult;
  iteration: int;
  action: ReplayAction;
  status: SolverStatus;
  tag: InvariantTag;
  fingerprint: string;
  queryTag: string;
  operatorKind: RefinementOperatorKind = opTightenLower
) {.inline, axiom: ["(assert (and (and (>= iteration -9223372036854775808) (<= iteration 9223372036854775807)) (>= (str.len fingerprint) 0) (>= (str.len queryTag) 0)))", "iteration ≥ -9223372036854775808 ∧ iteration ≤ 9223372036854775807 ∧ fingerprint.length ≥ 0 ∧ queryTag.length ≥ 0"].} =
  if loop.decisionCount >= integrityMaxDecisionPoints:
    return
  loop.decisions[loop.decisionCount] = DecisionPoint(
    iteration: iteration,
    seed: loop.fixedSeed,
    action: action,
    solverStatus: status,
    tag: tag,
    fingerprint: fingerprint,
    queryTag: queryTag,
    operatorKind: operatorKind
  )
  inc loop.decisionCount

func recordRewardSnapshot(controller: var LoopControllerState; unsatCore: seq[string]) {.raises: [], axiom: ["(assert (and (>= (seq.len unsatCore) 0) (forall ((unsatCoreIdx Int)) (=> (and (>= unsatCoreIdx 0) (< unsatCoreIdx (seq.len unsatCore))) (>= (str.len (seq.nth unsatCore unsatCoreIdx)) 0))) (forall ((unsatCoreIdx Int)) (=> (and (>= unsatCoreIdx 0) (< unsatCoreIdx (seq.len unsatCore))) (>= (str.len (seq.nth unsatCore unsatCoreIdx)) 0)))))", "unsatCore.size ≥ 0 ∧ (∀ (unsatCoreIdx : Fin unsatCore.size), (unsatCore.get unsatCoreIdx).length ≥ 0) ∧ (∀ (unsatCoreIdx : Fin unsatCore.size), (unsatCore.get unsatCoreIdx).length ≥ 0)"].} =
  if controller.rewardHistoryCount >= integrityMaxIterations:
    return
  controller.rewardHistory[controller.rewardHistoryCount] = totalControllerReward(controller.actionStats)
  controller.unsatCoreHistory[controller.rewardHistoryCount] = unsatCoreSignature(unsatCore)
  inc controller.rewardHistoryCount

## Minimize Registry By Unsat Core.
func minimizeRegistryByUnsatCore*(registry: var InvariantRegistry; unsatCore: seq[string]) {.raises: [], axiom: ["(assert (and (= (str.len unsatCore) 0) (>= entry 0) (forall ((unsatCoreIdx Int)) (=> (and (>= unsatCoreIdx 0) (< unsatCoreIdx (seq.len unsatCore))) (>= (str.len (seq.nth unsatCore unsatCoreIdx)) 0)))))", "unsatCore.length = 0 ∧ (entry ≥ 0) ∧ (∀ (unsatCoreIdx : Fin unsatCore.size), (unsatCore.get unsatCoreIdx).length ≥ 0)"].} =
  if unsatCore.len == 0:
    return
  for idx in 0 ..< registry.count:
    var entry = registry.entries[idx]
    if entry.status == invariantEvicted:
      continue
    if invariantRelevantToUnsatCore(entry, unsatCore):
      entry.priority = min(140, max(100, entry.priority + 5))
      inc entry.stabilityStreak
    else:
      let penalty = max(1, (entry.priority * integrityUnsatCorePriorityPenaltyPercent) div 100)
      entry.priority = min(95, max(1, entry.priority - penalty))
      entry.stabilityStreak = 0
    registry.entries[idx] = entry

## Run Deterministic Z3.
func runDeterministicZ3*(registry: InvariantRegistry; fixedSeed: int): SolverObservation {.raises: [], axiom: ["(assert (and (and (>= fixedSeed -9223372036854775808) (<= fixedSeed 9223372036854775807))))", "fixedSeed ≥ -9223372036854775808 ∧ fixedSeed ≤ 9223372036854775807"].} =
  runDeterministicZ3ForTarget(registry, fixedSeed, buildBitcoinScriptTargetProfile("", "script/interpreter.cpp"))

func recordActionStat(
  stats: var array[RefinementOperatorKind, ActionStats];
  kind: RefinementOperatorKind;
  success: bool;
  reward: float
) {.raises: [], axiom: ["(assert (and success (>= snapshot 0) (>= stats 0)))", "success ∧ (snapshot ≥ 0) ∧ (stats ≥ 0)"].} =
  var snapshot = stats[kind]
  inc snapshot.attempts
  if success:
    inc snapshot.successes
    snapshot.lastReward = roundReward(reward)
    snapshot.totalReward = roundReward(snapshot.totalReward + snapshot.lastReward)
  else:
    inc snapshot.failures
    snapshot.lastReward = roundReward(-reward)
    snapshot.totalReward = roundReward(snapshot.totalReward + snapshot.lastReward)
  stats[kind] = snapshot

func addRewardBonus(
  stats: var array[RefinementOperatorKind, ActionStats];
  kind: RefinementOperatorKind;
  bonus: float
) {.raises: [], axiom: ["(assert (and (>= depth 0) (>= snapshot 0) (>= stats 0)))", "depth >= 0 ∧ (snapshot ≥ 0) ∧ (stats ≥ 0)"].} =
  var snapshot = stats[kind]
  snapshot.lastReward = roundReward(snapshot.lastReward + bonus)
  snapshot.totalReward = roundReward(snapshot.totalReward + bonus)
  stats[kind] = snapshot

## Apply Operator.
func applyOperator*(
  registry: var InvariantRegistry;
  operator: RefinementOperator;
  counterExample: CounterExample;
  iteration: int
): bool {.raises: [], axiom: ["(assert (and (and (>= iteration -9223372036854775808) (<= iteration 9223372036854775807)) (< idx 0) opTightenLower opTightenUpper opAddPredicate opAddImplication opAddRelational (= result true) (= exists true) (=> (< idx 0) (= result false)) (>= exists 0) (>= requireValidTop 0) (>= entry 0) (>= result 0) (>= minSize 0) (>= maxSize 0)))", "iteration ≥ -9223372036854775808 ∧ iteration ≤ 9223372036854775807 ∧ idx < 0 ∧ opTightenLower ∧ opTightenUpper ∧ opAddPredicate ∧ opAddImplication ∧ opAddRelational ∧ result = true ∧ exists = true ∧ idx < 0 → result = false ∧ (exists ≥ 0) ∧ (requireValidTop ≥ 0) ∧ (entry ≥ 0) ∧ (result ≥ 0) ∧ (minSize ≥ 0) ∧ (maxSize ≥ 0)"].} =
  let idx = findInvariantIndex(registry, operator.targetTag)
  if idx < 0:
    return false
  var entry = registry.entries[idx]
  case operator.kind
  of opTightenLower:
    if entry.dsl.minSize < operator.lowerBound:
      entry.dsl.minSize = operator.lowerBound
      result = true
  of opTightenUpper:
    if entry.dsl.maxSize > operator.upperBound:
      entry.dsl.maxSize = operator.upperBound
      result = true
  of opAddPredicate:
    if not entry.dsl.requireValidTop:
      entry.dsl.requireValidTop = true
      result = true
  of opAddImplication:
    var exists = false
    for implication in entry.dsl.implications:
      if implication.id == operator.implication.id:
        exists = true
        break
    if not exists:
      entry.dsl.implications.add(operator.implication)
      entry.dsl.requireValidTop = false
      result = true
  of opAddRelational:
    let candidate = relationalTopValidityPredicateRule()
    var exists = false
    for predicate in entry.dsl.predicates:
      if predicate.id == candidate.id:
        exists = true
        break
    if not exists:
      entry.dsl.predicates.add(candidate)
      entry.dsl.requireValidTop = false
      result = true
  if not result:
    return false
  entry.status = invariantActive
  entry.ttl = 0
  entry.priority = min(120, entry.priority + 5)
  entry.lastTouchedIteration = iteration
  entry.lastValidatedIteration = iteration
  entry.ownerOperator = operator.kind
  registry.entries[idx] = entry
  discard counterExample

func markDependentsSuspicious(
  registry: var InvariantRegistry;
  changedTag: InvariantTag;
  iteration: int;
  loop: var IntegrityLoopResult
) {.raises: [], axiom: ["(assert (and (and (>= iteration -9223372036854775808) (<= iteration 9223372036854775807)) (>= entry 0)))", "iteration ≥ -9223372036854775808 ∧ iteration ≤ 9223372036854775807 ∧ (entry ≥ 0)"].} =
  for idx in 0 ..< registry.count:
    var entry = registry.entries[idx]
    if entry.tag == changedTag or entry.status == invariantEvicted:
      continue
    if changedTag in entry.dependsOn:
      entry.status = invariantSuspicious
      entry.ttl = integritySuspiciousTtl
      entry.lastTouchedIteration = iteration
      registry.entries[idx] = entry
      pushDecision(
        loop,
        iteration,
        actionMarkSuspicious,
        solverSat,
        entry.tag,
        "",
        "dependency/" & $ord(changedTag) & "->" & $ord(entry.tag)
      )

func refreshSuspiciousInvariants(
  registry: var InvariantRegistry;
  iteration: int;
  loop: var IntegrityLoopResult
) {.raises: [], axiom: ["(assert (and (and (>= iteration -9223372036854775808) (<= iteration 9223372036854775807)) (>= entry 0)))", "iteration ≥ -9223372036854775808 ∧ iteration ≤ 9223372036854775807 ∧ (entry ≥ 0)"].} =
  for idx in 0 ..< registry.count:
    var entry = registry.entries[idx]
    if entry.status != invariantSuspicious:
      continue
    if entry.ttl > 0:
      entry.ttl = typeof(entry.ttl)(entry.ttl - 1)
    if entry.ttl == 0:
      entry.status = invariantActive
      entry.lastValidatedIteration = iteration
      entry.lastTouchedIteration = iteration
      pushDecision(
        loop,
        iteration,
        actionRevalidate,
        solverUnsat,
        entry.tag,
        "",
        "revalidate/" & $ord(entry.tag)
      )
    registry.entries[idx] = entry

func refineInvariantRegistry(
  registry: var InvariantRegistry;
  counterExample: CounterExample;
  controller: var LoopControllerState;
  iteration: int;
  loop: var IntegrityLoopResult
) {.raises: [], axiom: ["(assert (and (and (>= iteration -9223372036854775808) (<= iteration 9223372036854775807)) applied (>= controller 0)))", "iteration ≥ -9223372036854775808 ∧ iteration ≤ 9223372036854775807 ∧ applied ∧ (controller ≥ 0)"].} =
  let selected = selectOperator(counterExample, controller)
  let applied = applyOperator(registry, selected, counterExample, iteration)
  controller.pendingOperator = some(selected.kind)
  controller.pendingSeverity = counterExampleSeverity(counterExample)
  recordActionStat(
    controller.actionStats,
    selected.kind,
    applied,
    max(1.0, controller.pendingSeverity)
  )
  if not applied:
    controller.pendingOperator = none(RefinementOperatorKind)
    controller.pendingSeverity = 0.0
  controller.registry = registry
  pushDecision(
    loop,
    iteration,
    actionRefine,
    solverSat,
    selected.targetTag,
    counterExample.fingerprint,
    counterExample.queryTag,
    selected.kind
  )
  if applied:
    markDependentsSuspicious(registry, selected.targetTag, iteration, loop)

## Run Integrity Loop.
func runIntegrityLoop*(
  sourceCode: string;
  sourcePath: string;
  targetProfile: TargetProfile;
  budgetMs: int = integrityBudgetMs;
  maxIterations: int = integrityMaxIterations;
  fixedSeed: int = integrityFixedSeed
): IntegrityLoopResult {.raises: [].} =
  result.fixedSeed = fixedSeed
  result.registry = bootstrapRegistry()
  var controller = initLoopControllerState(result.registry, fixedSeed)
  result.verdict = loopIterationLimit
  result.targetProfile = targetProfile
  while result.iterations < maxIterations and result.elapsedMs < budgetMs:
    let nextIteration = result.iterations + 1
    controller.iteration = nextIteration
    refreshSuspiciousInvariants(result.registry, nextIteration, result)
    let observation = runDeterministicZ3ForTarget(result.registry, fixedSeed, result.targetProfile)
    result.lastObservation = observation
    result.elapsedMs += observation.elapsedMs
    pushDecision(
      result,
      nextIteration,
      actionSolve,
      observation.status,
      if observation.counterExample.isSome(): targetTag(observation.counterExample.get().violation) else: invariantStackDiscipline,
      if observation.counterExample.isSome(): observation.counterExample.get().fingerprint else: "",
      observation.config.queryTag
    )
    result.iterations = nextIteration
    if result.elapsedMs > budgetMs:
      result.lastCounterExample = observation.counterExample
      result.verdict = loopBudgetExceeded
      result.actionStats = controller.actionStats
      return
    if observation.status == solverUnsat:
      minimizeRegistryByUnsatCore(result.registry, observation.unsatCore)
      recordRewardSnapshot(controller, observation.unsatCore)
      if controller.pendingOperator.isSome():
        let reward =
          max(1.0, controller.pendingSeverity) +
          observation.unsatCore.len.float +
          integrityStabilityBonus
        addRewardBonus(controller.actionStats, controller.pendingOperator.get(), reward)
        controller.pendingOperator = none(RefinementOperatorKind)
        controller.pendingSeverity = 0.0
      if isStagnating(controller):
        controller.epsilonPercent = min(80, controller.epsilonPercent + 10)
    if observation.status == solverUnsat and not hasSuspiciousInvariants(result.registry):
      result.lastCounterExample = none(CounterExample)
      pushDecision(
        result,
        nextIteration,
        actionProve,
        solverUnsat,
        invariantStackDiscipline,
        "",
        "prove/fixed-point"
      )
      result.actionStats = controller.actionStats
      result.verdict = loopProven
      return
    if observation.counterExample.isSome():
      let counterExample = observation.counterExample.get()
      if counterExample.fingerprint == controller.previousFingerprint:
        inc result.repeatedCounterExampleCount
        controller.epsilonPercent = min(80, controller.epsilonPercent + 5)
      result.lastCounterExample = some(counterExample)
      refineInvariantRegistry(result.registry, counterExample, controller, nextIteration, result)
      controller.previousFingerprint = counterExample.fingerprint
      result.actionStats = controller.actionStats
  if result.elapsedMs >= budgetMs:
    result.verdict = loopBudgetExceeded
  result.actionStats = controller.actionStats

## Run Integrity Loop For Bitcoin Script.
func runIntegrityLoopForBitcoinScript*(
  sourceCode: string;
  sourcePath: string = "script/interpreter.cpp";
  budgetMs: int = integrityBudgetMs;
  maxIterations: int = integrityMaxIterations;
  fixedSeed: int = integrityFixedSeed
): IntegrityLoopResult {.raises: [].} =
  runIntegrityLoop(sourceCode, sourcePath, buildBitcoinScriptTargetProfile(sourceCode, sourcePath), budgetMs, maxIterations, fixedSeed)

## Run Integrity Loop (legacy no-arg entry point).
func runIntegrityLoop*(
  budgetMs: int = integrityBudgetMs;
  maxIterations: int = integrityMaxIterations;
  fixedSeed: int = integrityFixedSeed
): IntegrityLoopResult {.raises: [].} =
  runIntegrityLoop("", "script/interpreter.cpp", buildBitcoinScriptTargetProfile("", "script/interpreter.cpp"), budgetMs, maxIterations, fixedSeed)

{.pop.}

{.pop.}
