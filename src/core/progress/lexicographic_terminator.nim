## Lexicographic Progress Metric — formal termination guarantee for iterative refinement loops.
##
## Models the pipeline loop state as M = ⟨U, F⟩ where:
##   U = unverified items count (strictly decreases on progress)
##   F = refinement fuel (monotonically decreasing, resets on U decrease)
##
## Well-founded ordering: ⟨U', F'⟩ ≺ ⟨U, F⟩ iff U' < U ∨ (U' = U ∧ F' < F)
## Termination: ℕ × ℕ is well-ordered under lexicographic ordering.
##
## Fixed-point detection: HashSet[stateHash] catches cycles in finite state space.
## Inspired by Z3 Spacer's model_node lexicographic ordering (level<, depth<, id).

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/sets
import std/hashes

type
  LexVerdict* = enum
    lvContinue       ## No change — continue iteration
    lvProgressReset  ## U decreased — reset F to initial value
    lvFuelBurned     ## U unchanged — F decremented
    lvFixedPoint     ## Hash seen before → pipeline state cycle detected
    lvFuelExhausted  ## F = 0 → deterministic escalation required

  LexProgressMetric* = object
    unverifiedCount: int    ## U — unverified items remaining
    refinementFuel: int     ## F — logical steps before stagnation
    initialFuel: int        ## F₀ — reset target when U decreases
    stateHashHistory: HashSet[uint64]  ## Fixed-point detection

## @axiom-vacuity-exempt: infrastructure — pipeline orchestration, no SMT obligation
func initLexMetric*(initialUnverified: int, initialFuel: int): LexProgressMetric =
  ## Initialize the metric with the starting unverified count and fuel budget.
  LexProgressMetric(
    unverifiedCount: initialUnverified,
    refinementFuel: initialFuel,
    initialFuel: initialFuel,
    stateHashHistory: initHashSet[uint64]()
  )

## @axiom-vacuity-exempt: pure-metric — progress tracking, no SMT verification obligation
func evaluate*(m: var LexProgressMetric; newUnverified: int; stateHash: uint64): LexVerdict =
  ## Evaluate lexicographic progress metric for one iteration.
  ##
  ## Priority order:
  ##   1. Progress (U decreased) — always wins, resets fuel
  ##   2. Fixed-point (same hash seen before) — stagnation cycle
  ##   3. Fuel exhaustion (F = 0) — deterministic escalation
  ##   4. Fuel burn (U unchanged, F > 0) — continue with less fuel

  # 1. Progress: U decreased — highest priority
  if newUnverified < m.unverifiedCount:
    m.unverifiedCount = newUnverified
    m.refinementFuel = m.initialFuel
    m.stateHashHistory.incl(stateHash)
    return lvProgressReset

  # 2. Stagnation: U unchanged — check for cycle or fuel
  if stateHash in m.stateHashHistory:
    return lvFixedPoint
  m.stateHashHistory.incl(stateHash)

  # 3. Fuel check
  if m.refinementFuel <= 0:
    return lvFuelExhausted

  # 4. Burn one fuel unit
  dec m.refinementFuel
  return lvFuelBurned

func computeStateHash*(nodeReportCount: int; refactorTaskCount: int;
                       verifiedCount: int;
                       sourceFingerprints: openArray[string];
                       evidenceHash: uint64 = 0): uint64 =
  ## Compute a deterministic hash of the pipeline state snapshot.
  ## Used for fixed-point detection in the lexicographic metric.
  var h: Hash = 0
  h = h !& nodeReportCount
  h = h !& refactorTaskCount
  h = h !& verifiedCount
  for fp in sourceFingerprints:
    h = h !& hash(fp)
  h = h !& hash(evidenceHash)  # evidence data volatility
  result = uint64(h)

func formatMetric*(m: LexProgressMetric): string =
  ## Debug-friendly string representation of the metric state.
  "LexM<U=" & $m.unverifiedCount & ", F=" & $m.refinementFuel &
    "/" & $m.initialFuel & ", seen=" & $m.stateHashHistory.len & ">"

{.pop.}
