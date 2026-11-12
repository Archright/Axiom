## Pure topology planning functions for the depth-loop orchestrator.
## No I/O, no mutable state — all functions are `{.func.}` and `{.raises: [].}`.
## Extracted from loop_driver.nim to separate pure computation from stateful
## scheduling, following the func/proc boundary principle (§0.6).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/orchestrator/orchestrator_types
import core/sorter/sorter_core
import std/sets
import std/tables

const
  maxAllowedDepth* = 64  ## §2.5 ceiling for pathological dependency graphs.

type
  DepthPlan* = object
    ## Immutable plan for the depth-loop iteration.  Built once from the
    ## topological sort output; consumed by the scheduler without mutation.
    maxDepth*: int
    depthToItems*: Table[int, seq[SorterWorkItem]]
    effectiveNodeLimit*: int
    primedReportCount*: int

func buildDepthPlan*(
  workItems: seq[SorterWorkItem];
  primedReportCount: int;
  effectiveNodeLimit: int
): DepthPlan =
  ## Compute maxDepth from workItems (capped at maxAllowedDepth) and build
  ## the depth→items index for O(1) lookup per depth level (W3-D optimisation).
  var maxDepth = 0
  for item in workItems:
    if item.dependencyDepth > maxDepth:
      maxDepth = item.dependencyDepth
  if maxDepth > maxAllowedDepth:
    maxDepth = maxAllowedDepth
  var depthToItems = initTable[int, seq[SorterWorkItem]]()
  for item in workItems:
    depthToItems.mgetOrPut(item.dependencyDepth, @[]).add(item)
  result = DepthPlan(
    maxDepth: maxDepth,
    depthToItems: depthToItems,
    effectiveNodeLimit: effectiveNodeLimit,
    primedReportCount: primedReportCount,
  )

func shouldContinueDepth*(
  newReportCount: int;
  effectiveNodeLimit: int;
  remainingFuel: int
): bool =
  ## Deterministic termination predicate: returns false when fuel is
  ## exhausted or the effective node limit has been reached.
  if remainingFuel <= 0:
    return false
  if effectiveNodeLimit > 0 and newReportCount >= effectiveNodeLimit:
    return false
  true

func computeVerifiedIds*(
  nodeReports: seq[OrchestrationNodeReport]
): HashSet[string] =
  ## Extract already-verified node IDs into a HashSet for O(1) lookup.
  ## Replaces the O(N²) repeated linear scans in the depth loop.
  result = initHashSet[string]()
  for nr in nodeReports:
    if nr.status == orchestrationVerified:
      result.incl(string(nr.nodeId))
