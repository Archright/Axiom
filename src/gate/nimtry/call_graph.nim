import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import core/gate/architecture_policy
import gate/architecture_ast_facts
import gate/rule_patterns
import std/sequtils
import std/sets
import std/strutils
import std/tables
import std/algorithm
import ../../core/trusted/axiom_pragmas_lite
export rule_patterns.ArchitectureViolationArtifact

type
  CallGraph* = object
    edges*: Table[string, seq[string]]       ## caller_fn -> callee_fns
    callerModule*: Table[string, string]     ## fn -> module
    calleeModule*: Table[string, string]     ## fn -> module (best-effort)
proc buildCallGraph*(facts: seq[ModuleFacts]): CallGraph {.raises: [].} =
  ## Ingest all CallEdgeFacts from all modules into adjacency list.
  for moduleFacts in facts:
    for edge in moduleFacts.callEdges:
      let callerKey = edge.callerModule & "::" & edge.callerFunction
      let calleeKey = edge.calleeFunction
      result.edges.mgetOrPut(callerKey, @[]).add(calleeKey)
      result.callerModule[callerKey] = edge.callerModule
      # calleeModule is empty from extractor; resolve later via callerModule lookup
      if edge.calleeModule.len > 0:
        result.calleeModule[calleeKey] = edge.calleeModule
proc resolveCalleeModules*(graph: var CallGraph; allFacts: seq[ModuleFacts]) {.raises: [].} =
  ## Resolve callee modules by matching callee function names to their definitions.
  ## Iterates allFacts in deterministic (path-sorted) order so that last-write-wins
  ## bare-name collision resolution never depends on filesystem walk order.
  var fnToModule = initTable[string, string]()
  for moduleFacts in allFacts.sortedByIt(it.path):
    for fn in moduleFacts.functions:
      let key = moduleFacts.path & "::" & fn.name
      fnToModule[fn.name] = moduleFacts.path
      fnToModule[key] = moduleFacts.path
  for callerKey, callees in graph.edges:
    for callee in callees:
      if callee notin graph.calleeModule:
        try:
          if callee in fnToModule:
            graph.calleeModule[callee] = fnToModule[callee]
        except KeyError:
          discard
proc transitiveCallees*(graph: CallGraph; function: string; maxDepth: int): seq[string] {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  ## BFS from a function up to maxDepth, returning all reachable callees.
  if maxDepth <= 0:
    return
  var visited = initHashSet[string]()
  var queue: seq[tuple[fn: string; depth: int]] = @[(function, 0)]
  while queue.len > 0:
    let current = queue[0]
    queue = queue[1 .. ^1]
    if current.fn in visited:
      continue
    visited.incl(current.fn)
    if current.depth >= maxDepth:
      continue
    let callerKey = if "::" in current.fn: current.fn else: ""
    let actualKey = if callerKey.len > 0: callerKey else: current.fn
    let callees = graph.edges.getOrDefault(actualKey, @[])
    for callee in callees:
      if callee notin visited:
        queue.add((callee, current.depth + 1))
        result.add(callee)
  result = result.deduplicate()
proc findTransitiveLayerViolations*(
  graph: CallGraph;
  policy: ArchitecturePolicy;
  allFacts: seq[ModuleFacts];
  maxDepth: int = 2
): seq[ArchitectureViolationArtifact] {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  ## For each Domain-layer function, BFS to maxDepth. If any callee is in a
  ## forbidden layer, flag a SoC violation with the full path.
  var resolvedGraph = graph
  resolvedGraph.resolveCalleeModules(allFacts)
  
  for callerKey, callees in resolvedGraph.edges:
    let callerModule = resolvedGraph.callerModule.getOrDefault(callerKey, "")
    if callerModule.len == 0:
      continue
    let sourceLayer = policy.layerForPath(callerModule)
    if sourceLayer.len == 0 or sourceLayer == "Test":
      continue
    
    let reachable = transitiveCallees(resolvedGraph, callerKey, maxDepth)
    for callee in reachable:
      let calleeModule = resolvedGraph.calleeModule.getOrDefault(callee, "")
      if calleeModule.len == 0:
        continue
      let targetLayer = policy.layerForPath(calleeModule)
      if targetLayer.len == 0:
        continue
      if targetLayer notin policy.allowedLayersFor(sourceLayer):
        # Check if there's an intermediate module that is allowed
        # Only flag if the DIRECT path violates (not just any path)
        let directCallees = resolvedGraph.edges.getOrDefault(callerKey, @[])
        var foundDirectViolation = false
        for directCallee in directCallees:
          let directModule = resolvedGraph.calleeModule.getOrDefault(directCallee, "")
          if directModule.len > 0:
            let directLayer = policy.layerForPath(directModule)
            if directLayer notin policy.allowedLayersFor(sourceLayer):
              foundDirectViolation = true
              break
        # For transitive violations, check if intermediate is allowed
        if not foundDirectViolation:
          # This is a transitive violation: A(Domain) -> B(Domain) -> C(Infrastructure)
          # B is allowed, but C is not from A's perspective
          let detail = callerModule & "::" & callerKey.split("::")[^1] &
            " indirectly reaches forbidden layer " & targetLayer &
            " via " & calleeModule & "::" & callee
          result.add(ArchitectureViolationArtifact(
            rule: "SoC",
            detail: detail,
            files: @[callerModule, calleeModule],
            severity: "warning"))
proc buildCallGraphAndCheck*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy;
  maxDepth: int = 2
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  let graph = buildCallGraph(allFacts)
  findTransitiveLayerViolations(graph, policy, allFacts, maxDepth)

{.pop.}

