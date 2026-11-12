import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import core/integrity/integrity_refinement_types
import core/logic/refinement_string
import std/options

## Make Stack Discipline Invariant.
func makeStackDisciplineInvariant*(minSize: int = 0): TrackedInvariant {.inline.} =
  TrackedInvariant(
    tag: invariantStackDiscipline,
    id: invariantId(invariantStackDiscipline),
    dsl: InvariantDsl(minSize: minSize, requireValidTop: false, maxSize: high(int), predicates: @[], implications: @[]),
    dependsOn: {invariantBoundedGrowth},
    status: invariantActive,
    priority: 100,
    ttl: 0,
    lastTouchedIteration: 0,
    lastValidatedIteration: 0,
    ownerOperator: opTightenLower,
    stabilityStreak: 0
  )

## Make Top Validity Invariant.
func makeTopValidityInvariant*(requireValidTop: bool = true): TrackedInvariant {.inline.} =
  TrackedInvariant(
    tag: invariantTopValidity,
    id: invariantId(invariantTopValidity),
    dsl: InvariantDsl(minSize: low(int), requireValidTop: requireValidTop, maxSize: high(int), predicates: @[], implications: @[]),
    dependsOn: {invariantStackDiscipline},
    status: invariantActive,
    priority: 100,
    ttl: 0,
    lastTouchedIteration: 0,
    lastValidatedIteration: 0,
    ownerOperator: opAddImplication,
    stabilityStreak: 0
  )

## Make Bounded Growth Invariant.
func makeBoundedGrowthInvariant*(maxSize: int = 512): TrackedInvariant {.inline.} =
  TrackedInvariant(
    tag: invariantBoundedGrowth,
    id: invariantId(invariantBoundedGrowth),
    dsl: InvariantDsl(minSize: low(int), requireValidTop: false, maxSize: maxSize, predicates: @[], implications: @[]),
    dependsOn: {invariantTopValidity},
    status: invariantActive,
    priority: 100,
    ttl: 0,
    lastTouchedIteration: 0,
    lastValidatedIteration: 0,
    ownerOperator: opTightenUpper,
    stabilityStreak: 0
  )

## Relaxed Invariant For.
func relaxedInvariantFor*(tag: InvariantTag): TrackedInvariant {.inline.} =
  case tag
  of invariantStackDiscipline: makeStackDisciplineInvariant(-1)
  of invariantTopValidity: makeTopValidityInvariant(false)
  of invariantBoundedGrowth: makeBoundedGrowthInvariant(1_024)

## Bootstrap Registry.
func bootstrapRegistry*(): InvariantRegistry {.raises: [].} =
  result.count = 3
  result.entries[0] = relaxedInvariantFor(invariantStackDiscipline)
  result.entries[1] = relaxedInvariantFor(invariantTopValidity)
  result.entries[2] = relaxedInvariantFor(invariantBoundedGrowth)

func initInvariantRegistry*(): InvariantRegistry {.inline.} =
  InvariantRegistry()

func initTrackedInvariant*(invariantText: string; iteration: int): TrackedInvariant {.inline.} =
  TrackedInvariant(
    tag: invariantStackDiscipline,
    id: invariantText,
    dsl: InvariantDsl(minSize: 0, requireValidTop: false, maxSize: high(int), predicates: @[], implications: @[]),
    dependsOn: {},
    status: invariantActive,
    priority: 100,
    ttl: 0,
    lastTouchedIteration: iteration,
    lastValidatedIteration: iteration,
    ownerOperator: opTightenLower,
    stabilityStreak: 0
  )

## Find Invariant Index.
func findInvariantIndex*(registry: InvariantRegistry; tag: InvariantTag): int {.inline.} =
  for idx in 0 ..< registry.count:
    if registry.entries[idx].tag == tag and registry.entries[idx].status != invariantEvicted:
      return idx
  -1

## Find Invariant.
func findInvariant*(registry: InvariantRegistry; tag: InvariantTag): Option[TrackedInvariant] {.inline.} =
  let idx = findInvariantIndex(registry, tag)
  if idx < 0: return none(TrackedInvariant)
  some(registry.entries[idx])

## Has Suspicious Invariants.
func hasSuspiciousInvariants*(registry: InvariantRegistry): bool {.inline.} =
  for idx in 0 ..< registry.count:
    if registry.entries[idx].status == invariantSuspicious:
      return true
  false

## Target Tag.
func targetTag*(violation: IntegrityViolationKind): InvariantTag {.inline.} =
  case violation
  of violationUnderflow: invariantStackDiscipline
  of violationInvalidPointer: invariantTopValidity
  of violationBoundExceeded: invariantBoundedGrowth
  of violationNone: invariantStackDiscipline

## Invariant Max Size.
func invariantMaxSize*(registry: InvariantRegistry): int {.inline.} =
  let boundedGrowth = registry.findInvariant(invariantBoundedGrowth)
  if boundedGrowth.isSome():
    return boundedGrowth.get().dsl.maxSize
  high(int)

## Underflow Witness Size.
func underflowWitnessSize*(registry: InvariantRegistry): int {.inline.} =
  let stackInvariant = registry.findInvariant(invariantStackDiscipline)
  if stackInvariant.isSome():
    return min(-1, stackInvariant.get().dsl.minSize - 1)
  -1

## Next Power Of Two.
func nextPowerOfTwo*(value: int): int {.inline.} =
  if value <= 1: return 1
  result = 1
  while result < value:
    result = result shl 1

## Bound Witness Size.
func boundWitnessSize*(registry: InvariantRegistry): int {.inline.} =
  let currentMax = invariantMaxSize(registry)
  if currentMax <= 512: return 512
  nextPowerOfTwo(max(513, currentMax + 1))

{.pop.}

{.pop.}
