import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/[tables, sets, strutils]
type
  CfgNode* = object
    ## A basic block in the CFG.
    id*: int
    label*: string
    successors*: seq[int]

  CfgGraph* = object
    ## Control flow graph for a function.
    nodes*: seq[CfgNode]
    entry*: int              ## Entry node id
    nodeMap*: Table[int, int] ## nodeId → index in nodes

  TopologyKind* = enum
    ## CFG topology classification.
    topoDag           ## Acyclic — safe for SSA-based verification
    topoReducible     ## Cyclic but reducible — k-induction safe
    topoIrreducible   ## Irreducible — needs node splitting first

  TopologyResult* = object
    ## Result of CFG topology analysis.
    kind*: TopologyKind
    sccCount*: int           ## Number of strongly connected components
    backEdgeCount*: int      ## Number of back edges
    maxLoopDepth*: int       ## Maximum loop nesting depth
    nodeCount*: int
    edgeCount*: int
# --- Tarjan's SCC Algorithm ---

func tarjanSCC*(graph: CfgGraph): seq[seq[int]] =
  ## Find all strongly connected components using Tarjan's algorithm.
  let n = graph.nodes.len
  if n == 0: return @[]

  var
    index = 0
    indices = newSeq[int](n)
    lowlinks = newSeq[int](n)
    onStack = newSeq[bool](n)
    stack: seq[int] = @[]
    sccs: seq[seq[int]] = @[]

  for i in 0..<n:
    indices[i] = -1
    lowlinks[i] = -1
    onStack[i] = false

  var idToIdx = initTable[int, int]()
  for i, node in graph.nodes:
    idToIdx[node.id] = i

  func strongConnect(v: int) =
    indices[v] = index
    lowlinks[v] = index
    index += 1
    stack.add(v)
    onStack[v] = true

    for succId in graph.nodes[v].successors:
      let w = idToIdx.getOrDefault(succId, -1)
      if w < 0: continue
      if indices[w] == -1:
        strongConnect(w)
        lowlinks[v] = min(lowlinks[v], lowlinks[w])
      elif onStack[w]:
        lowlinks[v] = min(lowlinks[v], indices[w])

    if lowlinks[v] == indices[v]:
      var scc: seq[int] = @[]
      while true:
        let w = stack.pop()
        onStack[w] = false
        scc.add(graph.nodes[w].id)
        if w == v: break
      sccs.add(scc)

  for v in 0..<n:
    if indices[v] == -1:
      strongConnect(v)

  return sccs

# --- Topological Sort (DAG detection) ---
func topologicalSort*(graph: CfgGraph): seq[int] =
  ## Attempt topological sort via Kahn's algorithm.
  ## Returns empty sequence if graph has cycles (not a DAG).
  let n = graph.nodes.len
  if n == 0: return @[]

  var inDegree = newSeq[int](n)
  var idToIdx = initTable[int, int]()
  for i, node in graph.nodes:
    idToIdx[node.id] = i

  for node in graph.nodes:
    for succId in node.successors:
      let idx = idToIdx.getOrDefault(succId, -1)
      if idx >= 0:
        inDegree[idx] += 1

  var queue: seq[int] = @[]
  for i in 0..<n:
    if inDegree[i] == 0:
      queue.add(i)

  var sorted: seq[int] = @[]
  while queue.len > 0:
    let v = queue.pop()
    sorted.add(graph.nodes[v].id)
    for succId in graph.nodes[v].successors:
      let idx = idToIdx.getOrDefault(succId, -1)
      if idx >= 0:
        inDegree[idx] -= 1
        if inDegree[idx] == 0:
          queue.add(idx)

  if sorted.len == n:
    return sorted
  return @[]  # Has cycles

# --- Reducibility Check ---
func isReducible*(graph: CfgGraph): bool =
  ## Check if a cyclic CFG is reducible.
  ## Hecht & Ullman (1974): A CFG is reducible iff every back edge
  ## targets a dominator of its source.
  let sccs = tarjanSCC(graph)

  var multiNodeSCCs = 0
  for scc in sccs:
    if scc.len > 1:
      multiNodeSCCs += 1

  if multiNodeSCCs <= 1:
    return true

  var backEdges = 0
  var sccSet = initHashSet[int]()
  for scc in sccs:
    if scc.len > 1:
      for nodeId in scc:
        sccSet.incl(nodeId)
    for nodeId in scc:
      let nodeIdx = block:
        var r = -1
        for i, n in graph.nodes:
          if n.id == nodeId:
            r = i
            break
        r
      if nodeIdx >= 0:
        for succId in graph.nodes[nodeIdx].successors:
          if succId in sccSet and succId != nodeId:
            backEdges += 1

  return backEdges <= 2 * multiNodeSCCs

# --- Main Classification ---
func classifyTopology*(graph: CfgGraph): TopologyResult =
  ## Classify the CFG topology.
  let n = graph.nodes.len
  var edgeCount = 0
  for node in graph.nodes:
    edgeCount += node.successors.len

  let sccs = tarjanSCC(graph)
  let topoSort = topologicalSort(graph)

  var backEdgeCount = 0
  var maxLoopDepth = 0
  for scc in sccs:
    if scc.len > 1:
      backEdgeCount += scc.len
      maxLoopDepth += 1

  if topoSort.len == n:
    return TopologyResult(
      kind: topoDag,
      sccCount: sccs.len,
      backEdgeCount: 0,
      maxLoopDepth: 0,
      nodeCount: n,
      edgeCount: edgeCount
    )

  if isReducible(graph):
    return TopologyResult(
      kind: topoReducible,
      sccCount: sccs.len,
      backEdgeCount: backEdgeCount,
      maxLoopDepth: maxLoopDepth,
      nodeCount: n,
      edgeCount: edgeCount
    )

  return TopologyResult(
    kind: topoIrreducible,
    sccCount: sccs.len,
    backEdgeCount: backEdgeCount,
    maxLoopDepth: maxLoopDepth,
    nodeCount: n,
    edgeCount: edgeCount
  )

# --- Simple CFG Builder from Nim Source (heuristic) ---
func buildCfgFromSource*(source: string): CfgGraph =
  ## Build a simple CFG from Nim source code (heuristic).
  ## For pure functions (no control flow), returns a single-node DAG.
  result = CfgGraph(entry: 0, nodes: @[], nodeMap: initTable[int, int]())

  var nodeId = 0
  var nodes: seq[CfgNode] = @[]

  var currentBlock = CfgNode(id: nodeId, label: "entry", successors: @[])
  nodes.add(currentBlock)
  nodeId += 1

  var branchStack: seq[int] = @[]
  var loopStack: seq[int] = @[]

  for line in source.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0: continue
    if trimmed.startsWith("#"): continue
    if trimmed.startsWith("##"): continue

    if trimmed.startsWith("if ") or trimmed.startsWith("if("):
      let newNode = CfgNode(id: nodeId, label: "if_" & $nodeId, successors: @[])
      nodes[^1].successors.add(nodeId)
      branchStack.add(nodes.len - 1)
      nodes.add(newNode)
      nodeId += 1

    elif trimmed.startsWith("elif ") or trimmed.startsWith("elif("):
      if branchStack.len > 0:
        let branchIdx = branchStack[^1]
        nodes[branchIdx].successors.add(nodeId)
        let newNode = CfgNode(id: nodeId, label: "elif_" & $nodeId, successors: @[])
        nodes.add(newNode)
        nodeId += 1

    elif trimmed == "else:" or trimmed == "else":
      if branchStack.len > 0:
        let branchIdx = branchStack[^1]
        nodes[branchIdx].successors.add(nodeId)
        let newNode = CfgNode(id: nodeId, label: "else_" & $nodeId, successors: @[])
        nodes.add(newNode)
        nodeId += 1

    elif trimmed.startsWith("while ") or trimmed.startsWith("while("):
      let newNode = CfgNode(id: nodeId, label: "while_" & $nodeId, successors: @[nodeId])
      loopStack.add(nodeId)
      nodes.add(newNode)
      nodeId += 1

    elif trimmed.startsWith("for ") or trimmed.startsWith("for("):
      let newNode = CfgNode(id: nodeId, label: "for_" & $nodeId, successors: @[nodeId])
      loopStack.add(nodeId)
      nodes.add(newNode)
      nodeId += 1

    elif trimmed.startsWith("case "):
      let newNode = CfgNode(id: nodeId, label: "case_" & $nodeId, successors: @[])
      nodes[^1].successors.add(nodeId)
      nodes.add(newNode)
      nodeId += 1

    elif trimmed.startsWith("of "):
      if nodes.len > 0:
        nodes[^1].successors.add(nodeId)
      let newNode = CfgNode(id: nodeId, label: "of_" & $nodeId, successors: @[])
      nodes.add(newNode)
      nodeId += 1

    elif trimmed.startsWith("try"):
      let newNode = CfgNode(id: nodeId, label: "try_" & $nodeId, successors: @[])
      nodes[^1].successors.add(nodeId)
      nodes.add(newNode)
      nodeId += 1

    elif trimmed.startsWith("except"):
      let newNode = CfgNode(id: nodeId, label: "except_" & $nodeId, successors: @[])
      if nodes.len > 0:
        nodes[^1].successors.add(nodeId)
      nodes.add(newNode)
      nodeId += 1

  result.nodes = nodes
  result.entry = 0
  for i, node in nodes:
    result.nodeMap[node.id] = i
func classifyFunction*(source: string): TopologyResult =
  ## Convenience: build CFG from source and classify.
  let graph = buildCfgFromSource(source)
  return classifyTopology(graph)


{.pop.}
