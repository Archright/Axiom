import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Sorter State Ops — O(1) node source update via index table lookup.
## S7b of the Sieve Refactoring Trigger plan.

import std/tables
import core/sorter/sorter_core_index_base   # SorterState, SorterNode, SorterNodeId
import core/sorter/sorter_core_index_table  # findNodeIndex

func updateNodeSource*(
  state: var SorterState;
  nodeIndexTable: Table[string, int];
  nodeId: SorterNodeId;
  newSource: string
): bool {.raises: [].} =
  ## Update the refactoredSource of a node via O(1) index table lookup.
  ## Returns true if the node was found and updated, false otherwise.
  let idx = findNodeIndex(nodeIndexTable, nodeId)
  if idx < 0:
    return false
  state.nodes[idx].refactoredSource = newSource
  state.nodes[idx].isStale = true
  true

func getEffectiveSource*(
  node: SorterNode;
  originalSource: string
): string {.inline, raises: [].} =
  ## Return refactoredSource if non-empty, otherwise originalSource.
  if node.refactoredSource.len > 0:
    node.refactoredSource
  else:
    originalSource

{.pop.}
{.pop.}
