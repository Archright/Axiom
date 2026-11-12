## orchestrator_topology_emit.nim
## Orchestration progress event emitters.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary


import core/sorter/sorter_core
import core/orchestrator/orchestrator_types
import core/orchestrator/orchestrator_report_types

## Emit Progress.
proc emitProgress*(
  sink: OrchestrationProgressSink;
  event: OrchestrationProgressEvent
) {.raises: [].} =
  if sink.isNil:
    return
  try:
    sink(event)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

## Emit Depth Started.
proc emitDepthStarted*(
  sink: OrchestrationProgressSink;
  depth: int;
  totalDepths: int;
  itemsAtDepth: int
) {.raises: [].} =
  emitProgress(sink, OrchestrationProgressEvent(
    kind: orchestrationDepthStarted,
    dependencyDepth: depth,
    totalDepths: totalDepths,
    activeNodeCount: itemsAtDepth
  ))

## Emit Node Started.
proc emitNodeStarted*(
  sink: OrchestrationProgressSink;
  nodeId: SorterNodeId;
  depth: int;
  workerIndex: int
) {.raises: [].} =
  emitProgress(sink, OrchestrationProgressEvent(
    kind: orchestrationNodeStarted,
    nodeId: nodeId,
    dependencyDepth: depth,
    workerCount: workerIndex
  ))

## Emit Node Finished.
proc emitNodeFinished*(
  sink: OrchestrationProgressSink;
  nodeId: SorterNodeId;
  depth: int;
  workerIndex: int;
  status: OrchestrationNodeStatus
) {.raises: [].} =
  emitProgress(sink, OrchestrationProgressEvent(
    kind: orchestrationNodeFinished,
    nodeId: nodeId,
    dependencyDepth: depth,
    workerCount: workerIndex,
    status: status
  ))

{.pop.}
