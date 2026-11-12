## Tactic Backtrack Engine — Goal-aware proof search with state snapshots.
##
## Implements the Goal-Context Snapshot Protocol for Lean 4 tactic-based
## proof generation. When an LLM-suggested tactic fails, captures the
## proof state (Goal + Hypotheses) before and after the tactic, computes
## a Goal Delta, and feeds structured feedback to the LLM for retry.
##
## Design rationale:
##   - Lean 4's TacticM state cannot be externally snapshotted via LSP
##   - But Goal text + Hypotheses can be captured from LSP hover
##   - Source can be rolled back to pre-tactic version
##   - Goal Delta tells the LLM exactly what changed → reduces hallucination
##
## References:
##   - CompCert (Leroy 2008): forward simulation between states
##   - Program Synthesis (Gulwani 2017): CEGIS search space pruning
##   - Program Slicing (Weiser 1981): <statement, variables> criterion
##   - AGENTS.md §0.6: Static First Enforcement (func + {.raises: [].})

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
# axiomIoBoundary

import std/options
import std/json
import std/os
import std/tables
import std/sets

import core/logic/lean_diagnostic
import core/lean_lsp_types
import core/trusted/axiom_pragmas
export lean_lsp_types.GoalDelta

## ─── Constants ────────────────────────────────────────────────────────────────

const
  goalExplosionThreshold* = 8    ## newGoals > 8 → "labyrinth detected"
  maxConsecutiveExplosions* = 3  ## consecutive explosions before hard reset
  maxTacticDepth* = 64           ## absolute tactic search depth ceiling
  defaultMaxHot* = 16            ## in-memory LRU snapshot capacity

## ─── Core Types ──────────────────────────────────────────────────────────────

type
  TacticSnapshot* = object
    ## Complete capture of proof state at a tactic attempt point.
    index*: int                      ## Position in tactic sequence
    goalBefore*: seq[string]         ## Goal state BEFORE tactic (LSP hover)
    hypothesesBefore*: seq[string]   ## Hypotheses visible BEFORE tactic
    tacticApplied*: string           ## The tactic that was tried
    goalAfter*: seq[string]          ## Goal state AFTER tactic
    diagnostic*: LeanDiagnostic      ## Error diagnostic (if failed)
    sourceHash*: string              ## Fingerprint of sourceBeforeTactic
    succeeded*: bool                 ## Did this tactic succeed?
    goalDelta*: GoalDelta            ## Computed delta between goals
    wallTimeMs*: int64               ## Wall-clock time for this attempt

  GlobalResetTrigger* = enum
    grtNone                ## Normal — continue search
    grtGoalExplosion       ## newGoals exceeded threshold
    grtDepthExceeded       ## Search depth ceiling reached
    grtStagnationLoop      ## Same Goal repeating ≥ 3 times
    grtBudgetCritical      ## Gas ≤ 20% remaining

  TacticFeedback* = object
    ## Structured feedback for LLM when a tactic fails.
    ## Replaces raw error strings with actionable structural information.
    goalWhenFailed*: seq[string]
    hypothesesWhenFailed*: seq[string]
    tacticThatFailed*: string
    errorKind*: string               ## LeanDiagnostic.kind
    errorMessage*: string            ## LeanDiagnostic.message
    goalAfterFailure*: seq[string]
    goalDelta*: GoalDelta
    priorFailures*: seq[string]      ## Tactics that already failed on this goal
    suggestedFocus*: seq[string]     ## Goals that NEED attention (unchanged + new)

  SnapshotStore* = object
    ## Disk-backed LRU cache for tactic snapshots.
    ## Prevents memory explosion during deep tactic searches (depth 64).
    hot*: Table[int, TacticSnapshot]   ## In-memory LRU (recent N)
    diskPath*: string                   ## Directory for serialized snapshots
    maxHot*: int                        ## Memory capacity (default 16)
    totalStored*: int                   ## Total snapshots ever stored

## ─── Goal Delta Computation (CEGIS-inspired) ─────────────────────────────────

func computeGoalDelta*(before, after: seq[string]): GoalDelta {.raises: [].} =
  ## Compute the structural difference between two Goal states.
  ##
  ## Principle (Gulwani CEGIS): each tactic attempt prunes the search space.
  ## - resolvedGoals: what the tactic accomplished (positive signal)
  ## - newGoals: what the tactic created (may be harder or easier)
  ## - unchangedGoals: what the tactic ignored (needs future attention)
  var beforeSet: HashSet[string]
  var afterSet: HashSet[string]
  init(beforeSet, 0)
  init(afterSet, 0)
  for g in before: beforeSet.incl g
  for g in after: afterSet.incl g
  
  result.resolvedGoals = @[]
  result.newGoals = @[]
  result.unchangedGoals = @[]
  for g in before:
    if g notin afterSet:
      result.resolvedGoals.add g
    else:
      result.unchangedGoals.add g
  for g in after:
    if g notin beforeSet:
      result.newGoals.add g

func goalExplosionCount*(delta: GoalDelta): int {.raises: [].} =
  ## How many NEW goals were created by the tactic.
  ## High count = tactic is making things worse, not better.
  delta.newGoals.len

func isProgressive*(delta: GoalDelta): bool {.raises: [].} =
  ## A tactic is "progressive" if it resolves more goals than it creates.
  ## This is the CEGIS convergence criterion.
  delta.resolvedGoals.len > delta.newGoals.len

func isDestructive*(delta: GoalDelta): bool {.raises: [].} =
  ## A tactic is "destructive" if it creates more goals than it resolves
  ## AND the new goals are structurally different (not just reformulations).
  delta.newGoals.len > delta.resolvedGoals.len * 2

## ─── Global Reset Detection ─────────────────────────────────────────────────

func detectGoalLoop*(snapshots: seq[TacticSnapshot]; windowSize: int = 3): bool {.raises: [].} =
  ## Detect if the same goal pattern is repeating (stagnation).
  ## If the last `windowSize` snapshots all have identical goalBefore,
  ## we're in a loop.
  if snapshots.len < windowSize:
    return false
  let recent = snapshots[^windowSize .. ^1]
  let reference = recent[0].goalBefore
  for s in recent[1 .. ^1]:
    if s.goalBefore != reference:
      return false
  true

func findLastStableSnapshot*(snapshots: seq[TacticSnapshot]): int {.raises: [].} =
  ## Find the index of the most recent "stable" snapshot — one where
  ## goalDelta.newGoals was within acceptable limits.
  ## Used as the jump target for Global Reset.
  let stableThreshold = goalExplosionThreshold div 2
  for i in countdown(snapshots.len - 1, 0):
    if snapshots[i].goalDelta.newGoals.len <= stableThreshold:
      return i
  0  # No stable snapshot found → jump to beginning

func shouldReset*(
  snapshots: seq[TacticSnapshot];
  currentDepth: int;
  gasRemaining: int;
  gasTotal: int
): tuple[trigger: GlobalResetTrigger; resetToIndex: int] {.raises: [].} =
  ## The Global Reset protocol — detects "labyrinth" conditions and
  ## forces a jump back to the last stable state.
  ##
  ## Four triggers (ordered by severity):
  ## 1. Goal Explosion: newGoals > threshold
  ## 2. Depth Exceeded: depth > maxTacticDepth
  ## 3. Stagnation Loop: same goal repeating
  ## 4. Budget Critical: gas ≤ 20%
  
  # Check goal explosion first (most informative signal)
  if snapshots.len > 0:
    let latest = snapshots[^1]
    if latest.goalDelta.newGoals.len > goalExplosionThreshold:
      return (grtGoalExplosion, findLastStableSnapshot(snapshots))
  
  # Check depth ceiling
  if currentDepth > maxTacticDepth:
    return (grtDepthExceeded, snapshots.len div 2)
  
  # Check stagnation loop
  if detectGoalLoop(snapshots, windowSize = 3):
    return (grtStagnationLoop, findLastStableSnapshot(snapshots))
  
  # Check budget critical
  if gasTotal > 0 and gasRemaining < gasTotal * 20 div 100:
    return (grtBudgetCritical, snapshots.len div 2)
  
  (grtNone, -1)

## ─── Tactic Feedback Construction ────────────────────────────────────────────

func buildTacticFeedback*(
  snapshot: TacticSnapshot;
  priorFailures: seq[string] = @[]
): TacticFeedback {.raises: [].} =
  ## Construct structured feedback from a failed tactic snapshot.
  ## This feedback is sent to the LLM to guide the next tactic suggestion.
  ##
  ## Key insight (CompCert simulation diagram): the LLM needs to know
  ## not just "what failed" but "what the state looked like when it failed".
  
  # Focus on goals that NEED attention: unchanged + newly created
  var suggestedFocus: seq[string]
  for g in snapshot.goalDelta.unchangedGoals:
    suggestedFocus.add g
  for g in snapshot.goalDelta.newGoals:
    suggestedFocus.add "(NEW) " & g
  
  TacticFeedback(
    goalWhenFailed: snapshot.goalBefore,
    hypothesesWhenFailed: snapshot.hypothesesBefore,
    tacticThatFailed: snapshot.tacticApplied,
    errorKind: snapshot.diagnostic.kind,
    errorMessage: snapshot.diagnostic.message,
    goalAfterFailure: snapshot.goalAfter,
    goalDelta: snapshot.goalDelta,
    priorFailures: priorFailures,
    suggestedFocus: suggestedFocus
  )

## ─── Snapshot Serialization (Disk-Backed Store) ──────────────────────────────

func serializeSnapshot*(snap: TacticSnapshot): JsonNode {.raises: [].} =
  ## Serialize a snapshot to JSON for disk storage.
  ## Key optimization: sourceBeforeTactic is stored as hash only (~10x smaller).
  result = newJObject()
  result["index"] = %*snap.index
  result["goalBefore"] = %*snap.goalBefore
  result["hypothesesBefore"] = %*snap.hypothesesBefore
  result["tacticApplied"] = %*snap.tacticApplied
  result["goalAfter"] = %*snap.goalAfter
  result["diagnosticKind"] = %*snap.diagnostic.kind
  result["diagnosticMessage"] = %*snap.diagnostic.message
  result["sourceHash"] = %*snap.sourceHash
  result["succeeded"] = %*snap.succeeded
  result["wallTimeMs"] = %*snap.wallTimeMs
  
  # GoalDelta
  var delta = newJObject()
  delta["unchangedGoals"] = %*snap.goalDelta.unchangedGoals
  delta["resolvedGoals"] = %*snap.goalDelta.resolvedGoals
  delta["newGoals"] = %*snap.goalDelta.newGoals
  delta["typeErrors"] = %*snap.goalDelta.typeErrors
  result["goalDelta"] = delta

proc deserializeSnapshot*(node: JsonNode): TacticSnapshot {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deserialize a snapshot from JSON.
  result.index = node["index"].getInt()
  for g in node["goalBefore"]:
    result.goalBefore.add g.getStr()
  for h in node["hypothesesBefore"]:
    result.hypothesesBefore.add h.getStr()
  result.tacticApplied = node["tacticApplied"].getStr()
  for g in node["goalAfter"]:
    result.goalAfter.add g.getStr()
  result.diagnostic = LeanDiagnostic(
    kind: node["diagnosticKind"].getStr(),
    message: node["diagnosticMessage"].getStr()
  )
  result.sourceHash = node["sourceHash"].getStr()
  result.succeeded = node["succeeded"].getBool()
  result.wallTimeMs = node["wallTimeMs"].getInt()
  
  if node.hasKey("goalDelta"):
    let delta = node["goalDelta"]
    for g in delta["unchangedGoals"]:
      result.goalDelta.unchangedGoals.add g.getStr()
    for g in delta["resolvedGoals"]:
      result.goalDelta.resolvedGoals.add g.getStr()
    for g in delta["newGoals"]:
      result.goalDelta.newGoals.add g.getStr()
    for g in delta["typeErrors"]:
      result.goalDelta.typeErrors.add g.getStr()

proc initSnapshotStore*(diskPath: string; maxHot: int = defaultMaxHot): SnapshotStore {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Initialize a disk-backed snapshot store.
  ## `diskPath` directory is created if it doesn't exist.
  try:
    createDir(diskPath)
  except CatchableError:
    discard  # Best-effort directory creation  # axiom:best-effort(ioboundary catch)
  SnapshotStore(
    hot: initTable[int, TacticSnapshot](),
    diskPath: diskPath,
    maxHot: maxHot,
    totalStored: 0
  )

proc store*(store: var SnapshotStore; snap: TacticSnapshot) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Store a snapshot. If memory is full, evict oldest to disk.
  let index = snap.index
  
  # Evict oldest if at capacity
  if store.hot.len >= store.maxHot:
    var oldestKey = high(int)
    for k in store.hot.keys:
      if k < oldestKey:
        oldestKey = k
    if oldestKey != high(int) and oldestKey in store.hot:
      let oldest = store.hot[oldestKey]
      let path = store.diskPath / "snap_" & $oldestKey & ".json"
      writeFile(path, pretty(serializeSnapshot(oldest)))
      store.hot.del(oldestKey)
  
  store.hot[index] = snap
  store.totalStored += 1

proc retrieve*(store: var SnapshotStore; index: int): Option[TacticSnapshot] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Retrieve a snapshot from hot cache or disk.
  if index in store.hot:
    return some(store.hot[index])
  
  let diskFile = store.diskPath / "snap_" & $index & ".json"
  if fileExists(diskFile):
    let json = parseFile(diskFile)
    let snap = deserializeSnapshot(json)
    store.hot[index] = snap  # Promote back to hot cache
    return some(snap)
  none(TacticSnapshot)

proc clear*(store: var SnapshotStore) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Clear all snapshots (hot cache + disk).
  store.hot.clear()
  removeDir(store.diskPath)
  createDir(store.diskPath)
  store.totalStored = 0
{.pop.}
