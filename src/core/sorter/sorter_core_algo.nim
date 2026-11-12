import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import core/sorter/sorter_core_index_base
import core/sorter/sorter_core_index_table
import core/vault/vault_manager_spec
import core/vault/vault_manager_storage
import core/types/results
import std/os
import std/strutils
import std/tables
import core/trusted/axiom_pragmas

## Cascade Stale Dependents — Phase 10 Cascading Sort Defense.
## BFS through reverse dependency graph marking all reachable nodes stale.
## When node X is invalid, every node Y that transitively depends on X
## must also be invalidated — its vault axiom chain is corrupted.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func cascadeStaleDependents*(state: var SorterState; nodeId: SorterNodeId) =
  let dependentsGraph = buildDependentsGraph(state)
  var visited = initTable[string, bool]()
  var queue = @[nodeId]
  while queue.len > 0:
    let current = queue[^1]
    queue.setLen(queue.len - 1)
    let key = sorterNodeIdString(current)
    if key in visited:
      continue
    visited[key] = true
    let idx = findNodeIndex(state, current)
    if idx >= 0 and (not state.nodes[idx].isStale):
      state.nodes[idx].isStale = true
      state.nodes[idx].astResidency = astResident
    let depList = dependentsGraph.getOrDefault(key, @[])
    for dep in depList:
      if dep notin visited:
        queue.add(sorterNodeId(dep))

## Set Node Stale.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func setNodeStale*(
  state: var SorterState;
  nodeId: SorterNodeId;
  isStale: bool
) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let nodeIdx = findNodeIndex(state, nodeId)
  if nodeIdx < 0:
    return
  state.nodes[nodeIdx].isStale = isStale
  if isStale:
    state.nodes[nodeIdx].astResidency = astResident
    ## Phase 10 Cascading Sort Defense: propagate stale to all transitive dependents.
    cascadeStaleDependents(state, nodeId)
  elif hasVaultEntry(state, nodeId):
    state.nodes[nodeIdx].astResidency = astReleased

## Promote Node To Vault.
# @axiom-hint: lean="state_nodes.size ≥ 0 ∧ state_vaultEntries.size ≥ 0 ∧ state_vaultIntegrityBlocks.size ≥ 0" smt="(assert (and (>= (seq.len state_nodes) 0) (>= (seq.len state_vaultEntries) 0) (>= (seq.len state_vaultIntegrityBlocks) 0)))"
# @axiom-hint: lean="nodeIdx ≥ 0 ∧ vaultIdx ≥ 0 ∧ blockIdx ≥ 0 ∧ result = state ∧ (isStale ≥ 0) ∧ (result ≥ 0) ∧ (astResidency ≥ 0)" smt="(assert (and (>= nodeIdx 0) (>= vaultIdx 0) (>= blockIdx 0) (= result state) (>= isStale 0) (>= result 0) (>= astResidency 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func promoteNodeToVault*(
  state: var SorterState;
  nodeId: SorterNodeId;
  axiom: AxiomFormula
) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let nodeIdx = findNodeIndex(state, nodeId)
  if nodeIdx >= 0:
    state.nodes[nodeIdx].astResidency = astReleased
    state.nodes[nodeIdx].isStale = false
  let vaultIdx = findVaultEntryIndex(state, nodeId)
  if vaultIdx >= 0:
    state.vaultEntries[vaultIdx] = makeVaultEntry(nodeId, axiom)
  else:
    state.vaultEntries.add(makeVaultEntry(nodeId, axiom))
  let blockIdx = findVaultIntegrityBlockIndex(state, nodeId)
  if blockIdx >= 0:
    state.vaultIntegrityBlocks.delete(blockIdx)

## Build Sorter Plan.
# @axiom-hint: lean="state_nodes.size ≥ 0 ∧ state_vaultEntries.size ≥ 0 ∧ state_vaultIntegrityBlocks.size ≥ 0" smt="(assert (and (>= (seq.len state_nodes) 0) (>= (seq.len state_vaultEntries) 0) (>= (seq.len state_vaultIntegrityBlocks) 0)))"
# @axiom-hint: lean="dependencyIdx ≥ 0 ∧ blockedByDependency ∧ cursor < queue.length ∧ blockedByDependency = true ∧ (processed ≥ 0) ∧ (executable ≥ 0) ∧ (indegree ≥ 0) ∧ ((cursor ≥ 0) ∧ (cursor < queue)) ∧ (blockedByDependency ≥ 0) ∧ (dependencyDepth ≥ 0)" smt="(assert (and (>= dependencyIdx 0) blockedByDependency (< cursor (str.len queue)) (= blockedByDependency true) (>= processed 0) (>= executable 0) (>= indegree 0) (and (>= cursor 0) (< cursor queue)) (>= blockedByDependency 0) (>= dependencyDepth 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildSorterPlan*(state: SorterState): SorterPlan =
  let nodeCount = state.nodes.len
  var indegree = newSeq[int](nodeCount)
  var dependencyDepth = newSeq[int](nodeCount)
  var dependents = newSeq[seq[int]](nodeCount)
  var queue: seq[int] = @[]
  var processed = newSeq[bool](nodeCount)
  var executable = newSeq[bool](nodeCount)
  let nodeIndexTable = buildNodeIndexTable(state)
  let vaultEntryIndexTable = buildVaultEntryIndexTable(state)
  let vaultIntegrityBlockIndexTable = buildVaultIntegrityBlockIndexTable(state)

  for idx, node in state.nodes:
    indegree[idx] = node.dependencyIds.len
    if indegree[idx] == 0:
      queue.add(idx)
    for dependencyId in node.dependencyIds:
      let dependencyIdx = findNodeIndex(nodeIndexTable, dependencyId)
      if dependencyIdx >= 0:
        addDependentEdge(dependents, dependencyIdx, idx)

  var cursor = 0
  while cursor < queue.len:
    let nodeIdx = queue[cursor]
    inc cursor
    processed[nodeIdx] = true
    let node = state.nodes[nodeIdx]
    if node.isStale and hasVaultIntegrityBlock(vaultIntegrityBlockIndexTable, node.id):
      addUniqueReleasedNode(result.staleDependencyNodes, node.id)
    var blockedByDependency = false
    for dependencyId in node.dependencyIds:
      let dependencyIdx = findNodeIndex(nodeIndexTable, dependencyId)
      if dependencyIdx < 0 and not hasVaultEntry(vaultEntryIndexTable, dependencyId):
        blockedByDependency = true
      elif dependencyIdx >= 0 and not executable[dependencyIdx]:
        blockedByDependency = true
      elif dependencyIdx >= 0 and state.nodes[dependencyIdx].astResidency == astReleased and
          not hasVaultEntry(vaultEntryIndexTable, dependencyId):
        blockedByDependency = true
    if blockedByDependency:
      addUniqueReleasedNode(result.blockedNodes, node.id)
      if node.astResidency == astReleased:
        addUniqueReleasedNode(result.releasedAstNodes, node.id)
      for dependentIdx in dependents[nodeIdx]:
        let nextDepth = dependencyDepth[nodeIdx] + 1
        if nextDepth > dependencyDepth[dependentIdx]:
          dependencyDepth[dependentIdx] = nextDepth
        dec indegree[dependentIdx]
        if indegree[dependentIdx] == 0:
          queue.add(dependentIdx)
      continue
    let dependencyAxioms = collectDependencyAxioms(state, node, vaultEntryIndexTable)
    let usesDependencyVault = dependencyAxioms.len == node.dependencyIds.len and node.dependencyIds.len > 0
    executable[nodeIdx] = true
    if node.isStale or not hasVaultEntry(vaultEntryIndexTable, node.id):
      result.workItems.add(SorterWorkItem(
        nodeId: node.id,
        dependencyDepth: dependencyDepth[nodeIdx],
        ownSourceKind: sourceDetailedAst,
        usesDependencyVault: usesDependencyVault,
        readsDependencySource: node.dependencyIds.len > 0 and not usesDependencyVault,
        dependencyAxioms: dependencyAxioms
      ))
    if node.astResidency == astReleased:
      addUniqueReleasedNode(result.releasedAstNodes, node.id)
    for dependentIdx in dependents[nodeIdx]:
      let nextDepth = dependencyDepth[nodeIdx] + 1
      if nextDepth > dependencyDepth[dependentIdx]:
        dependencyDepth[dependentIdx] = nextDepth
      dec indegree[dependentIdx]
      if indegree[dependentIdx] == 0:
        queue.add(dependentIdx)

  for idx, node in state.nodes:
    if not processed[idx]:
      addUniqueReleasedNode(result.blockedNodes, node.id)
      if node.astResidency == astReleased:
        addUniqueReleasedNode(result.releasedAstNodes, node.id)

# @axiom-hint: lean="vaultPath.length ≥ 0" smt="(assert (and (>= (str.len vaultPath) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeVaultIntegrityBlock(
  nodeId: SorterNodeId;
  error: AxiomInvalidError;
  vaultPath: string
): VaultIntegrityBlock {.raises: [].} =
  VaultIntegrityBlock(nodeId: nodeId, error: error, vaultPath: vaultPath.strip())

## Sync Node Axiom From Vault.
# @axiom-hint: lean="state_nodes.size ≥ 0 ∧ state_vaultEntries.size ≥ 0 ∧ state_vaultIntegrityBlocks.size ≥ 0 ∧ vaultFilePath.length ≥ 0 ∧ currentFingerprint.length ≥ 0" smt="(assert (and (>= (seq.len state_nodes) 0) (>= (seq.len state_vaultEntries) 0) (>= (seq.len state_vaultIntegrityBlocks) 0) (>= (str.len vaultFilePath) 0) (>= (str.len currentFingerprint) 0)))"
# @axiom-hint: lean="existingVaultIdx ≥ 0 ∧ existingBlockIdx ≥ 0 ∧ result = state ∧ result ∧ (result ≥ 0)" smt="(assert (and (>= existingVaultIdx 0) (>= existingBlockIdx 0) (= result state) result (>= result 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc syncNodeAxiomFromVault*(
  state: var SorterState;
  nodeId: SorterNodeId;
  vaultFilePath: string;
  currentFingerprint: string
) {.raises: [].} =
  let existingVaultIdx = findVaultEntryIndex(state, nodeId)
  if existingVaultIdx >= 0:
    state.vaultEntries.delete(existingVaultIdx)
  let existingBlockIdx = findVaultIntegrityBlockIndex(state, nodeId)
  if existingBlockIdx >= 0:
    state.vaultIntegrityBlocks.delete(existingBlockIdx)
  let loadRes = loadAxiomSpecFile(vaultFilePath, currentFingerprint)
  if loadRes.isErr():
    setNodeStale(state, nodeId, true)
    if loadRes.error.kind == vaultLoadInvalidAxiom:
      state.vaultIntegrityBlocks.add(makeVaultIntegrityBlock(
        nodeId,
        loadRes.error.invalidError,
        vaultFilePath
      ))
    return
  promoteNodeToVault(state, nodeId, axiomFormula(loadRes.get().smtlib2))

## Verify Workflow Label From Node.
# @axiom-hint: lean="node_modulePath.length ≥ 0 ∧ node_functionName.length ≥ 0 ∧ node_dependencyIds.size ≥ 0 ∧ node_isStale = true ∨ node_isStale = false" smt="(assert (and (>= (str.len node_modulePath) 0) (>= (str.len node_functionName) 0) (>= (seq.len node_dependencyIds) 0) (or (= node_isStale true) (= node_isStale false))))"
# @axiom-hint: lean="node_isStale = true ∨ node_isStale = false" smt="(assert (and (or (= node_isStale true) (= node_isStale false))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func verifyWorkflowLabelFromNode*(node: SorterNode): string {.noSideEffect.} =
  let moduleName = extractFilename(node.modulePath)
  moduleName & "::" & node.functionName

## Verify Workflow Label From Node Id.
# @axiom-hint: lean="state_nodes.size ≥ 0 ∧ state_vaultEntries.size ≥ 0 ∧ state_vaultIntegrityBlocks.size ≥ 0" smt="(assert (and (>= (seq.len state_nodes) 0) (>= (seq.len state_vaultEntries) 0) (>= (seq.len state_vaultIntegrityBlocks) 0)))"
# @axiom-hint: lean="nodeIdx ≥ 0" smt="(assert (and (>= nodeIdx 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func verifyWorkflowLabelFromNodeId*(state: SorterState; nodeId: SorterNodeId): string {.noSideEffect.} =
  let nodeIdx = findNodeIndex(state, nodeId)
  if nodeIdx >= 0:
    return verifyWorkflowLabelFromNode(state.nodes[nodeIdx])
  let raw = sorterNodeIdString(nodeId)
  let parts = raw.split("::")
  if parts.len >= 2:
    return extractFilename(parts[0]) & "::" & parts[1]
  raw

{.pop.}
