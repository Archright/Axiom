## Integration tests for Tactic Backtrack Engine.
##
## Tests: TacticSnapshot, GoalDelta, GlobalReset, SnapshotStore.
##
## AGENTS.md §0.7: Business-Only Test Scope — no unit tests for trivial behaviors.

import std/[unittest, json, os, options, tables, times]
import verification/tactic_backtrack
import core/logic/lean_diagnostic

suite "GoalDelta computation":
  test "resolved goals detected":
    let before = @["⊢ A", "⊢ B", "⊢ C"]
    let after = @["⊢ B", "⊢ C"]
    let delta = computeGoalDelta(before, after)
    check delta.resolvedGoals.len == 1
    check "⊢ A" in delta.resolvedGoals
    check delta.unchangedGoals.len == 2

  test "new goals detected":
    let before = @["⊢ A"]
    let after = @["⊢ A", "⊢ D"]
    let delta = computeGoalDelta(before, after)
    check delta.newGoals.len == 1
    check "⊢ D" in delta.newGoals

  test "empty before produces all new":
    let before: seq[string] = @[]
    let after = @["⊢ X", "⊢ Y"]
    let delta = computeGoalDelta(before, after)
    check delta.newGoals.len == 2
    check delta.resolvedGoals.len == 0

  test "identical goals produce no delta":
    let goals = @["⊢ A", "⊢ B"]
    let delta = computeGoalDelta(goals, goals)
    check delta.resolvedGoals.len == 0
    check delta.newGoals.len == 0
    check delta.unchangedGoals.len == 2

  test "progressive tactic resolves more than creates":
    let delta = GoalDelta(resolvedGoals: @["A", "B"], newGoals: @["C"])
    check isProgressive(delta) == true
    check isDestructive(delta) == false

  test "destructive tactic creates many new goals":
    let delta = GoalDelta(resolvedGoals: @["A"], newGoals: @["B", "C", "D"])
    check isProgressive(delta) == false
    check isDestructive(delta) == true

suite "Global Reset detection":
  test "no reset on empty snapshots":
    let (trigger, idx) = shouldReset(@[], 1, 5, 8)
    check trigger == grtNone

  test "goal explosion detected":
    var snapshots: seq[TacticSnapshot] = @[]
    for i in 0 .. 3:
      snapshots.add TacticSnapshot(
        index: i,
        goalDelta: GoalDelta(newGoals: @["a", "b", "c", "d", "e", "f", "g", "h", "i"])
      )
    let (trigger, idx) = shouldReset(snapshots, 4, 4, 8)
    check trigger == grtGoalExplosion
    check idx >= 0

  test "stagnation loop detected":
    var snapshots: seq[TacticSnapshot] = @[]
    for i in 0 .. 3:
      snapshots.add TacticSnapshot(
        index: i,
        goalBefore: @["⊢ same"],
        goalDelta: GoalDelta()
      )
    let (trigger, idx) = shouldReset(snapshots, 4, 4, 8)
    check trigger == grtStagnationLoop

  test "budget critical detected":
    let snapshots = @[TacticSnapshot(index: 0, goalDelta: GoalDelta())]
    # gasRemaining=1, gasTotal=10 → 1 < 10*20/100 = 2 → critical
    let (trigger, _) = shouldReset(snapshots, 1, 1, 10)
    check trigger == grtBudgetCritical

  test "depth exceeded detected":
    let snapshots = @[TacticSnapshot(index: 0, goalDelta: GoalDelta())]
    let (trigger, _) = shouldReset(snapshots, 65, 5, 8)
    check trigger == grtDepthExceeded

suite "SnapshotStore disk-backed operations":
  let testDir = "/tmp/test_snapshots_" & $epochTime().int

  test "store and retrieve":
    var store = initSnapshotStore(testDir, maxHot = 4)
    let snap = TacticSnapshot(
      index: 0,
      goalBefore: @["⊢ A"],
      tacticApplied: "simp",
      goalAfter: @[],
      succeeded: true,
      goalDelta: GoalDelta(resolvedGoals: @["⊢ A"])
    )
    store.store(snap)
    let retrieved = store.retrieve(0)
    check retrieved.isSome
    check retrieved.get().tacticApplied == "simp"
    check retrieved.get().goalDelta.resolvedGoals == @["⊢ A"]

  test "eviction to disk when hot cache full":
    var store = initSnapshotStore(testDir, maxHot = 2)
    for i in 0 .. 3:
      store.store(TacticSnapshot(index: i, tacticApplied: "t" & $i))
    # Hot cache should have at most 2 entries
    check store.hot.len <= 2
    # But all should be retrievable (some from disk)
    for i in 0 .. 3:
      let r = store.retrieve(i)
      check r.isSome

  test "serialization roundtrip":
    let snap = TacticSnapshot(
      index: 5,
      goalBefore: @["⊢ X ≥ 0"],
      hypothesesBefore: @["h : X > 0"],
      tacticApplied: "omega",
      goalAfter: @[],
      diagnostic: LeanDiagnostic(kind: "tactic_failed", message: "omega failed"),
      sourceHash: "abc123",
      succeeded: false,
      goalDelta: GoalDelta(
        unchangedGoals: @["⊢ X ≥ 0"],
        newGoals: @["⊢ X ≤ 100"]
      )
    )
    let json = serializeSnapshot(snap)
    let restored = deserializeSnapshot(json)
    check restored.index == 5
    check restored.tacticApplied == "omega"
    check restored.diagnostic.kind == "tactic_failed"
    check restored.goalDelta.newGoals == @["⊢ X ≤ 100"]

  # Cleanup
  removeDir(testDir)
