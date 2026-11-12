import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/algorithm

import core/diagnostics/diagnostics_engine
import core/sorter/sorter_core

import core/orchestrator/orchestrator_types
import ../../core/trusted/axiom_pragmas

## Sort Work Items By Depth.
func sortWorkItemsByDepth*(
  workItems: seq[SorterWorkItem];
  impactIndexLookup: NodeImpactIndexLookup = nil
): seq[SorterWorkItem] {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (seq.len workItems) 0) (< (str.len result) 2) (not (= aImpact bImpact)) (= result workItems) result (- bImpact aImpact) (=> (< (str.len result) 2) (= result result)) (=> (not (= aImpact bImpact)) (= result (- bImpact aImpact))) (>= result 0)))
  ## axiom-lean: workItems.size ≥ 0 ∧ result.length < 2 ∧ aImpact ≠ bImpact ∧ result = workItems ∧ result ∧ bImpact - aImpact ∧ result.length < 2 → result = result ∧ aImpact ≠ bImpact → result = bImpact - aImpact ∧ (result ≥ 0)
  result = workItems
  if result.len < 2:
    return result
  sort(result, proc(a, b: SorterWorkItem): int {.noSideEffect, gcsafe, closure, raises: [].} =
    if a.dependencyDepth != b.dependencyDepth:
      return a.dependencyDepth - b.dependencyDepth
    let aImpact =
      if impactIndexLookup.isNil:
        0
      else:
        impactIndexLookup(a.nodeId)
    let bImpact =
      if impactIndexLookup.isNil:
        0
      else:
        impactIndexLookup(b.nodeId)
    if aImpact != bImpact:
      return bImpact - aImpact
    cmp(sorterNodeIdString(a.nodeId), sorterNodeIdString(b.nodeId))
  )

## Collect Impacted Branch Nodes.
  ## axiom-smt: (assert (and (>= depth 0) (< cursor (str.len queue)) (= dependsOnActive true) (>= dependsOnActive 0) (and (>= cursor 0) (< cursor queue))))
  ## axiom-lean: depth >= 0 ∧ cursor < queue.length ∧ dependsOnActive = true ∧ (dependsOnActive ≥ 0) ∧ ((cursor ≥ 0) ∧ (cursor < queue))
func collectImpactedBranchNodes*(state: SorterState; rootNodeId: SorterNodeId): seq[SorterNodeId] {.axiomTryImpl.} =
  var queue: seq[SorterNodeId] = @[rootNodeId]
  var cursor = 0
  while cursor < queue.len:
    let activeNodeId = queue[cursor]
    inc cursor
    for node in state.nodes:
      var dependsOnActive = false
      for dependencyId in node.dependencyIds:
        if nodeIdEquals(dependencyId, activeNodeId):
          dependsOnActive = true
          break
      if dependsOnActive and not containsNodeId(result, node.id):
        result.add(node.id)
        if not containsNodeId(queue, node.id):
          queue.add(node.id)

  ## axiom-smt: (assert (and (and (>= timeoutMs -9223372036854775808) (<= timeoutMs 9223372036854775807)) (< timeoutMs minDynamicTimeoutMs) (> timeoutMs maxDynamicTimeoutMs) minDynamicTimeoutMs maxDynamicTimeoutMs (=> (< timeoutMs minDynamicTimeoutMs) (= result minDynamicTimeoutMs)) (=> (> timeoutMs maxDynamicTimeoutMs) (= result maxDynamicTimeoutMs)) (>= maxDepth 0)))
  ## axiom-lean: timeoutMs ≥ -9223372036854775808 ∧ timeoutMs ≤ 9223372036854775807 ∧ timeoutMs < minDynamicTimeoutMs ∧ timeoutMs > maxDynamicTimeoutMs ∧ minDynamicTimeoutMs ∧ maxDynamicTimeoutMs ∧ timeoutMs < minDynamicTimeoutMs → result = minDynamicTimeoutMs ∧ timeoutMs > maxDynamicTimeoutMs → result = maxDynamicTimeoutMs ∧ (maxDepth ≥ 0)
func totalPlanDepths*(plan: SorterPlan): int {.axiomTryImpl.} =
  var maxDepth = 0
  for workItem in plan.workItems:
    if workItem.dependencyDepth > maxDepth:
      maxDepth = workItem.dependencyDepth
  result = maxDepth + 1

## Compute Parallel Worker Limit.
  ## axiom-smt: (assert (and (and (>= nodeCount -9223372036854775808) (<= nodeCount 9223372036854775807)) (and (>= processorCount -9223372036854775808) (<= processorCount 9223372036854775807)) (> processorCount 2) (<= nodeCount 0) (< usableCores nodeCount) 1 usableCores (=> (<= nodeCount 0) (= result 1)) (=> (< usableCores nodeCount) (= result usableCores))))
  ## axiom-lean: nodeCount ≥ -9223372036854775808 ∧ nodeCount ≤ 9223372036854775807 ∧ processorCount ≥ -9223372036854775808 ∧ processorCount ≤ 9223372036854775807 ∧ processorCount > 2 ∧ nodeCount ≤ 0 ∧ usableCores < nodeCount ∧ 1 ∧ usableCores ∧ nodeCount ≤ 0 → result = 1 ∧ usableCores < nodeCount → result = usableCores
func computeParallelWorkerLimit*(nodeCount: int; processorCount: int): int {.axiomTryImpl.} =
  let usableCores =
    if processorCount > 2:
      processorCount - 2
    else:
      1
  if nodeCount <= 0:
    return 1
  if usableCores < nodeCount:
    return usableCores
  result = nodeCount

## Compute Node Depths.
  ## axiom-smt: (assert (and (>= depth 0) (>= dependencyIdx 0) (< cursor (str.len queue)) (>= indegree 0) (and (>= cursor 0) (< cursor queue)) (>= result 0)))
  ## axiom-lean: depth >= 0 ∧ dependencyIdx ≥ 0 ∧ cursor < queue.length ∧ (indegree ≥ 0) ∧ ((cursor ≥ 0) ∧ (cursor < queue)) ∧ (result ≥ 0)
func computeNodeDepths*(state: SorterState): seq[int] {.axiomTryImpl.} =
  let nodeCount = state.nodes.len
  var indegree = newSeq[int](nodeCount)
  var dependents = newSeq[seq[int]](nodeCount)
  var queue: seq[int] = @[]
  result = newSeq[int](nodeCount)
  let nodeIndexTable = buildNodeIndexTable(state)
  for idx, node in state.nodes:
    indegree[idx] = node.dependencyIds.len
    if indegree[idx] == 0:
      queue.add(idx)
    for dependencyId in node.dependencyIds:
      let dependencyIdx = findNodeIndex(nodeIndexTable, dependencyId)
      if dependencyIdx >= 0:
        dependents[dependencyIdx].add(idx)
  var cursor = 0
  while cursor < queue.len:
    let nodeIdx = queue[cursor]
    inc cursor
    for dependentIdx in dependents[nodeIdx]:
      let nextDepth = result[nodeIdx] + 1
      if nextDepth > result[dependentIdx]:
        result[dependentIdx] = nextDepth
      dec indegree[dependentIdx]
      if indegree[dependentIdx] == 0:
        queue.add(dependentIdx)

## Collect Topological Node Indices.
  ## axiom-smt: (assert (and (>= depth 0) (>= dependencyIdx 0) (< cursor (str.len queue)) (>= indegree 0) (and (>= cursor 0) (< cursor queue))))
  ## axiom-lean: depth >= 0 ∧ dependencyIdx ≥ 0 ∧ cursor < queue.length ∧ (indegree ≥ 0) ∧ ((cursor ≥ 0) ∧ (cursor < queue))
func collectTopologicalNodeIndices*(state: SorterState): seq[int] {.axiomTryImpl.} =
  let nodeCount = state.nodes.len
  var indegree = newSeq[int](nodeCount)
  var dependents = newSeq[seq[int]](nodeCount)
  var queue: seq[int] = @[]
  let nodeIndexTable = buildNodeIndexTable(state)
  for idx, node in state.nodes:
    indegree[idx] = node.dependencyIds.len
    if indegree[idx] == 0:
      queue.add(idx)
    for dependencyId in node.dependencyIds:
      let dependencyIdx = findNodeIndex(nodeIndexTable, dependencyId)
      if dependencyIdx >= 0:
        dependents[dependencyIdx].add(idx)
  var cursor = 0
  while cursor < queue.len:
    let nodeIdx = queue[cursor]
    inc cursor
    result.add(nodeIdx)
    for dependentIdx in dependents[nodeIdx]:
      dec indegree[dependentIdx]
      if indegree[dependentIdx] == 0:
        queue.add(dependentIdx)

## Compute Total Depths.
  ## axiom-smt: (assert (and (>= (seq.len depths) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len depths))) (and (>= (seq.nth depths i) -9223372036854775808) (<= (seq.nth depths i) 9223372036854775807)))) (> dependencyDepth maxDepth) (= maxDepth dependencyDepth) (>= maxDepth 0) (>= depths 0)))
  ## axiom-lean: depths.size ≥ 0 ∧ ∀ (i : Fin depths.size), (depths.get i) ≥ -9223372036854775808 ∧ (depths.get i) ≤ 9223372036854775807 ∧ dependencyDepth > maxDepth ∧ maxDepth = dependencyDepth ∧ (maxDepth ≥ 0) ∧ (depths ≥ 0)
func computeTotalDepths*(depths: seq[int]): int {.axiomTryImpl.} =
  var maxDepth = 0
  for dependencyDepth in depths:
    if dependencyDepth > maxDepth:
      maxDepth = dependencyDepth
  result = maxDepth + 1

## Select Next Depth Items.
func selectNextDepthItems*(
  orderedWorkItems: seq[SorterWorkItem];
  handledNodes: seq[SorterNodeId]
): seq[SorterWorkItem] {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (seq.len orderedWorkItems) 0) (>= (seq.len handledNodes) 0) (< activeDepth 0) (>= activeDepth 0) (>= orderedWorkItems 0)))
  ## axiom-lean: orderedWorkItems.size ≥ 0 ∧ handledNodes.size ≥ 0 ∧ activeDepth < 0 ∧ (activeDepth ≥ 0) ∧ (orderedWorkItems ≥ 0)
  var activeDepth = -1
  for item in orderedWorkItems:
    if containsNodeId(handledNodes, item.nodeId):
      continue
    if activeDepth < 0:
      activeDepth = item.dependencyDepth
    if item.dependencyDepth != activeDepth:
      break
    result.add(item)

## Build Worker Node Report.
func buildWorkerNodeReport*(
  workItem: SorterWorkItem;
  status: OrchestrationNodeStatus;
  vaultPath: string;
  cacheHit: bool = false;
  diagnosis: TimeoutDiagnosis = emptyTimeoutDiagnosis();
  smtlib2: string = "";
  evidenceLogJson: string = "";
  assuranceTier: string = "";
  tierResolution: string = ""
): OrchestrationNodeReport {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (str.len vaultPath) 0) (or (= cacheHit true) (= cacheHit false)) (>= (str.len smtlib2) 0) (>= (str.len evidenceLogJson) 0) (or (= cacheHit true) (= cacheHit false))))
  ## axiom-lean: vaultPath.length ≥ 0 ∧ cacheHit = true ∨ cacheHit = false ∧ smtlib2.length ≥ 0 ∧ evidenceLogJson.length ≥ 0 ∧ cacheHit = true ∨ cacheHit = false
  result = OrchestrationNodeReport(
    nodeId: workItem.nodeId,
    dependencyDepth: workItem.dependencyDepth,
    usesDependencyVault: workItem.usesDependencyVault,
    readsDependencySource: workItem.readsDependencySource,
    injectedAxioms: workItem.dependencyAxioms,
    status: status,
    vaultPath: vaultPath,
    cacheHit: cacheHit,
    remediationHint: diagnosis.remediationHint,
    mathematicalRationale: diagnosis.mathematicalRationale,
    timeoutComplexityWeight: diagnosis.complexityWeight,
    timeoutHotspots: diagnosis.hotspots,
    selfHealingGuidance: diagnosis.selfHealingGuidance,
    smtlib2: smtlib2,
    evidenceLogJson: evidenceLogJson,
    assuranceTier: assuranceTier,
    tierResolution: tierResolution
  )

## Emit Progress.
{.pop.}
