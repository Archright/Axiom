## integrity_refinement_test.nim
## Unit tests for integrity_refinement_loop core contracts.
##
## Coverage targets:
##   - upsertInvariant: idempotency, overwrite semantics, append, LRU eviction
##   - minimizeRegistryByUnsatCore: empty-set no-op, priority boost/penalty,
##     evicted-entry isolation, stability streak management
##
## Known gap vs. specification: upsertInvariant currently performs LRU eviction
## on capacity overflow instead of returning err(). This is documented as a
## behavioral contract test, not a failure-mode test.

import std/[unittest, strutils]
import core/results
import core/integrity/integrity_refinement_types
import core/integrity/integrity_refinement_loop
import core/api/axiom_api_verify
import core/contracts/universal_pipeline_contract

proc makeTestInvariant(
  tag: InvariantTag;
  id: string;
  priority: int = 100;
  lastTouched: int = 0;
  status: InvariantStatus = invariantActive
): TrackedInvariant =
  TrackedInvariant(
    tag: tag,
    id: id,
    dsl: InvariantDsl(
      minSize: low(int),
      requireValidTop: false,
      maxSize: high(int),
      predicates: @[],
      implications: @[]
    ),
    dependsOn: {},
    status: status,
    priority: priority,
    ttl: 0,
    lastTouchedIteration: lastTouched,
    lastValidatedIteration: 0,
    ownerOperator: opTightenLower,
    stabilityStreak: 0
  )

suite "upsertInvariant contract":
  test "duplicate invariant with identical data is idempotent":
    var reg = bootstrapRegistry()
    let beforeCount = reg.count
    let beforeEntry = reg.entries[0]
    let duplicate = reg.entries[0]
    upsertInvariant(reg, duplicate)
    check reg.count == beforeCount
    check reg.entries[0].id == beforeEntry.id
    check reg.entries[0].priority == beforeEntry.priority
    check reg.entries[0].status == beforeEntry.status

  test "duplicate invariant overwrites when data differs":
    var reg = bootstrapRegistry()
    var modified = reg.entries[0]
    modified.priority = 999
    modified.stabilityStreak = 42
    upsertInvariant(reg, modified)
    check reg.entries[0].priority == 999
    check reg.entries[0].stabilityStreak == 42
    check reg.count == 3

  test "new invariant appended to empty registry":
    var reg = InvariantRegistry(count: 0)
    let newInv = makeTestInvariant(invariantStackDiscipline, "new_inv", priority = 77)
    upsertInvariant(reg, newInv)
    check reg.count == 1
    check reg.entries[0].id == "new_inv"
    check reg.entries[0].priority == 77

  test "LRU eviction when registry at capacity with evicted slots":
    # upsertInvariant uses tag-based dedup for active entries.
    # To reach the LRU path, we need count >= max with the target tag evicted.
    var reg = InvariantRegistry(count: 0)
    # Fill registry with distinct tags cycling through the 3 available tags,
    # marking older entries as evicted to allow tag reuse.
    for i in 0 ..< integrityMaxInvariants:
      let tag = case i mod 3
        of 0: invariantStackDiscipline
        of 1: invariantTopValidity
        else: invariantBoundedGrowth
      var inv = makeTestInvariant(tag, "slot_" & $i, lastTouched = i)
      # Evict all but the last 3 to simulate a full registry with reusable tags
      if i < integrityMaxInvariants - 3:
        inv.status = invariantEvicted
      upsertInvariant(reg, inv)
    check reg.count == integrityMaxInvariants

    # Identify the LRU entry among active entries
    var lruIdx = -1
    for idx in 0 ..< reg.count:
      if reg.entries[idx].status != invariantEvicted:
        if lruIdx < 0 or reg.entries[idx].lastTouchedIteration < reg.entries[lruIdx].lastTouchedIteration:
          lruIdx = idx
    let lruId = reg.entries[lruIdx].id
    let lruTag = reg.entries[lruIdx].tag

    # Insert a new invariant with the same tag as the LRU entry
    var evictor = makeTestInvariant(lruTag, "evictor", lastTouched = 999)
    upsertInvariant(reg, evictor)

    check reg.count == integrityMaxInvariants
    var evictorFound = false
    var lruStillPresent = false
    for idx in 0 ..< reg.count:
      if reg.entries[idx].id == "evictor":
        evictorFound = true
      if reg.entries[idx].id == lruId and reg.entries[idx].status != invariantEvicted:
        lruStillPresent = true
    check evictorFound == true
    check lruStillPresent == false

  test "evicted invariants are ignored during duplicate check":
    var reg = bootstrapRegistry()
    reg.entries[0].status = invariantEvicted
    var replacement = makeTestInvariant(invariantStackDiscipline, "replacement")
    # tag matches evicted entry, but id differs; should append, not overwrite
    upsertInvariant(reg, replacement)
    check reg.count == 4
    check reg.entries[3].id == "replacement"

suite "minimizeRegistryByUnsatCore contract":
  test "empty unsat core is a no-op":
    var reg = bootstrapRegistry()
    let beforeCount = reg.count
    let beforePriorities = [reg.entries[0].priority, reg.entries[1].priority, reg.entries[2].priority]
    let beforeStreaks = [reg.entries[0].stabilityStreak, reg.entries[1].stabilityStreak, reg.entries[2].stabilityStreak]
    let beforeStatuses = [reg.entries[0].status, reg.entries[1].status, reg.entries[2].status]

    minimizeRegistryByUnsatCore(reg, @[])

    check reg.count == beforeCount
    for i in 0 ..< reg.count:
      check reg.entries[i].priority == beforePriorities[i]
      check reg.entries[i].stabilityStreak == beforeStreaks[i]
      check reg.entries[i].status == beforeStatuses[i]

  test "relevant invariant receives priority boost and stability streak increment":
    var reg = bootstrapRegistry()
    reg.entries[0].id = "relevant_inv"
    reg.entries[0].priority = 100
    reg.entries[0].stabilityStreak = 3
    let unsatCore = @["relevant_inv"]

    minimizeRegistryByUnsatCore(reg, unsatCore)

    check reg.entries[0].priority > 100
    check reg.entries[0].stabilityStreak == 4

  test "irrelevant invariant receives priority penalty and stability streak reset":
    var reg = bootstrapRegistry()
    reg.entries[0].id = "relevant_inv"
    reg.entries[1].id = "irrelevant_inv"
    reg.entries[1].priority = 100
    reg.entries[1].stabilityStreak = 5
    let unsatCore = @["relevant_inv"]

    minimizeRegistryByUnsatCore(reg, unsatCore)

    check reg.entries[1].priority < 100
    check reg.entries[1].stabilityStreak == 0

  test "evicted invariants are not modified by minimize":
    var reg = bootstrapRegistry()
    reg.entries[0].status = invariantEvicted
    reg.entries[0].priority = 50
    reg.entries[0].stabilityStreak = 7
    let unsatCore = @["relevant_inv"]  # does not match evicted entry

    minimizeRegistryByUnsatCore(reg, unsatCore)

    check reg.entries[0].priority == 50
    check reg.entries[0].stabilityStreak == 7
    check reg.entries[0].status == invariantEvicted

  test "predicate-level unsat core relevance triggers priority boost":
    var reg = bootstrapRegistry()
    reg.entries[0].id = "pred_inv"
    reg.entries[0].dsl.predicates = @[NamedPredicateRule(id: "pred_01", rule: PredicateRule())]
    reg.entries[0].priority = 100
    let unsatCore = @["pred_01"]  # matches predicate id, not entry id

    minimizeRegistryByUnsatCore(reg, unsatCore)

    check reg.entries[0].priority > 100
    check reg.entries[0].stabilityStreak == 1

  test "implication-level unsat core relevance triggers priority boost":
    var reg = bootstrapRegistry()
    reg.entries[0].id = "impl_inv"
    reg.entries[0].dsl.implications = @[ImplicationRule(id: "impl_01")]
    reg.entries[0].priority = 100
    let unsatCore = @["impl_01"]

    minimizeRegistryByUnsatCore(reg, unsatCore)

    check reg.entries[0].priority > 100
    check reg.entries[0].stabilityStreak == 1

  test "priority caps at 140 for relevant and floors at 1 for irrelevant":
    var reg = bootstrapRegistry()
    reg.entries[0].id = "relevant_cap"
    reg.entries[0].priority = 138
    reg.entries[1].id = "irrelevant_floor"
    reg.entries[1].priority = 2
    let unsatCore = @["relevant_cap"]

    minimizeRegistryByUnsatCore(reg, unsatCore)

    check reg.entries[0].priority == 140  # capped
    check reg.entries[1].priority == 1    # floored (2 - max(1, 2*20/100)=1 -> 1)

suite "Tier 1 string conversion contracts":
  test "loopVerdictString maps all verdicts correctly":
    check loopVerdictString(loopProven) == "proven"
    check loopVerdictString(loopBudgetExceeded) == "budget_exceeded"
    check loopVerdictString(loopIterationLimit) == "iteration_limit"

  test "refinementOperatorKindString maps all operators correctly":
    check refinementOperatorKindString(opTightenLower) == "opTightenLower"
    check refinementOperatorKindString(opTightenUpper) == "opTightenUpper"
    check refinementOperatorKindString(opAddPredicate) == "opAddPredicate"
    check refinementOperatorKindString(opAddImplication) == "opAddImplication"
    check refinementOperatorKindString(opAddRelational) == "opAddRelational"

suite "Tier 1 factory function contracts":
  test "makeStackDisciplineInvariant default fields":
    let inv = makeStackDisciplineInvariant()
    check inv.tag == invariantStackDiscipline
    check inv.dsl.minSize == 0
    check inv.dsl.requireValidTop == false
    check inv.dsl.maxSize == high(int)
    check inv.dependsOn == {invariantBoundedGrowth}
    check inv.status == invariantActive
    check inv.priority == 100
    check inv.ownerOperator == opTightenLower

  test "makeStackDisciplineInvariant custom minSize":
    let inv = makeStackDisciplineInvariant(3)
    check inv.dsl.minSize == 3
    check inv.tag == invariantStackDiscipline

  test "makeTopValidityInvariant default fields":
    let inv = makeTopValidityInvariant()
    check inv.tag == invariantTopValidity
    check inv.dsl.requireValidTop == true
    check inv.dsl.minSize == low(int)
    check inv.dsl.maxSize == high(int)
    check inv.dependsOn == {invariantStackDiscipline}
    check inv.ownerOperator == opAddImplication

  test "makeTopValidityInvariant custom requireValidTop":
    let inv = makeTopValidityInvariant(false)
    check inv.dsl.requireValidTop == false

  test "makeBoundedGrowthInvariant default fields":
    let inv = makeBoundedGrowthInvariant()
    check inv.tag == invariantBoundedGrowth
    check inv.dsl.maxSize == 512
    check inv.dsl.minSize == low(int)
    check inv.dsl.requireValidTop == false
    check inv.dependsOn == {invariantTopValidity}
    check inv.ownerOperator == opTightenUpper

  test "makeBoundedGrowthInvariant custom maxSize":
    let inv = makeBoundedGrowthInvariant(1024)
    check inv.dsl.maxSize == 1024

suite "buildSemanticEqualityPayloadSmt contract":
  test "returns err when enumValues has fewer than 2 elements":
    let payload = SemanticEqualityPayload(
      schemaVersion: SemanticPayloadSchemaVersion("v1"),
      modulePath: SemanticModulePath("src/core/test.nim"),
      functionName: SemanticFunctionName("testFunc"),
      enumTypeName: SemanticEnumTypeName("TestEnum"),
      leftSymbol: SemanticSymbolName("left"),
      rightSymbol: SemanticSymbolName("right"),
      throwsSymbol: SemanticSymbolName("throws"),
      enumValues: @[SemanticEnumLabel("A")],
      proofGoal: semanticGoalEqualValuesDoNotThrow,
      unsatCore: @[]
    )
    let result = buildSemanticEqualityPayloadSmt(payload)
    check result.isErr()

  test "returns valid SMT-LIB2 for equal_values_do_not_throw goal":
    let payload = SemanticEqualityPayload(
      schemaVersion: SemanticPayloadSchemaVersion("v1"),
      modulePath: SemanticModulePath("src/core/test.nim"),
      functionName: SemanticFunctionName("testFunc"),
      enumTypeName: SemanticEnumTypeName("TestEnum"),
      leftSymbol: SemanticSymbolName("left"),
      rightSymbol: SemanticSymbolName("right"),
      throwsSymbol: SemanticSymbolName("throws"),
      enumValues: @[SemanticEnumLabel("A"), SemanticEnumLabel("B")],
      proofGoal: semanticGoalEqualValuesDoNotThrow,
      unsatCore: @[]
    )
    let result = buildSemanticEqualityPayloadSmt(payload)
    check result.isOk()
    let smt = result.get()
    check smt.contains("(set-logic ALL)")
    check smt.contains("(declare-const left TestEnum)")
    check smt.contains("(declare-const right TestEnum)")
    check smt.contains("(declare-const throws Bool)")
    check smt.contains("(assert (= left right))")
    check smt.contains("(assert throws)")
    check smt.contains("(check-sat)")
    check smt.contains("(get-model)")

  test "returns valid SMT-LIB2 for mismatched_values_throw goal":
    let payload = SemanticEqualityPayload(
      schemaVersion: SemanticPayloadSchemaVersion("v1"),
      modulePath: SemanticModulePath("src/core/test.nim"),
      functionName: SemanticFunctionName("testFunc"),
      enumTypeName: SemanticEnumTypeName("TestEnum"),
      leftSymbol: SemanticSymbolName("left"),
      rightSymbol: SemanticSymbolName("right"),
      throwsSymbol: SemanticSymbolName("throws"),
      enumValues: @[SemanticEnumLabel("A"), SemanticEnumLabel("B")],
      proofGoal: semanticGoalMismatchedValuesThrow,
      unsatCore: @[]
    )
    let result = buildSemanticEqualityPayloadSmt(payload)
    check result.isOk()
    let smt = result.get()
    check smt.contains("(assert (not (= left right)))")
    check smt.contains("(assert (not throws))")
