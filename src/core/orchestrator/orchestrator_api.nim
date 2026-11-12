## orchestrator_api.nim — Domain interface for the orchestrator.
##
## Pure computation only. No I/O, no Z3, no process spawning.
## This module re-exports domain sub-modules and provides domain-level
## orchestration procs (plan building, work enqueueing, progress tracking).
##
## Infrastructure (Z3, solver, vault writes) lives in verification/orchestrator.nim.
## S2 measurement (2026-10-10): comment-only header change — irHash invariant
## probe for Pass 2.96b (proof-required vault admission, S1 #660).
## Org-gate canary (2026-10-10, .github#131): second comment-only probe —
## exercises closure-only re-anchor landing WITHOUT the path-level TWS
## atomicity false flag (landing-integrity twsFieldState classification,
## Axiom #669).

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import core/orchestrator/orchestrator_types
export orchestrator_types
import core/orchestrator/orchestrator_topology_depth
export orchestrator_topology_depth
import core/orchestrator/orchestrator_topology_worker
export orchestrator_topology_worker
import core/orchestrator/orchestrator_topology_emit
export orchestrator_topology_emit
import core/orchestrator/orchestrator_vault
export orchestrator_vault
import core/sorter/sorter_core
import core/sync/sync_utils_resource
import core/diagnostics/diagnostics_engine
import core/orchestrator/protocols
import ../../core/trusted/axiom_pragmas

# ── Domain procs (extracted from orchestrator.nim + parts) ──

## Compute the effective worker count for the parallel task queue.
## Scalar decision extracted out of initParallelTaskQueue (pure, no I/O).
func normalizeMaxWorkers(maxWorkers: int): int {.
  axiomImpl,
  axiom: [post: (result >= 1)]
.} =
  if maxWorkers > 0:
    return maxWorkers
  return 1

## Init Parallel Task Queue.
  ## axiom-smt: (assert (and (and (>= maxWorkers -9223372036854775808) (<= maxWorkers 9223372036854775807)) (> maxWorkers 0) (>= queue 0)))
  ## axiom-lean: maxWorkers ≥ -9223372036854775808 ∧ maxWorkers ≤ 9223372036854775807 ∧ maxWorkers > 0 ∧ (queue ≥ 0)
func initParallelTaskQueue*(queue: var ParallelTaskQueue; maxWorkers: int) =
  queue.maxWorkers = normalizeMaxWorkers(maxWorkers)

## Add Plan Reproof Nodes.
  ## axiom-smt: (assert (and (>= depth 0)))
  ## axiom-lean: depth >= 0
func addPlanReproofNodes*(report: var OrchestrationReport; plan: SorterPlan) {.axiom, axiomImpl.} =
  for nodeId in plan.staleDependencyNodes:
    addUniqueNodeId(report.staleDependencyNodes, nodeId)
    addUniqueNodeId(report.reproofNodes, nodeId)
  for nodeId in plan.blockedNodes:
    addUniqueNodeId(report.blockedNodes, nodeId)
    addUniqueNodeId(report.reproofNodes, nodeId)

## Register Terminal Node Status.
## axiom-smt: (assert (and (>= (seq.len handledNodes) 0) (and (>= totalDepths -9223372036854775808) (<= totalDepths 9223372036854775807)) (and (>= activeNodeCount -9223372036854775808) (<= activeNodeCount 9223372036854775807)) (and (>= workerCount -9223372036854775808) (<= workerCount 9223372036854775807))))
## axiom-lean: handledNodes.size ≥ 0 ∧ totalDepths ≥ -9223372036854775808 ∧ totalDepths ≤ 9223372036854775807 ∧ activeNodeCount ≥ -9223372036854775808 ∧ activeNodeCount ≤ 9223372036854775807 ∧ workerCount ≥ -9223372036854775808 ∧ workerCount ≤ 9223372036854775807
proc registerTerminalNodeStatus*(
  report: var OrchestrationReport;
  state: SorterState;
  handledNodes: var seq[SorterNodeId];
  progressSink: OrchestrationProgressSink;
  workItem: SorterWorkItem;
  status: OrchestrationNodeStatus;
  totalDepths: int;
  activeNodeCount: int;
  workerCount: int;
  propagateBranch: bool;
  timeoutMs: int = 0;
  recordStats: bool = true;
  diagnosis: TimeoutDiagnosis = emptyTimeoutDiagnosis();
  smtlib2: string = "";
  evidenceLogJson: string = ""
) {.axiom, axiomImpl.} =
  if propagateBranch:
    blockBranch(report, state, workItem.nodeId)
  if status == orchestrationTimedOut:
    registerTimeoutImpact(report, state, workItem.nodeId)
  addUniqueNodeId(handledNodes, workItem.nodeId)
  let nodeReport = buildWorkerNodeReport(workItem, status, "", false, diagnosis, smtlib2, evidenceLogJson, "unknown", "unavailable")
  addNodeReport(report, progressSink, nodeReport, totalDepths, activeNodeCount, workerCount)
  if recordStats:
    addNodeExecutionStat(
      report,
      workItem.nodeId,
      workItem.dependencyDepth,
      0'i64,
      0'i64,
      false,
      status,
      timeoutMs
    )

## Enqueue Parallel Work Item.
proc enqueueParallelWorkItem*(
  parallelInputs: var seq[ParallelTaskInput];
  report: var OrchestrationReport;
  state: SorterState;
  handledNodes: var seq[SorterNodeId];
  requests: seq[OrchestrationProofRequest];
  progressSink: OrchestrationProgressSink;
  workItem: SorterWorkItem;
  solverSemaphore: ptr ResourceSemaphore;
  totalDepths: int;
  activeNodeCount: int;
  workerCount: int;
  cegarEngine: CegarCallback = nil;
  encodeSmtlib2: EncodeSmtlib2Callback = nil
): bool {.axiom, axiomImpl.} =
  ## axiom-smt: (assert (and (>= (seq.len parallelInputs) 0) (>= (seq.len handledNodes) 0) (>= (seq.len requests) 0)))
  ## axiom-lean: parallelInputs.size ≥ 0 ∧ handledNodes.size ≥ 0 ∧ requests.size ≥ 0
  if workItem.ownSourceKind == sourceVaultAxiom:
    addUniqueNodeId(handledNodes, workItem.nodeId)
    return true
  let requestIdx = findRequestIndex(requests, workItem.nodeId)
  let nodeIdx = findNodeIndex(state, workItem.nodeId)
  if requestIdx >= 0 and nodeIdx >= 0:
    let effectiveTimeoutMs = calcDynamicTimeout(
      requests[requestIdx],
      workItem.dependencyDepth,
      collectImpactedBranchNodes(state, workItem.nodeId).len
    )
    var effectiveRequest = requests[requestIdx]
    effectiveRequest.timeoutMs = effectiveTimeoutMs
    parallelInputs.add(ParallelTaskInput(
      workItem: workItem,
      request: effectiveRequest,
      solverSemaphore: solverSemaphore,
      cegarEngine: cegarEngine,
      encodeSmtlib2: encodeSmtlib2
    ))
    emitNodeStarted(progressSink, workItem.nodeId, workItem.dependencyDepth, workerCount)
    return true
  registerTerminalNodeStatus(
    report,
    state,
    handledNodes,
    progressSink,
    workItem,
    orchestrationBlocked,
    totalDepths,
    activeNodeCount,
    workerCount,
    true
  )
  result = false

## Prepare Parallel Inputs.
proc prepareParallelInputs*(
  report: var OrchestrationReport;
  state: SorterState;
  handledNodes: var seq[SorterNodeId];
  requests: seq[OrchestrationProofRequest];
  progressSink: OrchestrationProgressSink;
  depthItems: seq[SorterWorkItem];
  solverSemaphore: ptr ResourceSemaphore;
  totalDepths: int;
  maxWorkers: int;
  cegarEngine: CegarCallback = nil;
  encodeSmtlib2: EncodeSmtlib2Callback = nil
): (seq[ParallelTaskInput], bool) {.axiom, axiomImpl.} =
  ## axiom-smt: (assert (and (>= (seq.len parallelInputs) 0) (>= (seq.len handledNodes) 0) (>= (seq.len requests) 0)))
  ## axiom-lean: parallelInputs.size ≥ 0 ∧ handledNodes.size ≥ 0 ∧ requests.size ≥ 0
  result[1] = true
  for workItem in depthItems:
    if not enqueueParallelWorkItem(
      result[0],
      report,
      state,
      handledNodes,
      requests,
      progressSink,
      workItem,
      solverSemaphore,
      totalDepths,
      depthItems.len,
      maxWorkers,
      cegarEngine,
      encodeSmtlib2
    ):
      result[1] = false

{.pop.}

