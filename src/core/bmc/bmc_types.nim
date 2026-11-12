import core/trusted/layer_declaration
axiomLayer "domain"
import ../../core/trusted/axiom_pragmas
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## BMC Race Types — type definitions and constructors.
## Split from bmc_race.nim for SRP compliance.

const
  bmcStepBound* = 10
  bmcWallClockTimeoutMs* = 5_000  ## 5-second safety net for BMC exploration
  bmcTimeoutCheckInterval* = 10   ## Check wall-clock every N steps (performance optimization)

type
  InvariantKind* = enum
    invariantMinValue
    invariantMaxValue

  InvariantRule* = object
    kind*: InvariantKind
    minValue*: int
    maxValue*: int

  TransitionOperator* = enum
    transitionSub
    transitionAdd

  TransitionRule* = object
    op*: TransitionOperator
    delta*: int
    invariant*: InvariantRule

  ThreadPc* = enum
    pcInit
    pcRead
    pcWrite
    pcDone

  StepOwner* = enum
    ownerNone
    ownerT1
    ownerT2

  BmcTrace* = object
    pc1*: array[bmcStepBound + 1, ThreadPc]
    pc2*: array[bmcStepBound + 1, ThreadPc]
    x*: array[bmcStepBound + 1, int]
    r1*: array[bmcStepBound + 1, int]
    r2*: array[bmcStepBound + 1, int]
    owner*: array[bmcStepBound, StepOwner]
    steps*: int

  BmcVerdict* = object
    raceDetected*: bool
    raceFinalState*: int
    sequentialResults*: array[2, int]
    sequentialUniqueCount*: int
    bothWritePathExists*: bool
    witness*: BmcTrace
    exploredPaths*: int
    timedOut*: bool               ## True if BMC exploration exceeded wall-clock timeout

  BmcTransition* = object
    preState*: seq[tuple[name: string, sort: string]]
    guard*: string            ## SMT-LIB2 boolean expression
    postState*: seq[tuple[name: string, expr: string]]

## Make Min Value Invariant.
func makeMinValueInvariant*(minValue: int): InvariantRule {.raises: [], axiom: ["(assert (and (and (>= minValue -9223372036854775808) (<= minValue 9223372036854775807))))", "minValue ≥ -9223372036854775808 ∧ minValue ≤ 9223372036854775807"].} =
  InvariantRule(kind: invariantMinValue, minValue: minValue, maxValue: 0)

## Make Max Value Invariant.
func makeMaxValueInvariant*(maxValue: int): InvariantRule {.raises: [], axiom: ["(assert (and (and (>= maxValue -9223372036854775808) (<= maxValue 9223372036854775807))))", "maxValue ≥ -9223372036854775808 ∧ maxValue ≤ 9223372036854775807"].} =
  InvariantRule(kind: invariantMaxValue, minValue: 0, maxValue: maxValue)

## Make Subtract Rule.
func makeSubtractRule*(delta: int): TransitionRule {.raises: [], axiom: ["(assert (and (and (>= delta -9223372036854775808) (<= delta 9223372036854775807))))", "delta ≥ -9223372036854775808 ∧ delta ≤ 9223372036854775807"].} =
  TransitionRule(op: transitionSub, delta: delta, invariant: makeMinValueInvariant(0))

## Make Add Rule.
func makeAddRule*(delta: int): TransitionRule {.raises: [].} =
  TransitionRule(op: transitionAdd, delta: delta, invariant: makeMinValueInvariant(0))

{.pop.}
{.pop.}
