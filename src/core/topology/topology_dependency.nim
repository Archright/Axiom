import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/algorithm
import std/sequtils
import std/tables
import std/sets
import core/topology/topology_types
import core/sorter/sorter_core
import ../../core/trusted/axiom_pragmas

# Auto-split from topology_engine.nim — dependency analysis + metrics
func resolveCallTarget*(
  symbols: seq[TopologySymbol];
  nameIndex: Table[string, seq[int]];
  modulePath: string;
  targetName: string
): ResolutionResult =
  let candidates = nameIndex.getOrDefault(targetName)
  if candidates.len == 0:
    return ResolutionResult(kind: rrUnresolved)
  let sameModule = candidates.filterIt(symbols[it].modulePath == modulePath)
  if sameModule.len == 1:
    return ResolutionResult(kind: rrUnique, resolvedIdx: sameModule[0])
  if sameModule.len > 1:
    return ResolutionResult(kind: rrAmbiguous, candidates: sameModule)
  # sameModule.len == 0 → no candidate in this module
  return ResolutionResult(kind: rrUnresolved)

func computeInterfaceDistances*(
  nodes: seq[SorterNode];
  symbols: seq[TopologySymbol];
  symbolIndexTable: Table[string, int]
): seq[int] {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (seq.len nodes) 0) (>= (seq.len symbols) 0) (< dependencyIdx 0) (< cursor (str.len queue)) (and (>= cursor 0) (< cursor queue)) (>= symbols 0) (>= result 0)))
  ## axiom-lean: nodes.size ≥ 0 ∧ symbols.size ≥ 0 ∧ dependencyIdx < 0 ∧ cursor < queue.length ∧ ((cursor ≥ 0) ∧ (cursor < queue)) ∧ (symbols ≥ 0) ∧ (result ≥ 0)
  let unreachableDistance = nodes.len + 1
  result = newSeq[int](nodes.len)
  for idx in 0 ..< result.len:
    result[idx] = unreachableDistance
  var queue: seq[int] = @[]
  var cursor = 0
  for idx, symbol in symbols:
    if symbol.boundaryKind == topologyBoundaryInterface:
      result[idx] = 0
      queue.add(idx)
  while cursor < queue.len:
    let nodeIdx = queue[cursor]
    inc cursor
    let nextDistance = result[nodeIdx] + 1
    for dependencyId in nodes[nodeIdx].dependencyIds:
      let dependencyIdx = symbolIndexTable.getOrDefault(sorterNodeIdString(dependencyId), -1)
      if dependencyIdx < 0:
        continue
      if nextDistance < result[dependencyIdx]:
        result[dependencyIdx] = nextDistance
        queue.add(dependencyIdx)

  ## axiom-smt: (assert (and (>= (seq.len nodes) 0) (>= dependencyIdx 0) (>= nodes 0) (>= nodeIndex 0) (>= result 0)))
  ## axiom-lean: nodes.size ≥ 0 ∧ dependencyIdx ≥ 0 ∧ (nodes ≥ 0) ∧ (nodeIndex ≥ 0) ∧ (result ≥ 0)
func computeDependents*(nodes: seq[SorterNode]): seq[seq[int]] {.axiomTryImpl.} =
  var nodeIndex: Table[string, int]
  for idx, node in nodes:
    nodeIndex[sorterNodeIdString(node.id)] = idx
  result = newSeq[seq[int]](nodes.len)
  for idx, node in nodes:
    for dependencyId in node.dependencyIds:
      let dependencyKey = sorterNodeIdString(dependencyId)
      let dependencyIdx = nodeIndex.getOrDefault(dependencyKey, -1)
      if dependencyIdx >= 0:
        result[dependencyIdx].add(idx)

func traverseDependentClosure(
  dependents: seq[seq[int]];
  active: int;
  ctx: var TopologyTraversalContext;
  closure: var seq[int]
) =
  if active < 0 or active >= dependents.len:
    return
  if active in ctx.visited:
    return
  assert active notin ctx.inFlight,
    "[TOPOLOGY ERROR] Traversal lock re-entry detected: node-index=" & $active
  ctx.inFlight.incl(active)
  ctx.visited.incl(active)
  closure.add(active)
  for next in dependents[active]:
    traverseDependentClosure(dependents, next, ctx, closure)
  ctx.inFlight.excl(active)

  ## axiom-smt: (assert (= (set.len ctx.inFlight) 0))
  ## axiom-lean: ctx.inFlight.len = 0
func verifyEngineQuiescence*(ctx: TopologyTraversalContext) {.axiomTryImpl.} =
  assert ctx.inFlight.len == 0,
    "[TOPOLOGY LEAK] Managed phase lock leak detected: " & $ctx.inFlight

func collectTransitiveDependentsMemo*(
  dependents: seq[seq[int]];
  startIdx: int;
  memo: var Table[int, seq[int]]
): seq[int] {.axiomTryImpl.} =
  ## Memoized transitive closure — iterative DFS, O(N+E) amortized across all calls.
  ## Replaces recursive traverseDependentClosure with stack-based DFS + memo table.
  if startIdx in memo:
    return memo.getOrDefault(startIdx)
  var visited = initHashSet[int]()
  var stack: seq[int] = @[]
  for dep in dependents[startIdx]:
    if dep notin visited:
      stack.add(dep)
  while stack.len > 0:
    let node = stack.pop()
    if node in visited:
      continue
    if node < 0 or node >= dependents.len:
      continue
    visited.incl(node)
    result.add(node)
    for next in dependents[node]:
      if next notin visited:
        stack.add(next)
  memo[startIdx] = result

func proximityScore(interfaceDistance: int; nodeCount: int): int {.
  axiomTryImpl,
  axiom: [pre: (interfaceDistance >= 0 and nodeCount >= 0),
          post: (result >= 0 and result <= 60)]
.} =
  if interfaceDistance > nodeCount:
    return 0
  60 div (interfaceDistance + 1)

func buildMetric*(
  node: SorterNode;
  symbol: TopologySymbol;
  interfaceDistance: int;
  dependentCount: int;
  transitiveDependentCount: int;
  nodeCount: int
): TopologyNodeMetric {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (str.len symbol_modulePath) 0) (>= (str.len symbol_functionName) 0) (and (>= symbol_declarationLine -9223372036854775808) (<= symbol_declarationLine 9223372036854775807)) (and (>= symbol_bodyStartLine -9223372036854775808) (<= symbol_bodyStartLine 9223372036854775807)) (and (>= symbol_bodyEndLine -9223372036854775808) (<= symbol_bodyEndLine 9223372036854775807)) (or (= symbol_exported true) (= symbol_exported false)) (>= (seq.len symbol_rawCallTargets) 0) (and (>= symbol_branchCount -9223372036854775808) (<= symbol_branchCount 9223372036854775807)) (and (>= symbol_nestingDepth -9223372036854775808) (<= symbol_nestingDepth 9223372036854775807)) (and (>= symbol_lineSpan -9223372036854775808) (<= symbol_lineSpan 9223372036854775807)) (and (>= interfaceDistance -9223372036854775808) (<= interfaceDistance 9223372036854775807)) (and (>= dependentCount -9223372036854775808) (<= dependentCount 9223372036854775807)) (and (>= transitiveDependentCount -9223372036854775808) (<= transitiveDependentCount 9223372036854775807)) (and (>= nodeCount -9223372036854775808) (<= nodeCount 9223372036854775807)) (or (= symbol_exported true) (= symbol_exported false))))
  ## axiom-lean: symbol_modulePath.length ≥ 0 ∧ symbol_functionName.length ≥ 0 ∧ symbol_declarationLine ≥ -9223372036854775808 ∧ symbol_declarationLine ≤ 9223372036854775807 ∧ symbol_bodyStartLine ≥ -9223372036854775808 ∧ symbol_bodyStartLine ≤ 9223372036854775807 ∧ symbol_bodyEndLine ≥ -9223372036854775808 ∧ symbol_bodyEndLine ≤ 9223372036854775807 ∧ symbol_exported = true ∨ symbol_exported = false ∧ symbol_rawCallTargets.size ≥ 0 ∧ symbol_branchCount ≥ -9223372036854775808 ∧ symbol_branchCount ≤ 9223372036854775807 ∧ symbol_nestingDepth ≥ -9223372036854775808 ∧ symbol_nestingDepth ≤ 9223372036854775807 ∧ symbol_lineSpan ≥ -9223372036854775808 ∧ symbol_lineSpan ≤ 9223372036854775807 ∧ interfaceDistance ≥ -9223372036854775808 ∧ interfaceDistance ≤ 9223372036854775807 ∧ dependentCount ≥ -9223372036854775808 ∧ dependentCount ≤ 9223372036854775807 ∧ transitiveDependentCount ≥ -9223372036854775808 ∧ transitiveDependentCount ≤ 9223372036854775807 ∧ nodeCount ≥ -9223372036854775808 ∧ nodeCount ≤ 9223372036854775807 ∧ symbol_exported = true ∨ symbol_exported = false
  let dependencyCount = node.dependencyIds.len
  let branchDensityBonus =
    if symbol.lineSpan <= 0:
      0
    else:
      min(12, (symbol.branchCount * 20) div symbol.lineSpan)
  let complexityScore =
    symbol.branchCount * 8 +
    symbol.nestingDepth * 10 +
    branchDensityBonus
  let centralityScore =
    dependentCount * 14 +
    dependencyCount * 5 +
    transitiveDependentCount * 6
  let couplingScore =
    dependentCount * 6 +
    dependencyCount * 4 +
    transitiveDependentCount * 3
  let rawWeight = symbol.branchCount.float * 0.3 + symbol.nestingDepth.float * 0.2 + symbol.lineSpan.float * 0.1 + interfaceDistance.float * 0.4
  TopologyNodeMetric(
    nodeId: node.id,
    interfaceDistance: interfaceDistance,
    dependencyCount: dependencyCount,
    dependentCount: dependentCount,
    transitiveDependentCount: transitiveDependentCount,
    couplingScore: couplingScore,
    centralityScore: centralityScore,
    complexityScore: complexityScore,
    topologyScore: proximityScore(interfaceDistance, nodeCount) + centralityScore + complexityScore,
    branchCount: symbol.branchCount,
    nestingDepth: symbol.nestingDepth,
    lineSpan: symbol.lineSpan,
    logicalDepth: symbol.branchCount + symbol.nestingDepth,
    semanticWeight: rawWeight
  )

func compareMetricPriority(
  left: TopologyNodeMetric;
  right: TopologyNodeMetric;
  nodeCount: int
): int {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (and (>= left_interfaceDistance -9223372036854775808) (<= left_interfaceDistance 9223372036854775807)) (and (>= left_dependencyCount -9223372036854775808) (<= left_dependencyCount 9223372036854775807)) (and (>= left_dependentCount -9223372036854775808) (<= left_dependentCount 9223372036854775807)) (and (>= left_transitiveDependentCount -9223372036854775808) (<= left_transitiveDependentCount 9223372036854775807)) (and (>= left_couplingScore -9223372036854775808) (<= left_couplingScore 9223372036854775807)) (and (>= left_centralityScore -9223372036854775808) (<= left_centralityScore 9223372036854775807)) (and (>= left_complexityScore -9223372036854775808) (<= left_complexityScore 9223372036854775807)) (and (>= left_topologyScore -9223372036854775808) (<= left_topologyScore 9223372036854775807)) (and (>= left_branchCount -9223372036854775808) (<= left_branchCount 9223372036854775807)) (and (>= left_nestingDepth -9223372036854775808) (<= left_nestingDepth 9223372036854775807)) (and (>= left_lineSpan -9223372036854775808) (<= left_lineSpan 9223372036854775807)) (and (>= left_logicalDepth -9223372036854775808) (<= left_logicalDepth 9223372036854775807)) (and (>= right_interfaceDistance -9223372036854775808) (<= right_interfaceDistance 9223372036854775807)) (and (>= right_dependencyCount -9223372036854775808) (<= right_dependencyCount 9223372036854775807)) (and (>= right_dependentCount -9223372036854775808) (<= right_dependentCount 9223372036854775807)) (and (>= right_transitiveDependentCount -9223372036854775808) (<= right_transitiveDependentCount 9223372036854775807)) (and (>= right_couplingScore -9223372036854775808) (<= right_couplingScore 9223372036854775807)) (and (>= right_centralityScore -9223372036854775808) (<= right_centralityScore 9223372036854775807)) (and (>= right_complexityScore -9223372036854775808) (<= right_complexityScore 9223372036854775807)) (and (>= right_topologyScore -9223372036854775808) (<= right_topologyScore 9223372036854775807)) (and (>= right_branchCount -9223372036854775808) (<= right_branchCount 9223372036854775807)) (and (>= right_nestingDepth -9223372036854775808) (<= right_nestingDepth 9223372036854775807)) (and (>= right_lineSpan -9223372036854775808) (<= right_lineSpan 9223372036854775807)) (and (>= right_logicalDepth -9223372036854775808) (<= right_logicalDepth 9223372036854775807)) (and (>= nodeCount -9223372036854775808) (<= nodeCount 9223372036854775807)) (not (= leftReachable rightReachable))))
  ## axiom-lean: left_interfaceDistance ≥ -9223372036854775808 ∧ left_interfaceDistance ≤ 9223372036854775807 ∧ left_dependencyCount ≥ -9223372036854775808 ∧ left_dependencyCount ≤ 9223372036854775807 ∧ left_dependentCount ≥ -9223372036854775808 ∧ left_dependentCount ≤ 9223372036854775807 ∧ left_transitiveDependentCount ≥ -9223372036854775808 ∧ left_transitiveDependentCount ≤ 9223372036854775807 ∧ left_couplingScore ≥ -9223372036854775808 ∧ left_couplingScore ≤ 9223372036854775807 ∧ left_centralityScore ≥ -9223372036854775808 ∧ left_centralityScore ≤ 9223372036854775807 ∧ left_complexityScore ≥ -9223372036854775808 ∧ left_complexityScore ≤ 9223372036854775807 ∧ left_topologyScore ≥ -9223372036854775808 ∧ left_topologyScore ≤ 9223372036854775807 ∧ left_branchCount ≥ -9223372036854775808 ∧ left_branchCount ≤ 9223372036854775807 ∧ left_nestingDepth ≥ -9223372036854775808 ∧ left_nestingDepth ≤ 9223372036854775807 ∧ left_lineSpan ≥ -9223372036854775808 ∧ left_lineSpan ≤ 9223372036854775807 ∧ left_logicalDepth ≥ -9223372036854775808 ∧ left_logicalDepth ≤ 9223372036854775807 ∧ right_interfaceDistance ≥ -9223372036854775808 ∧ right_interfaceDistance ≤ 9223372036854775807 ∧ right_dependencyCount ≥ -9223372036854775808 ∧ right_dependencyCount ≤ 9223372036854775807 ∧ right_dependentCount ≥ -9223372036854775808 ∧ right_dependentCount ≤ 9223372036854775807 ∧ right_transitiveDependentCount ≥ -9223372036854775808 ∧ right_transitiveDependentCount ≤ 9223372036854775807 ∧ right_couplingScore ≥ -9223372036854775808 ∧ right_couplingScore ≤ 9223372036854775807 ∧ right_centralityScore ≥ -9223372036854775808 ∧ right_centralityScore ≤ 9223372036854775807 ∧ right_complexityScore ≥ -9223372036854775808 ∧ right_complexityScore ≤ 9223372036854775807 ∧ right_topologyScore ≥ -9223372036854775808 ∧ right_topologyScore ≤ 9223372036854775807 ∧ right_branchCount ≥ -9223372036854775808 ∧ right_branchCount ≤ 9223372036854775807 ∧ right_nestingDepth ≥ -9223372036854775808 ∧ right_nestingDepth ≤ 9223372036854775807 ∧ right_lineSpan ≥ -9223372036854775808 ∧ right_lineSpan ≤ 9223372036854775807 ∧ right_logicalDepth ≥ -9223372036854775808 ∧ right_logicalDepth ≤ 9223372036854775807 ∧ nodeCount ≥ -9223372036854775808 ∧ nodeCount ≤ 9223372036854775807 ∧ leftReachable ≠ rightReachable
  let leftReachable = left.interfaceDistance <= nodeCount
  let rightReachable = right.interfaceDistance <= nodeCount
  if leftReachable != rightReachable:
    return cmp(ord(rightReachable), ord(leftReachable))
  if left.interfaceDistance != right.interfaceDistance:
    return cmp(left.interfaceDistance, right.interfaceDistance)
  if left.complexityScore != right.complexityScore:
    return cmp(left.complexityScore, right.complexityScore)
  if left.topologyScore != right.topologyScore:
    return cmp(right.topologyScore, left.topologyScore)
  if left.couplingScore != right.couplingScore:
    return cmp(right.couplingScore, left.couplingScore)
  result = cmp(sorterNodeIdString(left.nodeId), sorterNodeIdString(right.nodeId))

  ## axiom-smt: (assert (and (>= (seq.len metrics) 0) (and (>= left -9223372036854775808) (<= left 9223372036854775807)) (and (>= right -9223372036854775808) (<= right 9223372036854775807)) (< (str.len result) 2) result (=> (< (str.len result) 2) (= result result)) (>= result 0)))
  ## axiom-lean: metrics.size ≥ 0 ∧ left ≥ -9223372036854775808 ∧ left ≤ 9223372036854775807 ∧ right ≥ -9223372036854775808 ∧ right ≤ 9223372036854775807 ∧ result.length < 2 ∧ result ∧ result.length < 2 → result = result ∧ (result ≥ 0)
func sortMetricIndices*(metrics: seq[TopologyNodeMetric]): seq[int] {.axiomTryImpl.} =
  result = newSeq[int](metrics.len)
  for idx in 0 ..< metrics.len:
    result[idx] = idx
  if result.len < 2:
    return result
  result.sort(proc(left: int; right: int): int =
    compareMetricPriority(metrics[left], metrics[right], metrics.len)
  )

  ## axiom-smt: (assert (and (>= (seq.len metrics) 0) (and (>= left -9223372036854775808) (<= left 9223372036854775807)) (and (>= right -9223372036854775808) (<= right 9223372036854775807)) (< (str.len result) 2) result (=> (< (str.len result) 2) (= result result)) (>= result 0)))
  ## axiom-lean: metrics.size ≥ 0 ∧ left ≥ -9223372036854775808 ∧ left ≤ 9223372036854775807 ∧ right ≥ -9223372036854775808 ∧ right ≤ 9223372036854775807 ∧ result.length < 2 ∧ result ∧ result.length < 2 → result = result ∧ (result ≥ 0)
func sortByCoupling*(metrics: seq[TopologyNodeMetric]): seq[int] {.axiomTryImpl.} =
  result = newSeq[int](metrics.len)
  for idx in 0 ..< metrics.len:
    result[idx] = idx
  if result.len < 2:
    return result
  result.sort(proc(left: int; right: int): int =
    let leftMetric = metrics[left]
    let rightMetric = metrics[right]
    if leftMetric.couplingScore != rightMetric.couplingScore:
      return cmp(rightMetric.couplingScore, leftMetric.couplingScore)
    if leftMetric.topologyScore != rightMetric.topologyScore:
      return cmp(rightMetric.topologyScore, leftMetric.topologyScore)
    cmp(sorterNodeIdString(leftMetric.nodeId), sorterNodeIdString(rightMetric.nodeId))
  )

  ## axiom-smt: (assert (and (>= (seq.len metrics) 0) (and (>= left -9223372036854775808) (<= left 9223372036854775807)) (and (>= right -9223372036854775808) (<= right 9223372036854775807)) (< (str.len result) 2) (not (= leftPriority rightPriority)) result (=> (< (str.len result) 2) (= result result)) (>= result 0)))
  ## axiom-lean: metrics.size ≥ 0 ∧ left ≥ -9223372036854775808 ∧ left ≤ 9223372036854775807 ∧ right ≥ -9223372036854775808 ∧ right ≤ 9223372036854775807 ∧ result.length < 2 ∧ leftPriority ≠ rightPriority ∧ result ∧ result.length < 2 → result = result ∧ (result ≥ 0)
func sortByRepairPriority*(metrics: seq[TopologyNodeMetric]): seq[int] {.axiomTryImpl.} =
  result = newSeq[int](metrics.len)
  for idx in 0 ..< metrics.len:
    result[idx] = idx
  if result.len < 2:
    return result
  result.sort(proc(left: int; right: int): int =
    let leftMetric = metrics[left]
    let rightMetric = metrics[right]
    let leftPriority =
      leftMetric.complexityScore + leftMetric.couplingScore + proximityScore(leftMetric.interfaceDistance, metrics.len)
    let rightPriority =
      rightMetric.complexityScore + rightMetric.couplingScore + proximityScore(rightMetric.interfaceDistance, metrics.len)
    if leftPriority != rightPriority:
      return cmp(rightPriority, leftPriority)
    if leftMetric.logicalDepth != rightMetric.logicalDepth:
      return cmp(rightMetric.logicalDepth, leftMetric.logicalDepth)
    cmp(sorterNodeIdString(leftMetric.nodeId), sorterNodeIdString(rightMetric.nodeId))
  )

## Build Topology Analysis.
{.pop.}
