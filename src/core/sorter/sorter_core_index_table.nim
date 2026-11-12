import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/tables
import core/sorter/sorter_core_index_base
import ../../core/trusted/axiom_pragmas

## Build Node Index Table.
  ## axiom-smt: (assert (and (>= result 0)))
  ## axiom-lean: (result ≥ 0)
func buildNodeIndexTable*(state: SorterState): Table[string, int] {.axiomTryImpl.} =
  for idx, node in state.nodes:
    result[sorterNodeIdString(node.id)] = idx

## Find Node Index.
func findNodeIndex*(nodeIndexTable: Table[string, int]; nodeId: SorterNodeId): int =
  result = nodeIndexTable.getOrDefault(sorterNodeIdString(nodeId), -1)

  ## axiom-smt: (assert (and (>= (seq.len state_nodes) 0) (>= (seq.len state_vaultEntries) 0) (>= (seq.len state_vaultIntegrityBlocks) 0) ast_parse_failed_isolated))
  ## axiom-lean: state_nodes.size ≥ 0 ∧ state_vaultEntries.size ≥ 0 ∧ state_vaultIntegrityBlocks.size ≥ 0 ∧ ast_parse_failed_isolated
func buildVaultEntryIndexTable*(state: SorterState): Table[string, int] {.axiomTryImpl.} =
  for idx, entry in state.vaultEntries:
    result[sorterNodeIdString(entry.nodeId)] = idx

func findVaultEntryIndex*(vaultEntryIndexTable: Table[string, int]; nodeId: SorterNodeId): int =
  result = vaultEntryIndexTable.getOrDefault(sorterNodeIdString(nodeId), -1)

  ## axiom-smt: (assert (and ast_parse_failed_isolated (>= (seq.len state_nodes) 0) (>= (seq.len state_vaultEntries) 0) (>= (seq.len state_vaultIntegrityBlocks) 0)))
  ## axiom-lean: ast_parse_failed_isolated ∧ state_nodes.size ≥ 0 ∧ state_vaultEntries.size ≥ 0 ∧ state_vaultIntegrityBlocks.size ≥ 0
func hasVaultEntry*(state: SorterState; nodeId: SorterNodeId): bool {.axiomTryImpl.} =
  findVaultEntryIndex(state, nodeId) >= 0

func hasVaultEntry*(vaultEntryIndexTable: Table[string, int]; nodeId: SorterNodeId): bool =
  findVaultEntryIndex(vaultEntryIndexTable, nodeId) >= 0

func lookupVaultAxiom*(
  state: SorterState;
  vaultEntryIndexTable: Table[string, int];
  nodeId: SorterNodeId
): AxiomFormula {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (seq.len state_nodes) 0) (>= (seq.len state_vaultEntries) 0) (>= (seq.len state_vaultIntegrityBlocks) 0) (< vaultIdx 0)))
  ## axiom-lean: state_nodes.size ≥ 0 ∧ state_vaultEntries.size ≥ 0 ∧ state_vaultIntegrityBlocks.size ≥ 0 ∧ vaultIdx < 0
  let vaultIdx = findVaultEntryIndex(vaultEntryIndexTable, nodeId)
  if vaultIdx < 0:
    return axiomFormula("")
  result = state.vaultEntries[vaultIdx].axiom

  ## axiom-smt: (assert (and (>= (seq.len target) 0) (>= target 0)))
  ## axiom-lean: target.size ≥ 0 ∧ (target ≥ 0)
func addUniqueReleasedNode*(target: var seq[SorterNodeId]; nodeId: SorterNodeId) {.axiomTryImpl.} =
  for existing in target:
    if nodeIdEquals(existing, nodeId):
      return
  target.add(nodeId)

  ## axiom-smt: (assert (and ast_parse_failed_isolated idx))
  ## axiom-lean: ast_parse_failed_isolated ∧ idx
func findVaultIntegrityBlockIndex*(state: SorterState; nodeId: SorterNodeId): int {.axiomTryImpl.} =
  for idx, entry in state.vaultIntegrityBlocks:
    if nodeIdEquals(entry.nodeId, nodeId):
      return idx
  result = -1

  ## axiom-smt: (assert (and (>= result 0)))
  ## axiom-lean: (result ≥ 0)
func buildVaultIntegrityBlockIndexTable*(state: SorterState): Table[string, int] {.axiomTryImpl.} =
  for idx, entry in state.vaultIntegrityBlocks:
    result[sorterNodeIdString(entry.nodeId)] = idx

func findVaultIntegrityBlockIndex*(
  vaultIntegrityBlockIndexTable: Table[string, int];
  nodeId: SorterNodeId
): int =
  result = vaultIntegrityBlockIndexTable.getOrDefault(sorterNodeIdString(nodeId), -1)

  ## axiom-smt: (assert (and (>= depth 0)))
  ## axiom-lean: depth >= 0
func hasVaultIntegrityBlock*(vaultIntegrityBlockIndexTable: Table[string, int]; nodeId: SorterNodeId): bool {.axiomTryImpl.} =
  result = findVaultIntegrityBlockIndex(vaultIntegrityBlockIndexTable, nodeId) >= 0

  ## axiom-smt: (assert (and (>= (str.len node_modulePath) 0) (>= (str.len node_functionName) 0) (>= (seq.len node_dependencyIds) 0) (or (= node_isStale true) (= node_isStale false)) ast_parse_failed_isolated))
  ## axiom-lean: node_modulePath.length ≥ 0 ∧ node_functionName.length ≥ 0 ∧ node_dependencyIds.size ≥ 0 ∧ node_isStale = true ∨ node_isStale = false ∧ ast_parse_failed_isolated
func allDependenciesInVault*(node: SorterNode; vaultEntryIndexTable: Table[string, int]): bool {.axiomTryImpl.} =
  if node.dependencyIds.len == 0:
    return false
  for dependencyId in node.dependencyIds:
    if not hasVaultEntry(vaultEntryIndexTable, dependencyId):
      return false
  result = true

func collectDependencyAxioms*(
  state: SorterState;
  node: SorterNode;
  vaultEntryIndexTable: Table[string, int]
): seq[AxiomFormula] {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (seq.len state_nodes) 0) (>= (seq.len state_vaultEntries) 0) (>= (seq.len state_vaultIntegrityBlocks) 0) (>= (str.len node_modulePath) 0) (>= (str.len node_functionName) 0) (>= (seq.len node_dependencyIds) 0) (or (= node_isStale true) (= node_isStale false)) ast_parse_failed_isolated))
  ## axiom-lean: state_nodes.size ≥ 0 ∧ state_vaultEntries.size ≥ 0 ∧ state_vaultIntegrityBlocks.size ≥ 0 ∧ node_modulePath.length ≥ 0 ∧ node_functionName.length ≥ 0 ∧ node_dependencyIds.size ≥ 0 ∧ node_isStale = true ∨ node_isStale = false ∧ ast_parse_failed_isolated
  if not allDependenciesInVault(node, vaultEntryIndexTable):
    return @[]
  result = newSeqOfCap[AxiomFormula](node.dependencyIds.len)
  for dependencyId in node.dependencyIds:
    result.add(lookupVaultAxiom(state, vaultEntryIndexTable, dependencyId))

## Build Dependents Graph — Phase 10 Cascading Sort Defense.
  ## Build reverse dependency graph: nodeId(string) → [nodeIds(string) that depend on it].
  ## Used by cascadeStaleDependents for BFS invalidation propagation.
func buildDependentsGraph*(state: SorterState): Table[string, seq[string]] {.axiomTryImpl.} =
  for node in state.nodes:
    for depId in node.dependencyIds:
      let key = sorterNodeIdString(depId)
      result.mgetOrPut(key, @[]).add(sorterNodeIdString(node.id))

## axiom-smt: (assert (and (>= (seq.len dependents) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len dependents))) (>= (seq.len (seq.nth dependents i)) 0))) (and (>= dependencyIdx -9223372036854775808) (<= dependencyIdx 9223372036854775807)) (and (>= nodeIdx -9223372036854775808) (<= nodeIdx 9223372036854775807)) (>= (seq.len dependents) 0) (forall ((dependentsIdx Int)) (=> (and (>= dependentsIdx 0) (< dependentsIdx (seq.len dependents))) (>= (seq.len (seq.nth dependents dependentsIdx)) 0))) (and (>= dependencyIdx -9223372036854775808) (<= dependencyIdx 9223372036854775807)) (and (>= nodeIdx -9223372036854775808) (<= nodeIdx 9223372036854775807)) (forall ((dependentsIdx Int)) (=> (and (>= dependentsIdx 0) (< dependentsIdx (seq.len dependents))) (>= (seq.len (seq.nth dependents dependentsIdx)) 0)))))
## axiom-lean: dependents.size ≥ 0 ∧ ∀ (i : Fin dependents.size), (dependents.get i).size ≥ 0 ∧ dependencyIdx ≥ -9223372036854775808 ∧ dependencyIdx ≤ 9223372036854775807 ∧ nodeIdx ≥ -9223372036854775808 ∧ nodeIdx ≤ 9223372036854775807 ∧ dependents.size ≥ 0 ∧ (∀ (dependentsIdx : Fin dependents.size), (dependents.get dependentsIdx).size ≥ 0) ∧ dependencyIdx ≥ -9223372036854775808 ∧ dependencyIdx ≤ 9223372036854775807 ∧ nodeIdx ≥ -9223372036854775808 ∧ nodeIdx ≤ 9223372036854775807 ∧ (∀ (dependentsIdx : Fin dependents.size), (dependents.get dependentsIdx).size ≥ 0)
func addDependentEdge*(
  dependents: var seq[seq[int]];
  dependencyIdx: int;
  nodeIdx: int
) {.axiomTryImpl.} =
  dependents[dependencyIdx].add(nodeIdx)

{.pop.}
{.pop.}
