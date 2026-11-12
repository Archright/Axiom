import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Gate DAG — Dependency-aware scheduling for L2 functional gates.
##
## Builds a directed acyclic graph from GateConfig.after fields
## (declared in gate_manifest.json) and computes topological layers
## using Kahn's algorithm. The orchestrator runs gates layer-by-layer:
## gates within a layer execute in parallel, layers execute sequentially.
##
## If a gate in layer N fails, its dependents in layer N+1.. are skipped.
##
## Follows the same Kahn's algorithm pattern as
## ``src/core/topology/import_graph.nim`` (DRY, AGENTS.md §1.3).

import std/[tables, sets, strutils, strformat]
import gate/gate_types
import core/import_graph

type
  GateDag* = object
    ## Dependency graph for gate scheduling.
    ## adjacency: gate ID -> list of gate IDs that depend on it (reverse edges).
    ##             Used for transitive failure propagation.
    ## inDegree: gate ID -> number of unmet dependencies.
    ## layers: topological layer ordering (layer 0 has no dependencies).
    adjacency*: Table[string, seq[string]]
    inDegree*: Table[string, int]
    layers*: seq[seq[string]]

# ══════════════════════════════════════════════════════════════════════════════
# DAG Construction
# ══════════════════════════════════════════════════════════════════════════════

func buildGateDag*(gates: seq[GateConfig]): GateDag {.raises: [CatchableError].} =
  ## Build the gate dependency DAG from GateConfig.after fields.
  ## All dependency edges are declared in ``gate_manifest.json`` (SSOT).
  ## Only edges between gates present in the input seq are created.
  result.adjacency = initTable[string, seq[string]]()
  result.inDegree = initTable[string, int]()

  # Build gate ID lookup
  var gateIds = initHashSet[string]()
  for g in gates:
    gateIds.incl(g.id)
    result.adjacency[g.id] = @[]
    result.inDegree[g.id] = 0

  for g in gates:
    for depId in g.after:
      # depId must complete before g.id
      # Only add edge if depId is also in the gate set
      if depId in gateIds:
        result.adjacency[depId].add(g.id)
        result.inDegree[g.id] += 1

# ══════════════════════════════════════════════════════════════════════════════
# Topological Sort (Kahn's Algorithm)
# ══════════════════════════════════════════════════════════════════════════════

func topologicalLayers*(dag: GateDag): seq[seq[string]] =
  ## Kahn's algorithm: return gates grouped by topological layer.
  ## Layer 0 = gates with in-degree 0 (no dependencies).
  ## Layer N+1 = gates whose dependencies are all in layers <= N.
  ##
  ## Same pattern as ``import_graph.nim`` ``computeTopologicalLayers``.
  var remaining = dag.inDegree

  while remaining.len > 0:
    var layer: seq[string] = @[]
    for node, deg in remaining:
      if deg == 0:
        layer.add(node)
    if layer.len == 0:
      # Cycle detected — should not happen for a valid DAG
      break
    result.add(layer)
    for node in layer:
      remaining.del(node)
      for dependent in dag.adjacency.getOrDefault(node, @[]):
        if dependent in remaining:
          remaining[dependent] = remaining.getOrDefault(dependent, 0) - 1

# ══════════════════════════════════════════════════════════════════════════════
# Affected Gate Discovery
# ══════════════════════════════════════════════════════════════════════════════

func matchesFilesPattern*(gate: GateConfig, changedFiles: seq[string]): bool =
  ## Check if a gate's filesPattern matches any of the changed files.
  ## Empty pattern means always matches (no file filter).
  if gate.filesPattern.len == 0:
    return true
  let patterns = gate.filesPattern.split('|')
  for f in changedFiles:
    for p in patterns:
      if f.contains(p.strip()):
        return true
  return false

func findAffectedGates*(dag: GateDag, changedFiles: seq[string],
                        gates: seq[GateConfig]): HashSet[string] =
  ## Find all gate IDs that should run: directly affected (filesPattern match)
  ## plus transitive dependents through after edges.
  ##
  ## Phase 1: gates whose filesPattern matches changedFiles.
  ## Phase 2: if A is affected and B depends on A, B is also affected.
  result = initHashSet[string]()

  # Phase 1: directly affected (filesPattern match)
  for g in gates:
    if matchesFilesPattern(g, changedFiles):
      result.incl(g.id)

  # Phase 2: transitive propagation through reverse edges
  var changed = true
  while changed:
    changed = false
    for g in gates:
      if g.id in result:
        continue
      for depId in g.after:
        if depId in result:
          result.incl(g.id)
          changed = true
          break

# ══════════════════════════════════════════════════════════════════════════════
# Import Tree Integration (Phase 5.3)
# ══════════════════════════════════════════════════════════════════════════════

func fileToModule*(filePath: string): string {.raises: [].} =
  ## Convert a git-relative file path to a core module name for import graph lookup.
  ## ``src/core/types/domain_types.nim`` → ``types/domain_types``
  ## Non-core paths are returned with ``src/`` stripped and ``.nim`` removed.
  result = filePath
  if result.endsWith(".nim"):
    result = result[0..^5]
  # Strip src/ prefix (import graph keys are relative to src/core/)
  if result.startsWith("src/"):
    result = result[4..^1]
  # Strip core/ prefix to match import_graph key convention
  if result.startsWith("core/"):
    result = result[5..^1]

func findAffectedByImportTree*(dag: GateDag, changedFiles: seq[string],
                                importGraph: Table[string, seq[string]],
                                gates: seq[GateConfig]): HashSet[string] =
  ## Import Tree integration for fine-grained incremental execution.
  ##
  ## 1) Build reverse import graph from the core dependency graph.
  ## 2) Map changed files to core module names.
  ## 3) Compute transitive dependents through the reverse graph (BFS).
  ## 4) Match affected modules against gate filesPattern.
  ## 5) Propagate through DAG after edges.
  result = initHashSet[string]()

  # Step 1: Build reverse import graph
  let reverseGraph = buildReverseGraph(importGraph)

  # Step 2: Map changed files to Nim modules
  var changedModules = initHashSet[string]()
  for f in changedFiles:
    let modName = fileToModule(f)
    if modName.len > 0:
      changedModules.incl(modName)

  # Step 3: Compute transitive dependents
  let affectedModules = transitiveDependents(reverseGraph, changedModules)

  # Step 4: Match affected modules against gate filesPattern.
  # Convert affected modules back to file paths for pattern matching.
  var affectedFiles: seq[string]
  for modName in affectedModules:
    affectedFiles.add("src/core/" & modName & ".nim")
    affectedFiles.add(modName & ".nim")
  # Also include original changed files for direct pattern matching
  for f in changedFiles:
    affectedFiles.add(f)

  for g in gates:
    if matchesFilesPattern(g, affectedFiles):
      result.incl(g.id)

  # Step 5: Propagate through DAG after edges
  var propagateChanged = true
  while propagateChanged:
    propagateChanged = false
    for g in gates:
      if g.id in result:
        continue
      for depId in g.after:
        if depId in result:
          result.incl(g.id)
          propagateChanged = true
          break

# ══════════════════════════════════════════════════════════════════════════════
# Artifact Subscription Tracking (Phase H)
# ══════════════════════════════════════════════════════════════════════════════

type
  ArtifactTracker* = object
    ## Tracks which gate produces which artifact patterns and which gates
    ## subscribe to those artifacts. Enables cross-gate invalidation:
    ## when a producer gate's output changes, all subscribers are re-triggered.
    ##
    ## SSOT: `produces` and `subscribes` fields are optional in gate_manifest.json.
    ## Empty means the gate does not participate in artifact subscriptions.
    producers*: Table[string, seq[string]]  ## artifact pattern → gate IDs that produce it
    subscribers*: Table[string, seq[string]] ## artifact pattern → gate IDs that subscribe

func buildArtifactTracker*(gates: seq[GateConfig]): ArtifactTracker =
  ## Build artifact subscription index from GateConfig produces/subscribes fields.
  ## Each gate can produce zero or more artifact patterns and subscribe to zero or more.
  result.producers = initTable[string, seq[string]]()
  result.subscribers = initTable[string, seq[string]]()

  for g in gates:
    for artifact in g.produces:
      result.producers[artifact] = result.producers.getOrDefault(artifact, @[]) & @[g.id]
    for artifact in g.subscribes:
      result.subscribers[artifact] = result.subscribers.getOrDefault(artifact, @[]) & @[g.id]

func findAffectedByArtifacts*(tracker: ArtifactTracker,
                               completedGates: HashSet[string],
                               gates: seq[GateConfig]): HashSet[string] =
  ## After a gate completes, check if it produces artifacts that other gates
  ## subscribe to. Return the set of subscribing gate IDs that should be
  ## invalidated and re-run.
  ##
  ## Call this after each layer completes in the DAG scheduler.
  result = initHashSet[string]()

  for gateId in completedGates:
    # Find what this gate produces
    for artifact, producers in tracker.producers:
      if gateId in producers:
        # Find all subscribers to this artifact
        let subs = tracker.subscribers.getOrDefault(artifact, @[])
        for subscriberId in subs:
          if subscriberId notin completedGates:
            result.incl(subscriberId)

func logArtifactSubscriptions*(tracker: ArtifactTracker): seq[string] =
  ## Log lines summarizing artifact subscription topology for diagnostics.
  result = @[]
  for artifact, producers in tracker.producers:
    let subs = tracker.subscribers.getOrDefault(artifact, @[])
    if subs.len > 0:
      result.add(&"  {artifact}: {producers} → {subs}")

# ══════════════════════════════════════════════════════════════════════════════
# Tier Filtering
# ══════════════════════════════════════════════════════════════════════════════

func gatesInTier*(gates: seq[GateConfig], tier: int): seq[GateConfig] =
  ## Filter gates by execution tier. Tier 1 = fast-path, tier 2 = deep-path.
  result = @[]
  for g in gates:
    if g.tier == tier:
      result.add(g)

# ══════════════════════════════════════════════════════════════════════════════
# Failure Propagation
# ══════════════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════════════
# Critical Path Analysis (Phase 2.1: Eager Scheduling)
# ══════════════════════════════════════════════════════════════════════════════

func computeCriticalPath*(dag: GateDag, gates: seq[GateConfig]): Table[string, int] =
  ## Compute the critical path weight for each gate using reverse-topological DP.
  ##
  ## cp(G) = weight(G) + max(cp(H)) for all H that directly depend on G.
  ## Gates on the critical path have the highest cp values and should be
  ## scheduled first to minimize total makespan (Amdahl's law for DAG scheduling).
  ##
  ## Returns: gate ID → critical path weight (higher = more urgent).
  result = initTable[string, int]()

  # Build weight lookup
  var gateWeight = initTable[string, int]()
  for g in gates:
    gateWeight[g.id] = g.weight.int
    result[g.id] = g.weight.int  # Base case: own weight

  # Get topological layers and process in reverse order (bottom-up DP)
  let layers = dag.topologicalLayers()
  for i in countdown(layers.len - 1, 0):
    for gateId in layers[i]:
      var maxDepCp = 0
      for dependentId in dag.adjacency.getOrDefault(gateId, @[]):
        let depCp = result.getOrDefault(dependentId, 0)
        if depCp > maxDepCp:
          maxDepCp = depCp
      result[gateId] = gateWeight.getOrDefault(gateId, 1) + maxDepCp

func propagateFailures*(dag: GateDag, failedGates: HashSet[string]): HashSet[string] =
  ## Transitively propagate failures through the DAG.
  ## Returns the full set of gates that should be skipped (failed + dependents).
  ## Uses worklist pattern to avoid mutating HashSet during iteration.
  result = failedGates
  var frontier: seq[string]
  for g in failedGates:
    frontier.add(g)
  while frontier.len > 0:
    var nextFrontier: seq[string]
    for gId in frontier:
      for depId in dag.adjacency.getOrDefault(gId, @[]):
        if depId notin result:
          result.incl(depId)
          nextFrontier.add(depId)
    frontier = nextFrontier

{.pop.}
