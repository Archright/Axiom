import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Ordinal Index Tables — Data-Oriented Topological Refactoring (Phase 1)
##
## Provides O(1) dense-array lookups for nodes and vault entries using
## interned `NodeId` handles. Kept separate from `sorter_core_index_table`
## because interning mutates a table and would otherwise break the
## noSideEffect scope of the string-keyed table builders.

import core/sorter/sorter_core_index_base
import core/topology/symbol_interning

## Build Intern Pool from SorterState.
## All node IDs are interned so callers can use ordinal lookups.
func buildInternPool*(state: SorterState): InternPool {.raises: [].} =
  result = initInternPool(state.nodes.len)
  for node in state.nodes:
    discard internNode(result, sorterNodeIdString(node.id))

## Ordinal-based Node Index Table.
## `result[uint32(nodeId)]` is the index of that node in `state.nodes`, or -1.
func buildNodeOrdinalTable*(state: SorterState; pool: var InternPool): seq[int] {.raises: [].} =
  result = newSeq[int](pool.poolSize)
  for i in 0 ..< result.len:
    result[i] = -1
  for idx, node in state.nodes:
    let id = nodeIdForSorter(pool, node.id)
    let ord = int(uint32(id))
    if ord < result.len:
      result[ord] = idx

## Ordinal-based Vault Entry Index Table.
func buildVaultEntryOrdinalTable*(state: SorterState; pool: var InternPool): seq[int] {.raises: [].} =
  result = newSeq[int](pool.poolSize)
  for i in 0 ..< result.len:
    result[i] = -1
  for idx, entry in state.vaultEntries:
    let id = nodeIdForSorter(pool, entry.nodeId)
    let ord = int(uint32(id))
    if ord < result.len:
      result[ord] = idx

## Find Node Index via ordinal table.
func findNodeIndex*(ordinalTable: seq[int]; nodeId: NodeId): int =
  let ord = int(uint32(nodeId))
  if ord < ordinalTable.len:
    return ordinalTable[ord]
  -1

## Find Vault Entry Index via ordinal table.
func findVaultEntryIndex*(ordinalTable: seq[int]; nodeId: NodeId): int =
  let ord = int(uint32(nodeId))
  if ord < ordinalTable.len:
    return ordinalTable[ord]
  -1

## Has Vault Entry via ordinal table.
func hasVaultEntry*(ordinalTable: seq[int]; nodeId: NodeId): bool =
  findVaultEntryIndex(ordinalTable, nodeId) >= 0

{.pop.}
