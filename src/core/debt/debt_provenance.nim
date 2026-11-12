## src/core/debt/debt_provenance.nim — Provenance DAG append-only storage/query.
##
## Public API:
##   - buildGraph*(nodes, edges): ProvenanceGraph
##   - appendNode*(graph: var ProvenanceGraph, node)
##   - appendEdge*(graph: var ProvenanceGraph, edge)
##   - findPath*(graph, fromNode, toNode): seq[ProvenanceEdgeKind]  (BFS)
##   - nodeById*(graph, id): Option[ProvenanceNode]
##   - evidenceChainFor*(graph, nodeId): seq[ProvenanceNode]  (reverse trace via derivedFrom/observedIn)

import core/trusted/layer_declaration
axiomLayer "domain"

import core/types/debt_types
import core/axiom_pragmas
import std/[options, tables, sets]

{.push raises: [].}

func buildGraph*(nodes: seq[ProvenanceNode]; edges: seq[ProvenanceEdge]): ProvenanceGraph =
  ## Construct a ProvenanceGraph from the given nodes and edges.
  ## No validation — callers provide consistent data.
  ProvenanceGraph(nodes: nodes, edges: edges)

proc appendNode*(graph: var ProvenanceGraph; node: ProvenanceNode) =
  ## Append a node to the graph.
  ## Skips duplicate nodeId entries (idempotent).
  for existing in graph.nodes:
    if existing.nodeId == node.nodeId:
      return
  graph.nodes.add(node)

proc appendEdge*(graph: var ProvenanceGraph; edge: ProvenanceEdge) =
  ## Append an edge to the graph.
  ## No endpoint existence validation — edges are added regardless.
  graph.edges.add(edge)

func nodeById*(graph: ProvenanceGraph; id: string): Option[ProvenanceNode] {.axiomDecision(
  id = "DECISION-0658",
  reason = "Look up a ProvenanceNode by its nodeId in the graph; none if absent",
  adr = "docs/adr/0001-fail-closed-result-type.md",
  introduced = "v33"
).} =
  ## Look up a node by its nodeId.
  ## Returns none if no matching node exists.
  for node in graph.nodes:
    if node.nodeId == id:
      return some(node)
  none(ProvenanceNode)

func findPath*(graph: ProvenanceGraph; fromNode, toNode: string): seq[ProvenanceEdgeKind] {.axiomDecision(
  id = "DECISION-0659",
  reason = "Find the shortest path between two nodes in the provenance DAG via BFS; empty seq if unreachable",
  adr = "docs/adr/0001-fail-closed-result-type.md",
  introduced = "v33"
).} =
  ## Find a path from fromNode to toNode using BFS.
  ## Returns the sequence of edge kinds along the shortest path.
  ## Returns empty seq if no path exists.
  if fromNode == toNode:
    return @[]

  # Build adjacency list: fromNode → seq[(toNode, edgeKind)]
  var adj: Table[string, seq[(string, ProvenanceEdgeKind)]]
  for edge in graph.edges:
    let entry = adj.getOrDefault(edge.fromNode, @[])
    adj[edge.fromNode] = entry & @[(edge.toNode, edge.edgeKind)]

  # BFS with path tracking
  var visited: HashSet[string]
  visited.incl(fromNode)
  var queue: seq[(string, seq[ProvenanceEdgeKind])]
  queue.add((fromNode, @[]))

  var head = 0
  while head < queue.len:
    let (current, path) = queue[head]
    inc head
    let neighbors = adj.getOrDefault(current, @[])
    for (next, kind) in neighbors:
      if next == toNode:
        return path & @[kind]
      if next notin visited:
        visited.incl(next)
        queue.add((next, path & @[kind]))

  @[]  # no path found

func evidenceChainFor*(graph: ProvenanceGraph; nodeId: string): seq[ProvenanceNode] =
  ## Trace backward from nodeId to root nodes via derivedFrom/observedIn edges.
  ## Returns the chain starting from the queried node, then its ancestors.
  ## Uses iterative DFS to avoid stack overflow on deep graphs.
  var visited: HashSet[string]
  var chain: seq[ProvenanceNode]
  var stack: seq[string]
  stack.add(nodeId)

  while stack.len > 0:
    let current = stack.pop()
    if current in visited:
      continue
    visited.incl(current)
    let nodeOpt = nodeById(graph, current)
    if nodeOpt.isSome():
      chain.add(nodeOpt.get())
      # Follow incoming derivedFrom/observedIn edges to parents
      for edge in graph.edges:
        if edge.toNode == current and edge.edgeKind in {peDerivedFrom, peObservedIn}:
          if edge.fromNode notin visited:
            stack.add(edge.fromNode)

  chain

{.pop.}
