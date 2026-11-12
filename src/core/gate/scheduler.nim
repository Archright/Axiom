import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Task Duration Tracker & Priority Queue (Wave 12)
##
## Records per-node Leanstral synthesis durations and schedules
## nodes by priority: complexity × staleness. Fast nodes processed first;
## slow nodes deferred to async queue to preserve pipeline liveness.

import std/tables
import std/times
import ../../core/trusted/axiom_pragmas

type
  TaskDuration* = object
    nodeId*: string
    durationMs*: int
    recordedAt*: Time

  SchedulerState* = object
    durations*: TableRef[string, seq[TaskDuration]]  ## nodeId → history
    slowThresholdMs*: int  ## nodes slower than this go to async queue

  ## axiom-smt: (assert (and (and (>= slowThresholdMs -9223372036854775808) (<= slowThresholdMs 9223372036854775807)) (>= result 0)))
  ## axiom-lean: slowThresholdMs ≥ -9223372036854775808 ∧ slowThresholdMs ≤ 9223372036854775807 ∧ (result ≥ 0)
func initScheduler*(slowThresholdMs: int = 30_000): SchedulerState {.axiomTryImpl.} =
  result = SchedulerState(
    durations: newTable[string, seq[TaskDuration]](),
    slowThresholdMs: slowThresholdMs
  )

func recordDuration*(s: var SchedulerState; nodeId: string; durationMs: int) {.raises: [], axiom: ["(assert (and (and (>= s_slowThresholdMs -9223372036854775808) (<= s_slowThresholdMs 9223372036854775807)) (>= (str.len nodeId) 0) (and (>= durationMs -9223372036854775808) (<= durationMs 9223372036854775807))))", "s_slowThresholdMs ≥ -9223372036854775808 ∧ s_slowThresholdMs ≤ 9223372036854775807 ∧ nodeId.length ≥ 0 ∧ durationMs ≥ -9223372036854775808 ∧ durationMs ≤ 9223372036854775807"].} =
  s.durations.mgetOrPut(nodeId, @[]).add(TaskDuration(
    nodeId: nodeId,
    durationMs: durationMs,
    recordedAt: getTime()
  ))

func avgDuration*(s: SchedulerState; nodeId: string): int {.raises: [], axiom: ["(assert (and (and (>= s_slowThresholdMs -9223372036854775808) (<= s_slowThresholdMs 9223372036854775807)) (>= (str.len nodeId) 0) (= (str.len history) 0) (= result (div total (str.len history))) (>= history 0) (>= result 0)))", "s_slowThresholdMs ≥ -9223372036854775808 ∧ s_slowThresholdMs ≤ 9223372036854775807 ∧ nodeId.length ≥ 0 ∧ history.length = 0 ∧ result = total div history.length ∧ (history ≥ 0) ∧ (result ≥ 0)"].} =
  let history = s.durations.getOrDefault(nodeId, @[])
  if history.len == 0:
    return s.slowThresholdMs
  var total = 0
  for d in history:
    total += d.durationMs
  result = total div history.len

  ## axiom-smt: (assert (and (and (>= s_slowThresholdMs -9223372036854775808) (<= s_slowThresholdMs 9223372036854775807)) (>= (str.len nodeId) 0)))
  ## axiom-lean: s_slowThresholdMs ≥ -9223372036854775808 ∧ s_slowThresholdMs ≤ 9223372036854775807 ∧ nodeId.length ≥ 0
func isSlow*(s: SchedulerState; nodeId: string): bool {.axiomTryImpl.} =
  s.avgDuration(nodeId) >= s.slowThresholdMs

  ## axiom-smt: (assert (and (>= (str.len nodeId) 0) (or (= isComplex true) (= isComplex false)) (or (= isStale true) (= isStale false)) (and (>= avgDurationMs -9223372036854775808) (<= avgDurationMs 9223372036854775807)) isStale isComplex (= result score) (>= result 0) (or (= isComplex true) (= isComplex false)) (or (= isStale true) (= isStale false))))
  ## axiom-lean: nodeId.length ≥ 0 ∧ isComplex = true ∨ isComplex = false ∧ isStale = true ∨ isStale = false ∧ avgDurationMs ≥ -9223372036854775808 ∧ avgDurationMs ≤ 9223372036854775807 ∧ isStale ∧ isComplex ∧ result = score ∧ (result ≥ 0) ∧ isComplex = true ∨ isComplex = false ∧ isStale = true ∨ isStale = false
func computePriority*(nodeId: string; isComplex, isStale: bool; avgDurationMs: int): int {.axiomTryImpl.} =
  ## Higher priority = lower number (sorted ascending).
  ## Stale > Complex > fast > slow.
  var score = 0
  if isStale: score -= 1000
  if isComplex: score -= 500
  score += avgDurationMs div 1000  # add seconds
  result = score

{.pop.}
