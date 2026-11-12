import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

## Tarjan's Strongly Connected Components algorithm for circular dependency
## detection in the Axiom module graph.
##
## Classic O(V+E) implementation using an index/lowlink stack.
## Only SCCs with size > 1 are reported (singleton SCCs are not cycles).

import std/[tables, sets, strutils]

type
  ModuleGraph* = object
    ## Directed graph of module imports.
    nodes*: seq[string]
    adjList*: Table[string, seq[string]]

  SCC* = seq[string]  ## A strongly connected component.

# ---------------------------------------------------------------------------
# Tarjan internals
# ---------------------------------------------------------------------------

type
  tarjanState = object
    index: int
    stack: seq[string]
    stackLen: int
    onStack: HashSet[string]
    indices: Table[string, int]
    lowlink: Table[string, int]
    result: seq[SCC]

func tarjanVisit(
    state: var tarjanState;
    graph: ModuleGraph;
    v: string
) =
  ## Recursive DFS visit following the classic Tarjan algorithm.
  ## Uses manual stack pointer and ``getOrDefault`` to stay within
  ## ``{.raises: []}`` constraints.
  state.indices[v] = state.index
  state.lowlink[v] = state.index
  # Push onto manual stack.
  if state.stackLen < state.stack.len:
    state.stack[state.stackLen] = v
  else:
    state.stack.add(v)
  inc state.stackLen
  state.onStack.incl(v)
  inc state.index

  let neighbors = graph.adjList.getOrDefault(v, @[])
  for w in neighbors:
    if w notin state.indices:
      tarjanVisit(state, graph, w)
      let vLow = state.lowlink.getOrDefault(v, state.index)
      let wLow = state.lowlink.getOrDefault(w, state.index)
      if vLow > wLow:
        state.lowlink[v] = wLow
    elif w in state.onStack:
      let vLow = state.lowlink.getOrDefault(v, state.index)
      let wIdx = state.indices.getOrDefault(w, state.index)
      if vLow > wIdx:
        state.lowlink[v] = wIdx

  # If v is a root node, pop the stack to extract the SCC.
  let vLow = state.lowlink.getOrDefault(v, state.index)
  let vIdx = state.indices.getOrDefault(v, state.index)
  if vLow == vIdx:
    var scc: SCC
    while state.stackLen > 0:
      dec state.stackLen
      let w = state.stack[state.stackLen]
      state.onStack.excl(w)
      scc.add(w)
      if w == v:
        break
    if scc.len > 1:
      state.result.add(scc)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func tarjanSCC*(graph: ModuleGraph): seq[SCC] =
  ## Compute strongly connected components via Tarjan's algorithm.
  ## Returns only SCCs with more than one node (actual cycles).
  ## Empty sequence means no circular dependencies.
  var state = tarjanState(index: 0, stackLen: 0)
  for v in graph.nodes:
    if v notin state.indices:
      tarjanVisit(state, graph, v)
  result = state.result

func detectCycles*(graph: ModuleGraph): seq[seq[string]] =
  ## Detect circular dependencies and return each as a closed chain
  ## ``[A, B, C, A]`` (first node repeated at end).
  ## Returns an empty sequence when no cycles exist.
  let sccs = tarjanSCC(graph)
  for scc in sccs:
    var chain: seq[string]
    var first: string
    for item in scc:
      chain.add(item)
      if chain.len == 1:
        first = item
    chain.add(first)
    result.add(chain)

func formatCycles*(cycles: seq[seq[string]]): string =
  ## Format detected cycles into a human-readable report.
  ##
  ## Example output::
  ##
  ##   FATAL: Circular dependency detected!
  ##     Cycle 1: modA -> modB -> modC -> modA
  ##     Cycle 2: modX -> modY -> modX
  if cycles.len == 0:
    return ""
  result = "FATAL: Circular dependency detected!\n"
  for i, cycle in cycles:
    let chain = cycle.join(" -> ")
    result.add("  Cycle " & $(i + 1) & ": " & chain & "\n")
  if result.endsWith("\n"):
    result.setLen(result.len - 1)

{.pop.}

proc buildGraph*(
    modules: seq[string],
    getImports: proc(module: string): seq[string]
): ModuleGraph =
  ## Build a ``ModuleGraph`` from a list of module paths.
  ##
  ## *getImports* is a callback that, given a module path, returns the
  ## list of module paths it imports.
  result.nodes = modules
  for m in modules:
    result.adjList[m] = getImports(m)
