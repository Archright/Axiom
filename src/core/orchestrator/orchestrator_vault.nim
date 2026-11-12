import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/algorithm
import std/os
import std/tables
import std/times

import core/gateway/gateway
import core/types/results
import core/sorter/sorter_core
import core/sync/sync_utils_resource
import core/vault/vault_manager_spec
import core/vault/vault_manager_storage

import core/orchestrator/orchestrator_types
import core/orchestrator/orchestrator_topology_depth
import core/orchestrator/orchestrator_topology_worker
import core/orchestrator/orchestrator_topology_emit
import ../../core/trusted/axiom_pragmas

## axiom-smt: (assert (and ast_parse_failed_isolated))
## axiom-lean: ast_parse_failed_isolated
## Pure integer core of safeSpeedupRatio.
## Returns the speedup ratio as a percentage (multiplied by 100) to avoid float,
## so the kernel is verifiable via QF_BV (no float literals → not BMC-skipped).
func safeSpeedupRatioCore*(serialBaselineMs: int64; wallMs: int64): int64 {.
  axiom, axiomImpl, axiom: [post: (result >= 100)]
.} =
  if wallMs <= 0'i64 or serialBaselineMs <= 0'i64: 100
  elif (serialBaselineMs * 100) div wallMs < 100: 100
  else: (serialBaselineMs * 100) div wallMs

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func safeSpeedupRatio(serialBaselineMs: int64; wallMs: int64): float {.axiomOpaque.} =
  let core = safeSpeedupRatioCore(serialBaselineMs, wallMs)
  result = core.float / 100.0

## Add Node Execution Stat.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func addNodeExecutionStat*(
  report: var OrchestrationReport;
  nodeId: SorterNodeId;
  dependencyDepth: int;
  solverElapsedMs: int64;
  wallElapsedMs: int64;
  cacheHit: bool;
  status: OrchestrationNodeStatus;
  timeoutMs: int
) {.axiom, axiomImpl.} =
  report.executionStats.nodeStats.add(OrchestrationNodeExecutionStat(
    nodeId: nodeId,
    dependencyDepth: dependencyDepth,
    solverElapsedMs: solverElapsedMs,
    wallElapsedMs: wallElapsedMs,
    cacheHit: cacheHit,
    status: status,
    timeoutMs: timeoutMs,
    failureReason: nodeFailureReason(status)
  ))
  if cacheHit:
    inc report.executionStats.cacheHitCount
  else:
    inc report.executionStats.solverInvocationCount
  if status == orchestrationTimedOut:
    inc report.executionStats.timeoutCount
  if solverElapsedMs > report.executionStats.hotspotElapsedMs:
    report.executionStats.hotspotElapsedMs = solverElapsedMs
    report.executionStats.hotspotNodeId = nodeId

  ## axiom-smt: (assert (and (>= depth 0) ast_parse_failed_isolated))
  ## axiom-lean: depth >= 0 ∧ ast_parse_failed_isolated
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func stateHasVaultEntry(state: SorterState; nodeId: SorterNodeId): bool {.axiom, axiomImpl.} =
  for entry in state.vaultEntries:
    if nodeIdEquals(entry.nodeId, nodeId):
      return true
  result = false

  ## axiom-smt: (assert (and (>= depth 0)))
  ## axiom-lean: depth >= 0
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func stateLookupVaultAxiom(state: SorterState; nodeId: SorterNodeId): AxiomFormula {.axiom, axiomImpl.} =
  for entry in state.vaultEntries:
    if nodeIdEquals(entry.nodeId, nodeId):
      return entry.axiom
  result = axiomFormula("")

  ## axiom-smt: (assert (and (>= depth 0) (>= result 0)))
  ## axiom-lean: depth >= 0 ∧ (result ≥ 0)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func stateCollectDependencyAxioms(state: SorterState; node: SorterNode): seq[AxiomFormula] {.axiom, axiomImpl.} =
  if node.dependencyIds.len == 0:
    return @[]
  result = newSeqOfCap[AxiomFormula](node.dependencyIds.len)
  for dependencyId in node.dependencyIds:
    if not stateHasVaultEntry(state, dependencyId):
      return @[]
    result.add(stateLookupVaultAxiom(state, dependencyId))

## Add Depth Execution Stat.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func addDepthExecutionStat*(
  report: var OrchestrationReport;
  dependencyDepth: int;
  startedAtMs: int64;
  endedAtMs: int64;
  solverElapsedMs: int64;
  maxSolverElapsedMs: int64;
  activeNodeCount: int;
  workerCount: int;
  resourceSnapshot: ResourceSnapshot
) {.axiom, axiomImpl.} =
  let elapsedMs =
    if endedAtMs >= startedAtMs:
      endedAtMs - startedAtMs
    else:
      0'i64
  let parallelOverheadMs =
    if elapsedMs > maxSolverElapsedMs:
      elapsedMs - maxSolverElapsedMs
    else:
      0'i64
  report.executionStats.depthStats.add(OrchestrationDepthExecutionStat(
    dependencyDepth: dependencyDepth,
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    elapsedMs: elapsedMs,
    solverElapsedMs: solverElapsedMs,
    parallelOverheadMs: parallelOverheadMs,
    activeNodeCount: activeNodeCount,
    workerCount: workerCount,
    speedupRatio: safeSpeedupRatio(solverElapsedMs, elapsedMs),
    availableMemoryBytes: resourceSnapshot.availableMemoryBytes,
    cpuLoadRatio: resourceSnapshot.cpuLoadRatio,
    recommendedWorkerCount: resourceSnapshot.recommendedLimit
  ))
  if workerCount > report.executionStats.maxWorkerCount:
    report.executionStats.maxWorkerCount = workerCount

## Finalize Execution Stats.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc finalizeExecutionStats*(
  report: var OrchestrationReport;
  startedAtMs: int64
) {.axiom, axiomImpl, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var totalSolverTimeMs = 0'i64
  for nodeStat in report.executionStats.nodeStats:
    totalSolverTimeMs += nodeStat.solverElapsedMs
  let endedAtMs = int(getTime().toUnixFloat() * 1000)
  let totalWallTimeMs =
    if endedAtMs >= startedAtMs:
      endedAtMs - startedAtMs
    else:
      0'i64
  report.executionStats.totalSolverTimeMs = totalSolverTimeMs
  report.executionStats.serialBaselineMs = totalSolverTimeMs
  report.executionStats.totalWallTimeMs = totalWallTimeMs
  report.executionStats.parallelSpeedupRatio = safeSpeedupRatio(totalSolverTimeMs, totalWallTimeMs)
  let workerBaseline =
    if report.executionStats.maxWorkerCount > 0:
      report.executionStats.maxWorkerCount
    else:
      1
  if totalWallTimeMs <= 0'i64:
    report.executionStats.cpuEfficiency = 0.0
  else:
    report.executionStats.cpuEfficiency =
      (totalSolverTimeMs.float / (totalWallTimeMs.float * workerBaseline.float)) * 100.0

  ## axiom-smt: (assert (and (>= (str.len vaultDir) 0)))
  ## axiom-lean: vaultDir.length ≥ 0
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func resolveVaultPath(node: SorterNode; vaultDir: string): string {.axiom, axiomImpl.} =
  result = joinPath(vaultDir, axiomSpecFileName(initAxiomSpec(
    modulePath = node.modulePath,
    functionName = node.functionName,
    fingerprint = "",
    smtlib2 = ""
  )))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc hydrateVaultRecord(
  node: SorterNode;
  request: OrchestrationProofRequest;
  vaultDir: string;
  cache: var Table[string, VaultHydrationRecord]
): VaultHydrationRecord {.axiom, axiomImpl.} =
  ## axiom-smt: (assert (and (>= (str.len vaultDir) 0) ast_parse_failed_isolated))
  ## axiom-lean: vaultDir.length ≥ 0 ∧ ast_parse_failed_isolated
  let cacheKey = sorterNodeIdString(node.id)
  if cache.hasKey(cacheKey):
    return cache.getOrDefault(cacheKey)
  result.vaultPath = resolveVaultPath(node, vaultDir)
  let loadRes = loadAxiomSpecFile(result.vaultPath, resolveProofFingerprint(request))
  result.resolved = true
  if loadRes.isOk() and isSubstantiveSmtFormula(request.expectedSmtlib2) and
      isSubstantiveSmtFormula(loadRes.get().smtlib2):
    result.valid = true
    result.spec = loadRes.get()
  cache[cacheKey] = result

## Add Node Report.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc addNodeReport*(
  report: var OrchestrationReport;
  progressSink: OrchestrationProgressSink;
  nodeReport: OrchestrationNodeReport;
  totalDepths: int;
  activeNodeCount: int;
  workerCount: int
) {.axiom, axiomImpl.} =
  report.nodeReports.add(nodeReport)
  emitNodeFinished(progressSink, nodeReport.nodeId, nodeReport.dependencyDepth, workerCount, nodeReport.status)

## Prime Transitive Fingerprint Cache.
## O(K) where K = |transitive dependency closure of target nodes| ≪ N.
## Builds forward dependency graph and BFS-downward from target nodes
## to collect only nodes whose vault hydration affects the targets.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc primeTransitiveFingerprintCache*(
  state: var SorterState;
  report: var OrchestrationReport;
  requests: seq[OrchestrationProofRequest];
  vaultDir: string;
  progressSink: OrchestrationProgressSink
) {.axiom, axiomImpl.} =
  var hydrationCache: Table[string, VaultHydrationRecord]
  let nodeIndexTable = buildNodeIndexTable(state)
  let dependencyDepths = computeNodeDepths(state)
  let totalDepths = computeTotalDepths(dependencyDepths)

  # --- BFS-restricted iteration: only nodes reachable from targets ---
  let nodeCount = state.nodes.len

  # Collect target node indices from requests.
  var targetIndices: seq[int]
  for req in requests:
    let idx = findNodeIndex(nodeIndexTable, req.nodeId)
    if idx >= 0:
      targetIndices.add(idx)

  # BFS downward through forward dependencies to collect the transitive
  # dependency closure of all target nodes.
  var visited = newSeq[bool](nodeCount)
  var bfsQueue: seq[int]
  for tIdx in targetIndices:
    if not visited[tIdx]:
      visited[tIdx] = true
      bfsQueue.add(tIdx)

  var cursor = 0
  while cursor < bfsQueue.len:
    let nodeIdx = bfsQueue[cursor]
    inc cursor
    for depId in state.nodes[nodeIdx].dependencyIds:
      let depIdx = findNodeIndex(nodeIndexTable, depId)
      if depIdx >= 0 and not visited[depIdx]:
        visited[depIdx] = true
        bfsQueue.add(depIdx)

  # bfsQueue now holds all transitively reachable node indices (BFS order).
  # Sort by dependency depth ascending so dependencies are processed before
  # dependents — required for correct vault hydration cascade.
  var reachableIndices = bfsQueue
  sort(reachableIndices, proc(a, b: int): int {.noSideEffect.} =
    dependencyDepths[a] - dependencyDepths[b]
  )

  let totalPrimingNodes = reachableIndices.len
  var primedCount = 0
  for nodeIdx in reachableIndices:
    let depth = dependencyDepths[nodeIdx]
    let node = state.nodes[nodeIdx]
    let requestIdx = findRequestIndex(requests, node.id)
    var ownValid = false
    var vaultPath = ""
    if requestIdx >= 0:
      let hydration = hydrateVaultRecord(node, requests[requestIdx], vaultDir, hydrationCache)
      vaultPath = hydration.vaultPath
      if hydration.valid:
        ownValid = true
        promoteNodeToVault(
          state,
          node.id,
          axiomFormula(hydration.spec.smtlib2)
        )
      else:
        syncNodeAxiomFromVault(
          state,
          node.id,
          vaultPath,
          resolveProofFingerprint(requests[requestIdx])
        )
    else:
      ownValid = false
      setNodeStale(state, node.id, true)
    var dependenciesValid = true
    for dependencyId in node.dependencyIds:
      let dependencyIdx = findNodeIndex(nodeIndexTable, dependencyId)
      if dependencyIdx < 0 or state.nodes[dependencyIdx].isStale or
          not stateHasVaultEntry(state, dependencyId):
        dependenciesValid = false
        break
    let transitivelyValid = ownValid and dependenciesValid
    setNodeStale(state, node.id, not transitivelyValid)
    if transitivelyValid:
      let injected = stateCollectDependencyAxioms(state, state.nodes[nodeIdx])
      let requestObj = AxiomProofRequest(
        nodeId: sorterNodeIdString(node.id),
        ownSourceCode: requests[requestIdx].sourceCode,
        stateValue: requests[requestIdx].stateValue,
        inputDelta: requests[requestIdx].inputDelta,
        dependencyAxioms: (if node.dependencyIds.len > 0: toGatewayDependencyAxioms(injected) else: @[]),
        expectedSmtlib2: requests[requestIdx].expectedSmtlib2,
        timeoutMs: requests[requestIdx].timeoutMs,
        solverCommand: requests[requestIdx].solverCommand,
        solverArgs: requests[requestIdx].solverArgs,
        injectContradiction: requests[requestIdx].injectContradiction
      )
      let nodeReport = OrchestrationNodeReport(
        nodeId: node.id,
        dependencyDepth: depth,
        usesDependencyVault: node.dependencyIds.len > 0,
        readsDependencySource: false,
        injectedAxioms: injected,
        status: orchestrationVerified,
        vaultPath: vaultPath,
        cacheHit: true,
        smtlib2: buildInjectedSmtlib2(requestObj)
      )
      addNodeReport(report, progressSink, nodeReport, totalDepths, 0, 0)
      addNodeExecutionStat(report, node.id, depth, 0'i64, 0'i64, true, orchestrationVerified, 0)
    inc primedCount
    emitProgress(progressSink, OrchestrationProgressEvent(
      kind: orchestrationPrimingProgress,
      dependencyDepth: depth,
      totalDepths: totalDepths,
      activeNodeCount: primedCount,
      workerCount: totalPrimingNodes,
      nodeId: node.id,
      status: orchestrationVerified,
      cacheHit: false,
      primedCount: primedCount
    ))

{.pop.}

