import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## DependencySlicer — Downward dynamic slicing for incremental topology analysis.
## Given target symbols and a call-graph, computes the transitive closure of
## dependents (symbols that would be affected by changes to the targets).
## Returns only the minimal slice needed for re-verification.

import core/sorter/sorter_core
import core/topology/topology_types
import std/tables
import std/sets

func computeDependencySlice*(
  targetNodeIds: seq[SorterNodeId];
  analysis: TopologyAnalysis
): seq[SorterNodeId] =
  ## Compute transitive closure of dependents for target symbols.
  ## "Downward" = symbols that depend on the targets (affected by changes).
  ## BFS from targets following reverse dependency edges.
  ## Returns the complete affected slice including targets themselves.
  if targetNodeIds.len == 0 or analysis.metrics.len == 0:
    return targetNodeIds

  # Build reverse adjacency: nodeId_string → set of nodeIds that depend on it
  var dependents = initTable[string, seq[SorterNodeId]]()
  for symbol in analysis.symbols:
    for rawTarget in symbol.rawCallTargets:
      # Find which node this raw target resolves to
      for depSymbol in analysis.symbols:
        if depSymbol.functionName == rawTarget or
           depSymbol.nodeId == sorterNodeId(rawTarget):
          let depKey = sorterNodeIdString(depSymbol.nodeId)
          dependents.mgetOrPut(depKey, @[]).add(symbol.nodeId)
          break

  # BFS from targets
  var visited = initHashSet[string]()
  var queue: seq[SorterNodeId] = @[]

  for target in targetNodeIds:
    let key = sorterNodeIdString(target)
    if key notin visited:
      visited.incl(key)
      queue.add(target)

  var head = 0
  while head < queue.len:
    let current = queue[head]
    head += 1
    let currentKey = sorterNodeIdString(current)
    let deps = dependents.getOrDefault(currentKey, @[])
    for dep in deps:
        let depKey = sorterNodeIdString(dep)
        if depKey notin visited:
          visited.incl(depKey)
          queue.add(dep)

  queue

func findSymbolsForFiles*(
  changedFiles: seq[string];
  engineCache: Table[string, seq[string]]
): seq[string] =
  ## Given a list of changed file paths, return all symbol names
  ## that were defined in those files.
  ## Uses the symbolToFiles reverse index from MerkleQueryEngine.
  var resultNames: seq[string] = @[]
  var seen = initHashSet[string]()
  for symName, files in engineCache:
    for changedFile in changedFiles:
      if changedFile in files:
        if symName notin seen:
          seen.incl(symName)
          resultNames.add(symName)
        break
  resultNames

func findChangedSymbols*(
  oldSymbols: seq[string];
  newSymbols: seq[string]
): seq[string] =
  ## Compute the set difference: symbols in newSymbols but not in oldSymbols.
  ## Used to detect which functions were added or modified.
  var oldSet = initHashSet[string]()
  for s in oldSymbols:
    oldSet.incl(s)
  for s in newSymbols:
    if s notin oldSet:
      result.add(s)

{.pop.}
