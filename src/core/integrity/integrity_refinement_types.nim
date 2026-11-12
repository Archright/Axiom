import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/options

import core/solver/types

const
  integrityBudgetMs* = 3_000
  integrityMaxIterations* = 50
  integrityMaxInvariants* = 20
  integritySuspiciousTtl* = 3
  integrityMaxDecisionPoints* = integrityMaxIterations * 4
  integrityMaxOpcodeBlocks* = 8
  integrityFixedSeed* = 17
  integrityOperatorEpsilonPercent* = 20
  integrityUnsatCorePriorityPenaltyPercent* = 20
  integrityStagnationWindow* = 5
  integrityRewardPrecision* = 10_000.0
  integrityStabilityBonus* = 0.05

type
  InvariantTag* = enum
    invariantStackDiscipline
    invariantTopValidity
    invariantBoundedGrowth

  InvariantStatus* = enum
    invariantActive
    invariantSuspicious
    invariantEvicted

  ReplayAction* = enum
    actionSolve
    actionRefine
    actionMarkSuspicious
    actionRevalidate
    actionProve

  IntegrityViolationKind* = enum
    violationNone
    violationUnderflow
    violationInvalidPointer
    violationBoundExceeded

  LoopVerdict* = enum
    loopProven
    loopBudgetExceeded
    loopIterationLimit

  PredicateSubject* = enum
    predicateStackSize
    predicateTopValidity
    predicateIndex
    predicateObservedValue

  PredicateRelation* = enum
    predicateGreaterThan
    predicateGreaterEqual
    predicateLessThan
    predicateLessEqual
    predicateEqual
    predicateNotEqual
    predicateIsTrue
    predicateIsFalse

  PredicateValueKind* = enum
    predicateConstValue
    predicateSubjectValue

  PredicateRule* = object
    subject*: PredicateSubject
    relation*: PredicateRelation
    intValue*: int
    valueKind*: PredicateValueKind
    otherSubject*: PredicateSubject

  ImplicationRule* = object
    id*: string
    condition*: PredicateRule
    consequence*: PredicateRule

  NamedPredicateRule* = object
    id*: string
    rule*: PredicateRule

  InvariantDsl* = object
    minSize*: int
    requireValidTop*: bool
    maxSize*: int
    predicates*: seq[NamedPredicateRule]
    implications*: seq[ImplicationRule]

  TrackedInvariant* = object
    tag*: InvariantTag
    id*: string
    dsl*: InvariantDsl
    dependsOn*: set[InvariantTag]
    status*: InvariantStatus
    priority*: int
    ttl*: range[0 .. integritySuspiciousTtl]
    lastTouchedIteration*: int
    lastValidatedIteration*: int
    ownerOperator*: RefinementOperatorKind
    stabilityStreak*: int

  InvariantRegistry* = object
    count*: int
    entries*: array[integrityMaxInvariants, TrackedInvariant]

  InvariantAssertion* = object
    id*: string
    expr*: string
    owner*: InvariantTag

  CounterExample* = object
    fingerprint*: string
    violation*: IntegrityViolationKind
    stackSize*: int
    topValid*: bool
    indexValue*: int
    observedValue*: int
    severity*: float
    queryTag*: string
    opcodeLabel*: string
    opcodeFingerprint*: string

  Z3WrapperConfig* = object
    fixedSeed*: int
    singleThread*: bool
    queryTag*: string

  SolverObservation* = object
    status*: SolverStatus
    config*: Z3WrapperConfig
    queryText*: string
    modelText*: string
    elapsedMs*: int
    unsatCore*: seq[string]
    counterExample*: Option[CounterExample]

  RefinementOperatorKind* = enum
    opTightenLower
    opTightenUpper
    opAddPredicate
    opAddImplication
    opAddRelational

  RefinementOperator* = object
    kind*: RefinementOperatorKind
    targetTag*: InvariantTag
    lowerBound*: int
    upperBound*: int
    predicate*: PredicateRule
    implication*: ImplicationRule

  ActionStats* = object
    attempts*: int
    successes*: int
    failures*: int
    totalReward*: float
    lastReward*: float

  LoopControllerState* = object
    registry*: InvariantRegistry
    actionStats*: array[RefinementOperatorKind, ActionStats]
    fixedSeed*: int
    iteration*: int
    previousFingerprint*: string
    pendingOperator*: Option[RefinementOperatorKind]
    pendingSeverity*: float
    rewardHistoryCount*: int
    rewardHistory*: array[integrityMaxIterations, float]
    unsatCoreHistory*: array[integrityMaxIterations, string]
    epsilonPercent*: int

  DecisionPoint* = object
    iteration*: int
    seed*: int
    action*: ReplayAction
    solverStatus*: SolverStatus
    tag*: InvariantTag
    fingerprint*: string
    queryTag*: string
    operatorKind*: RefinementOperatorKind

  OpcodeBlockProfile* = object
    label*: string
    fingerprint*: string
    startLine*: int
    endLine*: int
    stackReads*: int
    stackPushes*: int
    stackPops*: int
    stackWrites*: int
    minRequiredDepth*: int
    netStackDelta*: int
    branchCount*: int
    hasNegativeTop*: bool
    hasBoundGuard*: bool

  TargetProfile* {.acyclic.} = ref object of RootObj
    sourcePath*: string
    sourceFingerprint*: string
    sourceLength*: int

  BitcoinScriptTargetProfile* {.acyclic.} = ref object of TargetProfile
    stackSignalCount*: int
    topSignalCount*: int
    boundSignalCount*: int
    opcodeSignalCount*: int
    branchSignalCount*: int
    stackMutationSignalCount*: int
    hasStackLimitGuard*: bool
    hasStackTopNegativeIndex*: bool
    opcodeBlockCount*: int
    opcodeBlocks*: array[integrityMaxOpcodeBlocks, OpcodeBlockProfile]

  IntegrityLoopResult* = object
    verdict*: LoopVerdict
    iterations*: int
    elapsedMs*: int
    fixedSeed*: int
    repeatedCounterExampleCount*: int
    lastCounterExample*: Option[CounterExample]
    targetProfile*: TargetProfile
    lastObservation*: SolverObservation
    registry*: InvariantRegistry
    actionStats*: array[RefinementOperatorKind, ActionStats]
    decisionCount*: int
    decisions*: array[integrityMaxDecisionPoints, DecisionPoint]



{.pop.}

{.pop.}
