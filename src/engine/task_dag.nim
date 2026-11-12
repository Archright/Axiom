## task_dag.nim — Pure Task DAG types and topological analysis
##
## Phase 0 Task DAG engine: core data types, cycle detection, and
## Kahn's algorithm topological sort. Adapted from core/topology/import_graph.nim
## for task-level dependency management.
##
## All functions are pure (`func`, `raises: []`). No I/O.
##
## TaskId and TaskState are imported from core/schema/task_schema (SSOT).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[tables, sets, hashes]
import core/boundary/results_boundary
import core/task_schema

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  TaskNode* = object
    id*: TaskId
    inputs*: seq[string]
    outputs*: seq[string]
    dependsOn*: seq[TaskId]
    executor*: TaskExecutor       ## I/O boundary closure
    state*: TaskState
    hash*: string                 ## Input hash for deterministic verification
    duration*: float              ## Execution time in seconds

  TaskDag* = object
    nodes*: seq[TaskNode]
    adjacency*: Table[string, seq[string]]  ## id → dependent ids (string keys for safe hashing)
    executionOrder*: seq[seq[TaskId]]       ## computed topological layers

  TaskExecutor* = proc(inputs: seq[string]): Result[seq[string], string] {.closure, raises: [CatchableError].}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func findNodeById*(dag: TaskDag, id: TaskId): int {.raises: [].} =
  ## Return index of node with given id, or -1 if not found.
  for i, node in dag.nodes:
    if node.id == id:
      return i
  return -1

func hasNode*(dag: TaskDag, id: TaskId): bool {.raises: [].} =
  findNodeById(dag, id) >= 0

# ---------------------------------------------------------------------------
# Topological sort (Kahn's algorithm) — declared first to avoid forward refs
# ---------------------------------------------------------------------------

func topologicalSort*(dag: TaskDag): Result[seq[seq[TaskId]], string] {.raises: [].} =
  ## Compute topological layers using Kahn's algorithm.
  ## Layer 0 = nodes with no dependencies (leaf tasks).
  ## Layer N+1 = nodes whose dependencies are all in layers ≤ N.
  ## Returns Err if cycles exist.
  ##
  ## NOTE: Implements its own cycle detection via Kahn's — does NOT call
  ## validateDag() to avoid false-positive DFS cycle bugs.

  # Build indegree: string id → count of its dependencies
  var indegree = initTable[string, int]()
  for node in dag.nodes:
    indegree[$node.id] = node.dependsOn.len

  # Seed queue with zero in-degree nodes
  var queue: seq[string] = @[]
  for nodeId, deg in indegree:
    if deg == 0:
      queue.add(nodeId)

  # Kahn's layer-by-layer peel
  var remaining = indegree
  var layers: seq[seq[TaskId]] = @[]

  while queue.len > 0:
    var layer: seq[TaskId] = @[]
    # Collect all zero-indegree nodes currently in queue
    for qNode in queue:
      layer.add(toTaskId(qNode))
    queue.setLen(0)  # clear queue

    if layer.len > 0:
      layers.add(layer)
      for taskId in layer:
        let nodeId = $taskId
        remaining.del(nodeId)
        # Decrement indegree of tasks that depend on this node
        let neighbors = dag.adjacency.getOrDefault(nodeId, @[])
        for dependent in neighbors:
          if dependent in remaining:
            let cur = remaining.getOrDefault(dependent, 0)
            remaining[dependent] = cur - 1
            if remaining.getOrDefault(dependent, 0) == 0:
              queue.add(dependent)
    else:
      # Should not happen, but defensive
      return err("internal error: cycle detected during topological sort")

  # Verify all nodes were processed
  var totalNodes = 0
  for layer in layers:
    inc totalNodes, layer.len
  if totalNodes != dag.nodes.len:
    return err("cycle detected: topological sort covered " &
               $totalNodes & " of " & $dag.nodes.len & " nodes")

  return ok(layers)

# ---------------------------------------------------------------------------
# Cycle detection (delegates to topologicalSort)
# ---------------------------------------------------------------------------

func detectCycles*(dag: TaskDag): seq[seq[TaskId]] {.raises: [].} =
  ## Detect cycles using Kahn's algorithm via topologicalSort.
  ## If topo sort fails, returns a seq containing all node ids as cycle participants.
  let topo = dag.topologicalSort()
  if topo.isErr():
    var cycleNodes: seq[TaskId] = @[]
    for node in dag.nodes:
      cycleNodes.add(node.id)
    result = @[cycleNodes]

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

func validateDag*(dag: TaskDag): Result[void, string] {.raises: [].} =
  ## Validate the DAG: check for cycles and missing dependencies.
  # Check all dependency references exist
  for node in dag.nodes:
    for depId in node.dependsOn:
      if not dag.hasNode(depId):
        return err("node " & $node.id & " depends on missing node: " & $depId)
  # Check for cycles via Kahn's
  let topoResult = dag.topologicalSort()
  if topoResult.isErr():
    return err(topoResult.error)
  result = Result[void, string](ok: true)

# ---------------------------------------------------------------------------
# Public API: DAG construction
# ---------------------------------------------------------------------------

func addNode*(dag: var TaskDag, node: TaskNode): Result[void, string] {.raises: [].} =
  ## Add a node to the DAG. Fails if a node with the same id already exists.
  let idStr = $node.id
  if dag.hasNode(node.id):
    return err("duplicate node id: " & idStr)
  dag.nodes.add(node)
  # Build adjacency: reverse edges — for each dep, record that this node depends on it
  for depId in node.dependsOn:
    let depKey = $depId
    var deps = dag.adjacency.getOrDefault(depKey, @[])
    deps.add(idStr)
    dag.adjacency[depKey] = deps
  # Ensure entry exists for node itself
  if idStr notin dag.adjacency:
    dag.adjacency[idStr] = @[]
  result = Result[void, string](ok: true)

func getNode*(dag: TaskDag, id: TaskId): Result[TaskNode, string] {.raises: [].} =
  ## Get a node by id.
  let idx = dag.findNodeById(id)
  if idx < 0:
    return err("node not found: " & $id)
  ok(dag.nodes[idx])

func updateNodeState*(dag: var TaskDag, id: TaskId, state: TaskState,
                      duration: float = 0.0): Result[void, string] {.raises: [].} =
  ## Update a node's state and duration.
  let idx = dag.findNodeById(id)
  if idx < 0:
    return err("node not found: " & $id)
  dag.nodes[idx].state = state
  dag.nodes[idx].duration = duration
  result = Result[void, string](ok: true)

# ---------------------------------------------------------------------------
# Convenience: create empty DAG
# ---------------------------------------------------------------------------

func newTaskDag*(): TaskDag {.raises: [].} =
  ## Create an empty TaskDag.
  TaskDag(
    nodes: @[],
    adjacency: initTable[string, seq[string]](),
    executionOrder: @[]
  )

{.pop.}
