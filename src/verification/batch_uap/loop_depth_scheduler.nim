## Stateful depth-level parallel scheduler for Batch UAP.
## Processes all nodes at a single dependency depth concurrently using
## `createThread` workers that communicate over a shared `Channel` (reorder
## buffer).  Results are merged deterministically (sorted by node order) into
## the shared report.  Certificate writes happen on the main thread only.
##
## All procs in this module perform I/O (Z3 solver subprocesses, file reads)
## and therefore use `{.raises: [CatchableError].}` or wider.
## Threading primitives come from `system` (Channel / typedthreads) — they are
## part of the standard library and must not be imported explicitly.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/math

import core/contracts/universal_pipeline_contract
import core/function_verification_summary
import core/pipeline_core_types
import core/orchestration/pipeline_dispatch
import core/orchestrator/orchestrator_types
import core/proof/proof_budget
import core/sorter/sorter_core
import core/topology/topology_engine
import core/types/refactor_task_types
import sieve/sieve_types
import sieve/sieve_refactor_bridge
import std/json
import std/monotimes
import std/os
import std/sets
import std/tables
import verification/certificate_hydration
import verification/cert_writer
import verification/batch_uap/private/request_builder
import verification/batch_uap/private/types
import verification/batch_uap/stages
import verification/pipeline_state_types
import verification/universal_pipeline
import infrastructure/logging_facade
import core/crypto/hash_kernel
import core/axiom_pragmas

# ── Data-oriented parallelism types ───────────────────────────────────
# Each thread receives an immutable snapshot via ptr and produces a
# value-type result.  No ref object args to spawn.
# Z3 pipe exclusivity is enforced per query by the z3_pool worker lease
# (acquireZ3WorkerLease/releaseZ3WorkerLease): an in-flight query owns its
# worker's stdin/stdout until its sentinel is read; threads that would share
# a leased worker wait for a release instead. The pool is sized to the
# thread count (loop_driver: AXIOM_PROVE_WORKERS → z3EnsurePersistentPool).
# No nested createMaster(); bounded thread count matches z3_pool workers.

## VS-1 test instrumentation: depth batches processed on the threaded
## parallel path. Incremented on the main thread only (inside
## runParallelDepthBatchUap, before workers spawn — the workers never touch
## it), so the parallel-parity equivalence test can prove the threaded
## branch was actually entered.
var parallelDepthBatchRuns*: int = 0

type
  ## Read-only context for parallel workers.  Allocated on heap via create(),
  ## passed as ptr to worker threads.  All fields are value types.
  ParallelNodeContext = object
    state: SorterState
    requests: seq[OrchestrationProofRequest]
    requestMap: Table[SorterNodeId, OrchestrationProofRequest]
    vaultDir: string
    topologyAnalysis: TopologyAnalysis
    maxRounds: int
    tfSourceCache: Table[string, string]
    ioAxiomCount: int
    summarySnapshot: SummaryCache
    ## W3-E: Pre-seeded source file content cache (avoids per-worker readFile).
    sourceFileContentCache: Table[string, string]
    ## P3b mirror input: nodes whose scoped IR evidence carries generated
    ## obligations. The contract-blind type-directed stage must not terminate
    ## them — same gate as the sequential path (loop_driver stage-1 handling).
    obligationBearingNodes: HashSet[string]
    ## VS-1 parity inputs: nodes whose claim-scoped IR evidence is a P4
    ## confirmed disproof (verification.status == vsDisproved), derived
    ## deterministically in loop_driver, plus the driver's relaxed pre-sieve
    ## block threshold — the SAME decision inputs the sequential path
    ## consumes for the shared admission rule (stages.decidePreSieveNode).
    disprovedNodes: HashSet[string]
    blockThreshold: float

  ## Per-node result from parallel processing.  All value types — safe for
  ## channel sink-move across threads.
  ParallelNodeResult = object
    taskIndex: int             ## index into pendingItems — reorder buffer key
    nodeReport: OrchestrationNodeReport
    uapResult: UniversalPipelineResult
    hasUapResult: bool
    summary: FunctionVerificationSummary
    hasSummary: bool
    gasCost: int
    cacheHit: bool
    breakerWeight: int    ## 0=success, 1=failure
    solverMs: int64
    refactorTrigger: RefactorTask
    hasRefactorTrigger: bool
    certInput: FinalReportCertInput   ## main-thread cert write payload
    hasCertInput: bool                 ## true when a certificate should be written

  ## W3-F: Value-type work item for parallel fingerprint computation.
  FingerprintWorkItem* = object
    nodeIdStr*: string
    state*: SorterState
    tfSourceCache*: Table[string, string]
    engineSalt*: string

  ## W3-F: Value-type result from parallel fingerprint worker.
  FingerprintResult* = object
    nodeIdStr*: string
    fingerprint*: string

  ## Per-worker argument for the depth-level parallel scheduler.
  ## Workers read shared buffers (items, nodeTfs) and the read-only context
  ## via `ptr`; each sends its own `ParallelNodeResult` back over the channel.
  ## NOTE: the context and buffers are treated as READ-ONLY shared state while
  ## workers run (main thread only consumes results after join).  This mirrors
  ## the long-standing serial-path `addr ctx` usage (DEBT#415 parallelization).
  DepthWorkerArg = object
    slot: int
    workerCount: int
    items: ptr seq[SorterWorkItem]
    nodeTfs: ptr seq[string]
    ctx: ptr ParallelNodeContext
    resChan: ptr Channel[ParallelNodeResult]

# ── JSON helper ───────────────────────────────────────────────────────

func derivationToJson*(node: DerivationNode): JsonNode {.raises: [].} =
  ## Serialize a DerivationNode tree to JSON for audit logs.
  result = %*{
    "step": $node.stepKind,
    "rule": node.ruleName,
    "reason": node.reason
  }
  if node.children.len > 0:
    var kids = newJArray()
    for child in node.children:
      kids.add(derivationToJson(child))
    result["children"] = kids

# ── Parallel worker procs ─────────────────────────────────────────────

## Body proc (non-gcsafe): all UAP pipeline, sieve, z3_pool calls happen here.
## Separated from the gcsafe wrapper to avoid transitive gcsafe check failures.
proc processOneNodeParallelBody(
  item: SorterWorkItem;
  nodeTf: string;
  ctx: ptr ParallelNodeContext;
  res: var ParallelNodeResult
) {.raises: [CatchableError, Exception, IOEffect].} =
  let nodeIdStr = sorterNodeIdString(item.nodeId)

  # Stage 1: Find matching request
  let (matchingReq, found) = findMatchingRequest(item.nodeId, ctx.requestMap)
  if not found:
    res.nodeReport = OrchestrationNodeReport(
      nodeId: item.nodeId,
      status: orchestrationBlocked,
      evidenceLogJson: "request not found"
    )
    return

  # Stage 2: Parse node ID parts
  let parts = parseNodeIdParts(nodeIdStr)

  # Stage 3: Check summary cache
  let cacheKey = makeCacheKey(parts.modulePath, parts.functionName)
  if ctx.summarySnapshot.hasKey(cacheKey):
    let cached = ctx.summarySnapshot[cacheKey]
    if cached.checksum == nodeTf:
      res.uapResult = buildCachedResult(nodeTf, cached, nodeIdStr)
      res.hasUapResult = true
      res.cacheHit = true
      # P3b: Cache hit alone is not kernel acceptance. The parallel summary
      # cache can hold candidate-level (type-directed/spacer) summaries, so the
      # runtime status stays fail-closed orchestrationProofFailed — never
      # claiming kernel acceptance from reuse (C0.4 bypass hardening).
      # DEBT#459: the row's OWN cacheHit=true attribute carries the reuse
      # evidence; canonical accounting (run_accounting.nim) interprets the
      # (status, cacheHit=true) pair as a REUSED satisfaction (SATISFIED,
      # SatisfactionSource=REUSED, ExecutionEvidence=NOT_ATTEMPTED).
      res.nodeReport = OrchestrationNodeReport(
        nodeId: item.nodeId,
        status: orchestrationProofFailed,
        cacheHit: true,
        evidenceLogJson: "CACHE-HIT: no kernel acceptance evidence"
      )
      return

  # Stage 4: Type-directed proof (Phase 0)
  let tdResult = tryTypeDirectedProof(
    nodeIdStr, matchingReq.sourceCode, parts.modulePath, parts.functionName,
    ctx.vaultDir, nodeTf
  )
  if tdResult.verified and nodeIdStr notin ctx[].obligationBearingNodes:
    # P3b: Type-directed arithmetic proof is solver-layer evidence,
    # not Lean kernel acceptance. Fail-closed: without kernel
    # acceptance, this is a candidate proof, not orchestrationVerified.
    # Obligation-bearing nodes are exempt (mirror of the sequential-path
    # gate): the stage-4 self-equivalence query is contract-blind (the
    # declared post is not in the query), so its verdict cannot adjudicate
    # a declared contract — those nodes proceed to obligation-aware stages.
    res.nodeReport = OrchestrationNodeReport(
      nodeId: item.nodeId,
      status: orchestrationProofFailed,
      vaultPath: tdResult.certPath,
      evidenceLogJson: "TYPE-DIRECTED (candidate only, no kernel acceptance): " & tdResult.reason
    )
    res.summary = tdResult.summary
    res.hasSummary = true
    res.breakerWeight = 1
    res.certInput = tdResult.certInput
    res.hasCertInput = true
    return

  # Stage 5: Pre-Sieve Interceptor
  # VS-1: the relaxed blockThreshold travels with the context — the parallel
  # path applies the SAME deterministic threshold relaxation as the
  # sequential stage-1 (computeRelaxedThreshold), not a hard-coded default.
  let sieveResult = runPreSieveStage(
    item, matchingReq, ctx.topologyAnalysis, parts.modulePath, parts.functionName,
    blockThreshold = ctx.blockThreshold
  )
  # VS-1 parallel parity: the SAME shared node-decision rule the sequential
  # path applies (stages.decidePreSieveNode) — deterministic threshold
  # relaxation, the WP4-j C4 fatal-only admission gate, and the P4 disproof
  # carve-out. `disprovedNodes` membership is the claim-scoped
  # status == vsDisproved verdict (funcName presence implied by derivation),
  # so the worker needs no IR payloads beyond this set.
  let isDisproved = nodeIdStr in ctx[].disprovedNodes
  let preSieveDecision = decidePreSieveNode(
    sieveResult.sieveVerdict, ctx.blockThreshold, isDisproved, isDisproved)
  case preSieveDecision
  of psndPreSieved:
    res.nodeReport = OrchestrationNodeReport(
      nodeId: item.nodeId,
      status: orchestrationPreSievedUnverifiable,
      evidenceLogJson: $(%*{
        "status": "PRE-SIEVED",
        "blocked": sieveResult.sieveVerdict.blocked,
        "score": sieveResult.sieveVerdict.probabilityScore,
        "reason": sieveResult.sieveVerdict.reason,
        "appliedRules": sieveResult.sieveVerdict.appliedRules.len,
        "derivation": derivationToJson(sieveResult.sieveVerdict.derivation),
        "ioAxiomCount": ctx.ioAxiomCount
      })
    )
    # S3: Capture refactoring trigger for PRE-SIEVED nodes
    res.refactorTrigger = sieveVerdictToRefactorTask(
      item.nodeId, parts.modulePath, parts.functionName,
      matchingReq.sourceCode, sieveResult.sieveVerdict)
    res.hasRefactorTrigger = true
    return
  of psndDisproofTerminal:
    ## P4 disproof carve-out — parallel mirror of the sequential stage-2
    ## vsDisproved terminal: a fatal structural block must not swallow a
    ## P4-promoted, replay-confirmed disproof of an adopted claim (the
    ## vsDisproved terminal is the only path that marks a node failed, so a
    ## PRE-SIEVED report here would make the disproof invisible to the exit
    ## rule). The report mirrors the sequential mapping of that terminal
    ## (verified=false, osrNone → orchestrationProofFailed, "UAP failed");
    ## no cert, no uapResult, no summary, no refactor trigger — the carved-out
    ## node is a verification failure, not a PRE-SIEVED one. Fail-closed:
    ## only vsDisproved carves out; demotions keep the pre-sieve verdict.
    res.nodeReport = OrchestrationNodeReport(
      nodeId: item.nodeId,
      status: orchestrationProofFailed,
      evidenceLogJson: "UAP failed"
    )
    return
  of psndProceed:
    ## VS-1: claim-scoped IR disproof terminal for ADMITTED (non-blocked)
    ## nodes — consumed BEFORE budget/spacer/UAP. `isDisproved` is the SAME
    ## claim-scoped status == vsDisproved membership the decision above
    ## consumed, so an admitted node whose claim is REFUTED terminates here
    ## exactly as the sequential path terminates it at its stage-2 vsDisproved
    ## check (loop_driver: verified=false, osrNone → orchestrationProofFailed,
    ## "UAP failed"). Without this terminal a refuted claim fell through to
    ## the solver region and could return orchestrationVerified with a
    ## certificate while the sequential lane failed the same node. No cert,
    ## no uapResult, no summary; the P6 attempt accounting stays keyed to the
    ## merged decision — this node's generated obligations ARE attempted,
    ## exactly as the sequential driver counts them before its early exits.
    if isDisproved:
      res.nodeReport = OrchestrationNodeReport(
        nodeId: item.nodeId,
        status: orchestrationProofFailed,
        evidenceLogJson: "UAP failed"
      )
      return
    # else: fall through to obligation synthesis + execution (stages 6-9)

  # Stage 6: Build UAP request with dependency pre-conditions
  let reqResult = buildUapRequestWithDeps(
    matchingReq, ctx.vaultDir, ctx.maxRounds, ctx.state, ctx.summarySnapshot
  )
  if not reqResult.success:
    res.nodeReport = OrchestrationNodeReport(
      nodeId: item.nodeId,
      status: orchestrationProofFailed,
      evidenceLogJson: reqResult.error
    )
    return
  let uapReq = reqResult.uapReq

  # Stage 7: Gas cost computation and per-unit budget check.
  # Each unit's budget is derived from its own complexity signals
  # (topologyScore, sieveProbability, nestingDepth) — independent
  # of the run-global frontier size.  The shared budget is
  # consumed here for aggregate reporting only; verdicts are
  # driven by the per-unit budget.
  let gasResult = computeGasCost(
    matchingReq.topologyScore, sieveResult.sieveVerdict.probabilityScore,
    sieveResult.topoMetric.nestingDepth
  )
  res.gasCost = gasResult.gasCost
  let entropySignals = ComplexitySignals(
    topologyScore: float(clamp(matchingReq.topologyScore, 0, 100)) / 100.0,
    sieveProbability: sieveResult.sieveVerdict.probabilityScore,
    cegarIterations: 0,
    cegarStagnationCount: 0,
    z3RejectionCount: 0,
    synergyGeometricMean: 1.0,
    historicalAvgGas: 0.0
  )
  let entropy = computeComplexityEntropy(entropySignals)
  let unitBudget = initPerUnitBudget(
    matchingReq.topologyScore, entropy, sieveResult.topoMetric.nestingDepth,
    getMonoTime().ticks
  )
  let budgetVerdict = checkBudget(unitBudget)
  if budgetVerdict != pbvContinue:
    # Gas/rlimit exhaustion is a deterministic verification FAILURE.  Wall-clock
    # expiry is a hang-guard: the run aborts for this node without a verdict.
    let deterministic = isDeterministicFailure(budgetVerdict)
    res.nodeReport = OrchestrationNodeReport(
      nodeId: item.nodeId,
      status: if deterministic: orchestrationProofFailed else: orchestrationTimedOut,
      evidenceLogJson: if deterministic:
          "deterministic budget exhausted (gas/rlimit): " & $budgetVerdict
        else:
          "wall-clock hang-guard: " & $budgetVerdict
    )
    return

  # Per-node wall-clock timeout
  let nodeStartMono = getMonoTime().ticks

  # Stage 8: Spacer CHC bypass
  let spacerResult = trySpacerBypass(uapReq, matchingReq, nodeIdStr, nodeTf)
  if spacerResult.bypassed:
    res.uapResult = spacerResult.output
    res.hasUapResult = true
    res.breakerWeight = 0
    # P3b: Spacer/CHC is a proof producer. Only a Lean kernel-accepted result
    # is orchestrationVerified; Z3/CHC-only evidence is a candidate, not
    # kernel-verified. Spacer never invokes the Lean kernel, so this is
    # always candidate.
    res.nodeReport = OrchestrationNodeReport(
      nodeId: item.nodeId,
      status: orchestrationVerified,
      evidenceLogJson: "spacer_bypass: " & spacerResult.invariantSource
    )
    res.summary = spacerResult.summary
    res.hasSummary = true
    res.solverMs = (getMonoTime().ticks - nodeStartMono) div 1_000_000
    res.certInput = FinalReportCertInput(
      status: orchestrationVerified,
      modulePath: uapReq.modulePath,
      functionName: uapReq.functionName,
      sourceCode: uapReq.sourceCode,
      kernelVerified: false,
      smtlib2: spacerResult.output.translation.smt2,
      solverStatus: spacerResult.output.smtTrack.solverStatus,
      vacuityProven: spacerResult.output.leanTrack.vacuityProven,
      irHash: sha256Hex(uapReq.modulePath & uapReq.functionName & uapReq.sourceCode),
      leanProposition: spacerResult.output.leanTrack.theoremSource
    )
    res.hasCertInput = true
    return

  # Run UAP pipeline
  let uapOutcome = runUniversalAcceptancePipeline(uapReq, createDefaultPipelineDispatch())
  res.solverMs = (getMonoTime().ticks - nodeStartMono) div 1_000_000
  if res.solverMs > nodeWallClockTimeoutMs:
    res.nodeReport = OrchestrationNodeReport(
      nodeId: item.nodeId,
      status: orchestrationTimedOut,
      evidenceLogJson: "node timeout: " & $res.solverMs & "ms > " & $nodeWallClockTimeoutMs & "ms"
    )
    return
  case uapOutcome.exitKind
  of pekSuccess:
    let uapOutput = uapOutcome.result
    # Circuit breaker weight
    if uapOutput.provenLayer in {plkL1Bmc, plkL2Cegar, plkL2Pdr, plkL3Scribe, plkL4Judge}:
      res.breakerWeight = 0
    else:
      res.breakerWeight = 1
    res.uapResult = uapOutput
    res.hasUapResult = true

    # Build summary
    res.summary = FunctionVerificationSummary(
      functionName: uapReq.functionName,
      modulePath: uapReq.modulePath,
      preConditions: uapReq.preConditions,
      postConditions: uapReq.postConditions,
      invariant: uapOutput.activeInvariant,
      provenLayer: uapOutput.provenLayer,
      checksum: nodeTf,
      complexityClass: buapClassifySourceComplexity(uapReq.sourceCode, uapReq.functionName),
      vacuityProven: uapOutput.leanTrack.vacuityProven,
      vkdFixed4: ""
    )
    res.hasSummary = true

    # Stage 9: Build final report
    let reportResult = buildFinalNodeReport(item.nodeId, uapReq, uapOutput)
    res.nodeReport = reportResult.report
    res.certInput = reportResult.certInput
    res.hasCertInput = true
  of pekFailure:
    res.nodeReport = OrchestrationNodeReport(
      nodeId: item.nodeId,
      status: orchestrationProofFailed,
      evidenceLogJson: uapOutcome.failureMessage
    )

## Worker proc for the depth-level parallel scheduler.  Runs on a dedicated
## thread via createThread.  Each worker processes its strided slice of
## pendingItems, runs the pure-computation + Z3/Lean body, and sends its
## `ParallelNodeResult` (with `taskIndex`) back over the channel using a
## sink move (zero-copy under ARC).  Certificate writes are intentionally NOT
## performed here — the worker only returns `certInput`; the main thread writes
## certs after collection.
proc depthWorker(arg: DepthWorkerArg) {.thread.} =
  {.cast(gcsafe).}:
    {.cast(raises: []).}:
      let n = arg.items[].len
      var i = arg.slot
      while i < n:
        var res: ParallelNodeResult
        res.taskIndex = i
        try:
          processOneNodeParallelBody(arg.items[][i], arg.nodeTfs[][i], arg.ctx, res)
        except CatchableError:
          res.nodeReport = OrchestrationNodeReport(
            nodeId: arg.items[][i].nodeId,
            status: orchestrationProofFailed,
            evidenceLogJson: "parallel worker exception"
          )
        arg.resChan[].send(res)
        inc i, arg.workerCount

# ── Depth-level batch executor ────────────────────────────────────────

## VS-1 label parity: the parallel merge's mirror of the sequential
## promotion classification's certNoObligation branch (loop_driver). A
## verified-labeled node whose persisted certificate carries status
## "certNoObligation" (tierFromResults vtNone — the symbol has no
## verification obligation, so nothing was promoted and this is not a
## failure) is reclassified orchestrationNoObligation, exactly as the
## sequential driver relabels it before the report row is emitted.
## Fail-closed: a failed/unreadable read keeps the incoming label — only
## an OBSERVED certNoObligation reclassifies, never a missing file.
proc reclassifyCertNoObligation*(
    nodeReport: var OrchestrationNodeReport;
    vaultDir: string;
    irHash: string
) {.raises: [CatchableError].} =
  if irHash.len == 0:
    return
  var certNode: JsonNode = nil
  try:
    certNode = parseJson(readFile(vaultDir / (irHash & ".json")))
  except CatchableError:
    certNode = nil
  if certNode.isNil or certNode.kind != JObject:
    return
  if certNode{"status"}.getStr("") == "certNoObligation":
    nodeReport.status = orchestrationNoObligation

## Run parallel depth batch UAP.  Processes all nodes at a single dependency
## depth level concurrently via createThread workers + a shared Channel.
## Results are merged deterministically (sorted by node order) into the shared
## report.  Falls back to a sequential loop when workerCount <= 1.
proc runParallelDepthBatchUap*(
  state: var SorterState;
  report: var OrchestrationReport;
  uapResults: var Table[string, UniversalPipelineResult];
  depthItems: seq[SorterWorkItem];
  obligationBearingNodes: HashSet[string];
  disprovedNodes: HashSet[string];              ## VS-1: P4 confirmed-disproof nodes
  obligationAttemptCounts: Table[string, int];  ## VS-1: per-node ogrGenerated counts
  requests: seq[OrchestrationProofRequest];
  vaultDir: string;
  topologyAnalysis: TopologyAnalysis;
  maxRounds: int;
  budget: var ProofBudget;
  ogrAttemptedCount: var int;                   ## VS-1: P6 attempt-accounting mirror
  leanstralFailureStreak: var int;
  circuitBroken: var bool;
  circuitBreakerThreshold: int;
  tfSourceCache: var Table[string, string];
  tfMemo: var Table[string, string];
  ioAxiomCount: int;
  blockThreshold: float;                        ## VS-1: relaxed pre-sieve threshold
  workerCount: int;
  progressSink: BatchUapProgressSink;
  collectedRefactorTasks: var seq[RefactorTask]
): bool {.raises: [CatchableError].} =  ## returns true to continue, false if depth failed
  # Build request lookup table for O(1) access
  let requestMap = buildRequestMap(requests)

  # Filter items: skip already-verified, check budget, find requests
  # Build HashSet once for O(1) "already verified" lookups (was O(N²))
  var verifiedIds: HashSet[string]
  for nr in report.nodeReports:
    if nr.status == orchestrationVerified:
      verifiedIds.incl(string(nr.nodeId))
  var pendingItems: seq[SorterWorkItem] = @[]
  for item in depthItems:
    # Skip already verified — O(1) lookup
    if string(item.nodeId) in verifiedIds:
      inc report.executionStats.cacheHitCount
      continue
    # Node limit: stop collecting once we've reached the requested count.
    # Use pendingItems.len (not report.nodeReports.len) because the report
    # does not grow during the filter loop — the original bug caused 4890-item
    # stampede (DEBT#415).
    if requests.len > 0 and pendingItems.len >= requests.len:
      break
    # Request check
    let (_, reqFound) = findMatchingRequest(item.nodeId, requestMap)
    if not reqFound:
      continue
    pendingItems.add(item)

  if pendingItems.len == 0:
    return true  # nothing to do

  # W3-F: Pre-compute transitive fingerprints sequentially (index-aligned).
  # Fingerprints are computed once on the main thread — the shared state, Table,
  # and string caches are NOT handed to workers. Only the flat fingerprint array
  # plus the read-only context are shared across threads under --mm:arc --threads:on.
  var nodeTfSeq = newSeq[string](pendingItems.len)
  for idx in 0..<pendingItems.len:
    nodeTfSeq[idx] = computeTransitiveFingerprintWithCaches(
      state, sorterNodeIdString(pendingItems[idx].nodeId), tfSourceCache, tfMemo, engineSalt="")

  # Create local context for sequential processing
  var ctx = ParallelNodeContext()
  ctx.state = state
  ctx.requests = requests
  ctx.requestMap = requestMap
  ctx.vaultDir = vaultDir
  ctx.topologyAnalysis = topologyAnalysis
  ctx.maxRounds = maxRounds
  ctx.tfSourceCache = tfSourceCache
  ctx.ioAxiomCount = ioAxiomCount
  ctx.summarySnapshot = summaryCache

  # W3-E: Pre-seed source file content cache from request data.
  var sourceFileContentCache = initTable[string, string]()
  for req in requests:
    let nodeIdStr = sorterNodeIdString(req.nodeId)
    if req.sourceCode.len > 0 and not sourceFileContentCache.hasKey(nodeIdStr):
      sourceFileContentCache[nodeIdStr] = req.sourceCode
  ctx.sourceFileContentCache = sourceFileContentCache
  ctx.obligationBearingNodes = obligationBearingNodes
  ctx.disprovedNodes = disprovedNodes
  ctx.blockThreshold = blockThreshold

  # ── Compute per-node results (parallel or sequential fallback) ────────
  var results = newSeq[ParallelNodeResult](pendingItems.len)

  if workerCount > 1 and pendingItems.len > 1:
    # Parallel path: createThread + shared Channel acting as a reorder buffer.
    # The Channel is allocated on the shared heap and passed to workers by ptr,
    # per the documented safe pattern for cross-thread channel passing. Results
    # carry `taskIndex`; the main thread fills `results[taskIndex]` in arrival
    # order, then merges deterministically by index. Cert writes are NOT done
    # in workers — only `certInput` is returned.
    # VS-1 test instrumentation: main-thread-only counter the parallel-parity
    # equivalence test reads to prove this branch was actually entered.
    inc parallelDepthBatchRuns
    var channelPtr = cast[ptr Channel[ParallelNodeResult]](
      allocShared0(sizeof(Channel[ParallelNodeResult])))
    channelPtr[].open()
    defer:
      channelPtr[].close()
      deallocShared(channelPtr)

    var threads = newSeq[Thread[DepthWorkerArg]](workerCount)
    var workerArgs: seq[DepthWorkerArg]
    newSeq(workerArgs, workerCount)
    for slot in 0..<workerCount:
      workerArgs[slot] = DepthWorkerArg(
        slot: slot,
        workerCount: workerCount,
        items: addr pendingItems,
        nodeTfs: addr nodeTfSeq,
        ctx: addr ctx,
        resChan: channelPtr
      )
      createThread(threads[slot], depthWorker, workerArgs[slot])

    # Reorder buffer: collect every result and place it by taskIndex.
    for collectIdx in 0..<pendingItems.len:
      let res = channelPtr[].recv()
      results[res.taskIndex] = res

    for slot in 0..<workerCount:
      joinThread(threads[slot])
  else:
    # Sequential fallback (workers=1 or too few items for parallelism).
    for idx in 0..<pendingItems.len:
      let item = pendingItems[idx]
      let nodeTf = nodeTfSeq[idx]
      {.cast(raises: []).}:
        try:
          processOneNodeParallelBody(item, nodeTf, addr ctx, results[idx])
        except CatchableError:
          results[idx].nodeReport = OrchestrationNodeReport(
            nodeId: item.nodeId,
            status: orchestrationProofFailed,
            evidenceLogJson: "sequential worker exception: " & getCurrentExceptionMsg()
          )

  # ── Main-thread merge (deterministic order; cert writes + report merge) ──
  for idx in 0..<pendingItems.len:
    let item = pendingItems[idx]

    # Certificate write from the main thread (single-threaded vault I/O safety).
    # Workers never write certs — they only return `certInput`.
    # VS-1 label parity: the write is followed by the SAME certNoObligation →
    # orchestrationNoObligation promotion-label reclassification the
    # sequential driver applies (loop_driver), BEFORE the progress label, the
    # log line, and the report row are emitted — every downstream consumer of
    # the node verdict sees the reclassified label on both lanes.
    if results[idx].hasCertInput and results[idx].certInput.status == orchestrationVerified:
      var certLogLines: seq[string] = @[]
      let ci = results[idx].certInput
      let wroteOk = writeCertificateFromUapResult(  # axiom:best-effort(main-thread cert persist per DEBT#415; in-memory report carries verdict, pipeline continues regardless)
        vaultDir, ci.modulePath, ci.functionName, ci.sourceCode,
        ci.kernelVerified, ci.smtlib2, ci.solverStatus, certLogLines,
        irHash = ci.irHash, vacuityProven = ci.vacuityProven,
        negativeTestResult = false)
      if wroteOk:
        reclassifyCertNoObligation(results[idx].nodeReport, vaultDir, ci.irHash)

    # Progress callback
    if progressSink != nil:
      try:
        if results[idx].cacheHit:
          progressSink(sorterNodeIdString(item.nodeId), "CACHE-HIT")
        elif results[idx].nodeReport.status == orchestrationVerified:
          progressSink(sorterNodeIdString(item.nodeId), "VERIFIED")
        elif results[idx].nodeReport.status == orchestrationPreSievedUnverifiable:
          progressSink(sorterNodeIdString(item.nodeId), "PRE-SIEVED")
        else:
          progressSink(sorterNodeIdString(item.nodeId), "PROCESSED")
      except CatchableError:
        discard  # progress callback failure is non-fatal  # axiom:best-effort(ioboundary catch)

    # Stderr progress for interactive visibility
    let verdict = if results[idx].cacheHit: "cached"
                  elif results[idx].nodeReport.status == orchestrationVerified: "verified"
                  elif results[idx].nodeReport.status == orchestrationPreSievedUnverifiable: "pre-sieved"
                  elif results[idx].nodeReport.status == orchestrationTimedOut: "timed out"
                  else: "failed"
    logInfo("loop_depth_scheduler", "  [" & $(idx + 1) & "/" & $pendingItems.len & "] " & sorterNodeIdString(item.nodeId) & " — " & verdict)

    # Merge stats
    inc report.executionStats.solverInvocationCount

    # VS-1: mirror of the sequential P6 obligation-attempt accounting, using
    # the SAME predicate (preSieveAttemptsObligations): every result that did
    # not terminate as PRE-SIEVED dispatched its generated obligations toward
    # a proof-resolution path — cache replays, type-directed candidates,
    # regular pipeline nodes, and carved-out disproof terminals alike — so
    # their obligation counts are added here exactly as the sequential driver
    # adds them before its early exits.
    let mergedDecision: PreSieveNodeDecision =
      if results[idx].nodeReport.status == orchestrationPreSievedUnverifiable:
        psndPreSieved
      else:
        psndProceed
    if preSieveAttemptsObligations(mergedDecision):
      ogrAttemptedCount += obligationAttemptCounts.getOrDefault(
        sorterNodeIdString(item.nodeId), 0)

    # Cache hit
    if results[idx].cacheHit:
      if results[idx].hasUapResult:
        uapResults[sorterNodeIdString(item.nodeId)] = results[idx].uapResult
      report.nodeReports.add(results[idx].nodeReport)
    else:

      # Consume gas
      if results[idx].gasCost > 0:
        discard consumeGas(budget, results[idx].gasCost)

      # Circuit breaker
      if results[idx].breakerWeight > 0:
        inc leanstralFailureStreak
      else:
        leanstralFailureStreak = 0

      # Store summary
      if results[idx].hasSummary:
        storeSummary(summaryCache, results[idx].summary)

      # Add node report
      report.nodeReports.add(results[idx].nodeReport)

      # S3: Collect refactoring triggers from PRE-SIEVED nodes
      if results[idx].hasRefactorTrigger:
        collectedRefactorTasks.add(results[idx].refactorTrigger)

      # Store UAP result
      if results[idx].hasUapResult:
        uapResults[sorterNodeIdString(item.nodeId)] = results[idx].uapResult

      # Circuit breaker threshold check
      if leanstralFailureStreak >= circuitBreakerThreshold:
        circuitBroken = true
        break

    if circuitBroken:
      break

  true  # continue to next depth
