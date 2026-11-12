import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import ../../core/trusted/axiom_pragmas
import ../utils/axiom_clock
import core/bmc/bmc_types
## Apply Rule.
func applyRule*(rule: TransitionRule; readVal: int): int {.raises: [].} =
  case rule.op
  of transitionSub:
    if readVal >= rule.delta:
      readVal - rule.delta
    else:
      readVal
  of transitionAdd:
    readVal + rule.delta

## Run Sequential By Rule.
func runSequentialByRule*(initialX: int; firstThread: StepOwner; rule: TransitionRule): int {.raises: [], axiom: ["(assert (and ownerT1 ownerT2 ownerNone))", "ownerT1 ∧ ownerT2 ∧ ownerNone"].} =
  case firstThread
  of ownerT1:
    let r1 = initialX
    let x1 = applyRule(rule, r1)
    let r2 = x1
    applyRule(rule, r2)
  of ownerT2:
    let r2 = initialX
    let x2 = applyRule(rule, r2)
    let r1 = x2
    applyRule(rule, r1)
  of ownerNone:
    initialX

## Run Sequential With Delta.
func runSequentialWithDelta*(initialState: int; firstThread: StepOwner; inputDelta: int): int {.raises: [], axiom: ["(assert (and (and (>= initialState -9223372036854775808) (<= initialState 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807))))", "initialState ≥ -9223372036854775808 ∧ initialState ≤ 9223372036854775807 ∧ inputDelta ≥ -9223372036854775808 ∧ inputDelta ≤ 9223372036854775807"].} =
  runSequentialByRule(initialState, firstThread, makeSubtractRule(inputDelta))

## I Sequential Outcome.
func isSequentialOutcome*(value: int; candidates: array[2, int]; uniqueCount: int): bool {.raises: [], axiom: ["(assert (and (<= uniqueCount 0) false true (=> (<= uniqueCount 0) (= result false))))", "uniqueCount ≤ 0 ∧ false ∧ true ∧ uniqueCount ≤ 0 → result = false"].} =
  if uniqueCount <= 0:
    return false
  if value == candidates[0]:
    return true
  if uniqueCount >= 2 and value == candidates[1]:
    return true
  false
func computeSequentialResults(initialX: int; rule: TransitionRule): tuple[values: array[2, int], uniqueCount: int] {.raises: [], axiom: ["(assert (and (and (>= initialX -9223372036854775808) (<= initialX 9223372036854775807)) (and (>= rule_delta -9223372036854775808) (<= rule_delta 9223372036854775807)) (and (>= rule_invariant_minValue -9223372036854775808) (<= rule_invariant_minValue 9223372036854775807)) (and (>= rule_invariant_maxValue -9223372036854775808) (<= rule_invariant_maxValue 9223372036854775807)) (= s12 s21)))", "initialX ≥ -9223372036854775808 ∧ initialX ≤ 9223372036854775807 ∧ rule_delta ≥ -9223372036854775808 ∧ rule_delta ≤ 9223372036854775807 ∧ rule_invariant_minValue ≥ -9223372036854775808 ∧ rule_invariant_minValue ≤ 9223372036854775807 ∧ rule_invariant_maxValue ≥ -9223372036854775808 ∧ rule_invariant_maxValue ≤ 9223372036854775807 ∧ s12 = s21"].} =
  let s12 = runSequentialByRule(initialX, ownerT1, rule)
  let s21 = runSequentialByRule(initialX, ownerT2, rule)
  if s12 == s21:
    ([s12, s21], 1)
  else:
    ([s12, s21], 2)
func initTrace(initialX: int): BmcTrace {.raises: [], axiom: ["(assert (and (and (>= initialX -9223372036854775808) (<= initialX 9223372036854775807)) (>= result 0)))", "initialX ≥ -9223372036854775808 ∧ initialX ≤ 9223372036854775807 ∧ (result ≥ 0)"].} =
  result.pc1[0] = pcInit
  result.pc2[0] = pcInit
  result.x[0] = initialX
  result.steps = 0
func applyTransition(trace: BmcTrace; step: int; owner: StepOwner; rule: TransitionRule): BmcTrace {.raises: [], axiom: ["(assert (and (and (>= trace_steps -9223372036854775808) (<= trace_steps 9223372036854775807)) (and (>= step -9223372036854775808) (<= step 9223372036854775807)) (and (>= rule_delta -9223372036854775808) (<= rule_delta 9223372036854775807)) (and (>= rule_invariant_minValue -9223372036854775808) (<= rule_invariant_minValue 9223372036854775807)) (and (>= rule_invariant_maxValue -9223372036854775808) (<= rule_invariant_maxValue 9223372036854775807)) ownerT1 pcInit pcRead pcWrite pcDone ownerT2 ownerNone (= result trace) (>= result 0)))", "trace_steps ≥ -9223372036854775808 ∧ trace_steps ≤ 9223372036854775807 ∧ step ≥ -9223372036854775808 ∧ step ≤ 9223372036854775807 ∧ rule_delta ≥ -9223372036854775808 ∧ rule_delta ≤ 9223372036854775807 ∧ rule_invariant_minValue ≥ -9223372036854775808 ∧ rule_invariant_minValue ≤ 9223372036854775807 ∧ rule_invariant_maxValue ≥ -9223372036854775808 ∧ rule_invariant_maxValue ≤ 9223372036854775807 ∧ ownerT1 ∧ pcInit ∧ pcRead ∧ pcWrite ∧ pcDone ∧ ownerT2 ∧ ownerNone ∧ result = trace ∧ (result ≥ 0)"].} =
  result = trace
  result.owner[step] = owner
  result.pc1[step + 1] = trace.pc1[step]
  result.pc2[step + 1] = trace.pc2[step]
  result.x[step + 1] = trace.x[step]
  result.r1[step + 1] = trace.r1[step]
  result.r2[step + 1] = trace.r2[step]

  case owner
  of ownerT1:
    case trace.pc1[step]
    of pcInit:
      result.pc1[step + 1] = pcRead
    of pcRead:
      result.r1[step + 1] = trace.x[step]
      result.pc1[step + 1] = pcWrite
    of pcWrite:
      result.x[step + 1] = applyRule(rule, trace.r1[step])
      result.pc1[step + 1] = pcDone
    of pcDone:
      discard
  of ownerT2:
    case trace.pc2[step]
    of pcInit:
      result.pc2[step + 1] = pcRead
    of pcRead:
      result.r2[step + 1] = trace.x[step]
      result.pc2[step + 1] = pcWrite
    of pcWrite:
      result.x[step + 1] = applyRule(rule, trace.r2[step])
      result.pc2[step + 1] = pcDone
    of pcDone:
      discard
  of ownerNone:
    discard

  result.steps = step + 1
func bothWritesDone(trace: BmcTrace; idx: int): bool {.raises: [], axiom: ["(assert (and (and (>= trace_steps -9223372036854775808) (<= trace_steps 9223372036854775807)) (and (>= idx -9223372036854775808) (<= idx 9223372036854775807))))", "trace_steps ≥ -9223372036854775808 ∧ trace_steps ≤ 9223372036854775807 ∧ idx ≥ -9223372036854775808 ∧ idx ≤ 9223372036854775807"].} =
  trace.pc1[idx] == pcDone and trace.pc2[idx] == pcDone
func explore[C](clk: var C; step: int; trace: BmcTrace; verdict: BmcVerdict; rule: TransitionRule; deadlineNs: int64): BmcVerdict {.raises: [], axiom: ["(assert (and (and (>= step -9223372036854775808) (<= step 9223372036854775807)) (and (>= trace_steps -9223372036854775808) (<= trace_steps 9223372036854775807)) (or (= verdict_raceDetected true) (= verdict_raceDetected false)) (and (>= verdict_raceFinalState -9223372036854775808) (<= verdict_raceFinalState 9223372036854775807)) (and (>= verdict_sequentialUniqueCount -9223372036854775808) (<= verdict_sequentialUniqueCount 9223372036854775807)) (or (= verdict_bothWritePathExists true) (= verdict_bothWritePathExists false)) (and (>= verdict_witness_steps -9223372036854775808) (<= verdict_witness_steps 9223372036854775807)) (and (>= verdict_exploredPaths -9223372036854775808) (<= verdict_exploredPaths 9223372036854775807)) (and (>= rule_delta -9223372036854775808) (<= rule_delta 9223372036854775807)) (and (>= rule_invariant_minValue -9223372036854775808) (<= rule_invariant_minValue 9223372036854775807)) (and (>= rule_invariant_maxValue -9223372036854775808) (<= rule_invariant_maxValue 9223372036854775807)) (= step bmcStepBound) (= result verdict) (>= result 0) (or (= verdict_raceDetected true) (= verdict_raceDetected false)) (or (= verdict_bothWritePathExists true) (= verdict_bothWritePathExists false))))", "step ≥ -9223372036854775808 ∧ step ≤ 9223372036854775807 ∧ trace_steps ≥ -9223372036854775808 ∧ trace_steps ≤ 9223372036854775807 ∧ verdict_raceDetected = true ∨ verdict_raceDetected = false ∧ verdict_raceFinalState ≥ -9223372036854775808 ∧ verdict_raceFinalState ≤ 9223372036854775807 ∧ verdict_sequentialUniqueCount ≥ -9223372036854775808 ∧ verdict_sequentialUniqueCount ≤ 9223372036854775807 ∧ verdict_bothWritePathExists = true ∨ verdict_bothWritePathExists = false ∧ verdict_witness_steps ≥ -9223372036854775808 ∧ verdict_witness_steps ≤ 9223372036854775807 ∧ verdict_exploredPaths ≥ -9223372036854775808 ∧ verdict_exploredPaths ≤ 9223372036854775807 ∧ rule_delta ≥ -9223372036854775808 ∧ rule_delta ≤ 9223372036854775807 ∧ rule_invariant_minValue ≥ -9223372036854775808 ∧ rule_invariant_minValue ≤ 9223372036854775807 ∧ rule_invariant_maxValue ≥ -9223372036854775808 ∧ rule_invariant_maxValue ≤ 9223372036854775807 ∧ step = bmcStepBound ∧ result = verdict ∧ (result ≥ 0) ∧ verdict_raceDetected = true ∨ verdict_raceDetected = false ∧ verdict_bothWritePathExists = true ∨ verdict_bothWritePathExists = false"].} =
  result = verdict
  if step == bmcStepBound:
    inc result.exploredPaths
    let finalX = trace.x[bmcStepBound]
    if bothWritesDone(trace, bmcStepBound):
      if not result.bothWritePathExists:
        result.bothWritePathExists = true
      if not isSequentialOutcome(finalX, result.sequentialResults, result.sequentialUniqueCount):
        if not result.raceDetected:
          result.raceDetected = true
          result.raceFinalState = finalX
          result.witness = trace
    return

  # Wall-clock timeout guard (checked every N steps for performance)
  if step mod bmcTimeoutCheckInterval == 0:
    if clk.monoNs() > deadlineNs:
      result.timedOut = true
      return

  for owner in [ownerT1, ownerT2]:
    let next = applyTransition(trace, step, owner, rule)
    clk.tick()
    result = explore[C](clk, step + 1, next, result, rule, deadlineNs)

## Verify Race Condition.
func verifyRaceCondition*[C](clk: var C; initialValue: int; rule: TransitionRule): BmcVerdict {.raises: [], axiom: ["(assert (and (>= result 0)))", "(result ≥ 0)"].} =
  let seq = computeSequentialResults(initialValue, rule)
  result.sequentialResults = seq.values
  result.sequentialUniqueCount = seq.uniqueCount
  let initial = initTrace(initialValue)
  let deadlineNs = clk.monoNs() + bmcWallClockTimeoutMs * 1_000_000
  result = explore[C](clk, 0, initial, result, rule, deadlineNs)

## Verify Race Condition With Delta.
func verifyRaceConditionWithDelta*[C](clk: var C; stateValue: int; inputDelta: int): BmcVerdict {.raises: [], axiom: ["(assert (and (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807))))", "stateValue ≥ -9223372036854775808 ∧ stateValue ≤ 9223372036854775807 ∧ inputDelta ≥ -9223372036854775808 ∧ inputDelta ≤ 9223372036854775807"].} =
  verifyRaceCondition[C](clk, stateValue, makeSubtractRule(inputDelta))
## Apply Rule.
{.pop.}
