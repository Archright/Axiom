import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/pure/json_parse
import core/testing/pbt_engine
import core/topology/lock
import std/[json, tables]

# ─── DAG Generator ────────────────────────────────────────────
# Composed from sub-generators via combinator chain.

func genModuleHistoryEntry*(): Gen[ModuleHistoryEntry] {.raises: [].} =
  return proc(bs: var BitStream): ModuleHistoryEntry {.raises: [].} =
    ModuleHistoryEntry(
      path: "src/" & bs.randAlphanumeric(8) & ".nim",
      changedAt: "2026-01-" & (if bs.randInt(1, 28) < 10: "0" else: "") &
                  $bs.randInt(1, 28) & "T00:00:00Z",
      changeType: "topology_apply",
      approvedInLock: bs.randInt(1, 100)
    )
func genModuleEntry*(): Gen[ModuleEntry] {.raises: [].} =
  return proc(bs: var BitStream): ModuleEntry {.raises: [].} =
    let path = "src/" & bs.randAlphanumeric(6) & ".nim"
    ModuleEntry(
      currentPath: path,
      initialPath: path,
      history: genSeq(genModuleHistoryEntry(), 0, 3)(bs)
    )
func genShardEntry*(): Gen[ShardEntry] {.raises: [].} =
  return proc(bs: var BitStream): ShardEntry {.raises: [].} =
    var members: seq[string] = @[]
    let count = bs.randInt(1, 4)
    for i in 0..<count:
      members.add("src/" & bs.randAlphanumeric(6) & ".nim")
    ShardEntry(
      members: members,
      module_type: "core",
      note: bs.randAlphanumeric(10)
    )
func genTransitionalEntry*(): Gen[TransitionalEntry] {.raises: [].} =
  return proc(bs: var BitStream): TransitionalEntry {.raises: [].} =
    TransitionalEntry(
      created_at: "2026-01-01T00:00:00Z",
      resolved_at: ""  # unresolved → triggers TTL check
    )
func genTopologyLock*(): Gen[TopologyLock] {.raises: [].} =
  ## Composed from sub-generators via combinator chain.
  let modules = genTable(genString(4, 8), genModuleEntry(), 1, 10)
  let shards = genTable(genString(4, 8), genShardEntry(), 0, 5)
  let transMods = genTable(genString(4, 8), genTransitionalEntry(), 0, 3)
  return proc(bs: var BitStream): TopologyLock {.raises: [].} =
    TopologyLock(
      schema: "axiom/topology-lock/v2",
      lock_revision: bs.randInt(1, 1000),
      generated_from_policy: "test-policy",
      generated_from_revision: bs.randInt(1, 100),
      generated_at: "2026-01-01T00:00:00Z",
      modules: modules(bs),
      shards: shards(bs),
      transitional_modules: transMods(bs)
    )
func genGateConfigMutation*(baseJson: string): Gen[JsonNode] {.raises: [].} =
  ## Takes a valid gate_exceptions.json string and applies guided mutations:
  ## - Remove an exception entry
  ## - Corrupt a date field
  ## - Change gate name to invalid value
  ## - Add duplicate entry
  ## Captures string (value type) to avoid deepcopy issues under ARC/ORC.
  return proc(bs: var BitStream): JsonNode {.raises: [].} =
    try:
      result = pureParseJson(baseJson)
      if result.kind != JObject or result.len == 0:
        return
      let mutationType = bs.randInt(0, 3)
      case mutationType
      of 0: # Remove a random entry
        var idx = bs.randInt(0, result.len - 1)
        var targetKey = ""
        for key, _ in result:
          if idx == 0:
            targetKey = key
            break
          dec idx
        if targetKey.len > 0:
          result.delete(targetKey)
      of 1: # Corrupt a date field
        for key, val in result:
          if val.kind == JString and val.getStr.len == 10:
            result[key] = newJString("invalid-date")
            break
      of 2: # Change gate name
        var idx = bs.randInt(0, result.len - 1)
        var targetKey = ""
        for key, _ in result:
          if idx == 0:
            targetKey = key
            break
          dec idx
        if targetKey.len > 0:
          let oldVal = result[targetKey]
          result.delete(targetKey)
          result["INVALID_GATE_" & bs.randAlphanumeric(4)] = oldVal
      of 3: # Add duplicate entry
        var idx = bs.randInt(0, result.len - 1)
        var targetKey = ""
        for key, _ in result:
          if idx == 0:
            targetKey = key
            break
          dec idx
        if targetKey.len > 0:
          result[targetKey & "_dup"] = pureParseJson($result[targetKey])
      else:
        discard
    except KeyError, CatchableError:
      discard  # Mutation failed; return unmodified base

{.pop.} # raises: []
# Self-contained DAG type for cycle-detection PBT.
# Adjacency-list representation matching existing codebase pattern
# (dependency_rules_gate.nim uses Table[string, seq[string]]).

type
  DagGraph* = object
    ## Test-only DAG type. Acyclic by construction.
    nodes*: seq[string]
    edges*: seq[tuple[src, dst: string]]
    adjacency*: Table[string, seq[string]]
func hasCycle*(g: DagGraph): bool =
  ## Kahn's algorithm: topological sort via in-degree elimination.
  ## Returns true if a cycle exists (not all nodes consumed).
  var inDegree = initTable[string, int]()
  for n in g.nodes:
    inDegree[n] = 0
  for e in g.edges:
    inDegree[e.dst] = inDegree.getOrDefault(e.dst, 0) + 1
  var queue: seq[string] = @[]
  for n in g.nodes:
    if inDegree.getOrDefault(n, 0) == 0:
      queue.add(n)
  var visited = 0
  while queue.len > 0:
    let node = queue.pop()
    inc visited
    for neighbor in g.adjacency.getOrDefault(node):
      inDegree[neighbor] = inDegree.getOrDefault(neighbor, 0) - 1
      if inDegree.getOrDefault(neighbor, 0) == 0:
        queue.add(neighbor)
  return visited < g.nodes.len
func genDAG*(maxNodes: int = 20): Gen[DagGraph] {.raises: [].} =
  ## Generates a random DAG by topological-order edge placement.
  ## Cycle-free by construction: only edges from lower-index to higher-index
  ## after Fisher-Yates shuffle of node order.
  return proc(bs: var BitStream): DagGraph {.raises: [].} =
    let nodeCount = bs.randInt(1, maxNodes)
    var nodes = newSeq[string](nodeCount)
    for i in 0..<nodeCount:
      nodes[i] = "n" & $i
    # Fisher-Yates shuffle for random topological order
    for i in countdown(nodes.high, 1):
      let j = bs.randInt(0, i)
      swap(nodes[i], nodes[j])
    # Add edges only forward in shuffled order → acyclic by construction
    var edges: seq[tuple[src, dst: string]] = @[]
    # Use seq-indexed adjacency (avoids Table KeyError under {.raises: [].})
    var adjSeq = newSeq[seq[int]](nodeCount)
    for i in 0..<nodeCount:
      for j in (i+1)..<nodeCount:
        if bs.randFloat() < 0.3:  # 30% edge probability
          edges.add((nodes[i], nodes[j]))
          adjSeq[i].add(j)
    # Build Table adjacency from seq-indexed form
    var adj = initTable[string, seq[string]]()
    for i in 0..<nodeCount:
      var neighbors: seq[string] = @[]
      for j in adjSeq[i]:
        neighbors.add(nodes[j])
      adj[nodes[i]] = neighbors
    DagGraph(nodes: nodes, edges: edges, adjacency: adj)
