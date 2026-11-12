import core/trusted/axiom_pragmas_lite
import core/trusted/layer_declaration
axiomLayer "infrastructure"
import core/interfaces/logging_hub
import core/utils/constants
import core/diagnostics/diagnostics_engine
import core/gate/resource_limits
import core/gateway/gateway
import core/orchestrator/cfg_builder
import core/topology/topology_engine
import core/orchestrator/orchestrator_api
import core/orchestrator/orchestrator_vault
import core/orchestrator/orchestrator_parallel_types
import core/parser_utils
import core/results
import core/sorter/sorter_core
import core/sync/sync_utils_resource
import core/vault/vault_manager_spec
import core/vault/vault_manager_storage
import std/cpuinfo
import std/locks
import std/options
import std/tables
import std/times
import verification/solver/provers
import verification/solver/z3_pool
import core/types/verification_tier
import malebolgia

# ── Infrastructure procs (Z3, solver, vault I/O, parallel execution) ──

# CEGAR fallback runs on the main thread only: compiler/parser (PNode) is not
# GC-safe, so parseStringAST cannot be called from malebolgia worker threads.
proc runCegarFallback(input: ParallelTaskInput; solverElapsed: int): Option[ParallelTaskResult]  {.axiomDecision.} =
  let parsedAst = parseStringAST(input.request.sourceCode)
  if parsedAst.isNil:
    return none(ParallelTaskResult)
  let cegarCfg = buildCfgFromAstP(parsedAst)
  var cegarHeaderId = -1
  for blk in cegarCfg.blocks:
    if blk.loopHeader:
      cegarHeaderId = blk.id
      break
  if cegarHeaderId < 0:
    return none(ParallelTaskResult)
  let prover = Z3PoolProver()
  let z3CheckImpl = proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].} =
    prove(prover, query, 5000)
  try:
    let abstraction = applyCegarAbstraction(input.workItem.nodeId, cegarCfg, cegarHeaderId, z3CheckImpl, solverElapsed, input.request.timeoutMs,
      cegarRun = input.cegarEngine,
      encodeSmtlib2 = input.encodeSmtlib2)
    # CEGAR always returns a definitive verdict — propagate it directly.
    return some(ParallelTaskResult(
      workItem: input.workItem,
      status: abstraction.status,
      smtlib2: abstraction.smtlib2,
      solverElapsedMs: solverElapsed,
      timeoutMs: input.request.timeoutMs,
      evidenceLogJson: abstraction.evidenceLog,
      usedIntervalDomain: abstraction.isAbstracted,
      vulnerabilityType: "cegar_" & $abstraction.status
    ))
  except CatchableError:
    return none(ParallelTaskResult)  # axiom:best-effort(ioboundary catch)

# @axiom-hint: lean="endedAtMs ≥ startedAtMs ∧ (ticket ≥ 0)" smt="(assert (and (>= endedAtMs startedAtMs) (>= ticket 0)))"
proc executeParallelTask(inputPtr: ptr ParallelTaskInput): ParallelTaskResult {.gcsafe.} =
  let input = inputPtr[]
  var ticket = ResourceTicket(semaphore: nil, acquired: false)
  try:
    ticket = acquireTicket(input.solverSemaphore)
  except ResourceTimeoutError:
    return ParallelTaskResult(
      workItem: input.workItem,
      status: orchestrationTimedOut,
      smtlib2: "",
      solverElapsedMs: 0,
      timeoutMs: input.request.timeoutMs,
      evidenceLogJson: "{\"error\":\"resource_semaphore_timeout\"}",
      usedIntervalDomain: false,
      vulnerabilityType: "resource_semaphore_timeout")
  except ResourceLimitError:
    return ParallelTaskResult(
      workItem: input.workItem,
      status: orchestrationProofFailed,
      smtlib2: "",
      solverElapsedMs: 0,
      timeoutMs: 0,
      evidenceLogJson: "{\"error\":\"resource_semaphore_limit_zero\"}",
      usedIntervalDomain: false,
      vulnerabilityType: "resource_semaphore_limit_zero")
  let startedAtMs = int(getTime().toUnixFloat() * 1000)
  let requestObj = AxiomProofRequest(
    nodeId: sorterNodeIdString(input.workItem.nodeId),
    ownSourceCode: input.request.sourceCode,
    stateValue: input.request.stateValue,
    inputDelta: input.request.inputDelta,
    dependencyAxioms:
      (if input.workItem.usesDependencyVault: toGatewayDependencyAxioms(input.workItem.dependencyAxioms) else: @[]),
    expectedSmtlib2: input.request.expectedSmtlib2,
    timeoutMs: input.request.timeoutMs,
    solverCommand: input.request.solverCommand,
    solverArgs: input.request.solverArgs,
    injectContradiction: input.request.injectContradiction
  )
  let generatedSmtlib2 = buildInjectedSmtlib2(requestObj)
  let proofRes = proveAxiomNode(requestObj)
  let endedAtMs = int(getTime().toUnixFloat() * 1000)
  let solverElapsed = if endedAtMs >= startedAtMs: endedAtMs - startedAtMs else: 0'i64
  releaseTicket(ticket)

  if proofRes.isErr():


    let status =
      if proofRes.error == axiomErrSolverTimeout:
        orchestrationTimedOut
      elif proofRes.error == axiomErrVacuousContradiction:
        orchestrationVacuousContradiction
      else:
        orchestrationProofFailed
    let errEvidence = "{\"error\":\"" & $proofRes.error & "\"}"
    let vulnType =
      if proofRes.error == axiomErrSolverTimeout: "solver_timeout"
      elif proofRes.error == axiomErrVacuousContradiction: "vacuous_contradiction"
      else: "proof_failed"
    return ParallelTaskResult(
      workItem: input.workItem,
      status: status,
      smtlib2: generatedSmtlib2,
      solverElapsedMs: solverElapsed,
      timeoutMs: input.request.timeoutMs,
      evidenceLogJson: errEvidence,
      usedIntervalDomain: false,
      vulnerabilityType: vulnType
    )

  let okEvidence =
    if proofRes.get().z3outHash.len > 0:
      "{\"z3outHash\":\"" & proofRes.get().z3outHash & "\"}"
    else:
      ""
  # Phase 1 Tier semantics: the orchestrator pure path carries Z3 evidence only
  # (AxiomProofResult.verified). Lean kernel verification is NOT performed on
  # this path — the batch UAP path (buildFinalNodeReport) is the dual-verified
  # source. With Z3 passed and no Lean signal, tierFromResults(true, false)
  # resolves to vtZ3Only. Both signals are present, so tierResolution = resolved.
  ParallelTaskResult(
    workItem: input.workItem,
    status: orchestrationVerified,
    smtlib2: generatedSmtlib2,
    solverElapsedMs: solverElapsed,
    timeoutMs: input.request.timeoutMs,
    evidenceLogJson: okEvidence,
    usedIntervalDomain: false,
    vulnerabilityType: "none",
    assuranceTier: tierLabel(tierFromResults(true, false)),
    tierResolution: "resolved"
  )
type
  ParallelTaskCompletionCallback* = proc(result: ParallelTaskResult) {.gcsafe, closure, raises: [].}
# @axiom-hint: lean="inputs.size ≥ 0 ∧ maxWorkers ≥ -9223372036854775808 ∧ maxWorkers ≤ 9223372036854775807" smt="(assert (and (>= (seq.len inputs) 0) (and (>= maxWorkers -9223372036854775808) (<= maxWorkers 9223372036854775807))))"
proc runParallelDepth(
  inputs: seq[ParallelTaskInput];
  maxWorkers: int;
 completionCallback: ParallelTaskCompletionCallback = nil;
  wallDeadlineMs: int64 = high(int64)
): seq[ParallelTaskResult] =
  if inputs.len == 0:
    return @[]
  let boundedWorkers = if maxWorkers > 0: maxWorkers else: 1
  var localInputs = inputs
  var nextInputIdx = 0
  while nextInputIdx < localInputs.len:
    if int(getTime().toUnixFloat() * 1000) >= wallDeadlineMs:
      break
    let batchEnd = min(localInputs.len, nextInputIdx + boundedWorkers)
    let batchLen = batchEnd - nextInputIdx
    var batchResults = newSeq[ParallelTaskResult](batchLen)
    discard resource_limits.raiseRlimitNoFile()
    ## W3-A: Parallelize task execution within each batch using malebolgia.
    if batchLen > 1:
      block parallelBatch:
        var m = createMaster()
        m.awaitAll:
          for i in 0 ..< batchLen:
            m.spawn executeParallelTask(addr localInputs[nextInputIdx + i]) -> batchResults[i]
    else:
      batchResults[0] = executeParallelTask(addr localInputs[nextInputIdx])
    for i in 0 ..< batchResults.len:
      var taskResult = batchResults[i]
      if taskResult.status == orchestrationTimedOut:
        let cegarOpt = runCegarFallback(localInputs[nextInputIdx + i], taskResult.solverElapsedMs)
        if cegarOpt.isSome:
          taskResult = cegarOpt.get
      result.add(taskResult)
      if not completionCallback.isNil:
        completionCallback(taskResult)
    nextInputIdx = batchEnd

# @axiom-hint: lean="handledNodes.size ≥ 0 ∧ requests.size ≥ 0 ∧ vaultDir.length ≥ 0" smt="(assert (and (>= (seq.len handledNodes) 0) (>= (seq.len requests) 0) (>= (str.len vaultDir) 0)))"
proc promoteVerifiedResult(
  state: var SorterState;
  report: var OrchestrationReport;
  handledNodes: var seq[SorterNodeId];
  requests: seq[OrchestrationProofRequest];
  vaultDir: string;
  vaultDirLock: var Lock;
  progressSink: OrchestrationProgressSink;
  workerResult: ParallelTaskResult;
  totalDepths: int;
  activeNodeCount: int;
  workerCount: int
): bool =
  let nodeId = workerResult.workItem.nodeId
  let nodeIdx = findNodeIndex(state, nodeId)
  let requestIdx = findRequestIndex(requests, nodeId)
  if nodeIdx < 0 or requestIdx < 0:
    registerTerminalNodeStatus(
      report,
      state,
      handledNodes,
      progressSink,
      workerResult.workItem,
      orchestrationBlocked,
      totalDepths,
      activeNodeCount,
      workerCount,
      true
    )
    return false
  acquire(vaultDirLock)
  let vaultWriteRes = storeAxiomSpec(
    vaultDir,
    initAxiomSpec(
      modulePath = state.nodes[nodeIdx].modulePath,
      functionName = state.nodes[nodeIdx].functionName,
      fingerprint = resolveProofFingerprint(requests[requestIdx]),
      smtlib2 = requests[requestIdx].expectedSmtlib2,
      winningStrategy = "orchestration",
      retryCount = 0
    )
  )
  release(vaultDirLock)
  if vaultWriteRes.isErr():
    discard
    registerTerminalNodeStatus(
      report,
      state,
      handledNodes,
      progressSink,
      workerResult.workItem,
      orchestrationProofFailed,
      totalDepths,
      activeNodeCount,
      workerCount,
      true,
      0,
      true,
      emptyTimeoutDiagnosis(),
      workerResult.smtlib2,
      workerResult.evidenceLogJson
    )
    return false
  addUniqueNodeId(handledNodes, nodeId)
  let nodeReport = buildWorkerNodeReport(workerResult.workItem, orchestrationVerified, vaultWriteRes.get(), false, emptyTimeoutDiagnosis(), workerResult.smtlib2, workerResult.evidenceLogJson, workerResult.assuranceTier, workerResult.tierResolution)
  addNodeReport(report, progressSink, nodeReport, totalDepths, activeNodeCount, workerCount)
  promoteNodeToVault(
    state,
    nodeId,
    axiomFormula(requests[requestIdx].expectedSmtlib2)
  )
  true

# @axiom-hint: lean="handledNodes.size ≥ 0 ∧ requests.size ≥ 0" smt="(assert (and (>= (seq.len handledNodes) 0) (>= (seq.len requests) 0)))"
proc handleParallelResult(
  state: var SorterState;
  report: var OrchestrationReport;
  handledNodes: var seq[SorterNodeId];
  requests: seq[OrchestrationProofRequest];
  vaultDir: string;
  vaultDirLock: var Lock;
  progressSink: OrchestrationProgressSink;
  workerResult: ParallelTaskResult;
  totalDepths: int;
  activeNodeCount: int;
  workerCount: int
): bool =
  let requestIdx = findRequestIndex(requests, workerResult.workItem.nodeId)
  addNodeExecutionStat(
    report,
    workerResult.workItem.nodeId,
    workerResult.workItem.dependencyDepth,
    workerResult.solverElapsedMs,
    workerResult.solverElapsedMs,
    false,
    workerResult.status,
    workerResult.timeoutMs
  )
  if workerResult.status == orchestrationVerified:
    result = promoteVerifiedResult(
      state,
      report,
      handledNodes,
      requests,
      vaultDir,
      vaultDirLock,
      progressSink,
      workerResult,
      totalDepths,
      activeNodeCount,
      workerCount
    )
    if workerResult.usedIntervalDomain:
      let nodeIdx = report.nodeReports.len - 1
      if nodeIdx >= 0:
        report.nodeReports[nodeIdx].selfHealingGuidance.add(workerResult.evidenceLogJson)
        report.nodeReports[nodeIdx].remediationHint = "CEGAR: Interval Abstraction applied. Needs refinement."
  else:
    result = false
    let diagnosis =
      if workerResult.status == orchestrationTimedOut and requestIdx >= 0:
        timeoutDiagnosisForNode(
          state,
          requests[requestIdx],
          workerResult.workItem.nodeId,
          workerResult.workItem.dependencyDepth,
          workerResult.timeoutMs
        )
      else:
        emptyTimeoutDiagnosis()
    registerTerminalNodeStatus(
      report,
      state,
      handledNodes,
      progressSink,
      workerResult.workItem,
      workerResult.status,
      totalDepths,
      activeNodeCount,
      workerCount,
      true,
      workerResult.timeoutMs,
      false,
      diagnosis,
      workerResult.smtlib2,
      workerResult.evidenceLogJson
    )

# @axiom-hint: lean="requests.size ≥ 0 ∧ vaultDir.length ≥ 0" smt="(assert (and (>= (seq.len requests) 0) (>= (str.len vaultDir) 0)))"
proc runAxiomOrchestrationLoop*(
  initialState: SorterState;
  requests: seq[OrchestrationProofRequest];
  vaultDir: string;
 ctx: OrchestrationContext = defaultOrchestrationContext()
): OrchestrationReport =
  doAssert ctx.isValid(), "OrchestrationContext validation failed"
  ## W3-B: Incremental topology cache — skip re-analysis for unchanged files.
  let topologyCachePath = ".axiom/topology_cache.json"
  let cacheLoad = loadTopologyCache(topologyCachePath)
  var topologyCache = if cacheLoad.isOk: cacheLoad.get else: initTable[string, TopologyCacheEntry]()
  defer:
    let saveRes = saveTopologyCache(topologyCachePath, topologyCache)
    if saveRes.isErr:
      logError("saveTopologyCache: " & saveRes.error.message)
  # Local aliases for backward compatibility with internal helper functions
  let progressSink = ctx.progressSink
  let impactIndexLookup = ctx.impactIndexLookup
  let maxWorkers = ctx.maxWorkers
  var state = initialState
  let runStartedAtMs = int(getTime().toUnixFloat() * 1000)
  let wallDeadlineMs = runStartedAtMs + int64(ctx.maxWallClockMs)
  primeTransitiveFingerprintCache(state, result, requests, vaultDir, ctx.progressSink)
  var handledNodes: seq[SorterNodeId] = @[]
  var queue: ParallelTaskQueue
  let effectiveWorkers = if maxWorkers > 0: maxWorkers else: computeParallelWorkerLimit(initialState.nodes.len, countProcessors())
  initParallelTaskQueue(queue, effectiveWorkers)
  var solverSemaphore: sync_utils_resource.ResourceSemaphore
  initResourceSemaphore(solverSemaphore, queue.maxWorkers)
  defer: deinitResourceSemaphore(solverSemaphore)
  var vaultDirLock: Lock
  initLock(vaultDirLock)
  defer: deinitLock(vaultDirLock)

  ## Fuel counter: deterministic, CPU-independent termination bound.
  ## Complements wall-clock timeout with a step-count guarantee.
  var remainingFuel = DefaultOrchestratorFuel

  while true:
    ## Fuel exhausted — deterministic termination
    if remainingFuel <= 0:
      result.finalState = state
      finalizeExecutionStats(result, runStartedAtMs)
      return result
    if int(getTime().toUnixFloat() * 1000) >= wallDeadlineMs:
      result.finalState = state
      finalizeExecutionStats(result, runStartedAtMs)
      return result
    let plan = buildSorterPlan(state)
    let orderedWorkItems = sortWorkItemsByDepth(plan.workItems, impactIndexLookup)
    let totalDepths = totalPlanDepths(plan)
    let depthItems = selectNextDepthItems(orderedWorkItems, handledNodes)
    if depthItems.len == 0:
      if plan.blockedNodes.len > 0 or plan.staleDependencyNodes.len > 0:
        addPlanReproofNodes(result, plan)
      result.finalState = state
      finalizeExecutionStats(result, runStartedAtMs)
      return result
    let activeDepth = depthItems[0].dependencyDepth
    var depthFailed = false
    let (parallelInputs, depthSuccess) = prepareParallelInputs(
      result,
      state,
      handledNodes,
      requests,
      progressSink,
      depthItems,
      addr solverSemaphore,
      totalDepths,
      queue.maxWorkers,
      ctx.cegarEngine,
      ctx.encodeSmtlib2
    )
    if not depthSuccess:
      depthFailed = true

    if parallelInputs.len > 0 and not depthFailed:
      let desiredWorkerCount = min(parallelInputs.len, effectiveWorkers)
      let resourceSnapshot = refreshResourceSemaphore(addr solverSemaphore, desiredWorkerCount)
      let workerCount = resourceSnapshot.recommendedLimit
      z3EnsurePersistentPool(workerCount)
      queue.maxWorkers = workerCount
      emitDepthStarted(progressSink, activeDepth, totalDepths, parallelInputs.len)
      let depthStartedAtMs = int(getTime().toUnixFloat() * 1000)
      var depthSolverElapsedMs = 0'i64
      var depthMaxSolverElapsedMs = 0'i64
      var completedResults: seq[ParallelTaskResult] = @[]
      let immediateCompletionCallback: ParallelTaskCompletionCallback = proc(wr: ParallelTaskResult) {.raises: [].} =
        completedResults.add(wr)
        depthSolverElapsedMs += wr.solverElapsedMs
        if wr.solverElapsedMs > depthMaxSolverElapsedMs:
          depthMaxSolverElapsedMs = wr.solverElapsedMs
      let depthDeadlineMs = min(wallDeadlineMs, int(getTime().toUnixFloat() * 1000) + int64(parallelDepthWallClockTimeoutMs))
      discard runParallelDepth(parallelInputs, workerCount, immediateCompletionCallback, depthDeadlineMs)
      let depthEndedAtMs = int(getTime().toUnixFloat() * 1000)
      for workerResult in completedResults:
        if not handleParallelResult(
          state,
          result,
          handledNodes,
          requests,
          vaultDir,
          vaultDirLock,
          progressSink,
          workerResult,
          totalDepths,
          parallelInputs.len,
          workerCount
        ):
          depthFailed = true
      addDepthExecutionStat(
        result,
        activeDepth,
        depthStartedAtMs,
        depthEndedAtMs,
        depthSolverElapsedMs,
        depthMaxSolverElapsedMs,
        parallelInputs.len,
        workerCount,
        resourceSnapshot
      )

    ## Decrement fuel after processing each depth level
    remainingFuel -= FuelPerDepthLevel

    if depthFailed:
      result.finalState = state
      finalizeExecutionStats(result, runStartedAtMs)
      return result

  result.finalState = state
  finalizeExecutionStats(result, runStartedAtMs)
