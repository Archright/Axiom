import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
import cli/cli_surface_generated
import cli/cli_outcome
import cli/cli_types
import cli/config_loader
import cli/external_subject_registry
import cli/lean_verify_cmd
import cli/payload_bridge
import cli/proof_gate
import cli/proposition_intake
import cli/queue_limit
import cli/rust_lane_cli
import cli/verdict_display
import cli/shared/baseline_snapshot_core
import cli/selection_state
import cli/frontier_selection
import cli/topology_cli
import cli/wf_render
import cli/wf_runners
import cli/wf_runners_common
import cli/wf_state
import core/axiom_pragmas
import core/types/asi_types
import core/types/universe_types
import core/domain_types
import core/orchestration/pipeline_dispatch
import core/orchestrator/orchestrator_types
import core/proof/proof_budget
import core/proof/proof_integrity
import core/results
import core/parsers/safe_parsers
import core/sorter/sorter_core
import core/telemetry/metrics
import core/topology/symbol_interning
import core/topology/verified_frontier
import core/topology/verified_set
import core/topology/topology_engine
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/semantic_fact_types
import core/trusted/specification_artifact
import core/deterministic_cas_key
import core/trusted/fingerprint_generator
import gate/semantic_alias_mapper
import std/algorithm
import std/json
import std/monotimes
import std/options
import std/os
import std/osproc
import std/sets
import std/strutils
import std/tables
import std/terminal
import verification/batch_uap/loop_driver
import verification/batch_uap/ir_pipeline_runner
import infrastructure/external_ir_materializer
import infrastructure/evidence_artifact_io
import verification/cert_writer
import verification/obligation/candidate_eligibility
import verification/obligation/verification_decision_authority
import verification/obligation/identity
import verification/obligation/lean_kernel_boundary
import verification/obligation/canonical_verification
import verification/counterexample_replay
import core/trusted/env_access
import core/trusted/env_types
import core/types/refactor_task_types
import core/types/verification_tier
import core/types/obligation_evidence
import core/types/execution_plan
import core/json/json_utils
import verification/selection/selection_digests
import verification/selection/closure_evaluation
import core/crypto/hash_kernel
import verification/selection/selection_engine
import verification/accounting/run_accounting except VerificationOutcome
import verification/accounting/execution_context
import core/types/residual_monad
import core/progress/lexicographic_terminator
import verification/batch_uap/refactor_executor
import verification/batch_uap/refactor_vfs
import verification/cert_vault_role
import verification/certificate_manager
import verification/cross_validation
import verification/pipeline_state_types
import verification/unified_trajectory
import verification/universal_pipeline
import verification/verified_set_hydration
import core/types/pipeline_core_types
import infrastructure/logging_facade
import core/context/run_context
import core/utils/constants
import std/typedthreads
import std/times

template stateJoin(parts: varargs[string]): string =
  ## WP2-a: AXIOM_STATE_DIR-aware path join (subject immutability).
  block:
    var acc = block:
      let v = getEnv("AXIOM_STATE_DIR")
      if v.len > 0: v else: getCurrentDir()
    for p in parts:
      acc = joinPath(acc, p)
    acc
import verification/vault_manifest
import engine/proof_certificate
import verification/proof_universe_commit
import verification/global_symbol_graph
import core/json/std_redirect
import core/parser_utils
import core/trusted/pnode_to_canon
import core/trusted/ast_to_ir

## ProofTask represents a fully-parsed, normalized proof request.
type
  ProofTask* = object
    limit*: QueueLimit
    vaultDir*: string
    emitJson*: bool
    maxRounds*: int
    budgetGas*: int
    target*: string
    planPath*: string               ## --plan <path> — consume an ExecutionPlan JSON
    propositionIntake*: PropositionIntake = PropositionIntake()
      ## BYOA 5.1: the accepted propositions intake (empty = no --proposals
      ## run). Assigned after buildProofTask; the default keeps every
      ## existing construction site source-compatible.

  GateEvent* = object
    gateName*: string
    passed*: bool
    timestamp*: int64
    detail*: string

  GateReporter* {.acyclic.} = ref object
    events*: seq[GateEvent]

  ProofReport* = object
    outputJson*: string
    logLines*: seq[string]
    exitCode*: int
    emitJson*: bool
    gateEvents*: seq[GateEvent]
    orchestrationNodeReports*: seq[OrchestrationNodeReport]
    canonicalRunResult*: CanonicalRunResult  ## X1 canonical boundary — authoritative execution source


  AxiomEngine* = object
    budget*: ProofBudget

  ## === FCIS: Pure Data Algebra (v3) ===
  ## All dependencies as values, side-effect spec as return data.
  ## No Mock needed for PBT — direct Table + tuple comparison.

  LedgerEvent* = object
    ## Pure data: one entry to be written to VSR ledger.
    ## Imperative Shell consumes this; Functional Core never touches disk.
    timestamp*: string
    vsr*: float
    vkd*: string
    verified*: int
    total*: int
    delta*: int
  ## Phase 10: Pipeline Parallelism — IR background thread context.
  ## Heap-allocated via `create(ParallelIrContext)` to bypass malebolgia's
  ## Nim 2.2 isolation check on seq/ref fields (ValidatedIrEntry contains
  ## IRFuncDef which contains IRExpr = ref object).
  ## AGENT-T: memoCache is per-worker — eliminates cross-thread global state.
  ## The worker thread reads entries and writes results back to the context.
  ParallelIrContext* = object
    entries: seq[ValidatedIrEntry]
    result: seq[IrPipelineResult]
    memoCache: Table[string, IrPipelineResult]
    subjectRoot: string  ## §2.1a: subject repo root for the canonical bound seal
                         ## (empty = internal-only path, binding fails closed)

proc irPipelineWorker*(ctx: ptr ParallelIrContext) {.thread, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ctx.result = runIrPipelinesFor(ctx.entries, ctx.memoCache, subjectRepoRoot = ctx.subjectRoot)

proc resolveVaultDir*(
  taskVaultDir: string;
  env: Table[string, string]
): string {.axiomDecision(id = "DECISION-0623", reason = "Backward-compat wrapper for resolveVaultDirForWrite; defaults to write mode (build/certificates)", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32"), raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Backward-compat wrapper: delegates to resolveVaultDirForWrite (write mode).
  ## Callers needing the current-product-trust read path should use
  ## resolveCertificate(cvRuntimeCanonical). Reference/engineering readers
  ## use resolveCertificate(cvCanonicalRead) for src/verification/certificates.
  result = resolveVaultDirForWrite(taskVaultDir, env)

proc computeGateAssessment*(
  batchReport: BatchUapReport;
  historicalVerified: int;
  totalSourceFunctions: int;
  kernelScope: KernelScopeInfo = KernelScopeInfo()
): tuple[canonicalState: CanonicalVKDState, netNewVerified: int, ledgerEvent: LedgerEvent] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Pure: compute ASI/VSR metrics and ledger event spec.
  ## All inputs are values — no IO, no JSON, no getEnv, no stderr.
  ## PBT can call this millions of times/sec with random data.
  ## Kernel-scope verified count is derived from the batch report's node reports
  ## limited to `kernelScope.kernelSymbols`, so non-kernel verifications (e.g.
  ## `parseJson`) are excluded from the cumulative VKD numerator.
  var kernelScopeVerifiedCount = 0
  for nodeReport in batchReport.orchestrationReport.nodeReports:
    let nodeIdStr = sorterNodeIdString(nodeReport.nodeId)
    if nodeIdStr in kernelScope.kernelSymbols:
      if nodeReport.status in [orchestrationVerified, orchestrationInductiveValid]:
        inc kernelScopeVerifiedCount
  let validatedReport = initValidatedProofReport(batchReport.orchestrationReport, totalSourceFunctions)
    .applyAntiVacuityGate()
    .applyAntiTautologySentinel()
  let canonicalState = computeCumulativeCanonicalVkd(validatedReport, historicalVerified, kernelScopeVerifiedCount)
  let netNewVerified = canonicalState.netVerifiedFunctions - historicalVerified

  let ledger = LedgerEvent(
    timestamp: canonicalState.timestamp,
    vsr: canonicalState.vsr,
    vkd: asString(canonicalState.vkd),
    verified: canonicalState.netVerifiedFunctions,
    total: canonicalState.totalFunctions,
    delta: netNewVerified
  )

  (canonicalState, netNewVerified, ledger)
proc buildVsrLedgerJson*(entry: LedgerEvent): JsonNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Pure: serialize one ledger event to JSON.
  ## Shell writes the result to disk.
  %*{
    "ts": entry.timestamp,
    "vsr": formatFloat(entry.vsr, ffDecimal, 4),
    "vkd": entry.vkd,
    "verified": entry.verified,
    "total": entry.total,
    "delta": entry.delta
  }
proc persistVsrLedger*(path: string; entry: LedgerEvent) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Imperative Shell: write one VSR ledger entry to append-only log.
  createDir(path.parentDir)
  var f = open(path, fmAppend)
  f.writeLine($buildVsrLedgerJson(entry))
  f.close()
proc executePipeline*(
  req: UniversalPipelineRequest
): VerificationOutcome {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Canonical IoC entry point for the Universal Acceptance Pipeline.
  ## Creates a PipelineContext, runs the closure iterator with
  ## the default persona dispatch, and returns the verification result.
  let dispatch = createDefaultPipelineDispatch()
  try:
    runPipelineWithDispatch(req, dispatch)
  except CatchableError:
    VerificationOutcome(exitKind: pekFailure, error: axiomErrInconsistentState, failureMessage: "pipeline dispatch exception")
proc buildProofTask*(
  flags: AxProveFlags;
  configVaultDir: string = "";
  configBudgetGas: int = 0;
  emitJson: bool = false
): Result[ProofTask, string] {.raises: [].} =
  ## Convert parsed CLI flags into the canonical domain task.
  ## Config values provide defaults; flags override.
  ## Boundary: int → QueueLimit conversion. 0 means unlimited.
  let queueLimit = if flags.limit > 0: capped(flags.limit.Positive)
                   else: unlimited()
  ok(ProofTask(
    limit: queueLimit,
    vaultDir: configVaultDir,
    emitJson: emitJson,
    maxRounds: 6,
    budgetGas: configBudgetGas,
    target: flags.target
  ))
proc initAxiomEngine*(startMono: int64; budgetGas: int = 0; expectedNodeCount: int = 0): AxiomEngine {.raises: [].} =
  ## Pure constructor — inject monotonic clock at the boundary.
  ## When budgetGas=0, auto-scales from expectedNodeCount × MaxGasCostPerNode.
  ## Falls back to maxTotalSolverInvocations when both are 0 (test compatibility).
  let gasLimit = if budgetGas > 0: budgetGas
                 elif expectedNodeCount > 0: expectedNodeCount * MaxGasCostPerNode
                 else: maxTotalSolverInvocations
  AxiomEngine(budget: initProofBudgetFromMono(startMono, gasLimit = gasLimit))
proc newGateReporter*(): GateReporter =
  GateReporter(events: @[])
proc report*(reporter: GateReporter; gateName: string; passed: bool; detail: string; timestamp: int64) =
  ## Pure report — inject monotonic clock at the boundary.
  reporter.events.add(GateEvent(
    gateName: gateName,
    passed: passed,
    timestamp: timestamp,
    detail: detail
  ))
proc collectVerifiedFuncNames*(verified: VerifiedSet; pool: InternPoolSnapshot; nodes: seq[SorterNode]): HashSet[string] {.raises: [].} =
  ## Convert the ProofVault `verifiedSet` (bitset over interned NodeId handles)
  ## into a set of bare function names matching `funcDef.name` in the IR
  ## registry. Each interned node resolves to `modulePath::functionName`; the
  ## function-name part (with any `*` export marker stripped) is what the IR
  ## pipeline compares against in selectRegistryEntries. Only nodes actually
  ## present in the current topology `nodes` are considered, guaranteeing
  ## consistency with the engine's verified frontier.
  result = initHashSet[string]()
  for node in nodes:
    let nodeIdOpt = nodeIdForSorter(pool, node.id)
    if nodeIdOpt.isSome and verified.contains(nodeIdOpt.get()):
      var funcName = node.functionName
      if funcName.endsWith("*"):
        funcName = funcName[0..^2]
      result.incl(funcName)
  
proc runBatchVerification*(
  engine: var AxiomEngine;
  task: ProofTask;
  state: var SorterState;
  requests: seq[OrchestrationProofRequest];
  topologyAnalysis: TopologyAnalysis = TopologyAnalysis();
  totalSourceFunctions: int = 0;
  historicalVerified: int = 0;
  verifiedFuncs: HashSet[string] = initHashSet[string]();
  kernelScope: KernelScopeInfo = KernelScopeInfo();
  externalCandidates: seq[ExternalIrEntry] = @[];
  subjectRepoRoot: string = "";
  targetVkd: string = ""
): Result[ProofReport, string] {.raises: [Exception, IOEffect], axiomEffect: IOEffect, tags: [TimeEffect, RootEffect, AxiomIOEffect, IOEffect].} =
  ## Full 4-layer pipeline path via batch UAP orchestrator.
  ## IO Shell: evaluates gates, delegates pure computation to computeGateAssessment.
  ## `subjectRepoRoot` is threaded to the canonical verification path (§2.1a
  ## subject binding): the analysis root, which IS the subject root for the
  ## external flow. `targetVkd` is the §13.1-frozen VKD baseline — read once at
  ## prepare, never re-read mid-run.
  logStage(skCliEntry, "", "ax prove started: " & $requests.len & " requests")
  let reporter = newGateReporter()

  # Gate 1: Pre-commit — quick syntax/structural validation
  let syntaxCheckPassed = requests.allIt(it.sourceCode.len > 0 and sorterNodeIdString(it.nodeId).len > 0)
  reporter.report(toDisplayName(toSemanticAlias("pre-commit")), syntaxCheckPassed, "structural validation of " & $requests.len & " requests", getMonoTime().ticks)

  # IO boundary: resolve vault dir from env + task config
  var envTable = initTable[string, string]()
  let envVaultRaw = getAxiomEnv(evProveVaultDir)
  if envVaultRaw.len > 0:
    envTable["AXIOM_PROVE_VAULT_DIR"] = envVaultRaw
  let vaultDir = resolveVaultDirForWrite(task.vaultDir, envTable)

  # Stall count: loaded from selection_state for deterministic threshold relaxation.
  var stallCount = 0
  block loadStallCount:
    # WP2-a: cache routes to stateRoot when set (subject immutability).
    let stateCacheDir = stateJoin(".axiom", "cache")
    var tmpSelState = loadSelectionState(stateCacheDir)
    stallCount = tmpSelState.stallCount

  # ── Phase 10: Pipeline Parallelism ─────────────────────────────────
  # Extract IR registry entries on main thread (TLS-safe data extraction),
  # then spawn IR pipeline in background thread while UAP runs in foreground.
  # §13.1 start-snapshot unification: the kernel scope and the VKD baseline
  # are the frozen prepared values (parameters) — no mid-run scope-lock or
  # baseline re-read (execution_accounting_contract.md §13.1).
  let irLimit = requests.len
  let irEntries = selectProofCandidates(irLimit, kernelScope.kernelTotal, targetVkd, verifiedFuncs, externalCandidates, subjectRepoRoot)
  logInfo("axiom_engine", "phase-10: IR extraction — " & $irEntries.len &
    "/" & $runtimeAxiomRegistry.len & " entries (limit=" & $irLimit & ")")

  let irCtx = create(ParallelIrContext)
  irCtx.entries = irEntries
  irCtx.subjectRoot = subjectRepoRoot
  var irThread: Thread[ptr ParallelIrContext]
  createThread(irThread, irPipelineWorker, irCtx)

  # ── Phase 10: Sync IR Background Thread ───────────────────────────
  # The honest certGreen short-circuit in loop_driver.stage2Budget requires
  # the IR pipeline results (z3Sat + leanSource) to be present while the UAP
  # loop runs. Join the IR thread first so preComputedIrResults is fully
  # populated before runBatchUapOrchestration consumes it.
  joinThread(irThread)
  let irResults = irCtx.result
  # Same-run CAS-keyed IR memo cache (populated by the background worker via
  # `runIrPipelinesFor(entries, ctx.memoCache)`). Extracted by value BEFORE
  # `dealloc(irCtx)` so the GC-backed Table buffer survives the struct free —
  # identical ownership pattern to `irResults = irCtx.result`. Reused by the
  # S9 refactor loop to avoid recomputing IR for identical inlined funcDefs
  # (same-run deterministic-derivation memo only; never cross-invocation).
  let sharedIrCache = irCtx.memoCache
  dealloc(irCtx)

  var currentRequests = requests
  var batchReport = runBatchUapOrchestration(
    state,
    currentRequests,
    vaultDir,
    topologyAnalysis = topologyAnalysis,
    maxRounds = task.maxRounds,
    gasLimit = engine.budget.gasTotal,
    stallCount = stallCount,
    preComputedIrResults = irResults,
    skipIrPipeline = false,
    kernelTotal = kernelScope.kernelTotal,
    targetVkd = targetVkd
  )

  # R8 persist leg: accumulate canonical-vault promotion failures from every
  # batch pass (the refactor loop below reassigns `batchReport`, so the
  # accumulator must live here, at function scope).
  var persistFailures: seq[string] = batchReport.persistFailures
  # Same accumulator discipline for the verification-axis IR pipeline failures
  # (surfaced as report.irPipelineFailures below — never the persist axis).
  var irPipelineFailures: seq[string] = batchReport.irPipelineFailures

  let irBatch = irResults.toCertificateBatch()
  for cert in irBatch.certificates:
    if cert.status == psSkip or cert.status == psNoObligation:
      let note = if cert.status == psNoObligation:
        " (no obligation — nothing to prove, excluded from VKD)"
      else:
        " (expected — type not BMC-representable or loop bound unresolved)"
      logInfo("axiom_engine", "IR pipeline skip: " & cert.functionName &
        " status=" & $cert.status & " provenance=" & cert.provenance & note)
    elif cert.status != psPass:
      logError("axiom_engine", "IR pipeline FAIL: " & cert.functionName &
        " status=" & $cert.status & " provenance=" & cert.provenance)
  logInfo("axiom_engine", "phase-10: IR pipeline completed — " & irBatch.formatSummary())

  # ── Phase 13: Content-Addressable Vault Manifest Sync ──────────────
  # Mirrors collectKernelSymbols normalization (axiom_pragmas_procs.nim) so
  # the manifest/certificate modulePath matches verification_scope.lock
  # kernel_symbols entries ("src/...::funcName") for VKD Set Membership.
  block vaultSync:
    proc scopeRelativeModulePath(rawPath: string): string =
      var modulePath = rawPath
      if modulePath.startsWith("src/"):
        discard
      elif modulePath.startsWith("/"):
        try:
          let rel = relativePath(modulePath, getCurrentDir(), '/')
          modulePath = if rel.startsWith("src/"): rel else: ""
        except CatchableError:
          modulePath = ""
      elif modulePath.find('/') >= 0:
        discard
      else:
        modulePath = ""
      modulePath

    let manifestPath = vaultDir / "manifest.json"
    var manifest = loadManifest(manifestPath)
    for cert in irBatch.certificates:
      if cert.irHash.len > 0:
        let modulePath = scopeRelativeModulePath(cert.sourceFile)
        let status = if cert.status == psPass: tierToStatusString(tierFromEvidence(CertificateEvidence(z3Passed: true, leanVerified: false)))
                     elif cert.status == psNoObligation: "certNoObligation"
                     elif cert.status == psFail: "certRed"
                     else: "certYellow"
        manifest.mergeResult(
          cert.functionName, modulePath, cert.irHash,
          status, $cert.solverMethod)
      manifest.atomicWriteManifest(manifestPath)
    logInfo("axiom_engine", "phase-13: vault manifest synced — " &
      $manifest.entries.len & " entries → " & manifestPath)

  # ── S9: Refactoring Re-verification Loop ──────────────────────────────
  # Lexicographic Progress Metric M = ⟨U, F⟩ for formal termination guarantee.
  # U = unverified items, F = refinement fuel. Well-founded ordering on ℕ×ℕ.
  # Fixed-point detection via state hash catches pipeline state cycles.
  var refactorResults: seq[RefactorResult] = @[]
  var refactorTaskNames: seq[string] = @[]
  var accumulatedEvidence = emptyEvidence()
  if batchReport.refactorTasks.len > 0:
    var vfs = RefactorVfs()
    const lexInitialFuel = 6
    var lexMetric = initLexMetric(batchReport.refactorTasks.len, lexInitialFuel)
    let maxCycles = batchReport.refactorTasks.len + lexInitialFuel + 1
    for cycle in 1 .. maxCycles:
      if batchReport.refactorTasks.len == 0:
        break
      var successfulRefactors = 0
      var stateFingerprints: seq[string]
      for task in batchReport.refactorTasks:
        stateFingerprints.add(task.sourceCode)
        let execResult = executeRefactorTask(task)
        refactorResults.add(execResult)
        accumulatedEvidence = combineEvidence(accumulatedEvidence, execResult.evidence)
        refactorTaskNames.add(task.functionName)
        case execResult.status
        of rsVerified:
          inc successfulRefactors
          vfsWrite(vfs, task.modulePath, task.functionName,
            task.sourceCode, execResult.refactoredSource)
        of rsSkipped:
          discard
        of rsEscalated:
          discard

      # Evaluate lexicographic progress metric
      let verifiedInBatch = batchReport.orchestrationReport.nodeReports.countIt(
        it.status == orchestrationVerified)
      let stateHash = computeStateHash(
        batchReport.orchestrationReport.nodeReports.len,
        batchReport.refactorTasks.len,
        verifiedInBatch,
        stateFingerprints)

      var currentUnverified = 0
      for task in batchReport.refactorTasks:
        inc currentUnverified

      let verdict = lexMetric.evaluate(currentUnverified, stateHash)
      case verdict
      of lvFixedPoint:
        logInfo("axiom_engine", "refactor loop: fixed-point detected at cycle " & $cycle &
          " — " & formatMetric(lexMetric))
        break
      of lvFuelExhausted:
        logInfo("axiom_engine", "refactor loop: fuel exhausted at cycle " & $cycle &
          " — escalating " & $batchReport.refactorTasks.len & " remaining")
        break
      of lvProgressReset:
        logInfo("axiom_engine", "refactor loop: progress at cycle " & $cycle &
          " — " & formatMetric(lexMetric))
      of lvFuelBurned:
        discard
      of lvContinue:
        discard

      if successfulRefactors == 0:
        break
      vfsCommitAll(vfs)
      currentRequests = syncRequestsFromVfs(vfs, currentRequests)
      batchReport = runBatchUapOrchestration(
        state,
        currentRequests,
        vaultDir,
        topologyAnalysis = topologyAnalysis,
        maxRounds = task.maxRounds,
        gasLimit = engine.budget.gasTotal,
        stallCount = stallCount,
        # Seed the refactor loop's IR memo cache with the first call's same-run
        # CAS-keyed results so identical inlined IR funcDefs are reused instead
        # of recomputed. NOT passed via preComputedIrResults: the refactor loop
        # selects a superset (verifiedFuncs empty here), so a flat pass-through
        # would drop IR results for functions absent from the first selection.
        sharedIrMemoCache = sharedIrCache,
        kernelTotal = kernelScope.kernelTotal,
        targetVkd = targetVkd
      )
      persistFailures &= batchReport.persistFailures
      irPipelineFailures &= batchReport.irPipelineFailures
    # Flush VFS to disk after all cycles
    if vfs.entries.len > 0:
      if not flushVfsToDisk(vfs):
        logError("axiom_engine", "VFS flush failed — refactored source may be lost")
        if existsEnv("AXIOM_STRICT_VFS"):
          raise newException(CatchableError, "CRITICAL: VFS flush failed in strict mode")
  # 렌더링 경계: 코어 루프 외부에서 디스패치
  dispatchRefactorReport(refactorResults, refactorTaskNames)

  # Gate 2: Pre-push — verification success rate
  let rawVerified = batchReport.orchestrationReport.nodeReports.countIt(it.status == orchestrationVerified)
  let inductiveCount = batchReport.orchestrationReport.nodeReports.countIt(it.status == orchestrationInductiveValid)
  let vacuousCount = batchReport.orchestrationReport.nodeReports.countIt(it.status == orchestrationVacuousContradiction)
  let verifiedCount = int(computeVerified(rawVerified, inductiveCount, vacuousCount))
  let allPassed = verifiedCount == batchReport.orchestrationReport.nodeReports.len and batchReport.orchestrationReport.nodeReports.len > 0
  reporter.report(toDisplayName(toSemanticAlias("pre-push")), allPassed, "verified " & $verifiedCount & "/" & $batchReport.orchestrationReport.nodeReports.len & " nodes (inductiveValid=" & $inductiveCount & ")", getMonoTime().ticks)

  # Gate 3: CI/CD — budget healthy and depth coverage
  let budgetHealthy = batchReport.budget.gasRemaining >= 0
  let depthCoverage = batchReport.orchestrationReport.executionStats.depthStats.len > 0
  reporter.report(toDisplayName(toSemanticAlias("ci-cd")), budgetHealthy and depthCoverage, "budgetRemaining=" & $batchReport.budget.gasRemaining & " depthCoverage=" & $depthCoverage, getMonoTime().ticks)

  # Pure computation: ASI/VSR metrics + ledger event spec (no IO, no JSON)
  let (canonicalState, _, ledgerEvent) = computeGateAssessment(
    batchReport, historicalVerified, totalSourceFunctions, kernelScope)

  # IO Shell: JSON building, stderr, logging, VSR ledger
  var reportJson = jsonFromOrchestrationReport(batchReport.orchestrationReport, totalSourceFunctions)
  reportJson["refactorSummary"] = jsonRefactorSummary(batchReport.refactorTasks)
  reportJson["refactorEvidence"] = accumulatedEvidence.toCanonicalJson()
  var gateArr = newJArray()
  for ev in reporter.events:
    gateArr.add(%*{
      "gate": ev.gateName,
      "passed": ev.passed,
      "timestamp": ev.timestamp,
      "detail": ev.detail
    })
  reportJson["gates"] = gateArr
  # LEGACY-LABEL: this field was historically named "vkd" but is NOT the canonical
  # Verified Kernel Density. It is the cumulative full-function success rate
  # (netVerifiedFunctions / totalSourceFunctions over all 40 kernel functions,
  # denominator = |Kernel| = kernel_total, NOT |VKS| = 23). Canonical VKD
  # (|VKS ∩ certGreen| / |VKS|) lives in report_json["metrics"]["vkd"], wired
  # from getCanonicalVkdMetrics in report_cli.nim (Phase 3 single-canonical-wire).
  # Renamed to verifiedRatio so no user-facing output claims "vkd" here.
  reportJson["summary"]["verifiedRatio"] = %(safeParseFloat(asString(canonicalState.vkd)).getOrDefault(0.0))
  reportJson["summary"]["vsr"] = %canonicalState.vsr
  reportJson["summary"]["completionRate"] = %canonicalState.completionRate
  reportJson["summary"]["verified"] = %canonicalState.netVerifiedFunctions
  reportJson["summary"]["netVerifiedFunctions"] = %canonicalState.netVerifiedFunctions
  reportJson["summary"]["vacuousDemotions"] = %canonicalState.vacuousDemotions
  reportJson["summary"]["tautologyDemotions"] = %canonicalState.tautologyDemotions

  # S11: ASI reflection — refactored-then-verified nodes are counted as
  # orchestrationVerified in the final batchReport, naturally reflected in
  # canonicalState.netVerifiedFunctions. Explicit repair count for audit.
  let refactorRepairedCount = canonicalState.netVerifiedFunctions
  reportJson["summary"]["refactorRepaired"] = %refactorRepairedCount
  # v1 report document identity (Phase 5 contract): every prove output document
  # carries the schema version; report_cli rejects states with a different one.
  reportJson["schemaVersion"] = %axiomReportSchemaVersion

  # R8 persist leg: a promotable certificate whose canonical-vault promotion
  # failed is a persist FAIL — surfaced in the report document and as a distinct
  # exit code (2 = INTERNAL_ERROR), never silently swallowed. Verification
  # failures (run produced no promotable cert) keep their pre-existing exit-1
  # semantics via axProofShortcutExitCode.
  if persistFailures.len > 0:
    reportJson["persistFailed"] = %true
    reportJson["persistFailures"] = %persistFailures
    logError("axiom_engine", "PERSIST FAIL: " & $persistFailures.len &
      " promotable certificate(s) failed canonical promotion")
    for pf in persistFailures:
      logError("axiom_engine", "  - " & pf)
  else:
    reportJson["persistFailed"] = %false

  # Verification-axis observability: IR pipeline failures of kernel units are
  # verification failures of those units, not persist failures — they surface
  # here (and in the IR batch summary + ERROR logs) without coupling the exit
  # axis, which stays the §7 run-exit rule over the summary.
  reportJson["irPipelineFailures"] = %irPipelineFailures

  # §2.4d display-scope evidence projection (wave-stage, in-memory only): the
  # per-unit claim/quartet ref the display builder joins on — keyed
  # `modulePath::funcName`, verbatim claim identity + the §2.2 payload lines.
  # Reference COPY of already-decided records (no new authority); the wave
  # loop merges these into the run's unitEvidence map and nothing here is
  # persisted beyond the display block the builder derives from it.
  block unitEvidenceProjection:
    var unitEvidence = newJObject()
    for r in irResults:
      let key = r.modulePath & "::" & r.funcName
      if key.len <= 2 or unitEvidence.hasKey(key):
        continue
      var node = newJObject()
      if r.verifiedClaim.isSome:
        let c = r.verifiedClaim.get()
        node["claimId"] = %c.claimId
        node["claimOutcome"] = %($c.outcome)
        node["evidenceId"] = %c.evidenceId
        node["obligationId"] = %c.obligationId
        node["specificationId"] = %c.specificationId
      if r.counterExample.len > 0:
        node["counterExample"] = %r.counterExample
      if node.len > 0:
        unitEvidence[key] = node
    reportJson["unitEvidenceRefs"] = unitEvidence

  let exitCode = if persistFailures.len > 0: CliOutcome.INTERNAL_ERROR.exitCode()
                 else: axProofShortcutExitCode(reportJson,
                   requirePerfectAsi = getAxiomEnv(evRequirePerfectAsi) == "1",
                   continueOnError = getAxiomEnv(evContinueOnError) == "1")
  # LEGACY-LABEL log: canonicalState.vkd is the cumulative full-function success
  # rate over |Kernel|=40 (netVerifiedFunctions / totalSourceFunctions), NOT
  # canonical VKD (|VKS ∩ certGreen| / |VKS| = 23, reported in metrics.vkd).
  logInfo("axiom_engine", "done: verifiedRatio=" & asString(canonicalState.vkd) & ", verified=" & $canonicalState.netVerifiedFunctions & "/" & $canonicalState.totalFunctions)
  logStage(skReport, "", "pipeline completed", extra=reportJson)
  try:
    # WP2-a: VSR ledger routes to stateRoot when set.
    persistVsrLedger(stateJoin("logs", "audit", "vsr_ledger.jsonl"), ledgerEvent)
  except CatchableError as e:
    stderr.writeLine("[WARN] VSR audit ledger write failed: " & e.msg)

  ok(ProofReport(
    outputJson: renderJsonMultiline(reportJson),
    logLines: renderVerifyWorkflowProgressLines(batchReport.orchestrationReport) &
      renderRefactorSummaryLines(batchReport.refactorTasks),
    exitCode: exitCode,
    emitJson: task.emitJson,
    gateEvents: reporter.events,
    orchestrationNodeReports: batchReport.orchestrationReport.nodeReports
  ))

proc captureRunReuseContext*(): ReuseVerificationContext {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Current reuse-verification context (execution path). Delegates to the ONE
  ## measurement site, verification/accounting/execution_context, which the
  ## report read path uses too — so a state written by this run re-validates
  ## against a later reader on the same host by construction rather than by two
  ## copies of the same contract staying in sync. Fail-closed: a component that
  ## cannot be measured stays empty and no reuse record can match it.
  captureReuseVerificationContext()

proc verifyReuseArtifacts(waves: seq[JsonNode]) {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Plan 1 — condition (d) per-READ content re-verification: for every
  ## cache-hit nodeReport carrying a reuseRecord, re-read the referenced
  ## concrete artifact and recompute its SHA-256. The record is marked
  ## artifactVerified=true ONLY on an exact contentDigest match; missing
  ## file / read failure / digest mismatch → artifactVerified=false, so the
  ## reducer classifies the row fail-closed PENDING.
  for wave in waves:
    let nr = wave{"nodeReports"}
    if nr.isNil or nr.kind != JArray: continue
    for row in nr.elems:
      if row.isNil or row.kind != JObject: continue
      let record = row{"reuseRecord"}
      if record.isNil or record.kind != JObject: continue
      let artifactRef = record{"artifactRef"}.getStr("")
      if artifactRef.len == 0: continue
      var verified = false
      try:
        if fileExists(artifactRef):
          verified = sha256Hex(readFile(artifactRef)) ==
                     record{"contentDigest"}.getStr("")
      except CatchableError:
        verified = false  # fail-closed: unreadable artifact is never reusable
      record["artifactVerified"] = %verified

proc renderPersist*(
  statePath: string;
  runResult: CanonicalRunResult;
  preRun: JsonNode;
  projections: JsonNode;
  display: JsonNode = nil;
  findingEvidence: JsonNode = nil
): Result[string, string] {.raises: [CatchableError].} =
  ## State-file projection: the post-loop persist writes
  ## projection(RunResult, PreRunContext) — the last-wave document is never
  ## written to the state file (X1 canonical boundary, DEBT#458 closed).
  ## `display` = the caller's already-built per-unit display container
  ## (display v3) — the per-unit resolution itself, never a hardwired entry
  ## constant; nil = no block (never fabricated here).
  ## `findingEvidence` = the WP-B per-unit canonical evidence carrier keyed
  ## by targetSymbol (machine observations + raw quartet payload lines +
  ## subject probe identity) — a FIXED reporter-consumed interface persisted
  ## at the state document ROOT (never a display-unit key); nil = no block.
  let reportJson = renderLegacyReport(runResult, preRun, projections)
  if not display.isNil:
    reportJson["display"] = display
  if not findingEvidence.isNil:
    reportJson["findingEvidence"] = findingEvidence
  persistAxProofState(statePath, reportJson)

# DEBT#458 marker removed — canonical boundary installed (Phase X1): the wave
# loop accumulates per-wave reports; the post-loop merge no longer copies only
# the FINAL wave's summary/nodeReports/executionStats into reportJson. The
# legacy report, the state file and the TrustCommit projection are pure
# projections of (CanonicalRunResult, PreRunContext) — see run_accounting.nim.

proc runCrossValidation(processedLimit: int): JsonNode {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Phase 1E: cross-validate IR → SMT and IR → Lean structural consistency.
  ## Fail-open: logs status but does not block the pipeline.
  ## Scope: only cross-validate entries that were processed by the IR pipeline
  ## (bounded by the MERGED request count across waves), not the entire
  ## registry. Matches the selection criteria in selectRegistryEntries.
  logInfo("axiom_engine", "cross-validation: running IR consistency check (scope=" & $processedLimit & ")...")
  if runtimeAxiomRegistry.len == 0:
    logInfo("axiom_engine", "cross-validation: no axioms registered (empty registry)")
    return %*{"consistent": true, "functionCount": 0}

  var allConsistent = true
  var checkedCount = 0
  var consistentCount = 0
  var vacuousCount = 0
  for entry in runtimeAxiomRegistry:
    # Stop once we've checked as many valid entries as the IR pipeline processed.
    # This mirrors selectRegistryEntries(limit) in loop_driver.nim.
    if checkedCount >= processedLimit:
      break
    let funcDef = deserializeIRFuncDef(entry.irSerialized)
    # Sentinel check: empty name means deserialization failed — skip without counting
    if funcDef.name.len == 0:
      continue
    let cvResult = crossValidate(funcDef)
    inc checkedCount
    if cvResult.consistent:
      # Both representations produced and structurally consistent.
      inc consistentCount
      logInfo("axiom_engine", "[axiom_engine] cross-validated: " & entry.name &
                       " digest=" & cvResult.irDigest)
    elif cvResult.z3Result.len == 0:
      # Vacuous: irToSmtScript returns "" when there are no postconditions
      # (or the entry is BMC-unverifiable), so no verification actually ran.
      # This is not a consistency failure — report at INFO, not ERROR.
      inc vacuousCount
      logInfo("axiom_engine", "[axiom_engine] cross-validation skipped (vacuous — no postconditions): " &
                       entry.name & " digest=" & cvResult.irDigest)
    elif cvResult.leanResult.len == 0:
      # SMT produced but Lean produced no output — nothing to compare against.
      inc vacuousCount
      logInfo("axiom_engine", "[axiom_engine] cross-validation skipped (no lean output): " &
                       entry.name & " digest=" & cvResult.irDigest)
    else:
      # Both representations produced but structurally inconsistent — genuine failure.
      allConsistent = false
      logError("axiom_engine", "[axiom_engine] CROSS-VALIDATION FAILED: " & entry.name &
                       " digest=" & cvResult.irDigest)
  %*{"consistent": allConsistent, "functionCount": runtimeAxiomRegistry.len,
    "checked": checkedCount, "consistentCount": consistentCount,
    "vacuous": vacuousCount, "scope": processedLimit}

proc runLeanVerifyBlock(): tuple[json: JsonNode, errMsg: string] {.raises: [Exception, IOEffect], axiomEffect: IOEffect, tags: [TimeEffect, RootEffect, AxiomIOEffect, IOEffect].} =
  ## Phase 3B: Verify proofs/ compiles cleanly via an isolated lake build.
  ## sorry → hard fail (certRed); build failure → hard fail. WP2-a skips this
  ## entirely in external subject mode, where there is no proofs/ directory.
  logInfo("axiom_engine", "lean-verify: running sandbox verification of proofs/...")
  let leanVerifyStartMs = getMonoTime().ticks
  let leanResult = runLeanVerify()
  let leanVerifyElapsedMs = int((getMonoTime().ticks - leanVerifyStartMs) div 1_000_000)
  logStage(skReport, "", "lean-verify completed", elapsedMs=leanVerifyElapsedMs)

  for line in leanResult.logLines:
    logInfo("axiom_engine", line)

  # Hard fail on sorry — proofs with sorry are invalid certificates
  if leanResult.sorryFound:
    return (nil, "lean-verify: HARD FAIL — sorry found in proofs/ directory. " &
      "All proofs must be fully verified (no sorry allowed).")

  # Hard fail on sandbox/build errors — proofs must compile
  if not leanResult.success and leanResult.exitCode != 0:
    return (nil, "lean-verify: FAIL — lake build failed (exit code: " & $leanResult.exitCode & "). " &
      "Fix Lean compilation errors before running ax prove.")

  (%*{
    "success": leanResult.success,
    "sorryFound": leanResult.sorryFound,
    "exitCode": leanResult.exitCode,
    "axiomsUsed": leanResult.axiomsUsed.len
  }, "")

type
  ExternalCandidateCensus* = ref object
    ## The one mutable accumulator the frontier eligibility gate writes to.
    ## A reference is what lets the gate keep the `proc(fnName, modulePath)`
    ## shape `selectFrontierNodes` takes while still accumulating across the
    ## frontier — a captured `var` would dangle once its factory returned.
    eligible*: seq[ExternalIrEntry]      ## candidates that passed the gate
    records*: seq[CandidateCensusRecord] ## every external candidate examined

proc isRegistryEligible*(fnName: string): bool {.raises: [].} =
  ## Registry-hit branch of the frontier gate. Strip a single trailing `*`
  ## export marker via the guarded canonical helper (a lone `"*"` operator name
  ## and empty names are left unchanged), then look the bare name up in the
  ## compile-time registry. Unknown names are not eligible.
  let bare = stripPostfixExportMarker(fnName)
  for entry in runtimeAxiomRegistry:
    if entry.name != bare or entry.irSerialized.len == 0:
      continue
    let funcDef = deserializeIRFuncDef(entry.irSerialized)
    if funcDef.name.len > 0:
      return classifyCandidateEligibility(entry, funcDef) == elProofCandidate
  false

# ---------------------------------------------------------------------------
# Base36 sizing binding overlay (docs/spec/base36_sizing_binding_contract.md)
# ---------------------------------------------------------------------------
# The out-of-tree explicit spec overlay is the only legitimate home of the
# relational sizing claim over the READ-ONLY subject tree. It is loaded here —
# the CLI layer — and any absence/parse/shape failure blocks `ax prove`
# outright (fail closed): a run that cannot establish the spec's authority
# must not silently degrade to single-symbol census behavior.

proc runtimeSpecOverlayPath*(fileName: string): Result[string, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Axiom-owned overlay path, RUNTIME-resolved through the S2b seam
  ## (`resolveExternalSubjectSpecDir`, productization contract §1b): AXIOM_ROOT
  ## first, else the strict anchor walk from the binary — the release bundle
  ## carries config/spec under its own root, so a tree-external bundle binary
  ## resolves ITS catalog. The former compile-time `repoRootConst()` join baked
  ## the build machine's path into the bundle binary and failed every
  ## external run (ax prove exit 2 at prepareProofRun). Shared by the legacy
  ## lane loaders below (sizing, rem, d2-agent, sidecar — the registry-flipped
  ## lanes already resolve through the same seam). The subject repository
  ## stays byte-identical (Zero-Footprint).
  let dirRes = resolveExternalSubjectSpecDir()
  if dirRes.isErr():
    return err(dirRes.error)
  ok(dirRes.get / fileName)

const Base36SizingOverlayFile* = "base36_sizing_relational_spec.json"
  ## The sizing lane's catalog document — the enumeration identity under
  ## config/spec (the registry loader and this lane's legacy load name the
  ## same file).

const Base36SizingCompositeName* = "roundtrip_dec_enc"
  ## Name of the synthesized relational candidate
  ## decodedLength(encodedLength(n)) under the overlay's domain.



type
  Base36OverlayDomain* = object
    ## The synthesis-relevant projection of the overlay: which module and
    ## symbols it governs, which composition the roundtrip clause fixes
    ## (`outer(inner(v)) == v`), and the width-derived domain bound. Everything
    ## here is parsed mechanically from the overlay document — no subject
    ## names are hardcoded in the engine.
    modulePath*: string
    symbols*: seq[string]
    outerSymbol*: string  ## the roundtrip's outer call (decodedLength)
    innerSymbol*: string  ## the roundtrip's inner call (encodedLength)
    domainVar*: string    ## the clause variable the domain binds
    domainLower*: int64   ## from the "0 <= n" clause
    domainBound*: int64   ## from the "n <= <bound>" clause (64-bit fixed)

func isIdentLike(s: string): bool {.raises: [].} =
  if s.len == 0: return false
  for c in s:
    if not (c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}): return false
  true

func isIntLiteral(s: string): bool {.raises: [].} =
  if s.len == 0: return false
  for c in s:
    if c notin {'0'..'9'}: return false
  true

proc parseRoundtripClause(clause: string): Option[(string, string, string)] {.
    raises: [].} =
  ## "<outer>(<inner>(<v>)) == <v>" → (outer, inner, v); none otherwise.
  let eq = clause.split("==")
  if eq.len != 2: return none((string, string, string))
  let lhs = eq[0].strip
  let rhs = eq[1].strip
  if not isIdentLike(rhs): return none((string, string, string))
  if not lhs.endsWith("))"): return none((string, string, string))
  let open1 = lhs.find('(')
  if open1 <= 0: return none((string, string, string))
  let outer = lhs[0 ..< open1].strip
  if not isIdentLike(outer): return none((string, string, string))
  let mid = lhs[(open1 + 1) ..< (lhs.len - 1)].strip
  let open2 = mid.find('(')
  if open2 <= 0: return none((string, string, string))
  if not mid.endsWith(")"): return none((string, string, string))
  let inner = mid[0 ..< open2].strip
  if not isIdentLike(inner): return none((string, string, string))
  let arg = mid[(open2 + 1) ..< (mid.len - 1)].strip
  if not isIdentLike(arg) or arg != rhs:
    return none((string, string, string))
  some((outer, inner, arg))

proc parseUpperDomainClause(clause: string): Option[(string, int64)] {.raises: [].} =
  ## "<ident> <= <INT>" → (ident, bound); none otherwise.
  let parts = clause.split("<=")
  if parts.len != 2: return none((string, int64))
  let lhs = parts[0].strip
  let rhs = parts[1].strip
  if not isIdentLike(lhs) or not isIntLiteral(rhs):
    return none((string, int64))
  let parsed = safeParseInt(rhs)
  if parsed.isOk:
    some((lhs, parsed.value.int64))
  else:
    none((string, int64))

proc parseLowerDomainClause(clause: string): Option[(int64, string)] {.raises: [].} =
  ## "<INT> <= <ident>" → (bound, ident); none otherwise.
  let parts = clause.split("<=")
  if parts.len != 2: return none((int64, string))
  let lhs = parts[0].strip
  let rhs = parts[1].strip
  if not isIntLiteral(lhs) or not isIdentLike(rhs):
    return none((int64, string))
  let parsed = safeParseInt(lhs)
  if parsed.isOk:
    some((parsed.value.int64, rhs))
  else:
    none((int64, string))

proc loadBase36OverlayDomain*(): Result[Base36OverlayDomain, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D1: read + validate the overlay. `explicitSpecFromOverlay` pins the
  ## origin to soExplicit and fails closed on anything else; the
  ## synthesis-relevant fields are parsed from the same document mechanically.
  var node: JsonNode
  let pathRes = runtimeSpecOverlayPath(Base36SizingOverlayFile)
  if pathRes.isErr():
    return err("cannot resolve the spec overlay directory (fail-closed): " &
      pathRes.error)
  let overlayPath = pathRes.get
  let nodeOpt = readJsonFile(overlayPath)
  if nodeOpt.isNone:
    return err("cannot read spec overlay " & overlayPath &
      " (missing, unreadable, or not valid JSON)")
  node = nodeOpt.get
  let specRes = explicitSpecFromOverlay(node)
  if specRes.isErr():
    return err("spec overlay rejected: " & specRes.error)
  let subject = node{"subject"}
  if subject.isNil or subject.kind != JObject:
    return err("spec overlay: subject object required")
  let modulePath = subject{"module"}.getStr("")
  let symbolsNode = subject{"symbols"}
  if modulePath.len == 0 or symbolsNode.isNil or symbolsNode.kind != JArray or
      symbolsNode.len < 2:
    return err("spec overlay: subject.module and >= 2 subject.symbols required")
  var symbols: seq[string]
  for s in symbolsNode:
    if s.kind != JString or s.getStr("").len == 0:
      return err("spec overlay: subject.symbols entries must be non-empty strings")
    symbols.add(s.getStr(""))
  var lowerOpt = none((int64, string))
  var upperOpt = none((string, int64))
  var roundtripOpt = none((string, string, string))
  for clause in specRes.value.canonicalSpecIR:
    let lowerParsed = parseLowerDomainClause(clause)
    let upperParsed = parseUpperDomainClause(clause)
    let roundtripParsed = parseRoundtripClause(clause)
    if lowerParsed.isSome:
      if lowerOpt.isSome:
        return err("spec overlay: ambiguous lower domain clause")
      lowerOpt = lowerParsed
    if upperParsed.isSome:
      if upperOpt.isSome:
        return err("spec overlay: ambiguous upper domain clause")
      upperOpt = upperParsed
    if roundtripParsed.isSome:
      if roundtripOpt.isSome:
        return err("spec overlay: ambiguous roundtrip clause")
      roundtripOpt = roundtripParsed
  if lowerOpt.isNone or upperOpt.isNone or roundtripOpt.isNone:
    return err("spec overlay: canonicalSpecIR must contain the '0 <= n', " &
      "'n <= <bound>' and '<outer>(<inner>(n)) == n' clauses")
  let (lower, lowerVar) = lowerOpt.get
  let (upperVar, bound) = upperOpt.get
  let (outerSym, innerSym, rtVar) = roundtripOpt.get
  if lowerVar != upperVar or upperVar != rtVar:
    return err("spec overlay: domain clauses must bind one variable")
  if outerSym notin symbols or innerSym notin symbols:
    return err("spec overlay: roundtrip symbols must be subject.symbols members")
  ok(Base36OverlayDomain(
    modulePath: modulePath, symbols: symbols,
    outerSymbol: outerSym, innerSymbol: innerSym,
    domainVar: rtVar, domainLower: lower, domainBound: bound))

proc overlayDeclaresSubject*(domain: Base36OverlayDomain; fnName,
    modulePath: string): bool {.raises: [].} =
  ## D4 membership: the gate hit is a subject the overlay governs.
  modulePath == domain.modulePath and fnName in domain.symbols

# ---------------------------------------------------------------------------
# Base32 rem-range binding overlay (docs/spec/nim_stew_base32_rem_binding_contract.md)
# ---------------------------------------------------------------------------
# Second out-of-tree explicit spec overlay, same authority pattern as the base36
# sizing overlay: the claim over the READ-ONLY subject lives only in this repo's
# config/spec, is pinned to soExplicit by explicitSpecFromOverlay, and any
# absence/parse/shape failure blocks `ax prove` (fail closed).
#
# The subject computes `let reminder = length mod 8` (stew/base32.nim:80 in
# decodedLength). The claim is the remainder-range relational theorem over
# that term: on the nonnegative-dividend domain, Nim's truncated `mod` and
# Lean's `Int.emod` coincide (Int.tmod_eq_emod_of_nonneg), and emod by 8 is
# exactly in 0..7. (Sibling `encodedLength`/mod 5 measured EA_UNSUPPORTED —
# its `when` is outside the certified-subset wire set; see the contract §2.)

const Base32RemOverlayFile* = "nim_stew_base32_rem_spec.json"
  ## Axiom-owned overlay document name (Zero-Footprint; runtime root
  ## resolution via `runtimeSpecOverlayPath`).

const Base32RemCandidateName* = "decodedLength_rem_range"
  ## Name of the synthesized remainder-range candidate over decodedLength.
  ## The name must never collide with a subject symbol — the claim is the
  ## overlay's, not a symbol the subject source declares.

type
  Base32RemOverlayDomain* = object
    ## The synthesis-relevant projection of the rem overlay: which module and
    ## symbol it governs, the dividend variable name, the divisor literal
    ## the claim constrains, and the spec rule identity the carrier binding
    ## records. Parsed mechanically from the overlay document.
    modulePath*: string
    symbol*: string
    dividendVar*: string ## the `0 <= <var>` clause variable (Nim param name)
    divisor*: int64      ## the mod divisor the range clause fixes
    ruleId*: string      ## the overlay spec's ruleId (carrier binding digest)

func parseRemLowerClause(clause: string): Option[(string, int64)] {.raises: [].} =
  ## "0 <= <ident>" → (ident, 0); none otherwise. The lower bound is
  ## structurally zero: the coincidence domain of truncated and nonnegative
  ## remainder starts at a nonnegative dividend.
  let parts = clause.split("<=")
  if parts.len != 2: return none((string, int64))
  let lhs = parts[0].strip
  let rhs = parts[1].strip
  if not isIntLiteral(lhs) or not isIdentLike(rhs): return none((string, int64))
  let parsed = safeParseInt(lhs)
  if parsed.isErr or parsed.value.int64 != 0: return none((string, int64))
  some((rhs, 0'i64))

func parseRemRangeClause(clause: string; v: string; d: int64): Option[string] {.
    raises: [].} =
  ## "<ident> mod <D> <= <BOUND>" → the ident, when it matches (v, d) and the
  ## bound is exactly d-1 (the closed top of the remainder range for divisor
  ## d). Any other shape is rejected — the overlay states ONE theorem.
  let tokens = clause.split({' '})
  if tokens.len != 5: return none(string)
  if tokens[1] != "mod" or tokens[3] != "<=": return none(string)
  if tokens[0] != v or not isIntLiteral(tokens[2]) or not isIntLiteral(tokens[4]):
    return none(string)
  let divisor = safeParseInt(tokens[2])
  let bound = safeParseInt(tokens[4])
  if divisor.isErr or bound.isErr: return none(string)
  if divisor.value.int64 != d or bound.value.int64 != d - 1: return none(string)
  some(tokens[0])

func parseRemGeZeroClause(clause: string; v: string; d: int64): Option[string] {.
    raises: [].} =
  ## "<ident> mod <D> >= 0" → the ident, when it matches (v, d).
  let tokens = clause.split({' '})
  if tokens.len != 5: return none(string)
  if tokens[1] != "mod" or tokens[3] != ">=": return none(string)
  if tokens[0] != v or not isIntLiteral(tokens[2]) or tokens[4] != "0":
    return none(string)
  let divisor = safeParseInt(tokens[2])
  if divisor.isErr or divisor.value.int64 != d: return none(string)
  some(tokens[0])

proc loadBase32RemOverlayDomain*(): Result[Base32RemOverlayDomain, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D1 for the rem overlay: read + validate via the same
  ## `explicitSpecFromOverlay` authority path as the base36 overlay.
  var node: JsonNode
  let pathRes = runtimeSpecOverlayPath(Base32RemOverlayFile)
  if pathRes.isErr():
    return err("cannot resolve the spec overlay directory (fail-closed): " &
      pathRes.error)
  let overlayPath = pathRes.get
  let nodeOpt = readJsonFile(overlayPath)
  if nodeOpt.isNone:
    return err("cannot read spec overlay " & overlayPath &
      " (missing, unreadable, or not valid JSON)")
  node = nodeOpt.get
  let specRes = explicitSpecFromOverlay(node)
  if specRes.isErr():
    return err("spec overlay rejected: " & specRes.error)
  let subject = node{"subject"}
  if subject.isNil or subject.kind != JObject:
    return err("spec overlay: subject object required")
  let modulePath = subject{"module"}.getStr("")
  let symbolsNode = subject{"symbols"}
  if modulePath.len == 0 or symbolsNode.isNil or symbolsNode.kind != JArray or
      symbolsNode.len != 1:
    return err("spec overlay: subject.module and exactly 1 subject.symbols required")
  let symbol = symbolsNode[0].getStr("")
  if symbol.len == 0:
    return err("spec overlay: subject.symbols entries must be non-empty strings")
  let clauses = specRes.value.canonicalSpecIR
  if clauses.len != 3:
    return err("spec overlay: canonicalSpecIR must contain exactly the " &
      "'0 <= length', '<v> mod <d> >= 0', '<v> mod <d> <= <d-1>' clauses")
  let lowerParsed = parseRemLowerClause(clauses[0])
  if lowerParsed.isNone:
    return err("spec overlay: first clause must be '0 <= <dividend>'")
  let (dividendVar, _) = lowerParsed.get
  let divisorCandidate = block:
    # The divisor is fixed by the two range clauses and must agree between them.
    var found = none(int64)
    for clause in clauses[1 .. ^1]:
      let tokens = clause.split({' '})
      if tokens.len == 5 and tokens[1] == "mod" and isIntLiteral(tokens[2]):
        let parsed = safeParseInt(tokens[2])
        if parsed.isOk:
          let d = parsed.value.int64
          if found.isSome and found.get != d:
            return err("spec overlay: range clauses must name one divisor")
          found = some(d)
    found
  if divisorCandidate.isNone:
    return err("spec overlay: range clauses must name an integer divisor")
  let divisor = divisorCandidate.get
  let geZero = parseRemGeZeroClause(clauses[1], dividendVar, divisor)
  let leTop = parseRemRangeClause(clauses[2], dividendVar, divisor)
  if geZero.isNone or leTop.isNone:
    return err("spec overlay: clauses 2-3 must be '<v> mod <d> >= 0' and " &
      "'<v> mod <d> <= <d-1>' over the dividend of clause 1")
  ok(Base32RemOverlayDomain(
    modulePath: modulePath, symbol: symbol,
    dividendVar: dividendVar, divisor: divisor,
    ruleId: specRes.value.ruleId))

func overlayDeclaresRemSubject*(domain: Base32RemOverlayDomain; fnName,
    modulePath: string): bool {.raises: [].} =
  ## D4 membership for the rem overlay: the gate hit is the subject symbol the
  ## overlay governs.
  modulePath == domain.modulePath and fnName == domain.symbol

# ---------------------------------------------------------------------------
# Base36 C_out out-sizing overlay (docs/spec/nim_stew_base36_cout_contract.md)
# ---------------------------------------------------------------------------
# Third out-of-tree explicit spec overlay, same authority pattern as the
# base36 sizing / base32 rem overlays: the claim over the READ-ONLY subject
# lives only in this repo's config/spec, is pinned to soExplicit by
# explicitSpecFromOverlay, and any absence/parse/shape failure blocks
# `ax prove` (fail closed).
#
# The claim is the output-sizing bound C_out: the sizing helper's estimate must
# dominate decode's actual output length. K = 2 is an EXTERNAL OBSERVATION
# (decode("kzz", buf >= 6) == Success, outlen = 2, read-only probe outside the
# subject tree) pinned as a CLAIM CONSTANT by the contract's K-pin condition —
# the pipeline refutes the claim against the pinned constant; it never
# re-derives K. The obligation is rendered OPEN over L with a literal domain
# pin (3 <= L and L <= 3): a closed arithmetic proposition would starve the
# SAT model binding, the exact-input gate, and the P4 pre-revalidation
# (contract §2 — 닫힌 명제 금지).

const coutRegistryEntryRelPath* = "nim_stew_base36_cout_spec.json"
  ## The C_out lane's registry document identity (REGISTRY_SPEC §5 PR-4):
  ## the flip gate and the mandatory-presence anchor. The per-lane path const
  ## is GONE with the flip: the §2.8 direct consumers (probeSubjectIdentity /
  ## buildBugVerdictDisplayJson) resolve every governed unit per-unit through
  ## `PreparedRun.adoptedSpecRefs` and the registry entries — never through
  ## this constant.

const Base36CoutCandidateName* = "decodedLength_cout_binding"
  ## Name of the synthesized out-sizing candidate over decodedLength. The name
  ## must never collide with a subject symbol — the claim is the overlay's,
  ## not a symbol the subject source declares.

type
  Base36CoutOverlayDomain* = object
    ## The synthesis-relevant projection of the C_out overlay: which module and
    ## claim symbol it governs, the pinned L domain, the K claim constant, and
    ## the canonical decision vector the evidence chain names. Parsed
    ## mechanically from the overlay document.
    modulePath*: string
    symbol*: string      ## the claim symbol the overlay quantifies (decodedLength)
    domainVar*: string   ## the `3 <= <var>` clause variable (L)
    domainLower*: int64  ## the literal domain pin's lower bound
    domainBound*: int64  ## the literal domain pin's upper bound (one instance)
    claimConstant*: int64 ## K of the claim clause (external observation, pinned)
    decisionInput*: string ## the canonical decision vector input (s = "kzz")
    ruleId*: string      ## the overlay spec's ruleId (carrier binding digest)

func parseCoutClaimClause(clause: string): Option[(string, string, int64)] {.
    raises: [].} =
  ## "<fn>(<v>) >= <K>" → (fn, v, K); none otherwise. The claim states ONE
  ## theorem instance: the sizing estimate over v must dominate the pinned
  ## constant K. Any other shape is rejected — the overlay states exactly one
  ## out-sizing clause.
  let ge = clause.split(">=")
  if ge.len != 2: return none((string, string, int64))
  let lhs = ge[0].strip
  let rhs = ge[1].strip
  if not lhs.endsWith(")"): return none((string, string, int64))
  let open1 = lhs.find('(')
  if open1 <= 0: return none((string, string, int64))
  let fn = lhs[0 ..< open1].strip
  let arg = lhs[(open1 + 1) ..< (lhs.len - 1)].strip
  if not isIdentLike(fn) or not isIdentLike(arg):
    return none((string, string, int64))
  if not isIntLiteral(rhs): return none((string, string, int64))
  let parsed = safeParseInt(rhs)
  if parsed.isErr or parsed.value.int64 <= 0:
    return none((string, string, int64))
  some((fn, arg, parsed.value.int64))

proc validateCoutOverlayNode*(node: JsonNode): Result[Base36CoutOverlayDomain, string] {.
    raises: [].}
  ## The pure validation core of the C_out loader — same document rules the
  ## I/O-bound loader enforces, exposed so the fail-closed rejections are
  ## testable without rewriting the pinned overlay file. Every rejection here
  ## blocks the run outright (fail closed).

proc loadBase36CoutOverlayDomain*(): Result[Base36CoutOverlayDomain, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D1 for the C_out overlay: read + validate via the same
  ## `explicitSpecFromOverlay` authority path as the base36/base32 overlays.
  ## PR-4: dispatch reads the registry payload; this loader survives as the
  ## parity shadow's cross-path counterfactual and the lane suite's load
  ## leg — its anchor is the registry module's spec dir (the per-lane path
  ## const is retired with the flip; the S2b seam resolves it at runtime —
  ## an unresolved catalog root errs fail-closed, Q-013).
  let specDirRes = resolveExternalSubjectSpecDir()
  if specDirRes.isErr():
    return err(specDirRes.error)
  var node: JsonNode
  let nodeOpt = readJsonFile(specDirRes.get / coutRegistryEntryRelPath)
  if nodeOpt.isNone:
    return err("cannot read spec overlay " & specDirRes.get /
      coutRegistryEntryRelPath &
      " (missing, unreadable, or not valid JSON)")
  validateCoutOverlayNode(nodeOpt.get)

proc validateCoutOverlayNode*(node: JsonNode): Result[Base36CoutOverlayDomain, string] {.
    raises: [].} =
  let specRes = explicitSpecFromOverlay(node)
  if specRes.isErr():
    return err("spec overlay rejected: " & specRes.error)
  let subject = node{"subject"}
  if subject.isNil or subject.kind != JObject:
    return err("spec overlay: subject object required")
  let modulePath = subject{"module"}.getStr("")
  let symbolsNode = subject{"symbols"}
  if modulePath.len == 0 or symbolsNode.isNil or symbolsNode.kind != JArray or
      symbolsNode.len < 1:
    return err("spec overlay: subject.module and >= 1 subject.symbols required")
  var symbols: seq[string]
  for s in symbolsNode:
    if s.kind != JString or s.getStr("").len == 0:
      return err("spec overlay: subject.symbols entries must be non-empty strings")
    symbols.add(s.getStr(""))
  let clauses = specRes.value.canonicalSpecIR
  if clauses.len != 3:
    return err("spec overlay: canonicalSpecIR must contain exactly the " &
      "'<low> <= <v>', '<v> <= <high>', '<fn>(<v>) >= <K>' clauses")
  let lowerParsed = parseLowerDomainClause(clauses[0])
  if lowerParsed.isNone:
    return err("spec overlay: first clause must be '<low> <= <var>'")
  let (lower, lowerVar) = lowerParsed.get
  let upperParsed = parseUpperDomainClause(clauses[1])
  if upperParsed.isNone:
    return err("spec overlay: second clause must be '<var> <= <high>'")
  let (upperVar, bound) = upperParsed.get
  if lowerVar != upperVar:
    return err("spec overlay: domain clauses must bind one variable")
  if lower > bound:
    return err("spec overlay: the literal domain pin is empty (lower > upper)")
  let claimParsed = parseCoutClaimClause(clauses[2])
  if claimParsed.isNone:
    return err("spec overlay: third clause must be '<fn>(<v>) >= <K>' " &
      "over the domain variable")
  let (claimFn, claimVar, claimK) = claimParsed.get
  if claimVar != lowerVar:
    return err("spec overlay: the claim must quantify the domain variable")
  if claimFn notin symbols:
    return err("spec overlay: the claim symbol must be a subject.symbols member")
  # K's provenance cross-check (fail-closed): the claim clause and the
  # claimConstant block must pin the SAME constant — the overlay states one
  # K, sourced once (contract §3; authority_contract.md — 미기록 수치 보고 금지).
  let claimConstantNode = node{"claimConstant"}{"K"}
  if claimConstantNode.isNil or claimConstantNode.kind != JInt or
      claimConstantNode.getInt().int64 != claimK:
    return err("spec overlay: claimConstant.K must equal the claim clause's K")
  # Decision vector consistency (fail-closed): the decision vector's L and the
  # domain pin must name the SAME instance, and the input must be present —
  # the evidence chain links the machine model (L) to the concrete input (s).
  let dv = node{"canonicalDecisionVector"}
  if dv.isNil or dv.kind != JObject:
    return err("spec overlay: canonicalDecisionVector object required")
  let decisionInput = dv{"input"}.getStr("")
  if decisionInput.len == 0:
    return err("spec overlay: canonicalDecisionVector.input required")
  let decisionL = dv{"L"}
  if decisionL.isNil or decisionL.kind != JInt or
      decisionL.getInt().int64 != bound:
    return err("spec overlay: canonicalDecisionVector.L must equal the " &
      "domain pin's upper bound")
  ok(Base36CoutOverlayDomain(
    modulePath: modulePath, symbol: claimFn,
    domainVar: lowerVar, domainLower: lower, domainBound: bound,
    claimConstant: claimK, decisionInput: decisionInput,
    ruleId: specRes.value.ruleId))

func overlayDeclaresCoutSubject*(domain: Base36CoutOverlayDomain; fnName,
    modulePath: string): bool {.raises: [].} =
  ## D4 membership for the C_out overlay: the gate hit is the claim symbol the
  ## overlay governs (decodedLength — the claim quantifies the sizing helper,
  ## not the buffer-taking decode).
  modulePath == domain.modulePath and fnName == domain.symbol

# ---------------------------------------------------------------------------
# toml d2-agent string-control-gate binding overlay
# (docs/spec/toml_d2_agent_binding_contract.md)
# ---------------------------------------------------------------------------
# Fourth out-of-tree explicit spec overlay, same authority pattern as the
# base36 sizing / base32 rem / base36 C_out overlays: the claim over the
# READ-ONLY subject lives only in this repo's config/spec, is pinned to
# soExplicit by explicitSpecFromOverlay, and any present-but-parse/shape
# failure blocks `ax prove` (fail closed). Presence is OPTIONAL (Amendment F
# two-PR landing discipline — the overlay is a non-closure companion): an
# ABSENT file logs an explicit inert-binding line and the run proceeds.
#
# The claim is ADOPTED from the p0d2g blind-discovery + spec-inference agent
# chain (claimOwnership.provenance — the content's authorship is the agent
# chain's, preserved verbatim in the experiment record; the authority is the
# explicit adoption act, never the authorship). The subject's string-content
# control gate rejects only {8,16,31,127} (lexer.nim:588) while the adopted
# spec's forbid set is {<=8} U {10..31} U {127} — the repository's own comment
# set (lexer.nim:75).
#
# Unlike the three predecessor overlays the carriers are CONSTRUCTED IR: the
# original gates are stream-coupled (lexer.next advances) and are deliberately
# not carried as bodies. Each carrier is a bool-valued predicate over one byte
# value; the solver decides the ADOPTED MODEL, and the replay (see
# counterexample_replay.nim's stamped-harness path) observes the ORIGINAL
# decoder through its public API.

const TomlD2AgentOverlayFile* = "toml_d2_agent_spec.json"
  ## Axiom-owned overlay document name (Zero-Footprint; runtime root
  ## resolution via `runtimeSpecOverlayPath`).

const D2AgentDefectCarrierName* = "d2StringGateReject"
  ## Name of the synthesized DEFECT carrier — the model of the code's actual
  ## single-line string gate (overlay canonicalSpecIR clause 8). SAT expected:
  ## every forbid member outside {8,16,31,127} refutes it.

const D2AgentControlCarrierName* = "d2CommentGateReject"
  ## Name of the synthesized CONTROL carrier — the repository's own correctness
  ## set (the comment gate, overlay clause 9). UNSAT expected: it is
  ## set-equal to forbid on the domain. A control SAT means the spec injection
  ## itself is defective, not the subject.

const D2AgentReplayTemplateId* = "d2-gate-reject-v1"
  ## The d2-agent replay harness (contract §replay), named by its
  ## closed-template-registry key (VS-2 REGISTRY_SPEC §1.5 — PR-2 flip): the
  ## template BODY lives only in the engine-owned registry
  ## (`external_subject_registry.replayTemplate`, body
  ## `replayTemplateD2GateRejectV1`); spec text never travels in JSON and the
  ## engine keeps exactly one copy. <module> is fixed by the overlay pin at
  ## synthesis; <lit> renders the model byte at replay time (the placeholders
  ## live in counterexample_replay so the adapter and the renderer share one
  ## definition). Scratch-verified against the pristine subject: c=7 → false
  ## (accept, the defect), c=8 → true (raise, the control), c=9 (tab) →
  ## false (non-forbidden).

proc d2AgentReplayHarnessBody*(): string {.raises: [].} =
  ## The d2 replay-harness BODY from the closed template registry (VS-2 §1.5
  ## — PR-2 flip): spec text never travels in JSON and the engine keeps
  ## exactly one copy. The lane's templateId is an engine-owned const pinned
  ## to the registry by the registry unit test, so an unknown id is an
  ## engine defect — `.get` fails closed at the stamp site (Defect), never a
  ## silent fallback.
  replayTemplate(D2AgentReplayTemplateId).get

func parseD2ExclusionClause(clause: string; v: string): Option[int64] {.
    raises: [].} =
  ## "<v> != <INT>" → the excluded byte literal; none otherwise. The exclusion
  ## terms name the structural paths outside the gate model (delimiter,
  ## terminators, escape), not forbidden-byte semantics.
  let parts = clause.split("!=")
  if parts.len != 2: return none(int64)
  if parts[0].strip != v or not isIntLiteral(parts[1].strip):
    return none(int64)
  let parsed = safeParseInt(parts[1].strip)
  if parsed.isErr: return none(int64)
  some(parsed.value.int64)

func parseD2AtomClause(atom: string; v: string): Option[(string, int64)] {.
    raises: [].} =
  ## One comparison atom inside a forbid-shaped disjunct, in either operand
  ## order: "<v> <op> <INT>" or "<INT> <op> <v>" with op ∈ {"<=", "=="}
  ## → (op, literal); none otherwise. Any other shape is rejected — the
  ## overlay states the forbid set in exactly one canonical form.
  let t = atom.strip(chars = {' ', '\t', '(', ')'})
  let tokens = t.split({' '})
  if tokens.len != 3: return none((string, int64))
  if tokens[1] != "<=" and tokens[1] != "==": return none((string, int64))
  if tokens[0] == v and isIntLiteral(tokens[2]):
    let parsed = safeParseInt(tokens[2])
    if parsed.isErr: return none((string, int64))
    return some((tokens[1], parsed.value.int64))
  if tokens[2] == v and isIntLiteral(tokens[0]):
    let parsed = safeParseInt(tokens[0])
    if parsed.isErr: return none((string, int64))
    return some((tokens[1], parsed.value.int64))
  none((string, int64))

func parseD2ForbidOperandCounts(clause: string): Option[(string, string,
    (int64, int64, int64, int64))] {.raises: [].} =
  ## "<fn>(<v>) == ((<v> <= <A>) or ((<B> <= <v>) and (<v> <= <C>)) or
  ## (<v> == <D>))" → (fn, v, (A, B, C, D)); none otherwise. The forbid shape
  ## is exactly one canonical disjunction: a low band, a middle band, and an
  ## equality member.
  let eqIdx = clause.find("==")
  if eqIdx <= 0: return none((string, string, (int64, int64, int64, int64)))
  let lhs = clause[0 ..< eqIdx].strip
  let rhs = clause[(eqIdx + 2) .. ^1].strip
  if not lhs.endsWith(")"): return none((string, string, (int64, int64, int64, int64)))
  let open1 = lhs.find('(')
  if open1 <= 0: return none((string, string, (int64, int64, int64, int64)))
  let fn = lhs[0 ..< open1].strip
  let arg = lhs[(open1 + 1) ..< (lhs.len - 1)].strip
  if not isIdentLike(fn) or not isIdentLike(arg):
    return none((string, string, (int64, int64, int64, int64)))
  # Strip the outermost paren pair, then split the three disjuncts.
  var body = rhs
  if not (body.startsWith("(") and body.endsWith(")")):
    return none((string, string, (int64, int64, int64, int64)))
  body = body[1 ..< body.len - 1]
  let disjuncts = body.split(" or ")
  if disjuncts.len != 3: return none((string, string, (int64, int64, int64, int64)))
  let lowParsed = parseD2AtomClause(disjuncts[0], arg)
  if lowParsed.isNone or lowParsed.get[0] != "<=":
    return none((string, string, (int64, int64, int64, int64)))
  let midParts = disjuncts[1].strip().strip(chars = {'(', ')'}).split(" and ")
  if midParts.len != 2: return none((string, string, (int64, int64, int64, int64)))
  let midLo = parseD2AtomClause(midParts[0], arg)
  let midHi = parseD2AtomClause(midParts[1], arg)
  if midLo.isNone or midLo.get[0] != "<=" or
      midHi.isNone or midHi.get[0] != "<=":
    return none((string, string, (int64, int64, int64, int64)))
  let eqParsed = parseD2AtomClause(disjuncts[2], arg)
  if eqParsed.isNone or eqParsed.get[0] != "==":
    return none((string, string, (int64, int64, int64, int64)))
  # Operand order is normalized inside the atoms: whichever side named the
  # variable, the band bounds are the literals.
  var loBound = midLo.get[1]
  var hiBound = midHi.get[1]
  if loBound > hiBound:
    return none((string, string, (int64, int64, int64, int64)))
  some((fn, arg, (lowParsed.get[1], loBound, hiBound, eqParsed.get[1])))

func parseD2GateClause(clause: string): Option[(string, string,
    seq[int64])] {.raises: [].} =
  ## "<fn>(<v>) == ((<v> == <a>) or (<v> == <b>) or (<v> == <c2>) or
  ## (<v> == <d>))" → (fn, v, @[a, b, c2, d]); none otherwise. The defect
  ## carrier's body is exactly this four-member equality gate — the code's
  ## actual single-line control-char set.
  let eqIdx = clause.find("==")
  if eqIdx <= 0: return none((string, string, seq[int64]))
  let lhs = clause[0 ..< eqIdx].strip
  let rhs = clause[(eqIdx + 2) .. ^1].strip
  if not lhs.endsWith(")"): return none((string, string, seq[int64]))
  let open1 = lhs.find('(')
  if open1 <= 0: return none((string, string, seq[int64]))
  let fn = lhs[0 ..< open1].strip
  let arg = lhs[(open1 + 1) ..< (lhs.len - 1)].strip
  if not isIdentLike(fn) or not isIdentLike(arg):
    return none((string, string, seq[int64]))
  var body = rhs
  if not (body.startsWith("(") and body.endsWith(")")):
    return none((string, string, seq[int64]))
  body = body[1 ..< body.len - 1]
  let disjuncts = body.split(" or ")
  if disjuncts.len != 4: return none((string, string, seq[int64]))
  var members: seq[int64]
  for d in disjuncts:
    let parsed = parseD2AtomClause(d, arg)
    if parsed.isNone or parsed.get[0] != "==":
      return none((string, string, seq[int64]))
    members.add(parsed.get[1])
  some((fn, arg, members))

type
  TomlD2AgentOverlayDomain* = object
    ## The synthesis-relevant projection of the d2-agent overlay: which module
    ## and symbols it governs, the adopted byte domain (bounds + structural
    ## exclusions), the forbid set, the defect gate set, the public API module
    ## the replay harness imports, and the two carriers' grounding. Everything
    ## is parsed mechanically from the overlay document — no subject names are
    ## hardcoded in the engine.
    modulePath*: string
    symbols*: seq[string]
    domainVar*: string    ## the byte variable every clause quantifies (c)
    domainLower*: int64   ## from the "<low> <= <v>" clause
    domainBound*: int64   ## from the "<v> <= <high>" clause
    exclusions*: seq[int64] ## the "<v> != <INT>" structural-path terms
    forbidLow*: int64     ## forbid: (<v> <= forbidLow) or ...
    forbidMidLo*: int64   ## ... or ((forbidMidLo <= <v>) and ...
    forbidMidHi*: int64   ##      ... (<v> <= forbidMidHi)) or ...
    forbidEq*: int64      ## ... or (<v> == forbidEq)
    defectGates*: seq[int64] ## the defect carrier's four gate members
    importModule*: string ## the public API module the replay harness imports
    subjectBlobSha256*: string ## the pinned module digest — verified against
                               ## the subject bytes at run time (REAL check)
                          ## (the subject module's parent directory name)
    defectGroundingSymbol*: string  ## the original proc the defect model grounds
    controlGroundingSymbol*: string ## the original proc the control model grounds
    defectGroundingLines*: string   ## the grounding lines folded into the
    controlGroundingLines*: string  ## carrier derivation digests
    ruleId*: string       ## the overlay spec's ruleId (carrier binding digest)

proc validateTomlD2AgentOverlayNode*(node: JsonNode): Result[
    TomlD2AgentOverlayDomain, string] {.raises: [].}
  ## The pure validation core of the d2-agent loader — same document rules the
  ## I/O-bound loader enforces, exposed so the fail-closed rejections are
  ## testable without rewriting the pinned overlay file. Every rejection here
  ## blocks the run outright (fail closed).

proc loadTomlD2AgentOverlayDomain*(): Result[TomlD2AgentOverlayDomain, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D1 for the d2-agent overlay: read + validate via the same
  ## `explicitSpecFromOverlay` authority path as the base36/base32/C_out
  ## overlays.
  var node: JsonNode
  let pathRes = runtimeSpecOverlayPath(TomlD2AgentOverlayFile)
  if pathRes.isErr():
    return err("cannot resolve the spec overlay directory (fail-closed): " &
      pathRes.error)
  let overlayPath = pathRes.get
  let nodeOpt = readJsonFile(overlayPath)
  if nodeOpt.isNone:
    return err("cannot read spec overlay " & overlayPath &
      " (missing, unreadable, or not valid JSON)")
  validateTomlD2AgentOverlayNode(nodeOpt.get)

proc validateTomlD2AgentOverlayNode*(node: JsonNode): Result[
    TomlD2AgentOverlayDomain, string] {.raises: [].} =
  let specRes = explicitSpecFromOverlay(node)
  if specRes.isErr():
    return err("spec overlay rejected: " & specRes.error)
  # VS-2 PR-2: the pin/ownership/carrier halves are the shared registry kit
  # (REGISTRY_SPEC §3.7) — the d2 validator trio folded there verbatim, the
  # carrier half parameterized by this binding's kernel carrier names, so
  # every rejection message stays byte-identical to the retired bodies.
  let ownership = validateOwnershipObject(node)
  if ownership.isErr():
    return err(ownership.error)
  let subjectRes = validateSubjectPinObject(node{"subject"})
  if subjectRes.isErr():
    return err(subjectRes.error)
  let (modulePath, symbols, subjectBlob) = subjectRes.get
  let carriersRes = validateCarrierPair(node, D2AgentDefectCarrierName,
    D2AgentControlCarrierName)
  if carriersRes.isErr():
    return err(carriersRes.error)
  let clauses = specRes.value.canonicalSpecIR
  # The adopted claim states EXACTLY: two domain bounds, four structural
  # exclusions, the forbid definition, and the two carrier definitions. Any
  # other clause count or shape is a different claim and is rejected.
  if clauses.len != 9:
    return err("spec overlay: canonicalSpecIR must contain exactly the " &
      "'<low> <= <v>', '<v> <= <high>', 4×'<v> != <INT>', the forbid " &
      "definition, and the two carrier definitions")
  let lowerParsed = parseLowerDomainClause(clauses[0])
  if lowerParsed.isNone:
    return err("spec overlay: clause 1 must be '<low> <= <var>'")
  let (lower, domainVar) = lowerParsed.get
  let upperParsed = parseUpperDomainClause(clauses[1])
  if upperParsed.isNone:
    return err("spec overlay: clause 2 must be '<var> <= <high>'")
  let (upperVar, bound) = upperParsed.get
  if domainVar != upperVar:
    return err("spec overlay: domain clauses must bind one variable")
  if lower > bound:
    return err("spec overlay: the domain is empty (lower > upper)")
  var exclusions: seq[int64]
  for i in 2 ..< 6:
    let excluded = parseD2ExclusionClause(clauses[i], domainVar)
    if excluded.isNone:
      return err("spec overlay: clauses 3-6 must be '<var> != <INT>' over " &
        "the domain variable")
    exclusions.add(excluded.get)
  for i in 0 ..< exclusions.len:
    for j in (i + 1) ..< exclusions.len:
      if exclusions[i] == exclusions[j]:
        return err("spec overlay: the structural exclusions must be distinct")
  let forbidParsed = parseD2ForbidOperandCounts(clauses[6])
  if forbidParsed.isNone or forbidParsed.get[0] != "forbid":
    return err("spec overlay: clause 7 must define forbid as " &
      "'forbid(<v>) == ((<v> <= <A>) or ((<B> <= <v>) and (<v> <= <C>)) or " &
      "(<v> == <D>))'")
  let (forbidFn, forbidVar, forbidSet) = forbidParsed.get
  if forbidVar != domainVar:
    return err("spec overlay: the forbid definition must quantify the domain variable")
  let defectParsed = parseD2GateClause(clauses[7])
  if defectParsed.isNone or defectParsed.get[0] != D2AgentDefectCarrierName:
    return err("spec overlay: clause 8 must define the defect carrier as '" &
      D2AgentDefectCarrierName & "(<v>) == ((<v> == <a>) or (<v> == <b>) or " &
      "(<v> == <c>) or (<v> == <d>))'")
  let (defectFn, defectVar, defectGates) = defectParsed.get
  if defectVar != domainVar:
    return err("spec overlay: the defect carrier must quantify the domain variable")
  for i in 0 ..< defectGates.len:
    for j in (i + 1) ..< defectGates.len:
      if defectGates[i] == defectGates[j]:
        return err("spec overlay: the defect gate members must be distinct")
  let controlParsed = parseD2ForbidOperandCounts(clauses[8])
  if controlParsed.isNone or controlParsed.get[0] != D2AgentControlCarrierName:
    return err("spec overlay: clause 9 must define the control carrier in " &
      "the forbid shape over the domain variable")
  let (controlFn, controlVar, controlSet) = controlParsed.get
  if controlVar != domainVar:
    return err("spec overlay: the control carrier must quantify the domain variable")
  # Control-carrier semantics (fail-closed): the control IS the forbid set —
  # set-equality between clause 9 and clause 7 is the differential's guard
  # against a spec-injection defect (a control that could go SAT would verify
  # nothing).
  if controlFn != D2AgentControlCarrierName or forbidFn != "forbid" or
      controlSet != forbidSet:
    return err("spec overlay: the control carrier must be set-equal to forbid")
  # The public API module the replay harness imports: the subject module's
  # parent directory (toml_serialization/lexer.nim → toml_serialization).
  let importModule = block:
    let dir = modulePath.splitFile().dir
    if dir.len == 0 or dir == ".":
      return err("spec overlay: subject.module must name a module inside a " &
        "public-API directory (replay import derivation)")
    dir.lastPathPart()
  let carriers = carriersRes.get
  ok(TomlD2AgentOverlayDomain(
    modulePath: modulePath, symbols: symbols,
    subjectBlobSha256: subjectBlob,
    domainVar: domainVar, domainLower: lower, domainBound: bound,
    exclusions: exclusions,
    forbidLow: forbidSet[0], forbidMidLo: forbidSet[1],
    forbidMidHi: forbidSet[2], forbidEq: forbidSet[3],
    defectGates: defectGates,
    importModule: importModule,
    defectGroundingSymbol: carriers.defectSymbol,
    controlGroundingSymbol: carriers.controlSymbol,
    defectGroundingLines: carriers.defectLines,
    controlGroundingLines: carriers.controlLines,
    ruleId: specRes.value.ruleId))

func overlayDeclaresD2AgentSubject*(domain: TomlD2AgentOverlayDomain; fnName,
    modulePath: string): bool {.raises: [].} =
  ## D4 membership for the d2-agent overlay: the gate hit is a subject symbol
  ## the overlay governs — including the two constructed carrier names, so a
  ## canonical --target naming a carrier routes to the same synthesis a
  ## parsed-subject gate hit uses (carriers never appear in the subject
  ## parse, so without this they are not frontier-addressable at all). The
  ## module-path gate is what keeps the binding inert for every other
  ## subject tree.
  modulePath == domain.modulePath and
    (fnName in domain.symbols or fnName == D2AgentDefectCarrierName or
     fnName == D2AgentControlCarrierName)

func d2AgentCarrierTargetRouting*(target: string;
    domain: TomlD2AgentOverlayDomain): tuple[routed: bool; fnName, modulePath: string] {.
    raises: [].} =
  ## Canonical-target routing for the d2-agent carriers: a canonical
  ## ``module::fn`` target naming an overlay-governed symbol (carriers
  ## included, via `overlayDeclaresD2AgentSubject`) routes to the carrier
  ## synthesizer when frontier resolution found no node — the carriers are
  ## constructed IR with no subject-parse presence, so a carrier target
  ## resolves to zero frontier nodes by construction. Non-canonical targets
  ## and non-governed hits never route (routed=false).
  let colonPos = target.find("::")
  if colonPos <= 0 or colonPos + 2 > target.len - 1:
    return
  let targetModule = target[0 ..< colonPos]
  let targetFn = target[colonPos + 2 .. ^1]
  if overlayDeclaresD2AgentSubject(domain, targetFn, targetModule):
    (true, targetFn, targetModule)
  else:
    (false, "", "")

func d2ForbidPredicate(cVar: IRExpr; domain: TomlD2AgentOverlayDomain): IRExpr {.
    raises: [].} =
  ## The adopted forbid set as constructed IR:
  ## (<v> <= low) or ((midLo <= <v>) and (<v> <= midHi)) or (<v> == eq).
  irOr(
    irOr(
      irLe(cVar, irLit(domain.forbidLow)),
      irAnd(irGe(cVar, irLit(domain.forbidMidLo)),
        irLe(cVar, irLit(domain.forbidMidHi)))),
    irEq(cVar, irLit(domain.forbidEq)))

func d2GatePredicate(cVar: IRExpr; gates: seq[int64]): IRExpr {.raises: [].} =
  ## The defect gate as constructed IR: the left-associated or-chain of the
  ## four equality members, in the overlay's stated order.
  var body = irEq(cVar, irLit(gates[0]))
  for i in 1 ..< gates.len:
    body = irOr(body, irEq(cVar, irLit(gates[i])))
  body

func d2DomainPreconditions(cVar: IRExpr; domain: TomlD2AgentOverlayDomain):
    seq[IRExpr] {.raises: [].} =
  ## The adopted domain D as conjuncts: both bounds plus the structural
  ## exclusions (each an inequality over the byte variable).
  result = @[irGe(cVar, irLit(domain.domainLower)),
             irLe(cVar, irLit(domain.domainBound))]
  for e in domain.exclusions:
    result.add(irNot(irEq(cVar, irLit(e))))

# ---------------------------------------------------------------------------
# nim-libp2p BytesView.toOpenArray slice-length binding overlay
# (docs/spec/nim_libp2p_bytesview_slice_contract.md)
# ---------------------------------------------------------------------------
# Fifth out-of-tree explicit spec overlay, same authority pattern as the
# base36 sizing / base32 rem / base36 C_out / toml d2-agent / proposition
# sidecar overlays: the claim over the READ-ONLY subject lives only in this
# repo's config/spec, is pinned to soExplicit by explicitSpecFromOverlay, and
# any present-but-parse/shape failure blocks `ax prove` (fail closed).
# Presence is OPTIONAL (Amendment F two-PR landing discipline — the overlay is
# a non-closure companion): an ABSENT file logs an explicit inert-binding line
# and the run proceeds.
#
# The claim is ADOPTED from the investigation agent chain
# (claimOwnership.provenance — the content's authorship is the agent chain's;
# the authority is the explicit adoption act, never the authorship). The
# subject's slice-length law is the INCLUSIVE view-relative law e - b + 1
# (Nim system toOpenArray semantics), while the template materializes
# e - 2b + 1 — exactly b elements short for every b > 0.
#
# Like the d2 lane the carriers are CONSTRUCTED IR: the subject symbol is a
# TEMPLATE (no materializable func body), so the solver decides the ADOPTED
# MODEL and the stamped replay harness observes the ORIGINAL template through
# its defining module. The overlay states the LAW as DATA (canonicalSpecIR
# names one law symbol per carrier and states its body), so the engine
# hardcodes no law content — only the carrier/law NAMES, which are binding
# identities.
#
# The subject pin is a REAL check (as in the d2 and sidecar lanes): the
# governed module's bytes under the run's subject root must hash to
# subject.blobSha256 (verifyLibp2pBytesviewSubjectPin) — a tree that presents
# the governed module with any other content fails the run.

proc nimLibp2pBytesviewSliceOverlayPath*(): Result[string, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Axiom-owned overlay path (Zero-Footprint; runtime root resolution —
  ## bytesview contract §3.1, revised 2026-11-08): the config/spec root is
  ## the runtime seam (`resolveExternalSubjectSpecDir`: AXIOM_ROOT first,
  ## else the strict anchor walk from the binary location). A tree-external
  ## anchor miss is a catalog read failure, fail-closed (Q-013) — never a
  ## CWD-relative join. Source-tree behavior is preserved: with AXIOM_ROOT
  ## unset and the binary inside the tree the walk reproduces the path the
  ## compile-time `repoRootConst()` anchor previously baked in.
  let dirRes = resolveExternalSubjectSpecDir()
  if dirRes.isErr():
    return err(dirRes.error)
  ok(dirRes.get / "nim_libp2p_bytesview_slice.json")

const BvSliceLenDefectCarrierName* = "bvSliceLenActual"
  ## Name of the synthesized DEFECT carrier — the model of the template's
  ## actual slice length with the start offset b pinned at 1 (overlay
  ## canonicalSpecIR). SAT expected: the model violates the adopted law for
  ## EVERY e in the domain, so the solver selects one witness.

const BvSliceLenControlCarrierName* = "bvSliceLenControl"
  ## Name of the synthesized CONTROL carrier — the model of the same
  ## template's actual length with b pinned at 0 (overlay canonicalSpecIR).
  ## UNSAT expected: it agrees with the adopted law for every e in the
  ## domain. A control SAT would indict the spec injection itself, not the
  ## subject.

const BvSliceLenDefectLawName* = "bvSliceLenLaw1"
  ## Name of the ADOPTED LAW symbol of the defect carrier — the inclusive
  ## view-relative law e - b + 1 at b = 1. The law's BODY is data (stated in
  ## the overlay); only its NAME is a binding identity.

const BvSliceLenControlLawName* = "bvSliceLenLaw0"
  ## Name of the ADOPTED LAW symbol of the control carrier — the inclusive
  ## view-relative law e - b + 1 at b = 0. The law's BODY is data (stated in
  ## the overlay); only its NAME is a binding identity.

const BvSliceLenReplayTemplateId* = "bv-slice-len-v1"
  ## The bytesview slice-length replay harness (contract §4), named by its
  ## closed-template-registry key (VS-2 REGISTRY_SPEC §1.5 — PR-1 flip): the
  ## template BODY lives only in the engine-owned registry
  ## (`external_subject_registry.replayTemplate`, body
  ## `replayTemplateBvSliceLenV1`); spec text never travels in JSON and the
  ## engine keeps exactly one copy. <module> is fixed by the overlay pin at
  ## synthesis; <lit> renders the solver's model value of e at replay time
  ## (the placeholders live in counterexample_replay so the adapter and the
  ## renderer share one definition). The fixture bounds the domain: a
  ## view-relative inclusive window [1..e] is valid up to e = 5.

func stripBvOuterParens(s: string): string {.raises: [].} =
  ## Strip ONE outermost parenthesis pair when it wraps the whole text; the
  ## text is returned unchanged when it is not parenthesized or when the
  ## closing parenthesis does not close the opening one (a partial wrap is
  ## never silently repaired).
  let t = s.strip
  if t.len < 2 or t[0] != '(' or t[^1] != ')':
    return t
  var depth = 0
  for i, c in t:
    if c == '(':
      inc depth
    elif c == ')':
      dec depth
      if depth == 0 and i != t.len - 1:
        return t
  if depth != 0:
    return t
  t[1 ..< t.len - 1].strip

func parseBvArithBody(text: string; v: string): Option[IRExpr] {.raises: [].} =
  ## The CLOSED arithmetic body grammar of this overlay: "<v>",
  ## "<v> + <INT>" or "<v> - <INT>" — each optionally wrapped in one
  ## parenthesis pair — → the IR expression over the model variable. The
  ## grammar is closed on purpose: an overlay that states a model in any
  ## other shape states a DIFFERENT claim and is rejected (fail closed),
  ## never approximated.
  let t = stripBvOuterParens(text)
  if t == v:
    return some(irVar(v, irTypeBitVec64()))
  let parts = t.split({' ', '\t'})
  if parts.len != 3:
    return none(IRExpr)
  if parts[0] != v or (parts[1] != "+" and parts[1] != "-"):
    return none(IRExpr)
  if not isIntLiteral(parts[2]):
    return none(IRExpr)
  let parsed = safeParseInt(parts[2])
  if parsed.isErr:
    return none(IRExpr)
  let varIr = irVar(v, irTypeBitVec64())
  let litIr = irLit(parsed.value.int64)
  if parts[1] == "+":
    some(irAdd(varIr, litIr))
  else:
    some(irSub(varIr, litIr))

func parseBvNamedDefClause(clause: string): Option[(string, string, string)] {.
    raises: [].} =
  ## "<fn>(<v>) == <body>" → (fn, v, body text); none otherwise. The
  ## overlay's named definitions are the ONLY way the claim reaches the
  ## engine: both the law side and the model side are named symbols, so no
  ## law content is hardcoded here.
  let eqIdx = clause.find("==")
  if eqIdx <= 0:
    return none((string, string, string))
  let lhs = clause[0 ..< eqIdx].strip
  let rhs = clause[(eqIdx + 2) .. ^1].strip
  if rhs.len == 0 or not lhs.endsWith(")"):
    return none((string, string, string))
  let open1 = lhs.find('(')
  if open1 <= 0:
    return none((string, string, string))
  let fn = lhs[0 ..< open1].strip
  let arg = lhs[(open1 + 1) ..< (lhs.len - 1)].strip
  if not isIdentLike(fn) or not isIdentLike(arg):
    return none((string, string, string))
  some((fn, arg, rhs))

type
  NimLibp2pBytesviewSliceDomain* = object
    ## The synthesis-relevant projection of the bytesview slice overlay: which
    ## module and symbols it governs, the adopted length domain (bounds), the
    ## two carrier MODELS and the two adopted LAW sides (all parsed
    ## mechanically from the overlay's canonicalSpecIR — no subject names and
    ## no law content are hardcoded in the engine), the subject blob digest
    ## the pin is verified against, and the carriers' grounding.
    modulePath*: string
    symbols*: seq[string]
    importModule*: string  ## the import path the replay harness uses (the
                          ## subject module path without its extension)
    subjectBlobSha256*: string ## the subject module bytes the pin binds
    domainVar*: string     ## the length variable every clause quantifies (e)
    domainLower*: int64    ## from the "<low> <= <v>" clause
    domainBound*: int64    ## from the "<v> <= <high>" clause
    defectModel*: IRExpr   ## the defect carrier's model — the template's
                           ## actual length at b = 1
    defectLaw*: IRExpr     ## the defect carrier's law side — the inclusive
                           ## law at b = 1
    controlModel*: IRExpr  ## the control carrier's model — b = 0
    controlLaw*: IRExpr    ## the control carrier's law side — b = 0
    defectGroundingSymbol*: string  ## the subject symbol the defect model
                                     ## grounds
    controlGroundingSymbol*: string ## the subject symbol the control model
                                     ## grounds
    defectGroundingLines*: string   ## the grounding lines folded into the
    controlGroundingLines*: string  ## carrier derivation digests
    ruleId*: string        ## the overlay spec's ruleId (carrier binding digest)

func validateBvSubjectPin(subject: JsonNode): Result[tuple[
    modulePath: string; symbols: seq[string]; blobSha256: string], string] {.
    raises: [].} =
  ## Fail-closed subject pin: module + symbols, and the exact-commit binding
  ## fields (repository, commit, sourceLines, blobSha256) present and
  ## well-formed — the claim names ONE immutable subject state. The digest
  ## is VERIFIED against the module bytes at the run's subject root
  ## (verifyLibp2pBytesviewSubjectPin), never merely format-checked.
  if subject.isNil or subject.kind != JObject:
    return err("spec overlay: subject object required")
  let modulePath = subject{"module"}.getStr("")
  let symbolsNode = subject{"symbols"}
  if modulePath.len == 0 or symbolsNode.isNil or symbolsNode.kind != JArray or
      symbolsNode.len < 1:
    return err("spec overlay: subject.module and >= 1 subject.symbols required")
  var symbols: seq[string]
  for s in symbolsNode:
    if s.kind != JString or s.getStr("").len == 0:
      return err("spec overlay: subject.symbols entries must be non-empty strings")
    symbols.add(s.getStr(""))
  for field in ["repository", "commit", "sourceLines"]:
    if subject{field}.getStr("").len == 0:
      return err("spec overlay: subject." & field & " is required (exact-commit pin)")
  let blob = subject{"blobSha256"}.getStr("")
  if blob.len != 64 or not blob.allCharsInSet(
      {'0'..'9', 'a'..'f', 'A'..'F'}):
    return err("spec overlay: subject.blobSha256 must be a 64-hex digest")
  ok((modulePath, symbols, blob))

func validateBvOwnership(node: JsonNode): Result[void, string] {.raises: [].} =
  ## Fail-closed adoption record: the adopted-content provenance and the
  ## adoption act must both be named — an overlay without them would claim
  ## verified-by-nobody content.
  let owner = node{"claimOwnership"}
  if owner.isNil or owner.kind != JObject:
    return err("spec overlay: claimOwnership object required")
  for field in ["owner", "contract", "adoptionRef", "provenance"]:
    if owner{field}.getStr("").len == 0:
      return err("spec overlay: claimOwnership." & field & " is required " &
        "(adoption authority record)")
  if node{"description"}.getStr("").len == 0:
    return err("spec overlay: description is required (the claim's prose)")
  for field in ["semanticCaveats", "nonClaims"]:
    let arr = node{field}
    if arr.isNil or arr.kind != JArray or arr.len < 1:
      return err("spec overlay: " & field & " must be a non-empty array")
    for e in arr:
      if e.kind != JString or e.getStr("").len == 0:
        return err("spec overlay: " & field & " entries must be non-empty strings")
  Result[void, string](ok: true)

func validateBvCarriers(node: JsonNode): Result[tuple[
    defectSymbol, defectLines, controlSymbol, controlLines: string], string] {.
    raises: [].} =
  ## Fail-closed carrier grounding: exactly one defect and one control
  ## carrier, named by the binding's kernel names, each with a non-empty
  ## grounding symbol + lines + note. The clause semantics live only in
  ## canonicalSpecIR — this block is provenance metadata, and the validator
  ## requires the two blocks to name the SAME carriers (no second semantic
  ## source).
  let carriers = node{"carriers"}
  if carriers.isNil or carriers.kind != JArray or carriers.len != 2:
    return err("spec overlay: exactly 2 carriers (defect + control) required")
  var seen: array[2, bool]
  var defectSymbol, defectLines, controlSymbol, controlLines = ""
  for c in carriers:
    if c.kind != JObject:
      return err("spec overlay: carrier entries must be objects")
    let name = c{"name"}.getStr("")
    let kind = c{"kind"}.getStr("")
    let gs = c{"groundingSymbol"}.getStr("")
    let gl = c{"groundingLines"}.getStr("")
    if gs.len == 0 or gl.len == 0:
      return err("spec overlay: carrier " & name &
        " needs groundingSymbol and groundingLines")
    if c{"grounding"}.getStr("").len == 0:
      return err("spec overlay: carrier " & name & " needs a grounding note")
    case kind
    of "defect":
      if name != BvSliceLenDefectCarrierName:
        return err("spec overlay: the defect carrier must be named " &
          BvSliceLenDefectCarrierName)
      if seen[0]:
        return err("spec overlay: duplicate defect carrier")
      seen[0] = true
      defectSymbol = gs
      defectLines = gl
    of "control":
      if name != BvSliceLenControlCarrierName:
        return err("spec overlay: the control carrier must be named " &
          BvSliceLenControlCarrierName)
      if seen[1]:
        return err("spec overlay: duplicate control carrier")
      seen[1] = true
      controlSymbol = gs
      controlLines = gl
    else:
      return err("spec overlay: carrier kind must be defect or control")
  if not (seen[0] and seen[1]):
    return err("spec overlay: exactly one defect and one control carrier required")
  ok((defectSymbol, defectLines, controlSymbol, controlLines))

proc validateNimLibp2pBytesviewSliceOverlayNode*(node: JsonNode): Result[NimLibp2pBytesviewSliceDomain, string] {.raises: [], axiomDecision.}
  ## The pure validation core of the bytesview slice loader — the document
  ## rules the I/O-bound loader enforces, exposed so the fail-closed
  ## rejections are testable without rewriting the pinned overlay file. Every
  ## rejection here blocks the run outright (fail closed).

proc loadNimLibp2pBytesviewSliceOverlayDomain*(): Result[NimLibp2pBytesviewSliceDomain, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D1 for the bytesview slice overlay: read + validate via the same
  ## `explicitSpecFromOverlay` authority path as the predecessor overlays.
  ## Absence is handled at the call site (presence-optional landing
  ## discipline); here an unreadable/present-but-invalid document is an
  ## error — as is an unresolved catalog root (S2b runtime seam: the path
  ## proc errs fail-closed, Q-013).
  let overlayPathRes = nimLibp2pBytesviewSliceOverlayPath()
  if overlayPathRes.isErr():
    return err(overlayPathRes.error)
  let overlayPath = overlayPathRes.get
  var node: JsonNode
  let nodeOpt = readJsonFile(overlayPath)
  if nodeOpt.isNone:
    return err("cannot read spec overlay " & overlayPath &
      " (missing, unreadable, or not valid JSON)")
  validateNimLibp2pBytesviewSliceOverlayNode(nodeOpt.get)

proc validateNimLibp2pBytesviewSliceOverlayNode*(node: JsonNode): Result[NimLibp2pBytesviewSliceDomain, string] {.raises: [], axiomDecision.} =
  ## The pure validation core of the bytesview slice loader — the document
  ## rules the I/O-bound loader enforces, exposed so the fail-closed
  ## rejections are testable without rewriting the pinned overlay file. Every
  ## rejection here blocks the run outright (fail closed).
  let specRes = explicitSpecFromOverlay(node)
  if specRes.isErr():
    return err("spec overlay rejected: " & specRes.error)
  let ownership = validateBvOwnership(node)
  if ownership.isErr():
    return err(ownership.error)
  let subjectRes = validateBvSubjectPin(node{"subject"})
  if subjectRes.isErr():
    return err(subjectRes.error)
  let (modulePath, symbols, blobSha256) = subjectRes.get
  let carriersRes = validateBvCarriers(node)
  if carriersRes.isErr():
    return err(carriersRes.error)
  let clauses = specRes.value.canonicalSpecIR
  # The adopted claim states EXACTLY: the two domain bounds and FOUR named
  # definitions — the defect law, the defect model, the control law and the
  # control model. Any other clause count or shape is a different claim and
  # is rejected.
  if clauses.len != 6:
    return err("spec overlay: canonicalSpecIR must contain exactly the " &
      "'<low> <= <v>', '<v> <= <high>' and the four named definitions (" &
      BvSliceLenDefectLawName & ", " & BvSliceLenDefectCarrierName & ", " &
      BvSliceLenControlLawName & ", " & BvSliceLenControlCarrierName & ")")
  let lowerParsed = parseLowerDomainClause(clauses[0])
  if lowerParsed.isNone:
    return err("spec overlay: clause 1 must be '<low> <= <var>'")
  let (lower, domainVar) = lowerParsed.get
  let upperParsed = parseUpperDomainClause(clauses[1])
  if upperParsed.isNone:
    return err("spec overlay: clause 2 must be '<var> <= <high>'")
  let (upperVar, bound) = upperParsed.get
  if domainVar != upperVar:
    return err("spec overlay: the domain clauses must bind one variable")
  if lower > bound:
    return err("spec overlay: the domain is empty (lower > upper)")
  # The four named definitions: each names its own variable and states its
  # body in the closed arithmetic grammar.
  var defs: seq[(string, string, IRExpr)]
  for i in 2 ..< 6:
    let parsed = parseBvNamedDefClause(clauses[i])
    if parsed.isNone:
      return err("spec overlay: clause " & $(i + 1) & " must be a named " &
        "definition '<fn>(<var>) == <body>'")
    let (fn, arg, bodyText) = parsed.get
    if arg != domainVar:
      return err("spec overlay: clause " & $(i + 1) &
        " must quantify the domain variable '" & domainVar & "'")
    let body = parseBvArithBody(bodyText, domainVar)
    if body.isNone:
      return err("spec overlay: clause " & $(i + 1) & " states its body " &
        "outside the closed grammar ('<var>', '<var> + <INT>', " &
        "'<var> - <INT>')")
    for existing in defs:
      if existing[0] == fn:
        return err("spec overlay: duplicate definition '" & fn & "'")
    defs.add((fn, arg, body.get))
  func definitionOf(name: string): Option[IRExpr] {.raises: [].} =
    ## The IR body of one named definition; none when the overlay does not
    ## define it.
    for d in defs:
      if d[0] == name:
        return some(d[2])
    none(IRExpr)
  let defectModel = definitionOf(BvSliceLenDefectCarrierName)
  let defectLaw = definitionOf(BvSliceLenDefectLawName)
  let controlModel = definitionOf(BvSliceLenControlCarrierName)
  let controlLaw = definitionOf(BvSliceLenControlLawName)
  if defectModel.isNone or defectLaw.isNone or controlModel.isNone or
      controlLaw.isNone:
    return err("spec overlay: canonicalSpecIR must define " &
      BvSliceLenDefectLawName & ", " & BvSliceLenDefectCarrierName & ", " &
      BvSliceLenControlLawName & " and " & BvSliceLenControlCarrierName)
  # The import path the replay harness uses: the subject module path without
  # its extension (libp2p/utils/bytesview.nim → libp2p/utils/bytesview).
  let importModule = block:
    let parts = modulePath.splitFile()
    if parts.name.len == 0:
      return err("spec overlay: subject.module must name a Nim module file")
    if parts.dir.len == 0 or parts.dir == ".":
      parts.name
    else:
      parts.dir / parts.name
  let carriers = carriersRes.get
  ok(NimLibp2pBytesviewSliceDomain(
    modulePath: modulePath, symbols: symbols,
    importModule: importModule,
    subjectBlobSha256: blobSha256,
    domainVar: domainVar, domainLower: lower, domainBound: bound,
    defectModel: defectModel.get, defectLaw: defectLaw.get,
    controlModel: controlModel.get, controlLaw: controlLaw.get,
    defectGroundingSymbol: carriers.defectSymbol,
    controlGroundingSymbol: carriers.controlSymbol,
    defectGroundingLines: carriers.defectLines,
    controlGroundingLines: carriers.controlLines,
    ruleId: specRes.value.ruleId))

func overlayDeclaresLibp2pBytesviewSubject*(domain: NimLibp2pBytesviewSliceDomain;
    fnName, modulePath: string): bool {.raises: [].} =
  ## D4 membership for the bytesview slice overlay: the hit is a subject
  ## symbol the overlay governs — including the two constructed carrier names,
  ## so a canonical --target naming a carrier routes to the same synthesis a
  ## parsed-subject gate hit uses (carriers never appear in the subject
  ## parse, so without this they are not frontier-addressable at all). The
  ## module-path gate keeps the binding inert for every other subject tree.
  modulePath == domain.modulePath and
    (fnName in domain.symbols or fnName == BvSliceLenDefectCarrierName or
     fnName == BvSliceLenControlCarrierName)

func libp2pBytesviewCarrierTargetRouting*(target: string;
    domain: NimLibp2pBytesviewSliceDomain): tuple[
    routed: bool; fnName, modulePath: string] {.raises: [].} =
  ## Target routing for the bytesview slice carriers: a canonical
  ## ``module::fn`` target naming an overlay-governed symbol (carriers
  ## included, via `overlayDeclaresLibp2pBytesviewSubject`) routes to the
  ## carrier synthesizer when frontier resolution found no node — the carriers
  ## are constructed IR with no subject-parse presence, so a carrier target
  ## resolves to zero frontier nodes by construction. A BARE carrier name (no
  ## module qualifier) routes to the overlay's own module: the constructed
  ## carrier exists in exactly one module, so the bare name is unambiguous.
  ## Non-governed hits never route (routed=false).
  let colonPos = target.find("::")
  if colonPos <= 0:
    if target == BvSliceLenDefectCarrierName or
        target == BvSliceLenControlCarrierName:
      return (true, target, domain.modulePath)
    return (false, "", "")
  if colonPos + 2 > target.len - 1:
    return (false, "", "")
  let targetModule = target[0 ..< colonPos]
  let targetFn = target[colonPos + 2 .. ^1]
  if overlayDeclaresLibp2pBytesviewSubject(domain, targetFn, targetModule):
    (true, targetFn, targetModule)
  else:
    (false, "", "")

proc verifyLibp2pBytesviewSubjectPin*(domain: NimLibp2pBytesviewSliceDomain;
    subjectRoot: string): Result[bool, string] {.raises: [], axiomDecision,
    axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The REAL subject-pin check (VS-2 PR-1 flip): the byte-hash semantics are
  ## the shared registry proc's (REGISTRY_SPEC §2.4 — ONE pin-verify; the
  ## lane name feeds only the diagnostic prefix, so every message stays
  ## byte-identical to the retired per-lane body). When the governed module
  ## exists under this run's subject root its bytes must hash to
  ## subject.blobSha256 — any other content does not match the adopted
  ## subject and fails the run (fail-closed). A root without the governed
  ## module is INERT here (ok(false)). ok(true) = pin verified against the
  ## actual module bytes.
  verifySubjectBlobPin("bytesview slice", domain.modulePath,
    domain.subjectBlobSha256, subjectRoot)

proc verifyTomlD2AgentSubjectPin*(domain: TomlD2AgentOverlayDomain;
    subjectRoot: string): Result[bool, string] {.raises: [], axiomDecision,
    axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The REAL subject-pin check for the d2-agent lane (VS-2 PR-2 flip): the
  ## byte-hash semantics are the shared registry proc's (REGISTRY_SPEC §2.4 —
  ## ONE pin-verify; the lane name feeds only the diagnostic prefix, so every
  ## message stays byte-identical to the retired per-lane body). When the
  ## governed module exists under this run's subject root its bytes must hash
  ## to subjectBlobSha256 — any other content does not match the adopted
  ## subject and fails the run (fail-closed). A root without the governed
  ## module is INERT here (ok(false)). ok(true) = pin verified against the
  ## actual module bytes.
  verifySubjectBlobPin("toml d2-agent", domain.modulePath,
    domain.subjectBlobSha256, subjectRoot)

# ---------------------------------------------------------------------------
# Generic Nim proposition sidecar with HASH-BOUND adoption
# (docs/spec/nim_stew_base36_sidecar_contract.md)
# ---------------------------------------------------------------------------
# Fifth out-of-tree explicit spec overlay, same authority pattern as the
# base36 sizing / base32 rem / base36 C_out / toml d2-agent overlays: the
# proposition over the READ-ONLY subject lives only in this repo's
# config/spec, is pinned to soExplicit by explicitSpecFromOverlay, and any
# present-but-parse/shape failure blocks `ax prove` (fail closed). Presence
# is OPTIONAL at the prepareProofRun call site (Amendment F two-PR landing
# discipline — config/spec/** is a non-closure companion): an ABSENT file
# logs an explicit inert-binding line and the run proceeds.
#
# What is NEW here is ADOPTION BINDING — the d2 lane's audit gap ("adoption
# = adoption (not authorship)" was documented but never mechanically
# enforced). The sidecar carries an adoption record whose adoptedSpecHash is
# the specification artifact's identity (SpecID = H(sorted canonicalSpecIR |
# origin | ruleVersion)) of the exact proposition content. The loader
# performs a TWO-STAGE check:
#   (i)  shape + closed-grammar validation (nim-sidecar-expr-v1 — the rust
#        lane's closed spec grammar family: additive ("==" additive)?,
#        'result'/declared value param idents, non-negative int literals,
#        '+', '==', parentheses; anything else fails closed);
#   (ii) the spec identity is RECOMPUTED from the loaded proposition content
#        and compared byte-exactly with adoption.adoptedSpecHash — any
#        post-adoption mutation of a clause, the ruleId, or the ruleVersion
#        invalidates the adoption mechanically (fail-closed error).
# The subject pin is likewise a REAL check, not a format check: the module
# bytes at the recorded path under the subject root must hash to
# adoption.subject.blobSha256 (verifySidecarSubjectPin) — a subject tree
# that presents the governed module with any other content fails the run.

const NimSidecarOverlayFile* = "nim_stew_base36_sidecar.json"
  ## Axiom-owned sidecar document name (Zero-Footprint; runtime root
  ## resolution via `runtimeSpecOverlayPath`).

const SidecarGrammarV1* = "nim-sidecar-expr-v1"
  ## The ONLY grammar version this engine accepts in adoption.grammarVersion.
  ## A document pinned to another grammar names a different contract and is
  ## rejected fail-closed (this engine version refuses what it cannot parse;
  ## a new grammar must ship with a new engine version).

type
  SidecarSubjectPin* = object
    ## The adoption record's subject pin: which exact bytes of which module
    ## symbol the adopted proposition is about. Every field is required and
    ## format-checked; the blob digest is additionally VERIFIED against the
    ## module bytes at the recorded path under the subject root.
    source*: string
    module*: string
    symbol*: string
    commit*: string
    blobSha256*: string

  SidecarAdoptionRecord* = object
    ## The hash-bound adoption record. adoptedSpecHash is the SpecID
    ## (specIdentity) of the exact proposition content — recomputed at load
    ## time and compared byte-exactly. provenance preserves the content's
    ## authorship chain; authorship confers NO authority — the adoption act
    ## (this committed, hash-bound record) is the authority.
    adoptedSpecHash*: string
    adopter*: string
    adoptedAt*: string
    basis*: string
    grammarVersion*: string
    subject*: SidecarSubjectPin
    provenance*: string

  SidecarProposition* = object
    ## One adopted proposition instance: defect (expected SAT — the
    ## counterexample witness) or control (expected UNSAT — the injection
    ## guard). pre/post are the closed-grammar texts and their parsed IR;
    ## the parsed post's `result` slot is β-spliced onto the ORIGINAL body
    ## at synthesis.
    kind*: string
    preText*: string
    postText*: string
    pre*: IRExpr
    post*: IRExpr

  SidecarDomain* = object
    ## The synthesis-relevant projection of the sidecar: which module+symbol
    ## key the adoption governs, the declared value parameter the
    ## propositions bind, the parsed propositions (defect + control), and
    ## the adoption record. Everything is parsed mechanically from the
    ## document — no subject names are hardcoded in the engine.
    modulePath*: string
    symbol*: string
    valueParam*: string
    ruleId*: string
    propositions*: seq[SidecarProposition]
    adoption*: SidecarAdoptionRecord

func sidecarCarrierName*(domain: SidecarDomain; kind: string): string {.
    raises: [].} =
  ## The synthesized carrier's kernel name for one proposition kind —
  ## derived from the governed symbol; never a symbol the subject declares.
  domain.symbol & "_sidecar_" & kind

func overlayDeclaresSidecarSubject*(domain: SidecarDomain; fnName,
    modulePath: string): bool {.raises: [].} =
  ## D4 membership for the sidecar: the EXACT module+symbol key the adoption
  ## pins. The module-path gate keeps the binding inert for every other
  ## subject tree.
  modulePath == domain.modulePath and fnName == domain.symbol

type
  SidecarParseResult* = object
    ## The closed-grammar parse outcome (the rust lane's SpecParseResult
    ## family, sidecar-owned so rejections name the sidecar clause and the
    ## grammar version).
    ok*: bool
    expr*: IRExpr
    reason*: string

func isSidecarIdentStart(c: char): bool {.raises: [].} = c in {'a'..'z', '_'}
func isSidecarIdentChar(c: char): bool {.raises: [].} = c in {'a'..'z', '0'..'9', '_'}

proc sidecarPrimary(s: string; pos: var int; paramNames: seq[string];
    clause: string): SidecarParseResult {.raises: [].}
proc sidecarAdditive(s: string; pos: var int; paramNames: seq[string];
    clause: string): SidecarParseResult {.raises: [].}

proc sidecarPrimary(s: string; pos: var int; paramNames: seq[string];
    clause: string): SidecarParseResult {.raises: [].} =
  ## primary := ident | non-negative-integer | "(" additive ")"
  ## The grammar is CLOSED (nim-sidecar-expr-v1): no operators beyond '+',
  ## '==', parentheses; no negative literals; no calls; no multiplication.
  ## Anything else is an explicit not-ok naming the sidecar clause.
  while pos < s.len and s[pos] in {' ', '\t'}: inc pos
  if pos >= s.len:
    return SidecarParseResult(ok: false, reason:
      "sidecar " & clause & " ended where a term was expected (grammar " &
      SidecarGrammarV1 & ")")
  let c = s[pos]
  if c == '(':
    inc pos
    let inner = sidecarAdditive(s, pos, paramNames, clause)
    if not inner.ok:
      return inner
    while pos < s.len and s[pos] in {' ', '\t'}: inc pos
    if pos >= s.len or s[pos] != ')':
      return SidecarParseResult(ok: false, reason:
        "sidecar " & clause & " expected ')' — outside the closed grammar " &
        SidecarGrammarV1)
    inc pos
    return inner
  if c in {'0'..'9'}:
    let start = pos
    while pos < s.len and s[pos] in {'0'..'9'}: inc pos
    var value: int64 = 0
    for i in start ..< pos:
      let digit = int64(s[i].ord - '0'.ord)
      if value > (int64.high - digit) div 10:
        return SidecarParseResult(ok: false, reason:
          "sidecar " & clause & " integer literal overflow — outside the " &
          "closed grammar " & SidecarGrammarV1)
      value = value * 10 + digit
    return SidecarParseResult(ok: true, expr: irLit(value))
  if isSidecarIdentStart(c):
    let start = pos
    inc pos
    while pos < s.len and isSidecarIdentChar(s[pos]): inc pos
    let name = s[start ..< pos]
    if name == "result" or name in paramNames:
      return SidecarParseResult(ok: true, expr: irVar(name, irTypeBitVec64()))
    return SidecarParseResult(ok: false, reason:
      "sidecar " & clause & " references unknown identifier '" & name &
      "' (neither 'result' nor the declared subject value parameter) — fail-closed")
  SidecarParseResult(ok: false, reason:
    "sidecar " & clause & " character '" & c & "' is outside the closed " &
    "grammar " & SidecarGrammarV1 & " (identifiers, non-negative integer " &
    "literals, '+', '==', parentheses)")

proc sidecarAdditive(s: string; pos: var int; paramNames: seq[string];
    clause: string): SidecarParseResult {.raises: [].} =
  ## additive := primary ("+" primary)*
  let first = sidecarPrimary(s, pos, paramNames, clause)
  if not first.ok:
    return first
  result = first
  while true:
    while pos < s.len and s[pos] in {' ', '\t'}: inc pos
    if pos < s.len and s[pos] == '+':
      inc pos
      let rhs = sidecarPrimary(s, pos, paramNames, clause)
      if not rhs.ok:
        return rhs
      result = SidecarParseResult(ok: true, expr: irAdd(result.expr, rhs.expr))
    else:
      return

proc parseSidecarClosedExpr*(text: string; paramNames: seq[string];
    clause: string): SidecarParseResult {.raises: [].} =
  ## The CLOSED sidecar proposition parser (grammar nim-sidecar-expr-v1):
  ## `additive ( "==" additive )?`. Same grammar family as the rust lane's
  ## parseClosedSpecPost (the specAddAdd shape), sidecar-owned so the
  ## rejections name the sidecar clause and grammar version. Builds the
  ## IRExpr family — 'result'/params → irVar(BV64; retyped to the subject's
  ## real parameter type at synthesis), '+' → irAdd, '==' → irEq, literals →
  ## irLit. Anything else fails closed. proc, not func — the mutually
  ## recursive descent defeats the effect inference (the parseLlbcFile
  ## purity precedent); raises: [] still holds.
  var pos = 0
  let lhs = sidecarAdditive(text, pos, paramNames, clause)
  if not lhs.ok:
    return lhs
  while pos < text.len and text[pos] in {' ', '\t'}: inc pos
  if pos < text.len and text[pos] == '=':
    if pos + 1 >= text.len or text[pos + 1] != '=':
      return SidecarParseResult(ok: false, reason:
        "sidecar " & clause & " single '=' is outside the closed grammar " &
        SidecarGrammarV1 & " (only '==')")
    pos += 2
    let rhs = sidecarAdditive(text, pos, paramNames, clause)
    if not rhs.ok:
      return rhs
    while pos < text.len and text[pos] in {' ', '\t'}: inc pos
    if pos != text.len:
      return SidecarParseResult(ok: false, reason:
        "sidecar " & clause & " has trailing input after the equality — " &
        "outside the closed grammar " & SidecarGrammarV1)
    return SidecarParseResult(ok: true, expr: irEq(lhs.expr, rhs.expr))
  if pos != text.len:
    return SidecarParseResult(ok: false, reason:
      "sidecar " & clause & " has unexpected trailing input — outside the " &
      "closed grammar " & SidecarGrammarV1)
  lhs

func validateSidecarAdoption(node: JsonNode): Result[SidecarAdoptionRecord,
    string] {.raises: [].} =
  ## Fail-closed adoption record: the hash, the adoption-act fields, the
  ## grammar pin, and the subject pin must all be present and well-formed —
  ## a record that does not name WHAT it adopted, WHO adopted it, and WHICH
  ## subject bytes it binds is not an adoption.
  let adoption = node{"adoption"}
  if adoption.isNil or adoption.kind != JObject:
    return err("spec sidecar: adoption object required (hash-bound adoption record)")
  for field in ["adoptedSpecHash", "adopter", "adoptedAt", "basis",
                "grammarVersion", "provenance"]:
    if adoption{field}.getStr("").len == 0:
      return err("spec sidecar: adoption." & field & " is required " &
        "(hash-bound adoption record)")
  let adoptedHash = adoption{"adoptedSpecHash"}.getStr("")
  if adoptedHash.len != 64 or not adoptedHash.allCharsInSet(
      {'0'..'9', 'a'..'f', 'A'..'F'}):
    return err("spec sidecar: adoption.adoptedSpecHash must be a 64-hex digest")
  if adoption{"grammarVersion"}.getStr("") != SidecarGrammarV1:
    return err("spec sidecar: adoption.grammarVersion must be " &
      SidecarGrammarV1 & " (this engine refuses propositions pinned to " &
      "any other grammar)")
  let subject = adoption{"subject"}
  if subject.isNil or subject.kind != JObject:
    return err("spec sidecar: adoption.subject object required (subject pin)")
  for field in ["source", "module", "symbol"]:
    if subject{field}.getStr("").len == 0:
      return err("spec sidecar: adoption.subject." & field &
        " is required (subject pin)")
  let commit = subject{"commit"}.getStr("")
  if commit.len != 40 or not commit.allCharsInSet({'0'..'9', 'a'..'f'}):
    return err("spec sidecar: adoption.subject.commit must be a 40-hex commit")
  let blob = subject{"blobSha256"}.getStr("")
  if blob.len != 64 or not blob.allCharsInSet({'0'..'9', 'a'..'f', 'A'..'F'}):
    return err("spec sidecar: adoption.subject.blobSha256 must be a 64-hex digest")
  ok(SidecarAdoptionRecord(
    adoptedSpecHash: adoptedHash,
    adopter: adoption{"adopter"}.getStr(""),
    adoptedAt: adoption{"adoptedAt"}.getStr(""),
    basis: adoption{"basis"}.getStr(""),
    grammarVersion: adoption{"grammarVersion"}.getStr(""),
    subject: SidecarSubjectPin(
      source: subject{"source"}.getStr(""),
      module: subject{"module"}.getStr(""),
      symbol: subject{"symbol"}.getStr(""),
      commit: commit,
      blobSha256: blob),
    provenance: adoption{"provenance"}.getStr("")))

proc validateSidecarOverlayNode*(node: JsonNode): Result[SidecarDomain, string] {.
    raises: [].}
  ## The pure validation core of the sidecar loader — the TWO-STAGE adoption
  ## check (stage i: authority + shape + closed grammar; stage ii: spec
  ## identity recomputed from the loaded content vs adoption.adoptedSpecHash,
  ## byte-exact). Every rejection here blocks the run outright (fail closed).

proc loadNimSidecarOverlayDomain*(): Result[SidecarDomain, string] {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D1 for the sidecar: read + validate via the same
  ## `explicitSpecFromOverlay` authority path as the predecessor overlays.
  ## Absence is handled at the call site (presence-optional landing
  ## discipline); here an unreadable/present-but-invalid document is an
  ## error.
  var node: JsonNode
  let pathRes = runtimeSpecOverlayPath(NimSidecarOverlayFile)
  if pathRes.isErr():
    return err("cannot resolve the spec overlay directory (fail-closed): " &
      pathRes.error)
  let overlayPath = pathRes.get
  let nodeOpt = readJsonFile(overlayPath)
  if nodeOpt.isNone:
    return err("cannot read spec sidecar " & overlayPath &
      " (unreadable or not valid JSON)")
  validateSidecarOverlayNode(nodeOpt.get)

proc validateSidecarOverlayNode*(node: JsonNode): Result[SidecarDomain, string] {.
    raises: [].} =
  # ── STAGE (i): authority + shape + closed grammar ──
  let specRes = explicitSpecFromOverlay(node)
  if specRes.isErr():
    return err("spec sidecar rejected: " & specRes.error)
  if node{"description"}.getStr("").len == 0:
    return err("spec sidecar: description is required (the claim's prose)")
  for field in ["semanticCaveats", "nonClaims"]:
    let arr = node{field}
    if arr.isNil or arr.kind != JArray or arr.len < 1:
      return err("spec sidecar: " & field & " must be a non-empty array")
    for e in arr:
      if e.kind != JString or e.getStr("").len == 0:
        return err("spec sidecar: " & field & " entries must be non-empty strings")
  let adoptionRes = validateSidecarAdoption(node)
  if adoptionRes.isErr():
    return err(adoptionRes.error)
  let valueParam = node{"valueParam"}.getStr("")
  if valueParam.len == 0 or not isIdentLike(valueParam):
    return err("spec sidecar: valueParam must name the subject's value " &
      "parameter (an identifier)")
  let propsNode = node{"propositions"}
  if propsNode.isNil or propsNode.kind != JArray or propsNode.len != 2:
    return err("spec sidecar: exactly 2 propositions (defect + control) required")
  var props: seq[SidecarProposition]
  var seen: array[2, bool]  # [defect, control]
  for p in propsNode:
    if p.isNil or p.kind != JObject:
      return err("spec sidecar: proposition entries must be objects")
    let kind = p{"kind"}.getStr("")
    if kind != "defect" and kind != "control":
      return err("spec sidecar: proposition kind must be defect or control")
    let slot = (if kind == "defect": 0 else: 1)
    if seen[slot]:
      return err("spec sidecar: duplicate " & kind & " proposition")
    seen[slot] = true
    let preText = p{"pre"}.getStr("")
    let postText = p{"post"}.getStr("")
    if preText.len == 0 or postText.len == 0:
      return err("spec sidecar: the " & kind &
        " proposition needs non-empty pre and post")
    let preRes = parseSidecarClosedExpr(preText, @[valueParam], kind & " pre")
    if not preRes.ok:
      return err(preRes.reason)
    let postRes = parseSidecarClosedExpr(postText, @[valueParam], kind & " post")
    if not postRes.ok:
      return err(postRes.reason)
    props.add(SidecarProposition(kind: kind, preText: preText,
      postText: postText, pre: preRes.expr, post: postRes.expr))
  if not (seen[0] and seen[1]):
    return err("spec sidecar: exactly one defect and one control proposition required")
  # One proposition content, two roles: canonicalSpecIR is the identity
  # carrier, the propositions block maps the same texts to defect/control.
  # The document must not be able to state them differently (no second
  # semantic source).
  let clauses = specRes.value.canonicalSpecIR
  if clauses != @[props[0].preText, props[0].postText,
                  props[1].preText, props[1].postText]:
    return err("spec sidecar: canonicalSpecIR must be exactly [defect.pre, " &
      "defect.post, control.pre, control.post] (one proposition content)")
  # ── STAGE (ii): HASH-BOUND ADOPTION ──
  # Recompute the spec identity from the LOADED proposition content and
  # compare byte-exactly with the adoption record. Any post-adoption
  # mutation of a clause, the ruleId, or the ruleVersion changes the
  # identity and mechanically invalidates the adoption.
  let computed = specRes.value.specIdentity
  if computed != adoptionRes.get.adoptedSpecHash:
    return err("spec sidecar: adoption does not bind the current proposition " &
      "content (spec identity mismatch): the adoption record pins " &
      adoptionRes.get.adoptedSpecHash & ", the loaded proposition computes " &
      computed)
  ok(SidecarDomain(
    modulePath: adoptionRes.get.subject.module,
    symbol: adoptionRes.get.subject.symbol,
    valueParam: valueParam,
    ruleId: specRes.value.ruleId,
    propositions: props,
    adoption: adoptionRes.get))

proc verifySidecarSubjectPin*(domain: SidecarDomain; subjectRoot: string):
    Result[bool, string] {.raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The REAL subject-pin check for the sidecar lane (VS-2 PR-3 flip): the
  ## byte-hash semantics are the shared registry proc's (REGISTRY_SPEC §2.4 —
  ## ONE pin-verify). The lane's diagnostic voice is preserved byte-for-byte:
  ## `lane` = "sidecar" (the retired body's prefix) and the adoption-record
  ## mismatch wording. When the governed module exists under this run's
  ## subject root, its bytes must hash to adoption.subject.blobSha256 — a
  ## tree that presents the governed module with any other content does not
  ## match the adoption's subject and fails the run (fail-closed). When the
  ## module does not exist under the subject root the lane is INERT here
  ## (ok(false)): the membership gate could never match this tree either,
  ## and a committed sidecar must not block runs on subjects it does not
  ## govern. ok(true) = pin verified against the actual module bytes.
  verifySubjectBlobPin("sidecar", domain.adoption.subject.module,
    domain.adoption.subject.blobSha256, subjectRoot, spwAdoptionRecord)

proc probeSubjectIdentity*(sourceRoot: string;
    entryRaw: JsonNode): BugVerdictSubjectIdentity {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §2.4d subject probe — the exact-commit binding inputs: `git -C
  ## <sourceRoot> rev-parse HEAD` + sha256 of the overlay module bytes. Any
  ## failure fails closed (probeOk=false ⇒ scope commitUnverifiable ⇒ the
  ## display block is absent — never Unknown, never fabricated). The module
  ## path reads the entry's subject pin node (`subject ?:
  ## adoption.subject` — the sidecar pins under its adoption record), one
  ## node, no second semantic source; a nil entry — or one naming no
  ## subject module — fails closed exactly as an absent document did.
  var probe = BugVerdictSubjectIdentity(probeOk: false)
  let subject = displaySubjectNode(entryRaw)
  if subject.isNil:
    return probe
  let modulePath = subject{"module"}.getStr("")
  if modulePath.len == 0:
    return probe
  let (headOut, headCode) = execCmdEx(
    "git -C " & quoteShell(sourceRoot) & " rev-parse HEAD",
    {poStdErrToStdOut, poUsePath})
  if headCode == 0:
    let commit = headOut.strip()
    if commit.len == 40 and commit.count({'0'..'9', 'a'..'f'}) == 40:
      probe.commit = commit
  try:
    probe.blob = sha256Hex(readFile(sourceRoot / modulePath))
  except CatchableError:
    probe.blob = ""  # fail-closed: an unreadable module can never blob-match
  probe.probeOk = probe.commit.len == 40
  probe

proc collectDisplayGrounds(specId: string; overlay: JsonNode):
    tuple[grounds: JsonNode; rawDigest: string; assessment: GroundsAssessment] {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The attribution leg (§2.2): the committed grounds record for the
  ## overlay's specId, its raw digest, and the derived assessment.
  ## Absent/unreadable records stay fail-closed ("grounds: absent" /
  ## unverified) — never fabricated.
  # Runtime root resolution (the S2b seam `findRepoRootStrict`, productization
  # contract §1b): the release bundle carries data/bug_attribution under its
  # own root, and a tree-external bundle binary must resolve ITS records — the
  # former compile-time `repoRootConst()` join baked the build machine's path
  # into the binary. An unresolvable root leaves grounds unread — the same
  # fail-closed "absent / unverified" posture as a missing record (never
  # fabricated).
  var groundsPath = ""
  let rootRes = findRepoRootStrict()
  if rootRes.isOk():
    groundsPath = rootRes.get / "data" / "bug_attribution" / (specId & ".json")
  var grounds: JsonNode = nil
  var rawDigest = ""
  let groundsOpt = if groundsPath.len > 0: readJsonFile(groundsPath)
                   else: none(JsonNode)
  if groundsOpt.isSome:
    grounds = groundsOpt.get
    try:
      rawDigest = sha256Hex(readFile(groundsPath))
    except CatchableError:
      rawDigest = ""  # fail-closed: an unreadable record is unverified
  let assessment = if grounds.isNil:
    GroundsAssessment(validationReason: "grounds: absent")
  else:
    assessGrounds(grounds, overlay)
  (grounds, rawDigest, assessment)

proc collectUnitQuartet(runResult: CanonicalRunResult; unitEvidence: JsonNode;
    targetSymbol: string): tuple[rowStatus: string; claimOutcome: string;
    quartetComplete: bool; quartetPayloadDigest: string;
    quartetLines: seq[string]] {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## ── §2.4d unit-scoped conjunction — the governed unit's own records ──
  ## The selected observed row's status, that unit's claim outcome, and the
  ## §2.2 shared quartet grouped from the verbatim payload lines (① subject
  ## binding ② exact input ③ violated conjunct ④ replay); fail-closed: any
  ## missing element never completes the premise. The digest binds the raw
  ## quartet payload; `quartetLines` carries the verbatim payload lines as
  ## the persistence carrier (findingEvidence) — one producer, no
  ## re-derivation elsewhere.
  var rowStatus = ""
  for row in runResult.executionEvidence.observedRows:
    if row{"nodeId"}.getStr("") == targetSymbol:
      rowStatus = row{"status"}.getStr("")
      break
  var claimOutcome = ""
  var quartetLines: seq[string] = @[]
  let unitNode = unitEvidence{targetSymbol}
  if not unitNode.isNil and unitNode.kind == JObject:
    claimOutcome = unitNode{"claimOutcome"}.getStr("")
    let ceNode = unitNode{"counterExample"}
    if not ceNode.isNil and ceNode.kind == JArray:
      for line in ceNode:
        if line.kind == JString:
          quartetLines.add(line.getStr())
  var g1, g2, g3, g4: seq[string] = @[]
  for line in quartetLines:
    if line.startsWith("replay.subjectGitRef=") or
        line.startsWith("replay.moduleSha256=") or
        line.startsWith("replay.treeMerkle="):
      g1.add(line)
    elif line.startsWith("input."):
      g2.add(line)
    elif line.startsWith("propertyViolated="):
      g3.add(line)
    elif line.startsWith("replay."):
      g4.add(line)
  let quartetComplete = g1.len > 0 and g2.len > 0 and g3.len > 0 and g4.len > 0
  let quartetPayloadDigest =
    if quartetLines.len > 0: sha256Hex(quartetLines.join("\n")) else: ""
  (rowStatus, claimOutcome, quartetComplete, quartetPayloadDigest, quartetLines)

func machineEstablishedOf(unitLeg: tuple[rowStatus: string; claimOutcome: string;
    quartetComplete: bool; quartetPayloadDigest: string;
    quartetLines: seq[string]]): bool {.raises: [].} =
  ## The §2.4d unit-scoped machine conjunction — ONE definition shared by
  ## buildDisplayInput (RULE-axis premise) and the findingEvidence
  ## persistence (appendDisplayAndPersist). rowStatus is a RULE-axis premise
  ## only: it is never a fallback conjunct of the §2.2 proposition verdict.
  unitLeg.rowStatus == "failed" and unitLeg.claimOutcome == "clDisproved" and
    unitLeg.quartetComplete

proc buildDisplayInput(runResult: CanonicalRunResult;
    probe: BugVerdictSubjectIdentity; overlay: JsonNode; specId: string;
    targetSymbol: string; scopeStatus: string; ownership: JsonNode;
    specRelPath: string;
    groundsLeg: tuple[grounds: JsonNode; rawDigest: string;
      assessment: GroundsAssessment];
    unitLeg: tuple[rowStatus: string; claimOutcome: string;
      quartetComplete: bool; quartetPayloadDigest: string;
      quartetLines: seq[string]]):
    BugVerdictDisplayInput {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Machine spellings + field assembly — PROJECTED from the decided outcome
  ## (never literals of the guarded vocabulary written to guarded keys; these
  ## ride only inside the display-owned machineTuple/digest and the display
  ## namespace). `machineEstablished` is the §2.4d UNIT-scoped conjunction
  ## (replaces the retired run-scoped premise): the governed unit's row
  ## supports a violation, that unit's claim disproved, and that unit's
  ## quartet record complete. `specRelPath` is the unit's adoptedSpecRef
  ## registry document identity — bound into the display input digest. The
  ## unit's quartet observation rides the carrier (quartetComplete feeds
  ## propositionVerdictOf's §2.2 conjunct; quartetLines is the persistence
  ## carrier, never a digest input — quartetPayloadDigest binds the payload).
  let verdictSpelling = $runResult.runOutcome.verdict
  let recordComplete = runResult.runOutcome.planComplete and
    runResult.runOutcome.executionComplete and
    runResult.runOutcome.verificationComplete
  let machineTuple = %*{
    "verdict": verdictSpelling,
    "basis": $runResult.runOutcome.basis,
    "recordComplete": recordComplete}
  BugVerdictDisplayInput(
    machineEstablished: machineEstablishedOf(unitLeg),
    machineTuple: machineTuple,
    ruleId: overlay{"ruleId"}.getStr(""),
    ownership: ownership,
    groundsRefs: (if groundsLeg.grounds.isNil: @[]
      else: groundsRefEntries(groundsLeg.grounds)),
    groundsRawDigest: groundsLeg.rawDigest,
    assessment: groundsLeg.assessment,
    targetSymbol: targetSymbol,
    rowStatus: unitLeg.rowStatus,
    scopeStatus: scopeStatus,
    claimOutcome: unitLeg.claimOutcome,
    quartetPayloadDigest: unitLeg.quartetPayloadDigest,
    quartetComplete: unitLeg.quartetComplete,
    quartetLines: unitLeg.quartetLines,
    subjectCommit: probe.commit,
    subjectBlob: probe.blob,
    specId: specId,
    specRelPath: specRelPath)

proc buildBugVerdictDisplayJson*(runResult: CanonicalRunResult;
    unitEvidence: JsonNode; probe: BugVerdictSubjectIdentity;
    entryRaw: JsonNode; specRelPath: string; specId: string;
    targetSymbol: string): JsonNode {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The per-UNIT builder (display v3, glossary §2.4d): ONE adopted
  ## governed unit's display block. The caller supplies the unit's adopted
  ## overlay identity — `entryRaw` (the registry entry's own raw node, one
  ## authority, no second file read), its `specRelPath`/`specId`, and the
  ## `targetSymbol` (`modulePath::funcName`, the unit-evidence row key) —
  ## so this proc recomputes no dispatch priority and hardwires no lane
  ## document. A nil node, an identity disagreement between the caller's
  ## resolution and the document, or a missing commit pin ⇒ nil block
  ## (never fabricated). Scope table: any commit/blob binding unmet ⇒ nil
  ## block (not-applicable — block absence is never Unknown). Display
  ## labels only (namespaced "display" key); never writes a guarded
  ## outcome key.
  if entryRaw.isNil:
    return nil
  if specRelPath.len == 0 or specId.len == 0 or targetSymbol.len == 0:
    return nil
  let overlay = entryRaw
  # The caller's per-unit resolution must name THIS document (fail-closed:
  # a disagreement means the adopted identity and the raw authority
  # diverged — the display never fabricates).
  if overlay{"specId"}.getStr("") != specId:
    return nil
  # §2.4d scope — the structured subject pin (`subject ?: adoption.subject`);
  # an absent pin ⇒ fail-closed (the exact-commit binding is unmet).
  let subject = displaySubjectNode(overlay)
  if subject.isNil:
    return nil
  let pinnedCommit = subject{"commit"}.getStr("")
  if pinnedCommit.len != 40:
    return nil
  let scopeStatus = classifySubjectScope(pinnedCommit,
    subject{"blobSha256"}.getStr(""), probe)
  if scopeStatus != scopeVerifiedMatch:
    return nil
  let ownership = if overlay{"claimOwnership"}.isNil:
    unrecordedOwnership()
  else:
    overlay{"claimOwnership"}.copy()
  let groundsLeg = collectDisplayGrounds(specId, overlay)
  let unitLeg = collectUnitQuartet(runResult, unitEvidence, targetSymbol)
  let input = buildDisplayInput(runResult, probe, overlay, specId,
    targetSymbol, scopeStatus, ownership, specRelPath, groundsLeg, unitLeg)
  displayToJson(displayBugVerdict(input))

proc buildBugVerdictDisplayJson*(runResult: CanonicalRunResult;
    unitEvidence: JsonNode; probe: BugVerdictSubjectIdentity;
    entry: RegistryEntry): JsonNode {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §2.8 per-ENTRY seam for callers OUTSIDE a prepared run (the bug-verdict
  ## display suite): the per-unit resolution over ONE registry entry's
  ## governed units (envelope `governedModule::symbol` — the same
  ## extractGoverned shapes the loader derives). Each governed unit goes
  ## through the per-UNIT builder with the entry's own raw node and
  ## identities; the v3 units container carries every block that passed the
  ## scope gate. No in-scope unit ⇒ nil container (never fabricated).
  var units: seq[JsonNode] = @[]
  for symbol in entry.governedSymbols:
    let unitKey = entry.governedModule & "::" & symbol
    let unitBlock = buildBugVerdictDisplayJson(runResult, unitEvidence,
      probe, entry.raw, entry.specRelPath, entry.specId, unitKey)
    if not unitBlock.isNil:
      units.add(unitBlock)
  if units.len == 0:
    return nil
  displayContainerJson(units)


func collectFreeNames(e: IRExpr; bound: HashSet[string]): seq[string] {.
    raises: [].} =
  ## Free variable names the tree references that `bound` does not cover —
  ## deduplicated and sorted, so the result never depends on traversal
  ## randomness. A let-binding covers its own continuation, not its value.
  var acc: seq[string]
  func walk(e: IRExpr; bound: HashSet[string]) =
    if e == nil: return
    case e.kind
    of irVar:
      if e.varName notin bound and e.varName notin acc:
        acc.add(e.varName)
    of irLet:
      walk(e.letVal, bound)
      var innerBound = bound
      innerBound.incl(e.letName)
      walk(e.letBody, innerBound)
    of irIf:
      walk(e.ifCond, bound); walk(e.ifThen, bound); walk(e.ifElse, bound)
    of irCase:
      walk(e.caseScrutinee, bound)
      for br in e.caseBranches: walk(br.body, bound)
      walk(e.caseDefault, bound)
    of irCall:
      for a in e.callArgs: walk(a, bound)
    of irBinOp:
      walk(e.binLhs, bound); walk(e.binRhs, bound)
    of irUnaryOp:
      walk(e.unaryArg, bound)
    of irRecCall:
      for a in e.recArgs: walk(a, bound)
    of irLoop:
      for i in e.loopInits: walk(i, bound)
      walk(e.loopCond, bound); walk(e.loopStep, bound); walk(e.loopBody, bound)
      for inv in e.loopInvariants: walk(inv, bound)
      walk(e.loopVariant, bound)
    of irCast:
      walk(e.castExpr, bound)
    of irLit, irFloatLit, irStringLit:
      discard
  walk(e, bound)
  acc.sort()
  result = acc

func cloneIRExpr(e: IRExpr): IRExpr {.raises: [].}
  ## Structural clone of an expression tree: composite nodes rebuilt fresh,
  ## leaves and type descriptors shared immutable metadata.

func substituteParamUse(e: IRExpr; target: string; replacement: IRExpr;
                        splices: var int): IRExpr {.raises: [].} =
  ## β-substitution with node cloning: every irVar naming `target` becomes a
  ## fresh structural clone of `replacement` — one clone per splice site,
  ## because IRExpr is a ref and one node shared between two parents would
  ## alias them. Every other node is rebuilt with substituted children;
  ## `typ`/`varType` and type descriptors are shared immutable metadata.
  ## nil optional children stay nil.
  if e == nil: return nil
  case e.kind
  of irVar:
    if e.varName == target:
      inc splices
      cloneIRExpr(replacement)
    else:
      e
  of irLit, irFloatLit, irStringLit:
    e
  of irLet:
    IRExpr(typ: e.typ, kind: irLet, letName: e.letName,
      letVal: substituteParamUse(e.letVal, target, replacement, splices),
      letBody: substituteParamUse(e.letBody, target, replacement, splices),
      isCompileTime: e.isCompileTime)
  of irIf:
    IRExpr(typ: e.typ, kind: irIf,
      ifCond: substituteParamUse(e.ifCond, target, replacement, splices),
      ifThen: substituteParamUse(e.ifThen, target, replacement, splices),
      ifElse: substituteParamUse(e.ifElse, target, replacement, splices))
  of irCase:
    var branches: seq[CaseBranch] = @[]
    for br in e.caseBranches:
      branches.add(CaseBranch(pattern: br.pattern,
        body: substituteParamUse(br.body, target, replacement, splices)))
    IRExpr(typ: e.typ, kind: irCase,
      caseScrutinee: substituteParamUse(e.caseScrutinee, target, replacement, splices),
      caseBranches: branches,
      caseDefault: substituteParamUse(e.caseDefault, target, replacement, splices))
  of irCall:
    var args: seq[IRExpr] = @[]
    for a in e.callArgs:
      args.add(substituteParamUse(a, target, replacement, splices))
    IRExpr(typ: e.typ, kind: irCall, callName: e.callName, callArgs: args)
  of irBinOp:
    IRExpr(typ: e.typ, kind: irBinOp, binOp: e.binOp,
      binLhs: substituteParamUse(e.binLhs, target, replacement, splices),
      binRhs: substituteParamUse(e.binRhs, target, replacement, splices))
  of irUnaryOp:
    IRExpr(typ: e.typ, kind: irUnaryOp, unaryOp: e.unaryOp,
      unaryArg: substituteParamUse(e.unaryArg, target, replacement, splices))
  of irRecCall:
    var args: seq[IRExpr] = @[]
    for a in e.recArgs:
      args.add(substituteParamUse(a, target, replacement, splices))
    IRExpr(typ: e.typ, kind: irRecCall, recArgs: args)
  of irLoop:
    var inits: seq[IRExpr] = @[]
    for i in e.loopInits:
      inits.add(substituteParamUse(i, target, replacement, splices))
    var invariants: seq[IRExpr] = @[]
    for inv in e.loopInvariants:
      invariants.add(substituteParamUse(inv, target, replacement, splices))
    IRExpr(typ: e.typ, kind: irLoop, loopKind: e.loopKind,
      loopVars: e.loopVars, loopInits: inits,
      loopCond: substituteParamUse(e.loopCond, target, replacement, splices),
      loopStep: substituteParamUse(e.loopStep, target, replacement, splices),
      loopBody: substituteParamUse(e.loopBody, target, replacement, splices),
      loopInvariants: invariants,
      loopVariant: substituteParamUse(e.loopVariant, target, replacement, splices))
  of irCast:
    IRExpr(typ: e.typ, kind: irCast,
      castExpr: substituteParamUse(e.castExpr, target, replacement, splices),
      castFrom: e.castFrom, castTo: e.castTo)

func cloneIRExpr(e: IRExpr): IRExpr {.raises: [].} =
  ## The sentinel target cannot name any irVar, so no splice fires and the
  ## replacement argument is never dereferenced.
  var splices = 0
  substituteParamUse(e, "\x00no-splice", nil, splices)

proc synthesizeTomlD2AgentCandidate*(examinedFn, modulePath: string;
    resolver: ModuleContentResolver; domain: TomlD2AgentOverlayDomain;
    census: ExternalCandidateCensus; subjectRepoRoot: string = ""): Result[bool, string] {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D2/D3/D4 for the d2-agent overlay
  ## (docs/spec/toml_d2_agent_binding_contract.md): TWO constructed-IR
  ## carriers over one byte variable. The defect carrier's body is the code's
  ## actual four-member gate; the control carrier's body is forbid exactly —
  ## the differential design (defect SAT, control UNSAT) proves the gap is a
  ## set-membership defect, not a blanket gate failure. The obligation stays
  ## OPEN over the byte variable (preconditions are the domain conjuncts), so
  ## the SAT model binds c and the exact-input gate, the P4 pre-revalidation,
  ## and the original-code replay can fire.
  ##
  ## ok(true)  → defect carrier recorded and census-eligible (the gate may
  ##             pass; the control carrier rides under its own name);
  ## ok(false) → both carriers recorded and excluded (honest census outcome);
  ## err       → no carriers could be produced, so the examined symbol falls
  ##             back to its own census record.
  # One carrier pair per subject module per run: when the gate hits a governed
  # symbol twice (no --target), the second hit must not duplicate them.
  for existing in census.records:
    if existing.modulePath == modulePath and
        (existing.functionName == D2AgentDefectCarrierName or
         existing.functionName == D2AgentControlCarrierName):
      logInfo("axiom_engine",
        "toml d2-agent carriers already recorded — dedupe skip: " &
        examinedFn & " in " & modulePath)
      return ok(false)
  # The subject module bytes ride on the entries (§2.1a binding inputs); the
  # carriers themselves are constructed IR and never materialize subject
  # symbols.
  let moduleBytesOpt = resolver(modulePath)
  if moduleBytesOpt.isNone or moduleBytesOpt.get.len == 0:
    return err("overlay subject module bytes unavailable: " & modulePath)
  let moduleBytes = moduleBytesOpt.get
  let cVar = irVar(domain.domainVar, irTypeBitVec64())
  let forbidIr = d2ForbidPredicate(cVar, domain)

  proc makeCarrier(carrierName, groundingSymbol, groundingLines: string;
      body: IRExpr): Result[ExternalIrEntry, string] {.raises: [].} =
    ## One carrier: constructed-IR body, domain preconditions, the forbid
    ## claim β-spliced to the `result` slot exactly once. The provenance
    ## stamp is honest by construction: the carriers are ADOPTED MODELS, not
    ## extractions — the parse-bound components carry the grounding symbol's
    ## real EA measurement (which reports EA_UNSUPPORTED on the generic gate
    ## procs — legs stay empty, the canonical seal declines and the BMC lane
    ## decides the model), plus the deterministic derivation digest, plus the
    ## replay harness template that observes the ORIGINAL decoder.
    var composite = IRFuncDef(
      name: carrierName,
      params: @[IRFuncParam(name: domain.domainVar, ty: irTypeBitVec64())],
      retType: irTypeBool(),
      body: body)
    composite.preConditions = d2DomainPreconditions(cVar, domain)
    # THE ADOPTED CLAIM (docs/spec/toml_d2_agent_binding_contract.md):
    #   D(c) -> reject(c) = forbid(c)
    # The result slot receives a β-spliced clone of the carrier body —
    # exactly one splice, fail-closed — so the proposition's free variables
    # are exactly the byte parameter (the C_out composite's result-splice
    # pattern). For the control carrier the spliced claim is
    # forbid(c) == forbid(c): the UNSAT guard against spec injection.
    var rSplices = 0
    let claim = substituteParamUse(
      irEq(irVar("result", composite.retType), forbidIr),
      "result", body, rSplices)
    if rSplices != 1:
      return err("β-splice: the claim's result slot did not splice exactly " &
        "once (" & $rSplices & ")")
    # Fail-closed free-variable guard: the spliced proposition must reference
    # nothing beyond the byte parameter.
    var claimFree = initHashSet[string]()
    claimFree.incl(domain.domainVar)
    let unbound = collectFreeNames(claim, claimFree)
    if unbound.len > 0:
      return err("claim references unbound name(s): " & unbound.join(", "))
    composite.postConditions = @[claim]
    # Constructed-IR completeness bits: nothing was translated — the carrier
    # is built directly in IR, so every region it carries is fully spelled by
    # construction. The renderers and the solver re-decide downstream,
    # fail-closed, exactly as for the predecessor overlays' spliced claims.
    composite.translationLossFree = true
    composite.bindingUniverseComplete = true
    composite.propositionRegionLossFree = true
    composite.lossOutsideBindingRegions = false
    # WP4-j.4 pattern: the completeness evidence artifact is keyed by the same
    # digest scheme the runner cache hashes (serializeIRFuncDef of the
    # delivered funcDef), so the pipeline's evidence lookup finds this carrier
    # the same way it finds materialized singles.
    let irDigest = computeDeterministicCasKey(serializeIRFuncDef(composite))
    let completenessEvidence = CompletenessEvidence(
      translationLossFree: composite.translationLossFree,
      bindingUniverseComplete: composite.bindingUniverseComplete,
      opaqueExpansionStatus: "none",
      sourceBindingCount: composite.params.len,
      irBindingCount: collectLetNames(composite.body).len + composite.params.len)
    saveEvidenceArtifact(irDigest, completenessEvidence)
    # Phase 1A dual-write: authenticated strict sibling at the same anchor
    # (fail-closed — an unmeasured capture keeps the legacy-only generation).
    discard saveCompletenessEvidenceDual(irDigest, composite,
      measureCompletenessSourceCapture(subjectRepoRoot, modulePath,
        moduleBytes), completenessEvidence)
    let symRef = SubjectSymbolRef(relativeModulePath: modulePath,
      functionName: carrierName)
    let entry = synthesizeExternalEntry(symRef, composite, moduleBytes)
    # §2.1a carrier binding (single origin, honest legs): the carrier name
    # never appears in the subject source, so name correspondence cannot
    # apply; the derivation digest folds the rule identity and the grounding
    # file:lines. The EA legs record the grounding symbol's REAL differential
    # outcome — EA_UNSUPPORTED on the stream-coupled generic gate procs — so
    # the binding never attests an extraction that did not happen.
    let derivationRule = "d2-gate-model-v1|rule=" & domain.ruleId &
      "|grounding=" & modulePath & ":" & groundingLines
    var parseBound = measureClaimCarrierParseBoundComponents(
      moduleBytes, groundingSymbol, derivationRule)
    # The replay binding (contract §replay): the stamped harness observes the
    # ORIGINAL decoder through its public API — the model byte c renders into
    # the <lit> slot at replay time; the <module> slot is fixed by the
    # overlay pin here. The body is the CLOSED template registry's (VS-2
    # §1.5, `d2AgentReplayHarnessBody`), resolved below exactly as the
    # retired engine const was consumed here.
    parseBound.replayHarnessTemplate =
      d2AgentReplayHarnessBody().replace(ReplayModulePlaceholder,
        domain.importModule)
    ok(ExternalIrEntry(entry: entry, funcDef: composite, parseBound: parseBound))

  let defectRes = makeCarrier(D2AgentDefectCarrierName,
    domain.defectGroundingSymbol, domain.defectGroundingLines,
    d2GatePredicate(cVar, domain.defectGates))
  if defectRes.isErr:
    return err(defectRes.error)
  let controlRes = makeCarrier(D2AgentControlCarrierName,
    domain.controlGroundingSymbol, domain.controlGroundingLines,
    cloneIRExpr(forbidIr))
  if controlRes.isErr:
    return err(controlRes.error)
  let defect = defectRes.get
  let control = controlRes.get
  let defectRecord = classifyCandidateForCensus(defect.entry, defect.funcDef)
  census.records.add(defectRecord)
  let controlRecord = classifyCandidateForCensus(control.entry, control.funcDef)
  census.records.add(controlRecord)
  if defectRecord.censusEligible:
    # The eligible DEFECT entry is WAVE-FACING: the pipeline attributes
    # results to the node's bare function name, so RuntimeAxiomEntry.name is
    # the EXAMINED symbol — the disproof attributes to the frontier node whose
    # eligibility this synthesis decided. The claim identity stays the carrier
    # name everywhere else (census record, funcDef name, obligation ids). The
    # CONTROL carrier rides under its own name: its UNSAT is the differential's
    # spec-injection guard, verified through the same eligibility gate.
    var waveEntry = defect.entry
    waveEntry.name = examinedFn
    census.eligible.add(ExternalIrEntry(entry: waveEntry,
      funcDef: defect.funcDef, parseBound: defect.parseBound))
  if controlRecord.censusEligible:
    census.eligible.add(ExternalIrEntry(entry: control.entry,
      funcDef: control.funcDef, parseBound: control.parseBound))
  logInfo("axiom_engine", "toml d2-agent overlay carriers synthesized: " &
    D2AgentDefectCarrierName & " (gate " & defect.funcDef.name & "=" &
    $domain.defectGates & ") + " & D2AgentControlCarrierName &
    " (forbid " & $domain.forbidLow & "/" & $domain.forbidMidLo & "/" &
    $domain.forbidMidHi & "/" & $domain.forbidEq & ")" &
    " domain=" & $domain.domainLower & "<=" & domain.domainVar &
    "<=" & $domain.domainBound &
    " exclusions=" & $domain.exclusions.len &
    " obligations=" & $defectRecord.generatedObligationCount &
    "/" & $controlRecord.generatedObligationCount &
    " eligible=" & $defectRecord.censusEligible & "/" &
    $controlRecord.censusEligible &
    " source=" & modulePath)
  if not defectRecord.censusEligible:
    logInfo("axiom_engine", "toml d2-agent defect carrier excluded: " &
      " eligibility=" & $defectRecord.eligibility &
      " rejection=" & rejectionToken(defectRecord.rejection) &
      " source=" & modulePath)
  if not controlRecord.censusEligible:
    logInfo("axiom_engine", "toml d2-agent control carrier excluded: " &
      " eligibility=" & $controlRecord.eligibility &
      " rejection=" & rejectionToken(controlRecord.rejection) &
      " source=" & modulePath)
  ok(defectRecord.censusEligible)

proc synthesizeNimLibp2pBytesviewSliceCandidate*(examinedFn, modulePath: string;
    resolver: ModuleContentResolver; domain: NimLibp2pBytesviewSliceDomain;
    census: ExternalCandidateCensus; subjectRepoRoot: string = ""): Result[bool, string] {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D2/D3/D4 for the bytesview slice overlay
  ## (docs/spec/nim_libp2p_bytesview_slice_contract.md): TWO constructed-IR
  ## carriers over ONE length variable. The defect carrier's body is the
  ## template's ACTUAL length with the start offset pinned at 1 (e - 1) and
  ## its law side is the adopted inclusive law (e); the control carrier's
  ## body is the same template at b = 0 (e + 1) with the law side (e + 1) —
  ## the differential design (defect SAT, control UNSAT) proves the gap is a
  ## slice-length defect, not a blanket law failure. The obligation stays
  ## OPEN over the length variable (preconditions are the domain conjuncts),
  ## so the SAT model binds e, the P4 pre-revalidation, and the
  ## original-template replay can fire.
  ##
  ## ok(true)  → defect carrier recorded and census-eligible (the gate may
  ##             pass; the control carrier rides under its own name);
  ## ok(false) → both carriers recorded and excluded (honest census outcome);
  ## err       → no carriers could be produced, so the examined symbol falls
  ##             back to its own census record.
  # One carrier pair per subject module per run: when the gate hits a governed
  # symbol twice (no --target), the second hit must not duplicate them.
  for existing in census.records:
    if existing.modulePath == modulePath and
        (existing.functionName == BvSliceLenDefectCarrierName or
         existing.functionName == BvSliceLenControlCarrierName):
      logInfo("axiom_engine",
        "nim-libp2p bytesview slice carriers already recorded — dedupe skip: " &
        examinedFn & " in " & modulePath)
      return ok(false)
  # The subject module bytes ride on the entries (§2.1a binding inputs); the
  # carriers themselves are constructed IR and never materialize subject
  # symbols (the governed subject symbol is a TEMPLATE).
  let moduleBytesOpt = resolver(modulePath)
  if moduleBytesOpt.isNone or moduleBytesOpt.get.len == 0:
    return err("overlay subject module bytes unavailable: " & modulePath)
  let moduleBytes = moduleBytesOpt.get
  let eVar = irVar(domain.domainVar, irTypeBitVec64())
  # The closed-template-registry body (VS-2 §1.5 — fail-closed on an unknown
  # id; the lane's id is engine-owned, so an err here is an engine defect,
  # never spec text), resolved once for both carriers.
  let harnessTemplate = replayTemplate(BvSliceLenReplayTemplateId)
  if harnessTemplate.isErr:
    return err(harnessTemplate.error)

  proc makeCarrier(carrierName, groundingSymbol, groundingLines: string;
      model, law: IRExpr): Result[ExternalIrEntry, string] {.raises: [].} =
    ## One carrier: constructed-IR model body, domain preconditions, the
    ## adopted law β-spliced to the `result` slot exactly once. The
    ## provenance stamp is honest by construction: the carriers are ADOPTED
    ## MODELS, not extractions — the parse-bound components carry the
    ## grounding symbol's real EA measurement (which reports
    ## EA_UNSUPPORTED on the subject's TEMPLATE — the legs stay empty, the
    ## canonical seal declines and the BMC lane decides the model), plus the
    ## deterministic derivation digest, plus the replay harness template that
    ## observes the ORIGINAL template.
    var composite = IRFuncDef(
      name: carrierName,
      params: @[IRFuncParam(name: domain.domainVar, ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: model)
    composite.preConditions = @[irGe(eVar, irLit(domain.domainLower)),
                                irLe(eVar, irLit(domain.domainBound))]
    # THE ADOPTED CLAIM (docs/spec/nim_libp2p_bytesview_slice_contract.md):
    #   D(e) -> L_actual(b, e) == L_incl(b, e)
    # The result slot receives a β-spliced clone of the carrier model —
    # exactly one splice, fail-closed — so the proposition's free variables
    # are exactly the length parameter (the C_out composite's result-splice
    # pattern). For the control carrier the spliced claim is
    # (e + 1) == (e + 1): the UNSAT guard against spec injection.
    var rSplices = 0
    let claim = substituteParamUse(
      irEq(irVar("result", composite.retType), law),
      "result", model, rSplices)
    if rSplices != 1:
      return err("β-splice: the claim's result slot did not splice exactly " &
        "once (" & $rSplices & ")")
    # Fail-closed free-variable guard: the spliced proposition must reference
    # nothing beyond the length parameter.
    var claimFree = initHashSet[string]()
    claimFree.incl(domain.domainVar)
    let unbound = collectFreeNames(claim, claimFree)
    if unbound.len > 0:
      return err("claim references unbound name(s): " & unbound.join(", "))
    composite.postConditions = @[claim]
    # Constructed-IR completeness bits: nothing was translated — the carrier
    # is built directly in IR, so every region it carries is fully spelled by
    # construction. The renderers and the solver re-decide downstream,
    # fail-closed, exactly as for the predecessor overlays' spliced claims.
    composite.translationLossFree = true
    composite.bindingUniverseComplete = true
    composite.propositionRegionLossFree = true
    composite.lossOutsideBindingRegions = false
    # WP4-j.4 pattern: the completeness evidence artifact is keyed by the same
    # digest scheme the runner cache hashes (serializeIRFuncDef of the
    # delivered funcDef), so the pipeline's evidence lookup finds this carrier
    # the same way it finds materialized singles.
    let irDigest = computeDeterministicCasKey(serializeIRFuncDef(composite))
    let completenessEvidence = CompletenessEvidence(
      translationLossFree: composite.translationLossFree,
      bindingUniverseComplete: composite.bindingUniverseComplete,
      opaqueExpansionStatus: "none",
      sourceBindingCount: composite.params.len,
      irBindingCount: collectLetNames(composite.body).len + composite.params.len)
    saveEvidenceArtifact(irDigest, completenessEvidence)
    # Phase 1A dual-write: authenticated strict sibling at the same anchor
    # (fail-closed — an unmeasured capture keeps the legacy-only generation).
    discard saveCompletenessEvidenceDual(irDigest, composite,
      measureCompletenessSourceCapture(subjectRepoRoot, modulePath,
        moduleBytes), completenessEvidence)
    let symRef = SubjectSymbolRef(relativeModulePath: modulePath,
      functionName: carrierName)
    let entry = synthesizeExternalEntry(symRef, composite, moduleBytes)
    # §2.1a carrier binding (single origin, honest legs): the carrier name
    # never appears in the subject source, so name correspondence cannot
    # apply; the derivation digest folds the rule identity and the grounding
    # file:lines. The EA legs record the grounding symbol's REAL differential
    # outcome — EA_UNSUPPORTED on the subject's template — so the binding
    # never attests an extraction that did not happen.
    let derivationRule = "bv-slice-length-model-v1|rule=" & domain.ruleId &
      "|grounding=" & modulePath & ":" & groundingLines
    var parseBound = measureClaimCarrierParseBoundComponents(
      moduleBytes, groundingSymbol, derivationRule)
    # The replay binding (contract §4): the stamped harness observes the
    # ORIGINAL template through its defining module — the model value e
    # renders into the <lit> slot at replay time; the <module> slot is fixed
    # by the overlay pin here. The body comes from the CLOSED template
    # registry (VS-2 §1.5), resolved once per synthesis below.
    parseBound.replayHarnessTemplate =
      harnessTemplate.get.replace(ReplayModulePlaceholder, domain.importModule)
    ok(ExternalIrEntry(entry: entry, funcDef: composite, parseBound: parseBound))

  let defectRes = makeCarrier(BvSliceLenDefectCarrierName,
    domain.defectGroundingSymbol, domain.defectGroundingLines,
    domain.defectModel, domain.defectLaw)
  if defectRes.isErr:
    return err(defectRes.error)
  let controlRes = makeCarrier(BvSliceLenControlCarrierName,
    domain.controlGroundingSymbol, domain.controlGroundingLines,
    domain.controlModel, domain.controlLaw)
  if controlRes.isErr:
    return err(controlRes.error)
  let defect = defectRes.get
  let control = controlRes.get
  let defectRecord = classifyCandidateForCensus(defect.entry, defect.funcDef)
  census.records.add(defectRecord)
  let controlRecord = classifyCandidateForCensus(control.entry, control.funcDef)
  census.records.add(controlRecord)
  if defectRecord.censusEligible:
    # The eligible DEFECT entry is WAVE-FACING: the pipeline attributes
    # results to the node's bare function name, so RuntimeAxiomEntry.name is
    # the EXAMINED symbol — the disproof attributes to the frontier node whose
    # eligibility this synthesis decided. The claim identity stays the carrier
    # name everywhere else (census record, funcDef name, obligation ids). The
    # CONTROL carrier rides under its own name: its UNSAT is the differential's
    # spec-injection guard, verified through the same eligibility gate.
    var waveEntry = defect.entry
    waveEntry.name = examinedFn
    census.eligible.add(ExternalIrEntry(entry: waveEntry,
      funcDef: defect.funcDef, parseBound: defect.parseBound))
  if controlRecord.censusEligible:
    census.eligible.add(ExternalIrEntry(entry: control.entry,
      funcDef: control.funcDef, parseBound: control.parseBound))
  logInfo("axiom_engine", "nim-libp2p bytesview slice carriers synthesized: " &
    BvSliceLenDefectCarrierName & " (model " & $domain.defectModel & ") + " &
    BvSliceLenControlCarrierName & " (model " & $domain.controlModel & ")" &
    " domain=" & $domain.domainLower & "<=" & domain.domainVar &
    "<=" & $domain.domainBound &
    " obligations=" & $defectRecord.generatedObligationCount &
    "/" & $controlRecord.generatedObligationCount &
    " eligible=" & $defectRecord.censusEligible & "/" &
    $controlRecord.censusEligible &
    " source=" & modulePath)
  if not defectRecord.censusEligible:
    logInfo("axiom_engine", "nim-libp2p bytesview slice defect carrier excluded: " &
      " eligibility=" & $defectRecord.eligibility &
      " rejection=" & rejectionToken(defectRecord.rejection) &
      " source=" & modulePath)
  if not controlRecord.censusEligible:
    logInfo("axiom_engine", "nim-libp2p bytesview slice control carrier excluded: " &
      " eligibility=" & $controlRecord.eligibility &
      " rejection=" & rejectionToken(controlRecord.rejection) &
      " source=" & modulePath)
  ok(defectRecord.censusEligible)

proc synthesizeNimSidecarCandidates*(examinedFn, modulePath: string;
    resolver: ModuleContentResolver; domain: SidecarDomain;
    census: ExternalCandidateCensus; subjectRepoRoot: string = ""): Result[bool, string] {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D2/D3/D4 for the proposition sidecar
  ## (docs/spec/nim_stew_base36_sidecar_contract.md): one carrier per adopted
  ## proposition (defect + control) over the governed subject symbol, in the
  ## C_out attach pattern — the subject body is materialized UNCHANGED and
  ## each carrier CARRIES it as its own body; the proposition's post has its
  ## `result` slot β-spliced onto that body exactly once. Unlike the d2
  ## lane's constructed carriers, the model here IS the original function
  ## body: the solver decides the subject's own arithmetic directly, and the
  ## replay observes the same body through the subject's real symbol
  ## (`<symbol>(<carrier>, <valueLit>)` — the measured typedesc token).
  ##
  ## ok(true)  → the defect carrier is recorded and census-eligible;
  ## ok(false) → carriers recorded and excluded (honest census outcome);
  ## err       → no carriers could be produced, so the examined symbol falls
  ##             back to its own census record.
  # One carrier pair per subject symbol per run: a second gate hit (no
  # --target) must not duplicate either carrier.
  for kind in ["defect", "control"]:
    let carrierName = sidecarCarrierName(domain, kind)
    for existing in census.records:
      if existing.functionName == carrierName and
          existing.modulePath == modulePath:
        logInfo("axiom_engine",
          "sidecar carriers already recorded — dedupe skip: " &
          examinedFn & " in " & modulePath)
        return ok(false)
  let mat = materializeExternalIR(
    SubjectSymbolRef(relativeModulePath: modulePath, functionName: domain.symbol),
    resolver, subjectRepoRoot)
  if mat.outcome != moMaterialized:
    return err("sidecar symbol '" & domain.symbol & "' materialization: " &
      $mat.outcome)
  let fd = mat.entry.funcDef
  if fd.isRecursive:
    return err("sidecar scope: recursive subject body")
  if fd.recordedBindings.len > 0:
    return err("sidecar scope: subject body carries let-bindings outside the " &
      "pure-expression scope of this sidecar")
  # The value parameter the body actually references — the propositions bind
  # the subject's real parameter, never an invented name, and never a second
  # one.
  func referencedParam(f: IRFuncDef): Option[string] {.raises: [].} =
    let names = collectFreeNames(f.body, initHashSet[string]())
    var referenced: seq[string]
    for name in names:
      for p in f.params:
        if p.name == name and name notin referenced:
          referenced.add(name)
    if referenced.len == 1: some(referenced[0]) else: none(string)
  let target = referencedParam(fd)
  if target.isNone:
    return err("sidecar scope: subject body must reference exactly one value parameter")
  if target.get != domain.valueParam:
    return err("sidecar binding: the subject's value parameter is '" &
      target.get & "' but the sidecar's propositions declare '" &
      domain.valueParam & "' — the adoption does not bind this signature")
  var paramTy = irTypeBitVec64()
  for p in fd.params:
    if p.name == target.get: paramTy = p.ty
  # The closed grammar types every ident BV64 (its only type); retype the
  # value-param leaves to the subject's REAL parameter type before the
  # propositions enter a funcDef. Total over the grammar's node set; any
  # other node kind is outside what the parser can produce and yields nil
  # (checked fail-closed below).
  func retypeSidecarVar(e: IRExpr): IRExpr {.raises: [].} =
    case e.kind
    of irLit: e
    of irVar:
      (if e.varName == target.get: irVar(e.varName, paramTy) else: e)
    of irBinOp:
      irBinOp(e.binOp, retypeSidecarVar(e.binLhs), retypeSidecarVar(e.binRhs))
    else: nil
  var defectRecord: CandidateCensusRecord
  var controlRecord: CandidateCensusRecord
  var defectIrEntry = ExternalIrEntry(entry: RuntimeAxiomEntry(),
    funcDef: IRFuncDef(), parseBound: SubjectParseBoundComponents())
  var controlIrEntry = defectIrEntry
  for prop in domain.propositions:
    let carrierName = sidecarCarrierName(domain, prop.kind)
    let preIr = retypeSidecarVar(prop.pre)
    let postIr = retypeSidecarVar(prop.post)
    if preIr.isNil or postIr.isNil:
      return err("sidecar " & prop.kind & " proposition IR is outside the " &
        "closed grammar's node set (internal parse invariant broken)")
    var composite = fd
    composite.name = carrierName
    composite.body = fd.body
    # Carrier params = the MODEL's variables: exactly the one value parameter
    # the body references. The original signature's remaining formals (the
    # typedesc discriminator) are not value parameters — the solver cannot
    # bind them, and the replay's exact-input gate requires every formal to
    # carry a model binding, so a formal that stayed would demote every
    # replay fail-closed (measured 2026-10-19: `model does not bind parameter
    # 'btype'`). The dropped formal is not lost: the ORIGINAL signature stays
    # pinned by the adoption's subject blob, and the typedesc formal renders
    # in the replay call as the MEASURED carrier token
    # (`decodedLength(Base36Types, <lit>)` — measureClaimCarrierParseBound
    # Components). The d2 carriers carry exactly their one model variable on
    # the same principle.
    composite.params = @[IRFuncParam(name: target.get, ty: paramTy)]
    composite.preConditions = @[preIr]
    # THE ADOPTED PROPOSITION (docs/spec/nim_stew_base36_sidecar_contract.md):
    # <pre> -> <post[result := body]>. The result slot receives a β-spliced
    # clone of the ORIGINAL subject body — exactly one splice, fail-closed —
    # so the proposition's free variables are exactly the subject's value
    # parameter (the C_out composite's result-splice pattern).
    var rSplices = 0
    let claim = substituteParamUse(postIr, "result", fd.body, rSplices)
    if rSplices != 1:
      return err("β-splice: the " & prop.kind &
        " proposition's result slot did not splice exactly once (" &
        $rSplices & ")")
    # Fail-closed free-variable guard: the spliced proposition must reference
    # nothing beyond the subject's value parameter.
    var claimFree = initHashSet[string]()
    claimFree.incl(target.get)
    let unbound = collectFreeNames(claim, claimFree)
    if unbound.len > 0:
      return err("sidecar " & prop.kind &
        " proposition references unbound name(s): " & unbound.join(", "))
    composite.postConditions = @[claim]
    # The carried region IS the original body (materialized whole under the
    # pure-expression scope guard above); the proposition region is the
    # spliced body itself. The renderers and the solver re-decide the
    # completeness bits downstream, fail-closed — the carrier does not widen
    # the subject's own loss record (the C_out carrier's discipline).
    composite.translationLossFree = true
    composite.bindingUniverseComplete = fd.bindingUniverseComplete
    composite.propositionRegionLossFree = true
    composite.lossOutsideBindingRegions = fd.lossOutsideBindingRegions
    # WP4-j.4 pattern: the completeness evidence artifact is keyed by the
    # same digest scheme the runner cache hashes (serializeIRFuncDef of the
    # delivered funcDef), so the pipeline's evidence lookup finds this
    # carrier the same way it finds materialized singles.
    let irDigest = computeDeterministicCasKey(serializeIRFuncDef(composite))
    let completenessEvidence = CompletenessEvidence(
      translationLossFree: composite.translationLossFree,
      bindingUniverseComplete: composite.bindingUniverseComplete,
      opaqueExpansionStatus: "none",
      sourceBindingCount: composite.params.len,
      irBindingCount: collectLetNames(composite.body).len + composite.params.len)
    saveEvidenceArtifact(irDigest, completenessEvidence)
    # Phase 1A dual-write: authenticated strict sibling at the same anchor
    # (fail-closed — an unmeasured capture keeps the legacy-only generation).
    discard saveCompletenessEvidenceDual(irDigest, composite,
      measureCompletenessSourceCapture(subjectRepoRoot, modulePath,
        mat.entry.entry.sourceContent), completenessEvidence)
    let symRef = SubjectSymbolRef(relativeModulePath: modulePath,
      functionName: carrierName)
    var entry = synthesizeExternalEntry(symRef, composite,
      mat.entry.entry.sourceContent)
    # The sidecar DECLARES an obligation (pre AND post are present): the
    # no-obligation scope contract treats expectedObligation=true with zero
    # derived obligations as a scope mismatch (fail), never a silent no-op.
    entry.expectedObligation = true
    let record = classifyCandidateForCensus(entry, composite)
    census.records.add(record)
    # §2.1a single-origin claim-carrier measurement: ONE EA leg for the
    # overlay's original subject symbol plus the deterministic result-splice
    # derivation digest, plus the measured typedesc carrier token the S6
    # replay needs (`<symbol>(<carrier>, <valueLit>)`). The materializer's
    # own parseBound is measured FOR the subject symbol, which the seal
    # would reject under carrier-name correspondence — the carrier carries
    # its own single-origin measurement instead.
    let parseBound = measureClaimCarrierParseBoundComponents(
      mat.entry.entry.sourceContent, domain.symbol,
      SidecarGrammarV1 & "|rule=" & domain.ruleId & "|kind=" & prop.kind)
    let irEntry = ExternalIrEntry(entry: entry, funcDef: composite,
      parseBound: parseBound)
    if prop.kind == "defect":
      defectRecord = record
      defectIrEntry = irEntry
    else:
      controlRecord = record
      controlIrEntry = irEntry
  if defectRecord.censusEligible:
    # The eligible DEFECT entry is WAVE-FACING: the pipeline attributes
    # results to the node's bare function name, so RuntimeAxiomEntry.name is
    # the EXAMINED symbol. The claim identity stays the carrier name
    # everywhere else (census record, funcDef name, obligation ids). The
    # CONTROL carrier rides under its own name: its UNSAT is the
    # differential's injection guard, verified through the same eligibility
    # gate.
    var waveEntry = defectIrEntry.entry
    waveEntry.name = examinedFn
    census.eligible.add(ExternalIrEntry(entry: waveEntry,
      funcDef: defectIrEntry.funcDef, parseBound: defectIrEntry.parseBound))
  if controlRecord.censusEligible:
    census.eligible.add(controlIrEntry)
  logInfo("axiom_engine", "sidecar carriers synthesized (hash-bound adoption " &
    domain.adoption.adoptedSpecHash[0 ..< 12] & "…): " &
    sidecarCarrierName(domain, "defect") & " [" & domain.propositions[0].preText &
    " -> " & domain.propositions[0].postText & "] + " &
    sidecarCarrierName(domain, "control") & " [" & domain.propositions[1].preText &
    " -> " & domain.propositions[1].postText & "]" &
    " obligations=" & $defectRecord.generatedObligationCount &
    "/" & $controlRecord.generatedObligationCount &
    " eligible=" & $defectRecord.censusEligible & "/" &
    $controlRecord.censusEligible &
    " source=" & modulePath)
  if not defectRecord.censusEligible:
    logInfo("axiom_engine", "sidecar defect carrier excluded: " &
      " eligibility=" & $defectRecord.eligibility &
      " rejection=" & rejectionToken(defectRecord.rejection) &
      " source=" & modulePath)
  if not controlRecord.censusEligible:
    logInfo("axiom_engine", "sidecar control carrier excluded: " &
      " eligibility=" & $controlRecord.eligibility &
      " rejection=" & rejectionToken(controlRecord.rejection) &
      " source=" & modulePath)
  ok(defectRecord.censusEligible)

proc synthesizeBase36RelationalCandidate*(examinedFn, modulePath: string;
    resolver: ModuleContentResolver; domain: Base36OverlayDomain;
    census: ExternalCandidateCensus; subjectRepoRoot: string = ""): Result[bool, string] {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D2/D3/D4: one relational candidate per overlay subject —
  ## `<outer>(<inner>(n))` as a single IRFuncDef whose body is the
  ## β-composition of the two materialized bodies, whose preconditions are
  ## the overlay domain as real IRExpr, and whose census record replaces the
  ## single-symbol records (the claim is about the pair; each single symbol
  ## stays excluded by the constant-divisor rule on its own).
  ##
  ## ok(true)  → composite recorded and census-eligible (the gate may pass);
  ## ok(false) → composite recorded and excluded (honest census outcome);
  ## err       → no composite could be produced, so the caller falls back to
  ##             the examined symbol's own census path.
  ##
  ## Scope guards are fail-closed: let-bindings or recursion in a subject
  ## body are outside this overlay's pure-expression scope, and the census —
  ## not this proc — decides eligibility of whatever composite IS produced.
  # One composite per subject module per run: when both overlay symbols flow
  # through the gate (no --target), the second hit must not duplicate the
  # candidate — it is already recorded, so the node is excluded.
  for existing in census.records:
    if existing.functionName == Base36SizingCompositeName and
        existing.modulePath == modulePath:
      logInfo("axiom_engine",
        "base36 overlay composite already recorded — dedupe skip: " &
        examinedFn & " in " & modulePath)
      return ok(false)
  let outerMat = materializeExternalIR(
    SubjectSymbolRef(relativeModulePath: modulePath, functionName: domain.outerSymbol),
    resolver, subjectRepoRoot)
  if outerMat.outcome != moMaterialized:
    return err("overlay symbol '" & domain.outerSymbol & "' materialization: " &
      $outerMat.outcome)
  let innerMat = materializeExternalIR(
    SubjectSymbolRef(relativeModulePath: modulePath, functionName: domain.innerSymbol),
    resolver, subjectRepoRoot)
  if innerMat.outcome != moMaterialized:
    return err("overlay symbol '" & domain.innerSymbol & "' materialization: " &
      $innerMat.outcome)
  let outerFd = outerMat.entry.funcDef
  let innerFd = innerMat.entry.funcDef
  if outerFd.recordedBindings.len > 0 or innerFd.recordedBindings.len > 0:
    return err("overlay scope: subject bodies carry let-bindings outside the " &
      "pure-expression scope of this overlay")
  if outerFd.isRecursive or innerFd.isRecursive:
    return err("overlay scope: recursive subject body")
  # The value parameter is the one the body actually references; the typedesc
  # carrier never appears as an irVar. Exactly one such parameter is required.
  func referencedParam(fd: IRFuncDef): Option[string] =
    let names = collectFreeNames(fd.body, initHashSet[string]())
    var referenced: seq[string]
    for name in names:
      for p in fd.params:
        if p.name == name and name notin referenced:
          referenced.add(name)
    if referenced.len == 1: some(referenced[0]) else: none(string)
  let outerTarget = referencedParam(outerFd)
  let innerTarget = referencedParam(innerFd)
  if outerTarget.isNone or innerTarget.isNone:
    return err("overlay scope: each subject body must reference exactly one " &
      "value parameter (outer: " & $outerTarget.isSome & ", inner: " &
      $innerTarget.isSome & ")")
  var outerParamNames: HashSet[string]
  for p in outerFd.params: outerParamNames.incl(p.name)
  if innerTarget.get notin outerParamNames:
    return err("composite binding: inner value parameter '" & innerTarget.get &
      "' is not bound by the composite parameter list")
  var splices = 0
  let compositeBody = substituteParamUse(outerFd.body, outerTarget.get,
    innerFd.body, splices)
  if splices == 0:
    return err("β-substitution: outer body never references its value parameter")
  var compositeParams: HashSet[string]
  for p in outerFd.params: compositeParams.incl(p.name)
  let unbound = collectFreeNames(compositeBody, compositeParams)
  if unbound.len > 0:
    return err("composite body references unbound name(s): " & unbound.join(", "))
  var paramTy = irTypeBitVec64()
  for p in outerFd.params:
    if p.name == outerTarget.get: paramTy = p.ty
  var composite = outerFd
  composite.name = Base36SizingCompositeName
  composite.body = compositeBody
  composite.preConditions = @[
    irGe(irVar(outerTarget.get, paramTy), irLit(domain.domainLower)),
    irLe(irVar(outerTarget.get, paramTy), irLit(domain.domainBound))]
  # (d) The postcondition is stated result-free: the `result` slot receives a
  # β-spliced clone of the composite body (substituteParamUse), so the
  # proposition's free variables are exactly the value parameter — inside
  # the rule-S closure — and no unresolved `result` fact is minted. The
  # conjunctive form carries the roundtrip equality plus the two overflow
  # goals the kernel discharges from the domain hypotheses (mirroring the
  # SMT-side goal shape and Denotation.lean:384-416).
  var rSplices = 0
  let roundtripEq = substituteParamUse(
    irEq(irVar("result", composite.retType), irVar(outerTarget.get, paramTy)),
    "result", compositeBody, rSplices)
  var oSplices = 0
  let overflowDec = substituteParamUse(
    irLe(irBinOp(boMul, irVar("result", composite.retType), irLit(179)),
      irLit(9223372036854775807'i64)),
    "result", compositeBody, oSplices)
  let overflowEnc = irLe(
    irBinOp(boMul, irVar(outerTarget.get, paramTy), irLit(277)),
    irLit(9223372036854775807'i64))
  if rSplices != 1 or oSplices != 1:
    return err("β-splice: postcondition result slots did not splice exactly " &
      "once (roundtrip=" & $rSplices & ", overflow=" & $oSplices & ")")
  composite.postConditions = @[
    irAnd(irAnd(roundtripEq, overflowEnc), overflowDec)]
  # The composite claims exactly the conjunction of the two source
  # certifications: both bodies translated loss-free (the parenthesized
  # subexpressions included) and both binding universes inventory-verified.
  # Pure substitution introduces no guard and no statement form, so the
  # proposition region stays loss-free exactly when both sources are.
  composite.translationLossFree =
    outerFd.translationLossFree and innerFd.translationLossFree
  composite.bindingUniverseComplete =
    outerFd.bindingUniverseComplete and innerFd.bindingUniverseComplete
  composite.propositionRegionLossFree =
    outerFd.propositionRegionLossFree and innerFd.propositionRegionLossFree
  composite.lossOutsideBindingRegions =
    outerFd.lossOutsideBindingRegions or innerFd.lossOutsideBindingRegions
  # WP4-j.4: the completeness evidence artifact is keyed by the same digest
  # scheme the runner cache hashes (serializeIRFuncDef of the delivered
  # funcDef), so the pipeline's evidence lookup finds this composite the same
  # way it finds materialized singles.
  let irDigest = computeDeterministicCasKey(serializeIRFuncDef(composite))
  let completenessEvidence = CompletenessEvidence(
    translationLossFree: composite.translationLossFree,
    bindingUniverseComplete: composite.bindingUniverseComplete,
    opaqueExpansionStatus: "none",
    sourceBindingCount: composite.params.len,
    irBindingCount: collectLetNames(compositeBody).len + composite.params.len)
  saveEvidenceArtifact(irDigest, completenessEvidence)
  # Phase 1A dual-write: authenticated strict sibling at the same anchor
  # (fail-closed — an unmeasured capture keeps the legacy-only generation).
  discard saveCompletenessEvidenceDual(irDigest, composite,
    measureCompletenessSourceCapture(subjectRepoRoot, modulePath,
      outerMat.entry.entry.sourceContent), completenessEvidence)
  let symRef = SubjectSymbolRef(relativeModulePath: modulePath,
    functionName: Base36SizingCompositeName)
  let entry = synthesizeExternalEntry(symRef, composite,
    outerMat.entry.entry.sourceContent)
  # §2.1a-1: the extraction agreement is measured per ORIGINAL symbol against
  # the real subject bytes — the composite name never appears in the subject
  # source, so the single-symbol differential cannot apply to it. The carried
  # components hold BOTH originals' fail-closed EA legs plus the recorded
  # β-splice derivation digest; the canonical binding site enforces that both
  # legs agree before any seal (no EA-free composite seal exists).
  let compositeParseBound = measureCompositeParseBoundComponents(
    outerMat.entry.entry.sourceContent, domain.outerSymbol, domain.innerSymbol)
  let record = classifyCandidateForCensus(entry, composite)
  census.records.add(record)
  if record.censusEligible:
    # The eligible entry is WAVE-FACING: loop_driver stage2 attributes IR
    # pipeline results to nodes by the node's bare function name, so the
    # entry's RuntimeAxiomEntry.name must be the EXAMINED symbol whose
    # eligibility this composite decides. The claim identity stays the
    # composite everywhere else: census record name (dedupe + selection),
    # funcDef name (def/theorem/obligation ids), and the sealed
    # CanonicalLeanEvidence obligationId (both EA legs + β-splice derivation
    # + composite IR digest).
    var waveEntry = entry
    waveEntry.name = examinedFn
    census.eligible.add(ExternalIrEntry(entry: waveEntry, funcDef: composite,
      parseBound: compositeParseBound))
    logInfo("axiom_engine", "base36 overlay composite candidate accepted: " &
      Base36SizingCompositeName &
      " composition=" & domain.outerSymbol & "(" & domain.innerSymbol & "(" &
      domain.domainVar & "))" &
      " bound=" & $domain.domainBound &
      " obligations=" & $record.generatedObligationCount &
      " nonTrivial=" & $record.nonTrivialObligationCount &
      " source=" & modulePath)
    return ok(true)
  logInfo("axiom_engine", "base36 overlay composite candidate excluded: " &
    Base36SizingCompositeName &
    " eligibility=" & $record.eligibility &
    " rejection=" & rejectionToken(record.rejection) &
    " obligations=" & $record.generatedObligationCount &
    " nonTrivial=" & $record.nonTrivialObligationCount &
    " source=" & modulePath)
  ok(false)

proc synthesizeBase32RemRangeCandidate*(examinedFn, modulePath: string;
    resolver: ModuleContentResolver; domain: Base32RemOverlayDomain;
    census: ExternalCandidateCensus; subjectRepoRoot: string = ""): Result[bool, string] {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D2/D3/D4 for the rem overlay: one remainder-range candidate over the
  ## subject symbol. The subject body is materialized UNCHANGED and the
  ## relational claim is bound onto the body's OWN `<param> mod <divisor>`
  ## term — the term comes from the subject source, never re-modeled by the
  ## overlay (the claim names what the subject computes).
  ##
  ## ok(true)  → candidate recorded and census-eligible (the gate may pass);
  ## ok(false) → candidate recorded and excluded (honest census outcome);
  ## err       → no candidate could be produced, so the examined symbol falls
  ##             back to its own census record.
  # One candidate per subject module per run: when the gate hits the governed
  # symbol twice (no --target), the second hit must not duplicate it.
  for existing in census.records:
    if existing.functionName == Base32RemCandidateName and
        existing.modulePath == modulePath:
      logInfo("axiom_engine",
        "base32 rem overlay candidate already recorded — dedupe skip: " &
        examinedFn & " in " & modulePath)
      return ok(false)
  let mat = materializeExternalIR(
    SubjectSymbolRef(relativeModulePath: modulePath, functionName: domain.symbol),
    resolver, subjectRepoRoot)
  if mat.outcome != moMaterialized:
    return err("overlay symbol '" & domain.symbol & "' materialization: " &
      $mat.outcome)
  let fd = mat.entry.funcDef
  if fd.isRecursive:
    return err("overlay scope: recursive subject body")
  # The value parameter the body actually references — the claim binds onto a
  # term over the subject's real parameter, never over an invented name.
  func referencedParam(f: IRFuncDef): Option[string] =
    let names = collectFreeNames(f.body, initHashSet[string]())
    var referenced: seq[string]
    for name in names:
      for p in f.params:
        if p.name == name and name notin referenced:
          referenced.add(name)
    if referenced.len == 1: some(referenced[0]) else: none(string)
  let target = referencedParam(fd)
  if target.isNone:
    return err("overlay scope: subject body must reference exactly one value parameter")
  var paramTy = irTypeBitVec64()
  for p in fd.params:
    if p.name == target.get: paramTy = p.ty
  # Locate the subject's own `<param> mod <divisor>` term in the materialized
  # body (first match, deterministic walk). Let-bindings do NOT disqualify the
  # subject here — unlike the β-splice overlay, no binding is moved or
  # rewritten; the matched term's free-variable set is checked directly.
  func findRemTerm(e: IRExpr): IRExpr {.raises: [].} =
    ## First `<target> mod <divisor>` term in a deterministic pre-order walk;
    ## nil when the body carries none.
    if e == nil: return nil
    if e.kind == irBinOp and e.binOp == boRem and
        e.binLhs != nil and e.binLhs.kind == irVar and
        e.binLhs.varName == target.get and
        e.binRhs != nil and e.binRhs.kind == irLit and
        e.binRhs.litVal == domain.divisor:
      return e
    case e.kind
    of irLet:
      result = findRemTerm(e.letVal)
      if result == nil: result = findRemTerm(e.letBody)
    of irIf:
      result = findRemTerm(e.ifCond)
      if result == nil: result = findRemTerm(e.ifThen)
      if result == nil: result = findRemTerm(e.ifElse)
    of irCase:
      result = findRemTerm(e.caseScrutinee)
      if result == nil:
        for br in e.caseBranches:
          result = findRemTerm(br.body)
          if result != nil: break
      if result == nil: result = findRemTerm(e.caseDefault)
    of irCall:
      result = nil
      for a in e.callArgs:
        result = findRemTerm(a)
        if result != nil: break
    of irBinOp:
      result = findRemTerm(e.binLhs)
      if result == nil: result = findRemTerm(e.binRhs)
    of irUnaryOp:
      result = findRemTerm(e.unaryArg)
    of irRecCall:
      result = nil
      for a in e.recArgs:
        result = findRemTerm(a)
        if result != nil: break
    of irLoop:
      result = nil
      for i in e.loopInits:
        result = findRemTerm(i)
        if result != nil: break
      if result == nil: result = findRemTerm(e.loopCond)
      if result == nil: result = findRemTerm(e.loopStep)
      if result == nil: result = findRemTerm(e.loopBody)
      if result == nil:
        for inv in e.loopInvariants:
          result = findRemTerm(inv)
          if result != nil: break
      if result == nil: result = findRemTerm(e.loopVariant)
    of irCast:
      result = findRemTerm(e.castExpr)
    of irLit, irFloatLit, irStringLit, irVar:
      result = nil
  let remTerm = findRemTerm(fd.body)
  if remTerm == nil:
    return err("overlay claim binding: the subject body contains no " &
      "<param> mod " & $domain.divisor & " term to bind the range claim onto")
  # Fail-closed shadowing guard: the matched term must be a pure term over the
  # subject parameter alone — any other free name (or a shadowed reading of it)
  # would state the claim about a different meaning.
  let remFree = collectFreeNames(remTerm, initHashSet[string]())
  if remFree.len != 1 or remFree[0] != target.get:
    return err("overlay claim binding: the matched mod term is not a pure " &
      "term over the subject parameter (free names: " & remFree.join(", ") & ")")
  # THE RELATIONAL CLAIM (docs/spec/nim_stew_base32_rem_binding_contract.md):
  #   0 <= length  ->  0 <= length mod <d>  AND  length mod <d> <= <d-1>
  #   (decodedLength: d = 8, stew/base32.nim:80)
  # Each conjunct splices a fresh structural clone of the subject's own term,
  # so the proposition's free variables are exactly the subject parameter. On
  # this nonnegative-dividend domain Nim's truncated mod and Lean's emod
  # coincide (Int.tmod_eq_emod_of_nonneg) — the coincidence is part of the
  # verified proposition as the discharged hypothesis, never prose.
  let claim = irAnd(
    irGe(cloneIRExpr(remTerm), irLit(0)),
    irLe(cloneIRExpr(remTerm), irLit(domain.divisor - 1)))
  var composite = fd
  composite.name = Base32RemCandidateName
  # The claim CARRIER's body is the spliced subject term itself — the exact
  # `<param> mod <divisor>` term the claim quantifies over (same composite
  # pattern as the base36 sizing overlay, whose carrier body is the β-spliced
  # composition of subject terms). The subject's FULL body is deliberately NOT
  # carried: its materialization collapses the `when btype is ...` result
  # selection into a loss-marked placeholder (translationLossFree=false), and
  # the canonical Int renderer is fail-closed on let-bound bodies — a carrier
  # holding that body would never reach the kernel (it would fall through to
  # the BitVec pipeline instead). The claim is result-free: the theorem never
  # references the carrier body, so the carrier holds only the term the claim
  # is about. No re-modeling: the term is a structural clone of the one
  # matched in the materialized subject body above.
  composite.body = cloneIRExpr(remTerm)
  composite.preConditions = @[irGe(irVar(target.get, paramTy), irLit(0))]
  composite.postConditions = @[claim]
  composite.translationLossFree = true
  composite.bindingUniverseComplete = fd.bindingUniverseComplete
  # The claim's proposition region is the spliced mod term — its completeness
  # is NOT inherited from the subject's loss channel. That channel records loss
  # in the subject's when/if result-selection branches; the claim region is
  # reconstructed by this synthesis and its completeness is decided downstream,
  # fail-closed, by the renderers that must spell it (lowerIRExprToLean,
  # lowerPostconditionToLean) and by the solver/kernel that must decide it.
  # Carrying the subject's false loss bit here would silently demote a
  # claim whose own region is fully spelled to an ineligible census record —
  # the honest measure is the region the claim actually occupies.
  composite.propositionRegionLossFree = true
  composite.lossOutsideBindingRegions = fd.lossOutsideBindingRegions
  # WP4-j.4 pattern: the completeness evidence artifact is keyed by the same
  # digest scheme the runner cache hashes (serializeIRFuncDef of the delivered
  # funcDef), so the pipeline's evidence lookup finds this composite the same
  # way it finds materialized singles.
  let irDigest = computeDeterministicCasKey(serializeIRFuncDef(composite))
  let completenessEvidence = CompletenessEvidence(
    translationLossFree: composite.translationLossFree,
    bindingUniverseComplete: composite.bindingUniverseComplete,
    opaqueExpansionStatus: "none",
    sourceBindingCount: composite.params.len,
    irBindingCount: collectLetNames(composite.body).len + composite.params.len)
  saveEvidenceArtifact(irDigest, completenessEvidence)
  # Phase 1A dual-write: authenticated strict sibling at the same anchor
  # (fail-closed — an unmeasured capture keeps the legacy-only generation).
  discard saveCompletenessEvidenceDual(irDigest, composite,
    measureCompletenessSourceCapture(subjectRepoRoot, modulePath,
      mat.entry.entry.sourceContent), completenessEvidence)
  let symRef = SubjectSymbolRef(relativeModulePath: modulePath,
    functionName: Base32RemCandidateName)
  let entry = synthesizeExternalEntry(symRef, composite,
    mat.entry.entry.sourceContent)
  let record = classifyCandidateForCensus(entry, composite)
  census.records.add(record)
  if record.censusEligible:
    # The eligible entry is WAVE-FACING: the pipeline attributes results to the
    # node's bare function name, so RuntimeAxiomEntry.name is the EXAMINED
    # symbol. The claim identity stays the overlay candidate name everywhere
    # else: census record, funcDef name, obligation ids.
    #
    # §2.1a claim-carrier measurement (main thread, same site as the base36
    # composite's two-leg measurement): ONE EA leg for the overlay's original
    # subject symbol plus the deterministic term-splice derivation digest.
    # The materializer's own parseBound is measured FOR the subject symbol,
    # which the seal would reject under carrier-name correspondence — the
    # carrier carries its own single-origin measurement instead.
    let carrierParseBound = measureClaimCarrierParseBoundComponents(
      mat.entry.entry.sourceContent, domain.symbol,
      "term-splice-v1|rule=" & domain.ruleId)
    var waveEntry = entry
    waveEntry.name = examinedFn
    census.eligible.add(ExternalIrEntry(entry: waveEntry, funcDef: composite,
      parseBound: carrierParseBound))
    logInfo("axiom_engine", "base32 rem overlay candidate accepted: " &
      Base32RemCandidateName &
      " dividend=" & domain.dividendVar &
      " mod=" & $domain.divisor &
      " claim=0<=" & domain.dividendVar & " mod " & $domain.divisor &
      " and " & domain.dividendVar & " mod " & $domain.divisor &
      " <= " & $(domain.divisor - 1) &
      " obligations=" & $record.generatedObligationCount &
      " nonTrivial=" & $record.nonTrivialObligationCount &
      " source=" & modulePath)
    return ok(true)
  logInfo("axiom_engine", "base32 rem overlay candidate excluded: " &
    Base32RemCandidateName &
    " eligibility=" & $record.eligibility &
    " rejection=" & rejectionToken(record.rejection) &
    " obligations=" & $record.generatedObligationCount &
    " nonTrivial=" & $record.nonTrivialObligationCount &
    " source=" & modulePath)
  ok(false)

proc synthesizeBase36CoutCandidate*(examinedFn, modulePath: string;
    resolver: ModuleContentResolver; domain: Base36CoutOverlayDomain;
    census: ExternalCandidateCensus; subjectRepoRoot: string = ""): Result[bool, string] {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## D2/D3/D4 for the C_out overlay (docs/spec/nim_stew_base36_cout_contract.md):
  ## one out-sizing candidate over the subject symbol. The subject body is
  ## materialized UNCHANGED and the carrier carries it as its own body; the
  ## claim binds the subject's result — β-spliced to a fresh clone of that
  ## body, exactly once — against the overlay's pinned K (an external
  ## observation pinned as a claim constant; contract §3). The obligation
  ## stays OPEN over the value parameter: preconditions are the literal
  ## domain pin (low <= L and L <= high), so the SAT model binds L and the
  ## exact-input gate and P4 pre-revalidation can fire (contract §2 — 닫힌
  ## 명제 금지).
  ##
  ## ok(true)  → candidate recorded and census-eligible (the gate may pass);
  ## ok(false) → candidate recorded and excluded (honest census outcome);
  ## err       → no candidate could be produced, so the examined symbol falls
  ##             back to its own census record.
  # One candidate per subject module per run: when the gate hits the governed
  # symbol twice (no --target), the second hit must not duplicate it.
  for existing in census.records:
    if existing.functionName == Base36CoutCandidateName and
        existing.modulePath == modulePath:
      logInfo("axiom_engine",
        "base36 C_out overlay candidate already recorded — dedupe skip: " &
        examinedFn & " in " & modulePath)
      return ok(false)
  let mat = materializeExternalIR(
    SubjectSymbolRef(relativeModulePath: modulePath, functionName: domain.symbol),
    resolver, subjectRepoRoot)
  if mat.outcome != moMaterialized:
    return err("overlay symbol '" & domain.symbol & "' materialization: " &
      $mat.outcome)
  let fd = mat.entry.funcDef
  if fd.isRecursive:
    return err("overlay scope: recursive subject body")
  if fd.recordedBindings.len > 0:
    return err("overlay scope: subject body carries let-bindings outside the " &
      "pure-expression scope of this overlay")
  # The value parameter the body actually references — the claim binds onto the
  # subject's real parameter, never over an invented name.
  func referencedParam(f: IRFuncDef): Option[string] {.raises: [].} =
    let names = collectFreeNames(f.body, initHashSet[string]())
    var referenced: seq[string]
    for name in names:
      for p in f.params:
        if p.name == name and name notin referenced:
          referenced.add(name)
    if referenced.len == 1: some(referenced[0]) else: none(string)
  let target = referencedParam(fd)
  if target.isNone:
    return err("overlay scope: subject body must reference exactly one value parameter")
  var paramTy = irTypeBitVec64()
  for p in fd.params:
    if p.name == target.get: paramTy = p.ty
  var composite = fd
  composite.name = Base36CoutCandidateName
  composite.body = fd.body
  # THE OUT-SIZING CLAIM (docs/spec/nim_stew_base36_cout_contract.md):
  #   <low> <= L  and  L <= <high>  ->  decodedLength(L) >= <K>
  #   (decodedLength: (L*179) div 277, stew/base36.nim:60; K = 2 is the
  #   externally observed output length of the decision vector input, pinned
  #   as a claim constant — the engine carries the overlay's K, never a
  #   re-derived or hardcoded one). The result slot receives a β-spliced clone
  #   of the subject body — exactly one splice, fail-closed — so the
  #   proposition's free variables are exactly the subject parameter (the
  #   base36 composite's result-splice pattern). The claim is stated over the
  #   body the subject actually computes; nothing is re-modeled.
  composite.preConditions = @[
    irGe(irVar(target.get, paramTy), irLit(domain.domainLower)),
    irLe(irVar(target.get, paramTy), irLit(domain.domainBound))]
  var rSplices = 0
  let claim = substituteParamUse(
    irGe(irVar("result", composite.retType), irLit(domain.claimConstant)),
    "result", fd.body, rSplices)
  if rSplices != 1:
    return err("β-splice: the claim's result slot did not splice exactly once (" &
      $rSplices & ")")
  # Fail-closed free-variable guard: the spliced proposition must reference
  # nothing beyond the subject parameter.
  var claimFree = initHashSet[string]()
  claimFree.incl(target.get)
  let unbound = collectFreeNames(claim, claimFree)
  if unbound.len > 0:
    return err("claim references unbound name(s): " & unbound.join(", "))
  composite.postConditions = @[claim]
  # The claim's region is the β-spliced subject body — a pure expression the
  # materializer carried whole (no let, no when). Its completeness is decided
  # downstream, fail-closed, by the renderers that must spell it and by the
  # solver/kernel that must decide it — the carrier does not widen the subject's
  # own loss record into a claim about a region it reconstructed.
  composite.translationLossFree = true
  composite.bindingUniverseComplete = fd.bindingUniverseComplete
  composite.propositionRegionLossFree = true
  composite.lossOutsideBindingRegions = fd.lossOutsideBindingRegions
  # WP4-j.4 pattern: the completeness evidence artifact is keyed by the same
  # digest scheme the runner cache hashes (serializeIRFuncDef of the delivered
  # funcDef), so the pipeline's evidence lookup finds this candidate the same
  # way it finds materialized singles.
  let irDigest = computeDeterministicCasKey(serializeIRFuncDef(composite))
  let completenessEvidence = CompletenessEvidence(
    translationLossFree: composite.translationLossFree,
    bindingUniverseComplete: composite.bindingUniverseComplete,
    opaqueExpansionStatus: "none",
    sourceBindingCount: composite.params.len,
    irBindingCount: collectLetNames(composite.body).len + composite.params.len)
  saveEvidenceArtifact(irDigest, completenessEvidence)
  # Phase 1A dual-write: authenticated strict sibling at the same anchor
  # (fail-closed — an unmeasured capture keeps the legacy-only generation).
  discard saveCompletenessEvidenceDual(irDigest, composite,
    measureCompletenessSourceCapture(subjectRepoRoot, modulePath,
      mat.entry.entry.sourceContent), completenessEvidence)
  let symRef = SubjectSymbolRef(relativeModulePath: modulePath,
    functionName: Base36CoutCandidateName)
  let entry = synthesizeExternalEntry(symRef, composite,
    mat.entry.entry.sourceContent)
  let record = classifyCandidateForCensus(entry, composite)
  census.records.add(record)
  if record.censusEligible:
    # The eligible entry is WAVE-FACING: the pipeline attributes results to the
    # node's bare function name, so RuntimeAxiomEntry.name is the EXAMINED
    # symbol. The claim identity stays the overlay candidate name everywhere
    # else: census record, funcDef name, obligation ids.
    #
    # §2.1a claim-carrier measurement (main thread, same site as the base32 rem
    # carrier's single-leg measurement): ONE EA leg for the overlay's original
    # subject symbol plus the deterministic result-splice derivation digest.
    # The materializer's own parseBound is measured FOR the subject symbol,
    # which the seal would reject under carrier-name correspondence — the
    # carrier carries its own single-origin measurement instead.
    let carrierParseBound = measureClaimCarrierParseBoundComponents(
      mat.entry.entry.sourceContent, domain.symbol,
      "result-splice-v1|rule=" & domain.ruleId)
    var waveEntry = entry
    waveEntry.name = examinedFn
    census.eligible.add(ExternalIrEntry(entry: waveEntry, funcDef: composite,
      parseBound: carrierParseBound))
    logInfo("axiom_engine", "base36 C_out overlay candidate accepted: " &
      Base36CoutCandidateName &
      " subject=" & domain.symbol &
      " domain=" & $domain.domainLower & "<=" & domain.domainVar &
      "<=" & $domain.domainBound &
      " claim=" & domain.symbol & "(" & domain.domainVar & ") >= " &
      $domain.claimConstant &
      " decisionInput=" & domain.decisionInput &
      " obligations=" & $record.generatedObligationCount &
      " nonTrivial=" & $record.nonTrivialObligationCount &
      " source=" & modulePath)
    return ok(true)
  logInfo("axiom_engine", "base36 C_out overlay candidate excluded: " &
    Base36CoutCandidateName &
    " eligibility=" & $record.eligibility &
    " rejection=" & rejectionToken(record.rejection) &
    " obligations=" & $record.generatedObligationCount &
    " nonTrivial=" & $record.nonTrivialObligationCount &
    " source=" & modulePath)
  ok(false)

proc classifyExternalCandidate(fnName, modulePath: string; resolver: ModuleContentResolver;
                              census: ExternalCandidateCensus;
                              subjectRepoRoot: string = ""): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Registry-miss branch: materialize the symbol from subject source through the
  ## subject-scoped resolver (OWNS subjectRoot; resolves location, never CWD —
  ## WP4-a B-5b) and census-classify it. Records the outcome either way.
  let (outcome, entry) = materializeExternalIR(
    SubjectSymbolRef(relativeModulePath: modulePath, functionName: fnName), resolver, subjectRepoRoot)
  if outcome == moMaterialized:
    # Census classification = base eligibility + the constant-divisor rule.
    # A candidate excluded here never reaches `eligible`, so the census
    # terminal and the solver invocation count cannot disagree.
    let record = classifyCandidateForCensus(entry.entry, entry.funcDef)
    census.records.add(record)
    if record.censusEligible:
      census.eligible.add(entry)
      return true
    logInfo("axiom_engine", "external candidate excluded: " & fnName &
      " eligibility=" & $record.eligibility &
      " rejection=" & rejectionToken(record.rejection) &
      " obligations=" & $record.generatedObligationCount &
      " nonTrivial=" & $record.nonTrivialObligationCount &
      " source=" & modulePath)
    return false
  elif outcome == moNotFound:
    logInfo("axiom_engine", "external candidate not found: " & fnName & " in " & modulePath)
  elif outcome == moAmbiguousOverload:
    logInfo("axiom_engine", "external candidate ambiguous overload: " & fnName & " in " & modulePath)
  elif outcome == moParseFailure:
    logInfo("axiom_engine", "external candidate parse failure: " & fnName & " in " & modulePath)
  elif outcome == moUnsupportedDeclKind:
    # An existing symbol must never be reported as absent, so a declaration
    # that was found but has no IR translation gets a reason on the same
    # footing as the sibling outcomes above — silent here would make the
    # census undercount without any trace.
    logInfo("axiom_engine", "external candidate unsupported decl kind: " & fnName &
      " in " & modulePath & " reason=" & entry.unsupportedReason)
  false

type
  WaveRename* = enum
    wrSole        ## sizing/rem/cout: the single eligible entry rides the
                  ## examined symbol's name
    wrDefectOnly  ## the DEFECT member of a differential pair (d2/sidecar/bv):
                  ## it rides examinedFn; the CONTROL member is published
                  ## separately under its own carrier name (wrOwnName)
    wrOwnName     ## the CONTROL member rides its own carrier name — the
                  ## differential's injection guard must stay addressable
                  ## under the carrier name

proc publishExternalCandidate*(census: var ExternalCandidateCensus;
    candidateName, examinedFn, modulePath, subjectRepoRoot, sourceContent: string;
    composite: IRFuncDef; parseBound: SubjectParseBoundComponents;
    waveRename: WaveRename; declareObligation: bool = false): Result[bool, string] {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The deduped tail of all six external-subject synthesizers, in the exact
  ## current order (VS-2 REGISTRY_SPEC §2.2):
  ##   1. irDigest = computeDeterministicCasKey(serializeIRFuncDef(composite))
  ##   2. CompletenessEvidence (sourceBindingCount = params, irBindingCount =
  ##      collectLetNames(body) + params)
  ##   3. saveEvidenceArtifact(irDigest, ev)
  ##   4. discard saveCompletenessEvidenceDual(irDigest, composite,
  ##        measureCompletenessSourceCapture(subjectRepoRoot, modulePath,
  ##        sourceContent), ev)
  ##   5. record = classifyCandidateForCensus(entry, composite);
  ##      census.records.add(record)
  ##   6. wave-facing rename per `waveRename`; census.eligible.add(...)
  ##   7. accepted/excluded log line (the generic tail fields in the lanes'
  ##      field order; the lane-specific prefix stays adapter-owned at flip
  ##      time)
  ##   8. return ok(record.censusEligible)
  ##
  ## Dedupe is NOT here — it is adapter-owned: each lane's dedupe key and
  ## its ok(false)-on-duplicate semantics are capability-specific today and
  ## must not drift. PR-0 (VS-2 coexistence): this core exists and is
  ## exercised by the P0-1 fixture test; the six lanes are NOT rewired onto
  ## it until their flip PRs. `declareObligation` extends the spec
  ## signature for the sidecar payload's expectedObligation=true contract.
  let irDigest = computeDeterministicCasKey(serializeIRFuncDef(composite))
  let completenessEvidence = CompletenessEvidence(
    translationLossFree: composite.translationLossFree,
    bindingUniverseComplete: composite.bindingUniverseComplete,
    opaqueExpansionStatus: "none",
    sourceBindingCount: composite.params.len,
    irBindingCount: collectLetNames(composite.body).len + composite.params.len)
  saveEvidenceArtifact(irDigest, completenessEvidence)
  # Phase 1A dual-write: authenticated strict sibling at the same anchor
  # (fail-closed — an unmeasured capture keeps the legacy-only generation).
  discard saveCompletenessEvidenceDual(irDigest, composite,
    measureCompletenessSourceCapture(subjectRepoRoot, modulePath, sourceContent),
    completenessEvidence)
  let symRef = SubjectSymbolRef(relativeModulePath: modulePath,
    functionName: candidateName)
  var entry = synthesizeExternalEntry(symRef, composite, sourceContent)
  if declareObligation:
    # The sidecar DECLARES an obligation (pre AND post are present): the
    # no-obligation scope contract treats expectedObligation=true with zero
    # derived obligations as a scope mismatch (fail), never a silent no-op.
    entry.expectedObligation = true
  let record = classifyCandidateForCensus(entry, composite)
  census.records.add(record)
  if record.censusEligible:
    # The eligible entry is WAVE-FACING: the pipeline attributes results to
    # the node's bare function name, so RuntimeAxiomEntry.name is the
    # EXAMINED symbol — except the CONTROL member of a differential pair
    # (wrOwnName), which must stay addressable under its own carrier name.
    var waveEntry = entry
    if waveRename != wrOwnName:
      waveEntry.name = examinedFn
    census.eligible.add(ExternalIrEntry(entry: waveEntry, funcDef: composite,
      parseBound: parseBound))
    logInfo("axiom_engine", "external subject candidate accepted: " &
      candidateName &
      " eligibility=" & $record.eligibility &
      " obligations=" & $record.generatedObligationCount &
      " nonTrivial=" & $record.nonTrivialObligationCount &
      " source=" & modulePath)
    return ok(true)
  logInfo("axiom_engine", "external subject candidate excluded: " &
    candidateName &
    " eligibility=" & $record.eligibility &
    " rejection=" & rejectionToken(record.rejection) &
    " obligations=" & $record.generatedObligationCount &
    " nonTrivial=" & $record.nonTrivialObligationCount &
    " source=" & modulePath)
  ok(false)

# ---------------------------------------------------------------------------
# VS-2 capability adapters (REGISTRY_SPEC §2.2) — the vtable lives HERE (not
# in external_subject_registry.nim) because the six domain objects it wraps
# are defined in this module; moving it across would create an import cycle.
# ---------------------------------------------------------------------------
type
  CapabilityPayload* = ref object
    ## Adapter-owned parsed projection (REGISTRY_SPEC §2.2): the lane's
    ## domain object, kept UNCHANGED, wrapped once per capability. A
    ## capability's payload exists only after its flip PR installed the
    ## adapter.
    case kind*: ExternalSubjectCapability
    of capConstructedGate: d2*: TomlD2AgentOverlayDomain
    of capArithmeticLaw: bv*: NimLibp2pBytesviewSliceDomain
    of capBodyCarry:
      cout*: Base36CoutOverlayDomain
      sidecar*: SidecarDomain
    of capTermSplice: rem*: Base32RemOverlayDomain
    of capBetaComposition: sizing*: Base36OverlayDomain

  CapabilityAdapter* = object
    ## The per-capability head the registry dispatch loop drives (§2.7).
    ## Every leg wraps the lane's public proc VERBATIM — the lane suites
    ## call those procs unmodified and are the semantic-equivalence proof.
    capability*: ExternalSubjectCapability
    validate*: proc(node: JsonNode): Result[CapabilityPayload, string] {.raises: [].}
    declares*: proc(payload: CapabilityPayload; fnName, modulePath: string): bool {.
      raises: [].}
    routeTarget*: proc(payload: CapabilityPayload; target: string):
      tuple[routed: bool; fnName, modulePath: string] {.raises: [].}
    synthesize*: proc(fnName, modulePath: string; payload: CapabilityPayload;
      resolver: ModuleContentResolver; census: ExternalCandidateCensus;
      subjectRepoRoot: string): Result[bool, string] {.raises: [],
      axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}

proc bvAdapterValidate(node: JsonNode): Result[CapabilityPayload, string] {.
    raises: [].} =
  ## arithmetic-law validate leg: the lane's pure validator, verbatim.
  let domainRes = validateNimLibp2pBytesviewSliceOverlayNode(node)
  if domainRes.isErr:
    err(domainRes.error)
  else:
    ok(CapabilityPayload(kind: capArithmeticLaw, bv: domainRes.get))

func bvAdapterDeclares(payload: CapabilityPayload; fnName, modulePath: string): bool {.
    raises: [].} =
  ## arithmetic-law membership leg: the lane's predicate, verbatim.
  overlayDeclaresLibp2pBytesviewSubject(payload.bv, fnName, modulePath)

proc bvAdapterRouteTarget(payload: CapabilityPayload; target: string):
    tuple[routed: bool; fnName, modulePath: string] {.raises: [].} =
  ## arithmetic-law routing leg: the lane's canonical + bare routing, verbatim.
  libp2pBytesviewCarrierTargetRouting(target, payload.bv)

proc bvAdapterSynthesize(fnName, modulePath: string; payload: CapabilityPayload;
    resolver: ModuleContentResolver; census: ExternalCandidateCensus;
    subjectRepoRoot: string): Result[bool, string] {.raises: [],
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## arithmetic-law synthesize leg: the lane synthesizer, verbatim.
  synthesizeNimLibp2pBytesviewSliceCandidate(fnName, modulePath, resolver,
    payload.bv, census, subjectRepoRoot)

let bvCapabilityAdapter* = CapabilityAdapter(
  capability: capArithmeticLaw,
  validate: bvAdapterValidate,
  declares: bvAdapterDeclares,
  routeTarget: bvAdapterRouteTarget,
  synthesize: bvAdapterSynthesize)

proc d2AdapterValidate(node: JsonNode): Result[CapabilityPayload, string] {.
    raises: [].} =
  ## constructed-gate validate leg: the lane's pure validator, verbatim.
  let domainRes = validateTomlD2AgentOverlayNode(node)
  if domainRes.isErr:
    err(domainRes.error)
  else:
    ok(CapabilityPayload(kind: capConstructedGate, d2: domainRes.get))

func d2AdapterDeclares(payload: CapabilityPayload; fnName, modulePath: string): bool {.
    raises: [].} =
  ## constructed-gate membership leg: the lane's predicate, verbatim.
  overlayDeclaresD2AgentSubject(payload.d2, fnName, modulePath)

proc d2AdapterRouteTarget(payload: CapabilityPayload; target: string):
    tuple[routed: bool; fnName, modulePath: string] {.raises: [].} =
  ## constructed-gate routing leg: the lane's canonical-only routing, verbatim.
  d2AgentCarrierTargetRouting(target, payload.d2)

proc d2AdapterSynthesize(fnName, modulePath: string; payload: CapabilityPayload;
    resolver: ModuleContentResolver; census: ExternalCandidateCensus;
    subjectRepoRoot: string): Result[bool, string] {.raises: [],
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## constructed-gate synthesize leg: the lane synthesizer, verbatim.
  synthesizeTomlD2AgentCandidate(fnName, modulePath, resolver,
    payload.d2, census, subjectRepoRoot)

let d2CapabilityAdapter* = CapabilityAdapter(
  capability: capConstructedGate,
  validate: d2AdapterValidate,
  declares: d2AdapterDeclares,
  routeTarget: d2AdapterRouteTarget,
  synthesize: d2AdapterSynthesize)

proc sidecarAdapterValidate(node: JsonNode): Result[CapabilityPayload, string] {.
    raises: [].} =
  ## body-carry (sidecar payload) validate leg: the lane's TWO-STAGE pure
  ## validator, verbatim — stage (i) adoption shape + closed grammar
  ## (nim-sidecar-expr-v1), stage (ii) the SpecID recomputed from the loaded
  ## proposition content vs adoption.adoptedSpecHash, byte-exact.
  let domainRes = validateSidecarOverlayNode(node)
  if domainRes.isErr:
    err(domainRes.error)
  else:
    ok(CapabilityPayload(kind: capBodyCarry, sidecar: domainRes.get))

func sidecarAdapterDeclares(payload: CapabilityPayload; fnName,
    modulePath: string): bool {.raises: [].} =
  ## body-carry (sidecar payload) membership leg: the lane's predicate,
  ## verbatim — the exact module+symbol key the adoption pins.
  overlayDeclaresSidecarSubject(payload.sidecar, fnName, modulePath)

func sidecarAdapterRouteTarget(payload: CapabilityPayload; target: string):
    tuple[routed: bool; fnName, modulePath: string] {.raises: [].} =
  ## body-carry (sidecar payload) routing leg: the nil-equivalent never-routing
  ## stub (REGISTRY_SPEC §2.2) — the lane declares no constructedIrTargets, so
  ## it routes nothing, exactly as the retired lane never appeared in the
  ## target-routing arms.
  (false, "", "")

proc sidecarAdapterSynthesize(fnName, modulePath: string;
    payload: CapabilityPayload; resolver: ModuleContentResolver;
    census: ExternalCandidateCensus; subjectRepoRoot: string): Result[bool, string] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## body-carry (sidecar payload) synthesize leg: the lane synthesizer,
  ## verbatim — one carrier per adopted proposition over the ORIGINAL body.
  synthesizeNimSidecarCandidates(fnName, modulePath, resolver,
    payload.sidecar, census, subjectRepoRoot)

let sidecarCapabilityAdapter* = CapabilityAdapter(
  capability: capBodyCarry,
  validate: sidecarAdapterValidate,
  declares: sidecarAdapterDeclares,
  routeTarget: sidecarAdapterRouteTarget,
  synthesize: sidecarAdapterSynthesize)

proc coutAdapterValidate(node: JsonNode): Result[CapabilityPayload, string] {.
    raises: [].} =
  ## body-carry (C_out payload) validate leg: the lane's pure validator,
  ## verbatim — exactly-3 clauses (`<low> <= <v>`, `<v> <= <high>`,
  ## `<fn>(<v>) >= <K>`), the `claimConstant.K` cross-check, the
  ## `canonicalDecisionVector.L` consistency, and the empty-domain-pin
  ## rejection. K = 2 stays an external observation pinned by the
  ## cross-check — never an engine-side constant (§6.8 contrast).
  let domainRes = validateCoutOverlayNode(node)
  if domainRes.isErr:
    err(domainRes.error)
  else:
    ok(CapabilityPayload(kind: capBodyCarry, cout: domainRes.get))

func coutAdapterDeclares(payload: CapabilityPayload; fnName,
    modulePath: string): bool {.raises: [].} =
  ## body-carry (C_out payload) membership leg: the lane's predicate,
  ## verbatim — the claim symbol the overlay quantifies (decodedLength, not
  ## the buffer-taking decode).
  overlayDeclaresCoutSubject(payload.cout, fnName, modulePath)

func coutAdapterRouteTarget(payload: CapabilityPayload; target: string):
    tuple[routed: bool; fnName, modulePath: string] {.raises: [].} =
  ## body-carry (C_out payload) routing leg: the nil-equivalent never-routing
  ## stub (REGISTRY_SPEC §2.2) — the lane declares no constructedIrTargets,
  ## so it routes nothing, exactly as the retired lane never appeared in the
  ## target-routing arms.
  (false, "", "")

proc coutAdapterSynthesize(fnName, modulePath: string; payload: CapabilityPayload;
    resolver: ModuleContentResolver; census: ExternalCandidateCensus;
    subjectRepoRoot: string): Result[bool, string] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## body-carry (C_out payload) synthesize leg: the lane synthesizer,
  ## verbatim — one out-sizing carrier over the ORIGINAL body, the claim
  ## β-spliced to the result slot exactly once, OPEN over the value
  ## parameter (contract §2 — 닫힌 명제 금지), `wrSole` wave rename.
  synthesizeBase36CoutCandidate(fnName, modulePath, resolver,
    payload.cout, census, subjectRepoRoot)

let coutCapabilityAdapter* = CapabilityAdapter(
  capability: capBodyCarry,
  validate: coutAdapterValidate,
  declares: coutAdapterDeclares,
  routeTarget: coutAdapterRouteTarget,
  synthesize: coutAdapterSynthesize)

const sidecarRegistryEntryRelPath* = "nim_stew_base36_sidecar.json"
  ## The sidecar member's registry identity (REGISTRY_SPEC §5 PR-3): the
  ## flip gate is per ENTRY, discriminated on the normalized specRelPath,
  ## because body-carry's two members flip in different PRs — the sidecar
  ## member (presence-optional) flipped in PR-3, and the C_out member
  ## (coutRegistryEntryRelPath, presence-mandatory) flips in PR-4 with the
  ## same per-entry discrimination.

const flippedLaneSpecRelPaths* = [
  "nim_libp2p_bytesview_slice.json",
  "toml_d2_agent_spec.json",
  sidecarRegistryEntryRelPath]
  ## The flipped OPTIONAL lanes' document identities, in flip order (PR-1,
  ## PR-2, PR-3): the absent-document inert log is checked per flipped
  ## DOCUMENT — an optional lane whose file is missing has no registry entry
  ## to loop over (§1.3). PR-4 note: C_out is deliberately NOT listed — it
  ## is presence-MANDATORY, so its document's absence blocks the run
  ## fail-closed (the mandatory-presence check in prepareProofRun), never
  ## an inert log.

const base36RelationalRegistryEntryRelPath* = "base36_sizing_relational_spec.json"
  ## The beta-composition lane's registry identity: dispatched through its
  ## legacy chain arm (the sizing overlay cascade in prepareProofRun) —
  ## unflipped, but equipped (laneDispatchEquipped), because that arm is
  ## dispatch truth (REGISTRY_SPEC §5 flip schedule).

const base32RemRegistryEntryRelPath* = "nim_stew_base32_rem_spec.json"
  ## The term-splice lane's registry identity: dispatched through its legacy
  ## chain arm (the rem overlay cascade in prepareProofRun) — unflipped, but
  ## equipped (laneDispatchEquipped), because that arm is dispatch truth
  ## (REGISTRY_SPEC §5 flip schedule).

func entryPinWording(entry: RegistryEntry): SubjectPinMismatchWording {.
    raises: [].} =
  ## The blob-mismatch wording the entry's retired lane body logged — the
  ## flip must not change a single diagnostic's voice (REGISTRY_SPEC §6.2):
  ## the sidecar speaks in adoption-record terms, the d2/bv overlays in
  ## overlay terms. `lane` (the specRelPath prefix) is the call site's.
  if entry.specRelPath == sidecarRegistryEntryRelPath:
    spwAdoptionRecord
  else:
    spwOverlayPins

proc capabilityAdapterFor*(entry: RegistryEntry): Option[CapabilityAdapter] {.
    raises: [].} =
  ## The installed adapter per registry ENTRY (REGISTRY_SPEC §5 flip
  ## schedule): none() = the lane has not flipped yet — its legacy chain arm
  ## stays the authoritative dispatch. PR-1 installs arithmetic-law; PR-2
  ## constructed-gate; PR-3 the sidecar member of body-carry (per entry —
  ## the capability's members flip in different PRs); PR-4 the C_out member
  ## of body-carry.
  case entry.capability
  of capArithmeticLaw: some(bvCapabilityAdapter)
  of capConstructedGate: some(d2CapabilityAdapter)
  of capBodyCarry:
    if entry.specRelPath == coutRegistryEntryRelPath:
      some(coutCapabilityAdapter)
    elif entry.specRelPath == sidecarRegistryEntryRelPath:
      some(sidecarCapabilityAdapter)
    else:
      none(CapabilityAdapter)
  else: none(CapabilityAdapter)

proc laneDispatchEquipped*(entry: RegistryEntry): bool {.raises: [].} =
  ## Whether a prove run dispatches through this registry ENTRY — the
  ## capability-disclosure truth (`ax capability`) and the proposition
  ## rollup's equipped-side predicate. Two dispatch paths are both truth:
  ## the flipped adapter path (capabilityAdapterFor) and the still-
  ## authoritative legacy chain arm (the sizing/rem overlay cascades,
  ## keyed on the entry's specRelPath — REGISTRY_SPEC §5 flip schedule).
  ## The engine is the SSOT; consumers project this, never re-derive it.
  capabilityAdapterFor(entry).isSome or
    entry.specRelPath == base36RelationalRegistryEntryRelPath or
    entry.specRelPath == base32RemRegistryEntryRelPath

func flippedLaneDiagnostics(specRelPath: string):
    tuple[pinRejected, inertModule, docInvalid, docAbsent, synthUnavailable,
      carrierTarget: string] {.raises: [].} =
  ## The lane diagnostic identities the retired legacy blocks logged with —
  ## the flip must not change a single logged line (REGISTRY_SPEC §6.2).
  ## One row per flipped lane, keyed off the entry's specRelPath (the
  ## flip gate's own key — body-carry's two members carry different rows).
  case specRelPath
  of "nim_libp2p_bytesview_slice.json":
    ("nim-libp2p bytesview slice subject pin rejected (fail-closed): ",
     "nim-libp2p bytesview slice governed module not present under this " &
       "subject root — binding inert: ",
     "nim-libp2p bytesview slice overlay unavailable (fail-closed): ",
     "nim-libp2p bytesview slice overlay absent — binding inert " &
       "(presence-optional; two-PR landing, see " &
       "docs/spec/nim_libp2p_bytesview_slice_contract.md)",
     "nim-libp2p bytesview slice carrier synthesis unavailable: ",
     "nim-libp2p bytesview slice carrier-target synthesis unavailable")
  of "toml_d2_agent_spec.json":
    ("toml d2-agent subject pin rejected (fail-closed): ",
     "toml d2-agent governed module not present under this subject root — " &
       "binding inert: ",
     "toml d2-agent binding overlay unavailable (fail-closed): ",
     "toml d2-agent binding overlay absent — binding inert " &
       "(presence-optional; two-PR landing, see " &
       "docs/spec/toml_d2_agent_binding_contract.md)",
     "toml d2-agent overlay carrier synthesis unavailable: ",
     "toml d2-agent overlay carrier-target synthesis unavailable")
  of sidecarRegistryEntryRelPath:
    ("nim sidecar subject pin rejected (fail-closed): ",
     "nim sidecar governed module not present under this subject root — " &
       "binding inert: ",
     "nim sidecar binding overlay unavailable (fail-closed): ",
     "nim sidecar binding overlay absent — binding inert " &
       "(presence-optional; two-PR landing, see " &
       "docs/spec/nim_stew_base36_sidecar_contract.md)",
     "sidecar candidate synthesis unavailable: ",
     "")
  of coutRegistryEntryRelPath:
    # PR-4 (C_out, presence-mandatory): the lane runs NO pin (§2.4 —
    # mandatory lanes never had one), so the pin-rejected and inert-module
    # rows are never spoken. An absent DOCUMENT is not an inert log either:
    # the mandatory-presence check blocks the run with the legacy load
    # block's exact fail-closed line (docAbsent stays empty here).
    ("",
     "",
     "base36 C_out binding overlay unavailable (fail-closed): ",
     "",
     "base36 C_out overlay candidate synthesis unavailable: ",
     "")
  else:
    ("", "", "", "", "", "")

type
  WaveInputs* = object
    ## Everything the wave loop needs from the pre-wave phase, named as one
    ## value so the loop is a routine rather than a 400-line proc body.
    task*: ProofTask
    analysis*: TopologyAnalysis
    sourceRoot*: string
    planPath*: string
    certDir*: string
    contentResolver*: ModuleContentResolver
    internSnapshot*: InternPoolSnapshot
    kernelScope*: KernelScopeInfo
    computeLimit*: int
    externalCandidates*: seq[ExternalIrEntry]
    targetVkd*: string
    verifiedFuncsInitial*: HashSet[string]
    excludedUnits*: HashSet[string]
    declaredRequired*: seq[string]

  WaveOutcome* = object
    ## What the wave loop produced. An object rather than a tuple: the caller
    ## reads these fields by name, and a 10-field tuple is unreadable there.
    ok*: bool
    errMsg*: string
    report*: ProofReport
    wavesExecuted*: int
    waveReports*: seq[JsonNode]
    dispatchedPerWave*: seq[seq[string]]
    mergedNodeReports*: seq[OrchestrationNodeReport]
    mergedRequestCount*: int
    unitEvidence*: JsonNode
      ## §2.4d display-scope per-unit claim/quartet refs — keyed union by
      ## `modulePath::funcName` (first occurrence, matching observedRows).
      ## ALWAYS a JObject: constructed empty before the wave loop, so a
      ## zero-wave run (empty frontier — e.g. an all-INCAPABLE propositions
      ## run) yields the EMPTY union, never nil. In-memory reference copy
      ## only; never persisted by the wave loop.
    frontier*: seq[SorterNodeId]
    verifiedSet*: VerifiedSet
    discoveredBeyond*: seq[string]
      ## §13.1: later-wave dispatched units outside declaredRequired.
    irPipelineFailures*: seq[string]
      ## §13.1 out-of-scope failure channel, accumulated across waves (deduped,
      ## order-stable): kernel-registry units whose IR verification failed.
      ## They surface in scopeObservability — never in persistFailures (R8).

  WaveStepOutcome* = object
    ## What one wave produced, including the re-hydrated verified set.
    ok*: bool
    errMsg*: string
    report*: ProofReport
    requestCount*: int
    dispatchedIds*: seq[string]
    verifiedSet*: VerifiedSet

proc wavePayload(inputs: WaveInputs; frontier: seq[SorterNodeId];
                 planPath: string):
    Result[tuple[state: SorterState, requests: seq[OrchestrationProofRequest]], string] {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## W2: when a selection-derived ExecutionPlan is supplied, the plan is
  ## authoritative — run ONLY plan.selectedUnitIds (umSelected) or the full
  ## frontier (umFull). Fail-closed: an invalid or tampered plan never runs
  ## partial, so every rejection is an error rather than a fallback.
  if planPath.len == 0:
    return topologyFrontierToWorkflowPayload(inputs.analysis, frontier, inputs.sourceRoot)
  let planNodeOpt = readJsonFile(planPath)
  if planNodeOpt.isNone:
    return err("plan file is not valid JSON or unreadable: " & planPath)
  let planOpt = fromJson(planNodeOpt.get())
  if planOpt.isNone:
    return err("plan file is not a valid ExecutionPlan JSON: " & planPath)
  if not verifyPlanDigest(planOpt.get()):
    return err("plan digest verification failed (tampered or regenerated plan): " & planPath)
  if planOpt.get().mode == umFull:
    topologyFrontierToWorkflowPayload(inputs.analysis, frontier, inputs.sourceRoot)
  else:
    payloadsForSelectedUnits(inputs.analysis, planOpt.get().selectedUnitIds, inputs.sourceRoot)

proc promoteVerifiedDependencies(state: var SorterState; verifiedSet: VerifiedSet;
                                 internSnapshot: InternPoolSnapshot;
                                 verifiedAxioms: Table[string, AxiomFormula]) {.raises: [Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Pre-promote verified dependencies into the state so frontier nodes can
  ## resolve their dependency axioms without re-verifying them.
  for node in state.nodes:
    let nodeIdOpt = nodeIdForSorter(internSnapshot, node.id)
    if nodeIdOpt.isSome and verifiedSet.contains(nodeIdOpt.get()):
      let key = sorterNodeIdString(node.id)
      if verifiedAxioms.hasKey(key):
        promoteNodeToVault(state, node.id, verifiedAxioms[key])

proc runOneWave(inputs: WaveInputs; engine: var AxiomEngine; frontier: seq[SorterNodeId];
                verifiedSet: VerifiedSet; dispatchedThisWave: HashSet[string]): WaveStepOutcome {.
  raises: [Exception, IOEffect], axiomEffect: IOEffect,
  tags: [TimeEffect, RootEffect, AxiomIOEffect, IOEffect].} =
  ## One wave: build the payload (plan-authoritative or full frontier),
  ## pre-promote already-verified dependencies, run the batch, then re-hydrate
  ## the verified set from whatever this wave wrote to the vault.
  let payloadRes = wavePayload(inputs, frontier, inputs.planPath)
  if payloadRes.isErr():
    return WaveStepOutcome(ok: false, errMsg: payloadRes.error)
  var state = payloadRes.get().state
  let requests = payloadRes.get().requests

  let verifiedAxioms = loadVerifiedAxiomsFromProofVault(
    inputs.certDir, inputs.contentResolver, inputs.analysis)
  promoteVerifiedDependencies(state, verifiedSet, inputs.internSnapshot, verifiedAxioms)

  # §13.1 start-snapshot unification: the IR selection basis is the frozen
  # prepared value — the wave loop never re-derives it from the re-hydrated
  # set mid-run (execution_accounting_contract.md §13.1).

  let verifyRes = runBatchVerification(engine, inputs.task, state, requests,
    topologyAnalysis = inputs.analysis,
    totalSourceFunctions = countKernelFunctions(),
    historicalVerified = verifiedSet.popcount(),
    verifiedFuncs = inputs.verifiedFuncsInitial,
    kernelScope = inputs.kernelScope,
    externalCandidates = inputs.externalCandidates,
    subjectRepoRoot = inputs.sourceRoot,
    targetVkd = inputs.targetVkd)
  if verifyRes.isErr():
    return WaveStepOutcome(ok: false, errMsg: verifyRes.error)

  var dispatchedIds: seq[string] = @[]
  for dispatchedId in dispatchedThisWave.items:
    dispatchedIds.add(dispatchedId)
  dispatchedIds.sort()

  WaveStepOutcome(
    ok: true,
    report: verifyRes.get(),
    requestCount: requests.len,
    dispatchedIds: dispatchedIds,
    # RE-HYDRATE verifiedSet: pick up newly written vault certs from this wave
    verifiedSet: hydrateVerifiedSetFromProofVault(inputs.certDir, inputs.internSnapshot,
      inputs.analysis, inputs.contentResolver, inputs.kernelScope))

proc claimWaveNodes(frontier: seq[SorterNodeId]; attempted: var HashSet[string]): HashSet[string] =
  ## Mark every node in this wave attempted and return the per-wave dispatched
  ## set — the diff of the attempted set before and after the claim. Terminal
  ## outcomes are authoritative, so a node is never attempted twice.
  let before = attempted
  for nid in frontier:
    attempted.incl(sorterNodeIdString(nid))
  attempted - before

func recordDiscoveredBeyond(dispatchedIds: seq[string]; declaredSet: HashSet[string];
                            discovered: var seq[string]) {.raises: [].} =
  ## §13.1: later-wave dispatched units outside declaredRequired are
  ## dependency-fixpoint discovery — accumulated (deduped, order-stable) for
  ## the scopeObservability report channel.
  for dispatchedId in dispatchedIds.items:
    if dispatchedId notin declaredSet and dispatchedId notin discovered:
      discovered.add(dispatchedId)

proc scopeFilteredFrontier(frontier: seq[SorterNodeId];
                           excludedUnits: HashSet[string]): seq[SorterNodeId] {.raises: [].} =
  ## §13.1 frozen scope policy: frontier recomputation respects the start
  ## eligibility classification — a unit the gate excluded at start never
  ## re-enters a later wave (execution_accounting_contract.md §13.1).
  frontier.filterIt(sorterNodeIdString(it) notin excludedUnits)

proc runVerificationWaves(inputs: WaveInputs; engine: var AxiomEngine;
                           initialFrontier: seq[SorterNodeId];
                           initialVerifiedSet: VerifiedSet): WaveOutcome {.
  raises: [Exception, IOEffect], axiomEffect: IOEffect,
  tags: [TimeEffect, RootEffect, AxiomIOEffect, IOEffect].} =
  ## ── WAVE LOOP: iterate until DiscoveryFixedPoint (frontier empty) ──
  ## Break when the frontier is empty (DiscoveryFixedPoint), also guarded with a
  ## sane max-iterations bound (64) to prevent infinite loops, logging if hit.
  ## The post-loop code (crossValidation, report merge, persist, ASI) runs ONCE
  ## after the loop, over the accumulated inputs — never the last wave alone.
  const waveMaxIterations = 64
  var frontier = initialFrontier
  var verifiedSet = initialVerifiedSet
  # §2.4d invariant (see WaveOutcome.unitEvidence): the keyed union starts
  # as an EMPTY JObject at construction — a zero-wave run must still hand
  # consumers (keys()/pairs() iteration in appendDisplayAndPersist) a
  # JObject; nil is never a state of this field.
  result.unitEvidence = newJObject()

  # Closure-loop termination: a node is attempted at most once. Nodes whose
  # verification ends terminal (e.g. no_obligation) never enter verifiedSet, so
  # without this filter the frontier would recompute the same nodes forever
  # (starvation). Attempted nodes are excluded from subsequent waves; newly
  # eligible nodes (deps verified by a prior wave) are still picked up.
  var attempted: HashSet[string] = initHashSet[string]()
  # §13.1: declared-vs-discovered lookup — later-wave dispatched units outside
  # the declared set are dependency-fixpoint discovery (discoveredBeyond).
  var declaredSet = initHashSet[string]()
  for declaredId in inputs.declaredRequired.items:
    declaredSet.incl(declaredId)
  # X1 canonical boundary (DEBT#458): the loop ACCUMULATES per-wave canonical
  # inputs — wave reports, per-wave dispatched unit sets, merged node reports
  # and the merged request count.
  # --target contract: exactly the selected target node(s), single wave (the
  # verify-contract-release-e2e-full gate asserts "target node not exactly 1"
  # must not fire). Closure-complete looping applies ONLY to untargeted (Full)
  # runs.
  while (frontier.len > 0 or result.wavesExecuted == 0) and
        not (inputs.task.target.len > 0 and result.wavesExecuted >= 1):
    if frontier.len == 0 and result.wavesExecuted > 0:
      break  # DiscoveryFixedPoint: no new candidates to verify
    if result.wavesExecuted >= waveMaxIterations:
      logInfo("axiom_engine", "WAVE_MAX_ITERATIONS_REACHED: frontier not empty after " & $waveMaxIterations & " waves")
      break

    # Exclude nodes already attempted in a prior wave (terminal outcomes are
    # authoritative; never re-attempt them).
    frontier = frontier.filterIt(sorterNodeIdString(it) notin attempted)
    if frontier.len == 0:
      # DiscoveryFixedPoint: nothing new to verify this round. A targeted run
      # whose governed routing populated external candidates despite an empty
      # selection (carrier standalone target — constructed IR has no
      # subject-parse presence) still owes its single --target wave: the
      # candidates verify through the external-candidates lane alone.
      if not (inputs.task.target.len > 0 and inputs.externalCandidates.len > 0):
        break

    inc result.wavesExecuted
    # Per-wave dispatched set = the diff of the attempted set (snapshot
    # before/after this wave) — X1 canonical boundary input.
    let dispatchedThisWave = claimWaveNodes(frontier, attempted)

    let step = runOneWave(inputs, engine, frontier, verifiedSet, dispatchedThisWave)
    if not step.ok:
      result.errMsg = step.errMsg
      return result

    # X1 canonical boundary: collect this wave's report + dispatched set.
    result.report = step.report
    let waveDoc = json.parseJson(step.report.outputJson)
    result.waveReports.add(waveDoc)
    # §13.1 out-of-scope failure channel: accumulate the wave's
    # irPipelineFailures (deduped, order-stable) for scopeObservability.
    let irFailuresNode = waveDoc{"irPipelineFailures"}
    if not irFailuresNode.isNil:
      for f in irFailuresNode.items:
        let s = f.getStr("")
        if s.len > 0 and s notin result.irPipelineFailures:
          result.irPipelineFailures.add(s)
    result.dispatchedPerWave.add(step.dispatchedIds)
    result.mergedNodeReports.add(step.report.orchestrationNodeReports)
    result.mergedRequestCount += step.requestCount
    # §2.4d display-scope refs — keyed union across waves (first occurrence,
    # the same merge algebra as collectObservedRows).
    let ueNode = waveDoc{"unitEvidenceRefs"}
    if not ueNode.isNil and ueNode.kind == JObject:
      for k, v in ueNode:
        if not result.unitEvidence.hasKey(k):
          result.unitEvidence[k] = v
    verifiedSet = step.verifiedSet

    # §13.1: later-wave dispatched units outside declaredRequired are
    # dependency-fixpoint discovery (scopeObservability channel).
    if result.wavesExecuted >= 2:
      recordDiscoveredBeyond(step.dispatchedIds, declaredSet, result.discoveredBeyond)

    # RECOMPUTE frontier with the same args as the initial call
    frontier = computeVerifiedFrontier(inputs.analysis, verifiedSet, inputs.internSnapshot,
      inputs.computeLimit, inputs.kernelScope, subjectMode = externalSubjectMode)
    frontier = scopeFilteredFrontier(frontier, inputs.excludedUnits)

  result.ok = true
  result.frontier = frontier
  result.verifiedSet = verifiedSet

proc makeSubjectResolver(sourceRoot: string; cache: Table[string, string]): ModuleContentResolver {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## WP4-a B-5b: subject-scoped resolver for the external materialization path.
  ## It OWNS the subject root and decides source location by resolving
  ## modulePath against sourceRoot — never against process CWD. The shared
  ## cache-only contentResolver remains separate for the Axiom-support hydration
  ## path, keeping support vs subject source acquisition independent.
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    # 1) fast path: content already loaded by the topology scan.
    let cached = cache.getOrDefault(modulePath, "")
    if cached.len > 0:
      return some(cached)
    # 2) disk path: resolve against the subject root (never CWD).
    let absPath = if len(sourceRoot) > 0: sourceRoot / modulePath else: modulePath
    try:
      if fileExists(absPath):
        let content = readFile(absPath)
        if content.len > 0:
          return some(content)
    except CatchableError:
      discard  # axiom:best-effort(subject source read failure is non-fatal; resolver falls through to none(string))
    none(string)

proc resolveScopeLockPath(): string {.raises: [Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §10: kernel scope lock follows the AXIOM repo (state identity), not the
  ## subject. Precedence: stateRoot/data → CWD-relative (legacy zero-diff:
  ## when stateDir is unset, getCurrentDir()/data is exactly the old path).
  let sr = getEnv("AXIOM_STATE_DIR", "").strip()
  if sr.len > 0: sr / "data" / "verification_scope.lock"
  else: getCurrentDir() / "data" / "verification_scope.lock"

proc buildNodeIndices(analysis: TopologyAnalysis):
    tuple[fnIdx, moduleIdx: Table[string, string]] =
  ## Node function/module index used by the eligibility classification.
  result.fnIdx = initTable[string, string]()
  result.moduleIdx = initTable[string, string]()
  for n in analysis.state.nodes:
    let nid = sorterNodeIdString(n.id)
    result.fnIdx[nid] = n.functionName
    result.moduleIdx[nid] = n.modulePath

proc logSelectionSummary(target: string; preEligibilityFrontier: seq[SorterNodeId];
                         preSelectLen, postSelectLen: int) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Log what the --target filter and the eligibility gate each removed.
  if target.len > 0:
    var targetMatches: seq[SorterNodeId] = @[]
    for nodeId in preEligibilityFrontier:
      if sorterNodeIdString(nodeId).contains(target):
        targetMatches.add(nodeId)
    if targetMatches.len == 0:
      logInfo("axiom_engine", "--target=" & target & " not found in frontier")
    else:
      logInfo("axiom_engine", "--target filter: " & $targetMatches.len & " node(s) match '" & target & "'")
  if postSelectLen < preSelectLen:
    logInfo("axiom_engine", "frontier eligibility gate: excluded " & $(preSelectLen - postSelectLen) &
      " non-proof-candidate candidate(s); eligible=" & $postSelectLen)

proc rankBySelectionScore(frontier: var seq[SorterNodeId]; selState: NodeSelectionState) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Ranked selection: re-order frontier by selection score (least-selected
  ## first). Score(s) = 1 / (Count(s) + 1), so nodes selected fewer times get
  ## higher priority. WP2-a: same state routing for ranked-selection cache.
  if frontier.len <= 1:
    return
  type ScoredNode = object
    nodeId: SorterNodeId
    score: float
  var scored: seq[ScoredNode] = @[]
  for nodeId in frontier:
    let nid = sorterNodeIdString(nodeId)
    scored.add(ScoredNode(nodeId: nodeId, score: computeScore(selState.counts.getOrDefault(nid, 0))))
  scored.sort(proc(a, b: ScoredNode): int =
    let sc = cmp(b.score, a.score)
    if sc != 0: return sc
    cmp(sorterNodeIdString(a.nodeId), sorterNodeIdString(b.nodeId))
  )
  frontier.setLen(0)
  for s in scored:
    frontier.add(s.nodeId)
  logInfo("axiom_engine", "ranked selection: reordered " & $frontier.len & " nodes by score")

proc analyzeSubjectSource(sourceRoot: string; queueLimit: int; explicit: bool):
    Result[TopologyCliAnalysisBundle, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## QueueLimit ADT: resolve() returns Positive (never 0). No magic number
  ## interpretation — unlimited vs capped is pattern-matched by the caller.
  let topoStartMs = getMonoTime().ticks
  logInfo("axiom_engine", "analyzing topology...")
  let res = analyzeTopologySourceRoot(sourceRoot, queueLimit = queueLimit,
    queueLimitExplicit = explicit, diagnosisDepth = 0, diagnosisDepthExplicit = false)
  if res.isOk():
    let topoElapsedMs = int((getMonoTime().ticks - topoStartMs) div 1_000_000)
    logStage(skTopology, "", "topology scan completed", elapsedMs=topoElapsedMs)
    logInfo("axiom_engine", "topology: " & $res.get().sourceFileCount & " files, " &
      $res.get().analysis.verificationQueue.len & " candidates")
  res

proc buildPreLoopReport(bundle: TopologyCliAnalysisBundle; frontier: seq[SorterNodeId];
                        censusRecords: seq[CandidateCensusRecord]): JsonNode {.raises: [Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The report skeleton written before the wave loop.
  result = jsonFromTopologyFrontier(bundle.analysis, bundle.diagnoses, frontier,
    bundle.sourceFileCount, bundle.effectiveDiagnosisDepth)
  # UniverseRegistry: inject totalSourceFunctions into initial proof state
  result["summary"]["totalSourceFunctions"] = %countKernelFunctions()
  # Record eligibility class for each selected frontier candidate in the report.
  # The frontier gate excludes elNoObligation/elUnsupported/elMalformed
  # candidates, so all selected entries are elProofCandidate. This field
  # provides auditability of the eligibility classification at selection time.
  var eligibilityObj = %*{}
  for f in frontier:
    eligibilityObj[sorterNodeIdString(f)] = %("elProofCandidate")
  result["eligibility"] = eligibilityObj
  # Candidacy census — the machine-readable answer to "did the canonical
  # obligation authority derive a NON-TRIVIAL obligation from the external
  # subject?". terminal == NO_ELIGIBLE_OBLIGATION is a publishable finding: a
  # zero solverInvocationCount under that terminal is the measured outcome, not
  # a verification failure.
  result["census"] = censusToJson(buildCandidacyCensus(censusRecords))

proc buildPreRunContext(reportJson: JsonNode): JsonNode {.raises: [Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## ── PreRunContext: immutable pre-loop skeleton snapshot (X1 canonical boundary) ──
  ## Captured BEFORE the wave loop; passed as the second input to the pure
  ## report projections (renderLegacyReport / renderPersist). NOT stored in
  ## RunResult. The pre-loop persist creates the PreRunContext on disk.
  result = newJObject()
  for preRunKey in ["diagnostics", "verificationQueue", "structuralBottlenecks",
                    "repairPriorityDependencies", "eligibility", "census", "summary",
                    "declaredRequired"]:
    let preRunVal = reportJson{preRunKey}
    if not preRunVal.isNil:
      result[preRunKey] = preRunVal

type
  PreparedRun* = object
    ## Everything the post-selection pipeline needs, resolved once before the
    ## wave loop: the vault identity, the frozen intern snapshot, the initial
    ## frontier, and the report skeleton that is persisted before any wave runs.
    analysis*: TopologyAnalysis
    sourceRoot*: string
    certDir*: string
    internSnapshot*: InternPoolSnapshot
    contentResolver*: ModuleContentResolver
    kernelScope*: KernelScopeInfo
    verifiedSet*: VerifiedSet
    universeDigestStart*: string
    computeLimit*: int
    frontier*: seq[SorterNodeId]
    preEligibilityFrontier*: seq[SorterNodeId]
    census*: ExternalCandidateCensus
    overlay*: Option[Base36OverlayDomain]
      ## D1: the validated explicit-spec overlay; every gate hit it governs
      ## synthesizes the relational candidate instead of a single symbol.
    remOverlay*: Option[Base32RemOverlayDomain]
      ## D1: the validated rem-range overlay (base32 subject); its governed
      ## symbol synthesizes the remainder-range candidate.
    subjectRegistry*: ExternalSubjectRegistry
      ## VS-2 PR-1: the external-subject registry, loaded ONCE per run
      ## (REGISTRY_SPEC §2.3) — the authoritative dispatch input for the
      ## flipped lanes (arithmetic-law in PR-1, constructed-gate in PR-2,
      ## body-carry's sidecar member in PR-3, body-carry's C_out member in
      ## PR-4) and the parity shadow's registry leg for the two unflipped
      ## lanes (sizing, rem).
    registryPayloads*: seq[tuple[specRelPath: string, payload: CapabilityPayload]]
      ## Pre-validated adapter payloads for the flipped, PIN-ACTIVE entries
      ## (§2.3 rule 3, §2.4): an entry absent from here (absent document, or
      ## pin-inert on this run's subject root) is skipped by the dispatch
      ## loop — the explicitly-logged inert binding.
    adoptedSpecRefs*: seq[tuple[unitKey, specRelPath, specId: string]]
      ## Display v3: the dispatch-winner lane's explicit overlay identity,
      ## recorded per dispatched unit where dispatch already decided
      ## (synthesis success / routing success) — `unitKey` is
      ## `modulePath & "::" & fnName`, the unit-evidence row key. A RECORD
      ## of the dispatch decision, never a priority recomputation; the
      ## display consumes it to resolve each unit's adoptedSpecRef.
    propositionIntake*: PropositionIntake
      ## BYOA 5.1: the run's accepted propositions intake (empty = no
      ## --proposals run). The display rollup's capability facts come from
      ## here (intake seeds) plus the adoptedSpecRefs records above
      ## (LANE_NOT_EQUIPPED = a capable proposition with no record).
    selState*: NodeSelectionState
    cacheDir*: string
    engine*: AxiomEngine
    reportJson*: JsonNode
    preRun*: JsonNode
    statePath*: string
    targetVkd*: string
      ## §13.1 start-snapshot unification: the VKD baseline is read ONCE at
      ## prepare; the IR selection consumes the frozen value, never a re-read.
    verifiedFuncsInitial*: HashSet[string]
      ## §13.1: the IR selection basis, collected once from the prepared
      ## verifiedSet — the wave loop never re-derives it mid-run.
    excludedUnits*: HashSet[string]
      ## §13.1 frozen scope policy: node IDs the eligibility gate excluded at
      ## start; frontier recomputation can never re-admit them.
    declaredRequired*: seq[string]
      ## §13.1: the post-eligibility declared frontier (sorted node IDs),
      ## frozen at start and carried by the pre-run document.
    discoveredBeyond*: seq[string]
      ## §13.1: units dispatched in a later wave that declaredRequired did not
      ## declare (dependency-fixpoint discovery), accumulated post-start.

func registryPayloadFor(prepared: PreparedRun; specRelPath: string): Option[CapabilityPayload] {.
    raises: [].} =
  ## The pre-validated payload of one registry entry; none = the entry is
  ## inactive on this run's tree (absent document or pin-inert — see
  ## `registryPayloads`), so the dispatch loop must skip it.
  for candidate in prepared.registryPayloads:
    if candidate.specRelPath == specRelPath:
      return some(candidate.payload)
  none(CapabilityPayload)

func registryEntryRawFor(prepared: PreparedRun;
    specRelPath: string): Option[JsonNode] {.raises: [].} =
  ## The registry entry's OWN raw document (§2.8): the direct consumers
  ## (probeSubjectIdentity / buildBugVerdictDisplayJson) read THIS node —
  ## same JSON, one authority, no second file read. none = the entry is
  ## absent (the consumers' fail-soft postures take over).
  for entry in prepared.subjectRegistry.entries:
    if entry.specRelPath == specRelPath:
      return some(entry.raw)
  none(JsonNode)

func adoptedSpecRefFor*(prepared: PreparedRun; unitKey: string):
    Option[tuple[specRelPath, specId: string]] {.raises: [].} =
  ## The per-unit adopted overlay identity (display v3): the FIRST record
  ## for the key wins — the dispatch-winner lane's own binding, recorded at
  ## dispatch time. none = the unit is ungoverned (no display block).
  for adopted in prepared.adoptedSpecRefs:
    if adopted.unitKey == unitKey:
      return some((specRelPath: adopted.specRelPath,
        specId: adopted.specId))
  none(tuple[specRelPath, specId: string])

proc buildCanonicalRunOutcome(eligibilityObj: JsonNode; waves: WaveOutcome;
                              universeDigestStart: string): CanonicalRunResult {.
  raises: [Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## ── X1 canonical boundary: CanonicalRunResult ──
  ## The canonical reducer runs over ALL wave reports (DEBT#458 closed); the
  ## legacy report, the state file and the TrustCommit projection are pure
  ## projections of (CanonicalRunResult, PreRunContext) — the last-wave
  ## document is never a data source anywhere.
  ##
  ## Plan 1 — Authority Unification (INV-X1 inversion): per-row REUSED
  ## re-verification context (current pinned identity values) + condition (d)
  ## artifact content re-verification on every read feed the reducer; the
  ## run-level verdict is decided by VerificationDecisionAuthority ONLY
  ## (run_accounting preserves raw state and never derives a gate verdict).
  let reuseContext = captureRunReuseContext()
  verifyReuseArtifacts(waves.waveReports)
  result = buildCanonicalRunResult(waves.waveReports, eligibilityObj,
    waves.dispatchedPerWave, reuseContext)
  let noObligationProvenance = NoObligationProvenance(
    universeEnumerated: not eligibilityObj.isNil and eligibilityObj.kind == JObject and
                        eligibilityObj.len > 0,
    source: "canonical_ogr_eligibility")
  let factGateActive = result.executionEvidence.blockedNodes.len > 0
  let runOutcome = evaluateRunOutcome(result.runAccounting, noObligationProvenance, factGateActive)
  result.runOutcome = runOutcome  ## single verdict assignment — VDA only (INV-X1)
  let canonicalDigest = canonicalRunDigest(result)

  # Canonical WARN (from RunResult ONLY — never legacy/last-wave/trajectory).
  if result.runAccounting.contestedCount > 0 or result.runAccounting.unsatisfiedCount > 0:
    logWarn("axiom_engine", "canonical run accounting: contestedCount=" &
      $result.runAccounting.contestedCount & " ∨ unsatisfiedCount=" &
      $result.runAccounting.unsatisfiedCount & " ⇒ GateVerdict=" &
      $gateVerdictProjection(runOutcome) & " (fail-closed; see reportJson.runOutcome)")

  # Trajectory reference record — ONE record post-reducer (skRunAccounting).
  # Existing streaming records stay untouched (nightly verify_trajectory keeps
  # passing: it asserts skSwat/skReport presence only).
  logStage(skRunAccounting, "", "canonical run accounting", extra = %*{
    "event": %*{"type": "run_result"},
    "canonicalRunDigest": canonicalDigest,
    "runAccountingDigest": sha256Hex($result.runAccounting.toJson()),
    "runOutcomeDigest": sha256Hex($runOutcomeToJson(runOutcome)),
    "gateVerdict": $gateVerdictProjection(runOutcome),
    "verdict": $runOutcome.verdict,
    "basis": $runOutcome.basis,
    "universeDigestRef": universeDigestStart
  })

proc recordSelectionOutcome(selState: var NodeSelectionState; cacheDir: string;
                            reportJson: JsonNode; frontier: seq[SorterNodeId]) {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Record ASI + selection counts for the next run's ranked selection.
  try:
    let asiVal = reportJson{"summary"}{"asi"}.getFloat(0.0)
    let asiRatio = initAsiRatio(asiVal).get(defaultAsiRatio())
    recordAsi(selState, asiRatio)
    var selectedIds: seq[string] = @[]
    for nodeId in frontier:
      selectedIds.add(sorterNodeIdString(nodeId))
    incrementCount(selState, selectedIds)
    saveSelectionState(selState, cacheDir)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc buildInternSnapshot(bundle: TopologyCliAnalysisBundle): InternPoolSnapshot =
  ## Pre-intern every source node ID so downstream workers receive an immutable
  ## snapshot and never need to mutate the pool.
  var internPool = initInternPool(bundle.analysis.verificationQueue.len)
  for node in bundle.analysis.state.nodes:
    discard nodeIdForSorter(internPool, node.id)
  freezeInternPool(internPool)

proc buildCacheResolver(cache: Table[string, string]): ModuleContentResolver =
  ## Cache-only resolver for the Axiom-support hydration path: content the
  ## topology scan already loaded, and nothing else. The subject resolver
  ## (makeSubjectResolver) is the only one allowed to touch disk.
  result = proc(modulePath: string): Option[string] {.raises: [], noSideEffect.} =
    let content = cache.getOrDefault(modulePath, "")
    if content.len > 0:
      return some(content)
    none(string)

func canonicalTargetRefusal(target: string; frontierLen: int): string {.raises: [].} =
  ## WP4-e: canonical ``module::function`` targets are fail-closed. A canonical
  ## target that resolves to zero nodes is NotFound; one that resolves to more
  ## than one node is Ambiguous. In both cases selection is empty, and instead of
  ## silently falling back to the full frontier we surface an explicit error so a
  ## typo'd or overloaded canonical target can never trigger an unrequested
  ## project-wide verification. Empty string = no refusal.
  if target.len > 0 and target.contains("::") and frontierLen == 0:
    return "--target " & target &
      " resolved to no frontier nodes (NotFound or Ambiguous). " &
      "Canonical targets require exactly one match; 0 matches = NotFound, >1 = Ambiguous. " &
      "Refuse to run an implicit full-frontier verification on a canonical target."
  ""

proc loadRankedSelectionState(): tuple[state: NodeSelectionState, cacheDir: string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## WP2-a: same state routing for ranked-selection cache.
  let cacheDir = stateJoin(".axiom", "cache")
  (loadSelectionState(cacheDir), cacheDir)

func makeWaveInputs(prepared: PreparedRun; task: ProofTask; planPath: string): WaveInputs {.raises: [].} =
  ## Everything the wave loop reads, in one value. §13.1: the frozen start
  ## snapshot fields ride along — the loop never re-derives them.
  WaveInputs(
    task: task,
    analysis: prepared.analysis,
    sourceRoot: prepared.sourceRoot,
    planPath: planPath,
    certDir: prepared.certDir,
    contentResolver: prepared.contentResolver,
    internSnapshot: prepared.internSnapshot,
    kernelScope: prepared.kernelScope,
    computeLimit: prepared.computeLimit,
    externalCandidates: prepared.census.eligible,
    targetVkd: prepared.targetVkd,
    verifiedFuncsInitial: prepared.verifiedFuncsInitial,
    excludedUnits: prepared.excludedUnits,
    declaredRequired: prepared.declaredRequired
  )

proc buildPostLoopProjections(closureJson, crossValidationJson,
                              leanVerifyJson: JsonNode;
                              scopeObservability: JsonNode = newJObject()): JsonNode =
  ## Post-loop projections (closure / crossValidation / leanVerify).
  ## §13.1: scopeObservability carries the out-of-scope failure channel
  ## (irPipelineFailures) and the dependency-fixpoint discovery record
  ## (discoveredBeyond) into the rendered document — separate from the
  ## subject outcome axes, never silently swallowed (§0.9).
  result = newJObject()
  result["closure"] = closureJson
  result["crossValidation"] = crossValidationJson
  result["leanVerify"] = leanVerifyJson
  result["scopeObservability"] = scopeObservability

proc hydrateRunVault(prepared: var PreparedRun; bundle: TopologyCliAnalysisBundle;
                      sourceRoot: string) {.raises: [Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Resolve the vault identity, freeze the intern snapshot, load kernel scope
  ## and hydrate the verified set — everything the frontier and the wave loop
  ## read on every iteration.
  prepared.certDir = resolveCertificate(cvRuntimeCanonical)
  prepared.internSnapshot = buildInternSnapshot(bundle)
  let sourceCache = bundle.sourceContentCache
  prepared.contentResolver = buildCacheResolver(sourceCache)
  prepared.kernelScope = loadKernelScope(resolveScopeLockPath(), failClosed = true)
  prepared.verifiedSet = hydrateVerifiedSetFromProofVault(prepared.certDir,
    prepared.internSnapshot, bundle.analysis, prepared.contentResolver, prepared.kernelScope)
  # I-F: capture universe digest at pipeline start for freshness guard.
  # Re-derive at closure-evaluation time; if they differ → closureComplete=false.
  prepared.universeDigestStart = sha256Hex(prepared.kernelScope.kernelSymbols.sorted(cmp).join("|"))

proc computeInitialFrontier(prepared: PreparedRun; bundle: TopologyCliAnalysisBundle;
                           computeLimit: int): seq[SorterNodeId] {.raises: [Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The unverified frontier under the computed limit, for the given verified set.
  computeVerifiedFrontier(bundle.analysis, prepared.verifiedSet, prepared.internSnapshot,
    computeLimit, prepared.kernelScope, subjectMode = externalSubjectMode)

proc prepareProofRun(task: ProofTask; sourceRoot: string;
                     shortcutStatePathOverride: string): Result[PreparedRun, string] {.
  raises: [Exception], axiomEffect: IOEffect,
  tags: [TimeEffect, RootEffect, AxiomIOEffect, IOEffect].} =
  ## Topology scan → vault hydration → frontier selection → pre-loop persist.
  ## Everything the wave loop needs, resolved before any wave runs.
  var prepared: PreparedRun
  # D1: the out-of-tree explicit spec overlay authorizes the relational
  # binding this product makes over the read-only subject tree. Fail closed:
  # absence, a parse failure, or a rejected origin blocks the run outright.
  let overlayRes = loadBase36OverlayDomain()
  if overlayRes.isErr():
    return err("base36 sizing binding overlay unavailable (fail-closed): " &
      overlayRes.error)
  prepared.overlay = some(overlayRes.value)
  let remOverlayRes = loadBase32RemOverlayDomain()
  if remOverlayRes.isErr():
    return err("base32 rem binding overlay unavailable (fail-closed): " &
      remOverlayRes.error)
  prepared.remOverlay = some(remOverlayRes.value)
  # ── VS-2 PR-1: external-subject registry — the AUTHORITATIVE load (§2.3) ──
  # The registry is loaded ONCE per run, here. The flipped lanes
  # (arithmetic-law, PR-1; constructed-gate, PR-2; body-carry's sidecar
  # member, PR-3; body-carry's C_out member, PR-4) dispatch through their
  # installed adapters below; the two unflipped lanes (sizing, rem) keep
  # their legacy loads above as the sole inputs of their chain arms
  # (REGISTRY_SPEC §5 flip schedule). A load rejection (any document) blocks
  # the run fail-closed.
  # BYOA specDir seam: the runtime proposition overlay ($AXIOM_STATE_DIR/specs,
  # installed by the --proposals intake) shadow-merges over the committed
  # catalog when present — same specRelPath wins by the overlay document;
  # envelope + duplicate-specId + overlap checks stay fail-closed unchanged.
  let subjectRegistryRes = loadExternalSubjectRegistry(
    overlayDir = runtimeOverlaySpecDir())
  if subjectRegistryRes.isErr():
    return err("external subject registry unavailable (fail-closed): " &
      subjectRegistryRes.error)
  prepared.subjectRegistry = subjectRegistryRes.get
  prepared.propositionIntake = task.propositionIntake
  # Flipped-lane presence + pin + payload (§2.3 rule 3, §2.4): an entry with
  # an installed adapter is pin-verified against this run's subject root,
  # then payload-validated from ITS OWN raw document (no second semantic
  # source). Absent module under the root → explicitly-logged inert binding;
  # present-but-invalid → fail-closed regardless of presence policy. The
  # sidecar entry's pin carries the adoption-record mismatch wording — the
  # diagnostic voice its retired lane body logged (§2.4). The C_out entry
  # runs NO pin (mandatory lanes never had one) and its payload validation
  # carries the same fail-closed voice the retired load block logged.
  block registryFlippedLanePrep:
    for entry in prepared.subjectRegistry.entries:
      let adapterOpt = capabilityAdapterFor(entry)
      if adapterOpt.isNone:
        continue
      let diag = flippedLaneDiagnostics(entry.specRelPath)
      if entry.presence == ppOptional and entry.governedBlobSha256.len > 0:
        let pin = verifySubjectBlobPin(entry.specRelPath, entry.governedModule,
          entry.governedBlobSha256, sourceRoot,
          entryPinWording(entry))
        if pin.isErr():
          return err(diag.pinRejected & pin.error)
        if not pin.get:
          logInfo("axiom_engine", diag.inertModule & entry.governedModule)
          continue
      let payloadRes = adapterOpt.get.validate(entry.raw)
      if payloadRes.isErr():
        return err(diag.docInvalid & payloadRes.error)
      prepared.registryPayloads.add((entry.specRelPath, payloadRes.get))
    # A flipped OPTIONAL lane whose DOCUMENT is absent has no entry to loop
    # over: the absence is an explicitly-logged inert binding (§1.3), the
    # exact line the retired legacy block logged. The check is per flipped
    # DOCUMENT (specRelPath — the flip gate's own key), not per capability:
    # body-carry's two members flip in different PRs (sidecar PR-3, cout
    # PR-4), so a capability-level probe cannot stand in for either.
    for lanePath in flippedLaneSpecRelPaths:
      var present = false
      for entry in prepared.subjectRegistry.entries:
        if entry.specRelPath == lanePath:
          present = true
          break
      if not present:
        logInfo("axiom_engine", flippedLaneDiagnostics(lanePath).docAbsent)
    # PR-4: C_out is presence-MANDATORY (§1.3) — its document's absence has
    # no entry to loop over (the loader cannot classify absence, the PR-0
    # note), so the consumer enforces the policy here: the run blocks
    # fail-closed with the retired load block's exact error line. Never an
    # inert log — the JSON cannot invent a third behavior.
    block coutMandatoryPresence:
      var coutPresent = false
      for entry in prepared.subjectRegistry.entries:
        if entry.specRelPath == coutRegistryEntryRelPath:
          coutPresent = true
          break
      if not coutPresent:
        # The registry above already resolved the catalog root (a miss
        # failed the run at its load), so the seam here re-resolves only to
        # render the same path the retired load block quoted — an err is
        # reported verbatim rather than joined (Q-013).
        let coutDirRes = resolveExternalSubjectSpecDir()
        if coutDirRes.isErr():
          return err("base36 C_out binding overlay unavailable (fail-closed): " &
            coutDirRes.error)
        return err("base36 C_out binding overlay unavailable (fail-closed): " &
          "cannot read spec overlay " & coutDirRes.get /
          coutRegistryEntryRelPath &
          " (missing, unreadable, or not valid JSON)")
  # ── VS-2 external-subject registry parity shadow (observability-only) ──
  # PR-0 ran the registry beside the six legacy loads; PR-1 promoted the
  # load above to the authoritative one. The shadow keeps comparing each
  # entry's registry activation against the chain: for the two unflipped
  # lanes (sizing, rem) the chain leg reads the legacy overlay fields;
  # for the flipped lanes (arithmetic-law PR-1, constructed-gate PR-2,
  # body-carry's sidecar member PR-3, body-carry's C_out member PR-4) the
  # chain arms are RETIRED, so the shadow computes what the retired chain
  # path WOULD have decided — the legacy loader + lane pin, observability-
  # only. The comparison stays cross-path (registry envelope + shared pin
  # vs legacy file read + lane validator + lane pin); a disagreement is an
  # explicit log line — never a behavior change.
  block registryParityShadow:
    let reg = prepared.subjectRegistry
    var specIdList: seq[string]
    var parityMismatches = 0
    for entry in reg.entries:
      specIdList.add(entry.specId)
      # Registry activation: an envelope-valid entry is active unless an
      # optional lane's governed module is absent under this run's subject
      # root (the shared pin check, §2.4). Mandatory lanes run no pin.
      var registryActive = true
      var pinNote = ""
      if entry.presence == ppOptional and entry.governedBlobSha256.len > 0:
        let pin = verifySubjectBlobPin(entry.specRelPath, entry.governedModule,
          entry.governedBlobSha256, sourceRoot, entryPinWording(entry))
        if pin.isErr():
          # The chain leg already failed the run for a present-but-mismatched
          # pin; reaching this line means the shared proc disagreed with the
          # lane path — parity finding, log it.
          inc parityMismatches
          pinNote = " pin=err(" & pin.error & ")"
        elif pin.get:
          pinNote = " pin=verified"
        else:
          registryActive = false
          pinNote = " pin=inert(" & entry.governedModule &
            " not present under this subject root)"
      # Chain activation. The (capability, presence) pair is unique across
      # the six lanes; the two body-carry members split on presence
      # (sidecar optional / cout mandatory).
      let chainActive = block:
        var active = false
        case entry.capability
        of capConstructedGate:
          # PR-2: the chain arm is retired — the counterfactual chain
          # decision is the legacy load+pin path (observability-only).
          let legacy = loadTomlD2AgentOverlayDomain()
          if legacy.isErr:
            active = false
          else:
            let legacyPin = verifyTomlD2AgentSubjectPin(legacy.get, sourceRoot)
            active = legacyPin.isOk and legacyPin.get
        of capArithmeticLaw:
          # PR-1: the chain arm is retired — the counterfactual chain
          # decision is the legacy load+pin path (observability-only).
          let legacy = loadNimLibp2pBytesviewSliceOverlayDomain()
          if legacy.isErr:
            active = false
          else:
            let legacyPin = verifyLibp2pBytesviewSubjectPin(legacy.get, sourceRoot)
            active = legacyPin.isOk and legacyPin.get
        of capTermSplice:
          active = prepared.remOverlay.isSome
        of capBetaComposition:
          active = prepared.overlay.isSome
        of capBodyCarry:
          if entry.presence == ppMandatory:
            # PR-4: the C_out chain arm is retired — the counterfactual
            # chain decision is the legacy load path (observability-only).
            # Mandatory lanes run no pin (§2.4): the fail-closed loader was
            # the whole gate.
            let legacy = loadBase36CoutOverlayDomain()
            active = legacy.isOk
          else:
            # PR-3: the sidecar chain arm is retired — the counterfactual
            # chain decision is the legacy load+pin path (observability-only).
            let legacy = loadNimSidecarOverlayDomain()
            if legacy.isErr:
              active = false
            else:
              let legacyPin = verifySidecarSubjectPin(legacy.get, sourceRoot)
              active = legacyPin.isOk and legacyPin.get
        active
      let parityLine = "external subject registry parity: " & entry.specRelPath &
        " capability=" & $entry.capability &
        " precedence=" & $entry.precedence &
        " presence=" & $entry.presence &
        " specId=" & entry.specId & pinNote
      if registryActive == chainActive:
        logInfo("axiom_engine", parityLine &
          " registry-decision == chain-decision")
      else:
        inc parityMismatches
        logWarn("axiom_engine", parityLine &
          " registry-decision != chain-decision (parity finding, " &
          "reported as-is)")
    logInfo("axiom_engine", "external subject registry parity summary: entries=" &
      $reg.entries.len & " specIds=[" & specIdList.join(", ") &
      "] mismatches=" & $parityMismatches)
  let effectiveQueueLimit = task.limit.resolve()
  let analysisRes = analyzeSubjectSource(sourceRoot, effectiveQueueLimit, not task.limit.isUnlimited())
  if analysisRes.isErr(): return err(analysisRes.error)
  let bundle = analysisRes.get()
  prepared.analysis = bundle.analysis
  prepared.sourceRoot = bundle.sourceRoot

  # Build VerifiedSet from the certificate vault and compute the unverified frontier.
  # Vault resolves to the RUNTIME canonical store (data/trusted/certificates/)
  # for reading — the current-product-truth source. Reference/engineering readers
  # (src/verification/certificates/) are separate and used only by maintenance tools.
  hydrateRunVault(prepared, bundle, sourceRoot)
  let subjectResolver = makeSubjectResolver(sourceRoot, bundle.sourceContentCache)
  let frontierLimit = if task.limit.isUnlimited(): 0 else: effectiveQueueLimit
  # F1: when an explicit --target is present, compute the UNRESTRICTED frontier so
  # target pre-filtering can find the symbol even when it lies beyond the --limit
  # boundary. selectFrontierNodes re-applies frontierLimit in its Step 3, so the
  # effective limit is preserved for the selected prepared. No-target runs keep the
  # original bounded computation (zero-drift).
  prepared.computeLimit = if task.target.len > 0: 0 else: frontierLimit
  prepared.frontier = computeInitialFrontier(prepared, bundle, prepared.computeLimit)
  if prepared.frontier.len == 0 and effectiveQueueLimit > 0:
    logInfo("axiom_engine", "NO_ADMISSIBLE_VKD_CANDIDATE: no admissible kernel-scope candidate available (kernelScope.kernelSymbols.len=" &
      $prepared.kernelScope.kernelSymbols.len & ")")

  # Save pre-eligibility frontier so --target can find its symbol even when
  # --limit would have selected a different node that is later excluded by the
  # eligibility gate.
  prepared.preEligibilityFrontier = prepared.frontier
  let nodeIndices = buildNodeIndices(bundle.analysis)

  # Candidacy census, one record per external-subject candidate the frontier
  # eligibility gate examined. This is the census' only data source, and it is
  # populated exclusively on the registry-MISS branch — kernel-registry entries
  # never appear here, which is what scopes the census to external subjects.
  prepared.census = ExternalCandidateCensus()
  let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
    # Registry hit keeps the existing isFrontierSelectionEligible behavior;
    # a registry miss falls through to subject-source materialization.
    if isRegistryEligible(fnName):
      return true
    # VS-2 PR-1: the registry dispatch loop (REGISTRY_SPEC §2.7) for the
    # FLIPPED lanes — ascending (precedence, specRelPath) order, the
    # capability's adapter decides, and the chain's return protocol is
    # preserved verbatim: ok(true) and ok(false) BOTH return; err falls
    # through to the examined symbol's own census record. PR-3/PR-4 note:
    # the loop sits ABOVE the still-unflipped chain arms because the
    # body-carry members (sidecar 10, C_out 20) share the governed
    # stew/base36.nim::decodedLength symbol with the sizing arm (30) —
    # precedence §1.4 requires the HASH-BOUND adoption to decide first and
    # the C_out carrier before the sizing composite (the retired arms sat
    # in exactly that order); bv (60) and d2 (50) are module-disjoint from
    # every unflipped lane, so the loop's position is immaterial for them.
    # An entry without a pre-validated payload is inert on this tree
    # (absent document or pin-inert — logged at prep).
    block registryDispatch:
      for entry in prepared.subjectRegistry.entries:
        let adapterOpt = capabilityAdapterFor(entry)
        if adapterOpt.isNone:
          continue
        let payloadOpt = registryPayloadFor(prepared, entry.specRelPath)
        if payloadOpt.isNone:
          continue
        if adapterOpt.get.declares(payloadOpt.get, fnName, modulePath):
          let synth = adapterOpt.get.synthesize(fnName, modulePath,
            payloadOpt.get, subjectResolver, prepared.census, sourceRoot)
          if synth.isOk():
            # Display v3: record the dispatch-winner lane's adopted overlay
            # identity for this unit (the decision dispatch already made).
            prepared.adoptedSpecRefs.add((modulePath & "::" & fnName,
              entry.specRelPath, entry.specId))
            return synth.value
          logWarn("axiom_engine",
            flippedLaneDiagnostics(entry.specRelPath).synthUnavailable &
            synth.error &
            " — examined symbol falls back to its own census record")
    # The still-unflipped chain arms (REGISTRY_SPEC §5 flip schedule):
    # sizing and rem, in their pre-flip cascade order — the loop above has
    # already given the flipped body-carry members (10, 20) their
    # precedence over the sizing composite (30).
    if prepared.overlay.isSome and
        overlayDeclaresSubject(prepared.overlay.get, fnName, modulePath):
      let synth = synthesizeBase36RelationalCandidate(fnName, modulePath,
        subjectResolver, prepared.overlay.get, prepared.census, sourceRoot)
      if synth.isOk():
        # Display v3: record the legacy chain arm's adopted overlay identity
        # for this unit (the dispatch decision already made — the arm is the
        # lane's authoritative pre-flip dispatch, laneDispatchEquipped).
        for entry in prepared.subjectRegistry.entries:
          if entry.specRelPath == base36RelationalRegistryEntryRelPath:
            prepared.adoptedSpecRefs.add((modulePath & "::" & fnName,
              entry.specRelPath, entry.specId))
            break
        return synth.value
      logWarn("axiom_engine",
        "base36 overlay composite synthesis unavailable: " & synth.error &
        " — examined symbol falls back to its own census record")
    if prepared.remOverlay.isSome and
        overlayDeclaresRemSubject(prepared.remOverlay.get, fnName, modulePath):
      let synth = synthesizeBase32RemRangeCandidate(fnName, modulePath,
        subjectResolver, prepared.remOverlay.get, prepared.census, sourceRoot)
      if synth.isOk():
        # Display v3: record the legacy chain arm's adopted overlay identity
        # for this unit (the dispatch decision already made — the arm is the
        # lane's authoritative pre-flip dispatch, laneDispatchEquipped).
        for entry in prepared.subjectRegistry.entries:
          if entry.specRelPath == base32RemRegistryEntryRelPath:
            prepared.adoptedSpecRefs.add((modulePath & "::" & fnName,
              entry.specRelPath, entry.specId))
            break
        return synth.value
      logWarn("axiom_engine",
        "base32 rem overlay candidate synthesis unavailable: " & synth.error &
        " — examined symbol falls back to its own census record")
    classifyExternalCandidate(fnName, modulePath, subjectResolver, prepared.census,
      sourceRoot)

  # Apply --target filter and eligibility gate in the correct order:
  # --target applies BEFORE automatic frontier filtering (eligibility gate + limit).
  # This ensures that a targeted symbol is found even when --limit selects a
  # different node first and the eligibility gate then removes that node,
  # leaving the frontier empty. Eligibility is still enforced as a final guard —
  # an explicitly targeted non-eligible symbol is still excluded.
  let preSelectLen = prepared.frontier.len
  prepared.frontier = selectFrontierNodes(prepared.preEligibilityFrontier, task.target,
    nodeIndices.fnIdx, nodeIndices.moduleIdx, frontierLimit, isEligible)
  let postSelectLen = prepared.frontier.len

  var refusal = canonicalTargetRefusal(task.target, prepared.frontier.len)
  # VS-2 PR-1: registry target routing (§2.7) for the FLIPPED capabilities —
  # the canonical pass first (attempted only on a canonical-target refusal,
  # exactly the retired arm's guard), then the bare pass below. The retired
  # arms' fail-closed asymmetry is reproduced verbatim: a canonical pass
  # failure LOGS and keeps the refusal; a bare pass failure ERRORS the run.
  if refusal.len > 0:
    # Canonical standalone targetability for a flipped lane's constructed
    # carriers (and governed symbols): same synthesizer, same census, same
    # refusal semantics as the retired arm — a routed hit that synthesizes
    # clears the refusal; one that cannot keeps it (logged).
    for entry in prepared.subjectRegistry.entries:
      let adapterOpt = capabilityAdapterFor(entry)
      if adapterOpt.isNone:
        continue
      let payloadOpt = registryPayloadFor(prepared, entry.specRelPath)
      if payloadOpt.isNone:
        continue
      let routed = adapterOpt.get.routeTarget(payloadOpt.get, task.target)
      if routed.routed:
        let synth = adapterOpt.get.synthesize(routed.fnName, routed.modulePath,
          payloadOpt.get, subjectResolver, prepared.census, sourceRoot)
        if synth.isOk():
          # Display v3: record the routing winner's adopted overlay identity
          # for the routed unit (the decision dispatch already made).
          prepared.adoptedSpecRefs.add((routed.modulePath & "::" & routed.fnName,
            entry.specRelPath, entry.specId))
          refusal = ""
        else:
          logWarn("axiom_engine",
            flippedLaneDiagnostics(entry.specRelPath).carrierTarget &
            ": " & synth.error & " — canonical target refusal stands")
  if task.target.len > 0 and not task.target.contains("::") and
      prepared.frontier.len == 0:
    # A BARE carrier target names a constructed carrier that has NO
    # subject-parse presence at all: the canonical-target refusal machinery
    # does not fire for a non-canonical target, so the routing happens here —
    # the same synthesizer, the same census, the same carriers. A synthesis
    # failure is fail-closed (an explicitly requested carrier that cannot be
    # produced must never degrade into a silent empty run). Only a lane
    # whose routing accepts the bare name routes (routeTarget decides).
    for entry in prepared.subjectRegistry.entries:
      let adapterOpt = capabilityAdapterFor(entry)
      if adapterOpt.isNone:
        continue
      let payloadOpt = registryPayloadFor(prepared, entry.specRelPath)
      if payloadOpt.isNone:
        continue
      let routed = adapterOpt.get.routeTarget(payloadOpt.get, task.target)
      if routed.routed:
        let synth = adapterOpt.get.synthesize(routed.fnName, routed.modulePath,
          payloadOpt.get, subjectResolver, prepared.census, sourceRoot)
        if synth.isErr:
          return err(flippedLaneDiagnostics(entry.specRelPath).carrierTarget &
            " (fail-closed): " & synth.error)
        # Display v3: record the bare-routing winner's adopted overlay
        # identity for the routed unit (the decision dispatch already made).
        prepared.adoptedSpecRefs.add((routed.modulePath & "::" & routed.fnName,
          entry.specRelPath, entry.specId))
  if refusal.len > 0:
    if task.propositionIntake.propositions.len > 0:
      # BYOA 5.1: a propositions-introduced target whose lane is absent is
      # NOT a run error — it degrades to the proposition's INCAPABLE
      # {LANE_NOT_EQUIPPED} rollup entry and the run completes in-contract
      # (exit 0/1). Non-propositions --target invocations keep the
      # fail-closed refusal unchanged (the WP4-e contract).
      logWarn("axiom_engine", refusal &
        " — propositions-introduced target: degrading to per-proposition " &
        "INCAPABLE{" & $pcrLaneNotEquipped & "} (byo_agent_proposition_contract §3); run continues")
    else:
      return err(refusal)

  logSelectionSummary(task.target, prepared.preEligibilityFrontier, preSelectLen, postSelectLen)

  # §13.1 frozen scope policy: record what the eligibility gate excluded at
  # start and freeze the declared required set. Later-wave frontier
  # recomputation filters through excludedUnits — a unit the gate excluded at
  # start never re-enters a later wave (execution_accounting_contract.md §13.1).
  var selectedSet = initHashSet[string]()
  for nid in prepared.frontier.items:
    let nidStr = sorterNodeIdString(nid)
    selectedSet.incl(nidStr)
    prepared.declaredRequired.add(nidStr)
  prepared.declaredRequired.sort()
  for nid in prepared.preEligibilityFrontier.items:
    let nidStr = sorterNodeIdString(nid)
    if nidStr notin selectedSet:
      prepared.excludedUnits.incl(nidStr)
  # §13.1 start-snapshot unification: VKD baseline and the IR selection basis
  # are read once here; phase-10 and the wave loop consume the frozen values.
  prepared.targetVkd = readBaselineVkdFixed4(block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0: sr / BaselineDataDir / BaselineFileName
    else: getCurrentDir() / BaselineDataDir / BaselineFileName)
  prepared.verifiedFuncsInitial = collectVerifiedFuncNames(prepared.verifiedSet,
    prepared.internSnapshot, bundle.analysis.state.nodes)

  let ranked = loadRankedSelectionState()
  (prepared.selState, prepared.cacheDir) = (ranked.state, ranked.cacheDir)
  rankBySelectionScore(prepared.frontier, prepared.selState)

  # Adaptive budget: scale with frontier size × MaxGasCostPerNode
  prepared.engine = initAxiomEngine(getMonoTime().ticks, task.budgetGas, max(1, prepared.frontier.len))
  prepared.reportJson = buildPreLoopReport(bundle, prepared.frontier, prepared.census.records)
  # §13.1: the pre-run snapshot document carries the declared set.
  prepared.reportJson["declaredRequired"] = %prepared.declaredRequired
  prepared.preRun = buildPreRunContext(prepared.reportJson)
  prepared.statePath = resolveAxStatePath(shortcutStatePathOverride)
  let persisted = persistAxProofState(prepared.statePath, prepared.reportJson)
  if persisted.isErr(): return err(persisted.error)
  ok(prepared)

proc appendDisplayAndPersist(prepared: PreparedRun; proofReport: var ProofReport;
    runResult: CanonicalRunResult; waves: WaveOutcome; projections: JsonNode;
    sourceRoot: string): Result[string, string] {.
    raises: [Exception, IOEffect], axiomEffect: IOEffect,
    tags: [TimeEffect, RootEffect, AxiomIOEffect, IOEffect].} =
  ## Display v3 projection + state-file persist: the display iterates the
  ## run's unit-evidence keys and resolves each unit's adopted overlay
  ## identity from `prepared.adoptedSpecRefs` (the dispatch-winner record —
  ## no priority recomputation, no hardwired lane document); a key without a
  ## binding is an ungoverned unit → no block (same as the retired C_out
  ## resolution produced). The subject probe runs ONCE PER GOVERNING ENTRY
  ## (≤ registry size), never per unit. Any scope binding unmet ⇒ that
  ## unit's block is absent, never fabricated; a persist failure is
  ## fail-closed. The same loop assembles the WP-B `findingEvidence`
  ## carrier — the governed units' machine observations + verbatim quartet
  ## payload lines + subject probe identity, persisted at the state document
  ## ROOT (fixed reporter-consumed interface). A scope-unmet unit still
  ## persists its evidence there — evidence is not display; an ungoverned
  ## unit (no resolving adoptedSpecRef → no probe) is in neither.
  var unitBlocks: seq[JsonNode] = @[]
  var findingEvidence = newJObject()
  var entryProbes: seq[tuple[specRelPath: string;
      probe: BugVerdictSubjectIdentity]] = @[]
  block displayProjection:
    for unitKey in keys(waves.unitEvidence):
      let adopted = adoptedSpecRefFor(prepared, unitKey)
      if adopted.isNone:
        continue  # ungoverned unit — no block (never fabricated)
      let specRelPath = adopted.get.specRelPath
      let rawOpt = registryEntryRawFor(prepared, specRelPath)
      if rawOpt.isNone:
        continue  # fail-soft: the entry is absent — the display never fabricates
      var probe: BugVerdictSubjectIdentity
      var probed = false
      for p in entryProbes:
        if p.specRelPath == specRelPath:
          probe = p.probe
          probed = true
          break
      if not probed:
        # ONE probe per governing entry, reused by every unit it governs.
        probe = probeSubjectIdentity(sourceRoot, rawOpt.get)
        entryProbes.add((specRelPath, probe))
      # WP-B evidence carrier — collectUnitQuartet is the SAME producer the
      # display builder consumes (a deterministic pure traversal over the
      # same inputs: same values, no second authority); machineEstablishedOf
      # is the shared §2.4d conjunction. Field spellings are the fixed
      # reporter interface — do not rename.
      let unitLeg = collectUnitQuartet(runResult, waves.unitEvidence, unitKey)
      findingEvidence[unitKey] = %*{
        "claimOutcome": unitLeg.claimOutcome,
        "rowStatus": unitLeg.rowStatus,
        "machineVerdict": $runResult.runOutcome.verdict,
        "machineEstablished": machineEstablishedOf(unitLeg),
        "counterExample": unitLeg.quartetLines,
        "quartetPayloadDigest": unitLeg.quartetPayloadDigest,
        "subjectCommit": probe.commit,
        "subjectBlob": probe.blob}
      let unitBlock = buildBugVerdictDisplayJson(runResult, waves.unitEvidence,
        probe, rawOpt.get, specRelPath, adopted.get.specId, unitKey)
      if not unitBlock.isNil:
        unitBlocks.add(unitBlock)
  var propositionRollup: seq[PropositionRollupDisplay] = @[]
  let intake = prepared.propositionIntake
  if intake.propositions.len > 0:
    for p in intake.propositions:
      var seedReason = none(PropositionCapabilityReason)
      for seed in intake.incapableSeeds:
        if seed.id == p.id:
          seedReason = some(seed.reason)
          break
      if seedReason.isSome:
        # Intake-decided capability fact — the display layer only projects
        # it; no lane attempt, no verdict (never fabricated).
        propositionRollup.add(PropositionRollupDisplay(
          id: p.id,
          capabilityStatus: propositionCapabilityIncapableSpelling,
          capabilityReason: $seedReason.get,
          attempted: false,
          verdict: ""))
        continue
      # Catalog-resolvable lane-form proposition: the dispatch-winner record
      # (the lane's own specId — adoptedSpecRefs is the dispatch decision's
      # record, never a recomputation) decides LANE_NOT_EQUIPPED vs attempted.
      var winner = none(tuple[unitKey, specRelPath, specId: string])
      for adopted in prepared.adoptedSpecRefs:
        if adopted.specId == p.specId:
          winner = some(adopted)
          break
      if winner.isNone:
        propositionRollup.add(PropositionRollupDisplay(
          id: p.id,
          capabilityStatus: propositionCapabilityIncapableSpelling,
          capabilityReason: $pcrLaneNotEquipped,
          attempted: false,
          verdict: ""))
        continue
      # Attempted: the verdict projects from the SAME inputs the unit block
      # consumed (collectUnitQuartet + the run verdict) via the exported
      # propositionVerdictOf — no second decision path.
      let unitLeg = collectUnitQuartet(runResult, waves.unitEvidence,
        winner.get.unitKey)
      propositionRollup.add(PropositionRollupDisplay(
        id: p.id,
        capabilityStatus: propositionCapabilityCapableSpelling,
        capabilityReason: "",
        attempted: true,
        verdict: propositionVerdictOf(unitLeg.claimOutcome,
          $runResult.runOutcome.verdict, unitLeg.quartetComplete)))
  let displayContainer = if unitBlocks.len > 0 or propositionRollup.len > 0:
    displayContainerJson(unitBlocks, propositionRollup)
  else:
    nil
  if not displayContainer.isNil:
    prepared.reportJson["display"] = displayContainer
  proofReport.outputJson = renderJsonMultiline(prepared.reportJson)
  proofReport.canonicalRunResult = runResult
  renderPersist(prepared.statePath, runResult, prepared.preRun, projections,
    displayContainer,
    (if findingEvidence.len > 0: findingEvidence else: nil))

proc runProofPipeline*(
  task: ProofTask;
  cwdOverride: string;
  shortcutStatePathOverride: string;
  planPath: string = ""
): Result[ProofReport, string] {.raises: [Exception, IOEffect], axiomEffect: IOEffect, tags: [TimeEffect, RootEffect, AxiomIOEffect, IOEffect].} =
  ## Topology scan → adaptive budget calculation → batch UAP pipeline.
  let sourceRoot = if cwdOverride.len > 0: cwdOverride else: getCurrentDir()
  let preparedRes = prepareProofRun(task, sourceRoot, shortcutStatePathOverride)
  if preparedRes.isErr():
    return err(preparedRes.error)
  var prepared = preparedRes.get()
  var verifiedSet = prepared.verifiedSet
  var frontier = prepared.frontier

  let waveInputs = makeWaveInputs(prepared, task, planPath)
  let waves = runVerificationWaves(waveInputs, prepared.engine, frontier, verifiedSet)
  if not waves.ok:
    return err(waves.errMsg)
  var proofReport = waves.report
  verifiedSet = waves.verifiedSet
  frontier = waves.frontier

  # ── CLOSURE EVALUATION (post-wave) — recomputed from MERGED rows +
  # cumulative verifiedSet (X1 canonical boundary; closure_evaluation.nim
  # signature unchanged — the merged nodeReports are passed in). ──
  # §13.1 I-F disk re-derivation: digestEnd comes from a fresh fail-closed
  # disk read of the scope lock — a digest re-derived from the in-memory
  # snapshot would never see a mid-run scope change, which is exactly what
  # the freshness guard exists to catch.
  let scopeEndDisk = loadKernelScope(resolveScopeLockPath(), failClosed = true)
  let closureJson = evaluateClosure(prepared.analysis, prepared.kernelScope, verifiedSet,
    waves.mergedNodeReports, frontier, waves.wavesExecuted,
    prepared.universeDigestStart, prepared.internSnapshot,
    sha256Hex(scopeEndDisk.kernelSymbols.sorted(cmp).join("|")))

  # ── POST-LOOP: crossValidation, canonical aggregation, projections, persist, ASI ──
  var crossValidationJson: JsonNode = runCrossValidation(waves.mergedRequestCount)

  ## WP2-a: Skip lean-verify in external subject mode (no proofs/ directory).
  var leanVerifyJson: JsonNode
  if not externalSubjectMode:
    let (lvJson, lvErr) = runLeanVerifyBlock()
    if lvErr.len > 0:
      return err(lvErr)
    leanVerifyJson = lvJson

  let runResult = buildCanonicalRunOutcome(prepared.reportJson{"eligibility"}, waves,
    prepared.universeDigestStart)

  let projections = buildPostLoopProjections(closureJson, crossValidationJson, leanVerifyJson,
    %*{"irPipelineFailures": waves.irPipelineFailures,
       "discoveredBeyond": waves.discoveredBeyond})

  # renderLegacyReport — PURE projection of the full legacy report from
  # (CanonicalRunResult, PreRunContext, projections).
  prepared.reportJson = renderLegacyReport(runResult, prepared.preRun, projections)
  # T3 display + persist — the §2.8 registry-raw projection and the state
  # file write, one cohesive tail (see appendDisplayAndPersist).
  let repersisted = appendDisplayAndPersist(prepared, proofReport, runResult,
    waves, projections, sourceRoot)
  if repersisted.isErr():
    return err(repersisted.error)

  recordSelectionOutcome(prepared.selState, prepared.cacheDir, prepared.reportJson, frontier)
  ok(proofReport)

proc runAxiomEngineCli*(
  args: seq[string];
  cwdOverride: string  = "";
  shortcutStatePathOverride: string = "";
  updateLock: bool = false
): Result[ProofReport, CliError] {.raises: [Exception, IOEffect], axiomEffect: IOEffect, tags: [TimeEffect, RootEffect, AxiomIOEffect, IOEffect].} =
  ## Unified entry point for `ax prove`.
  let flagsRes = parseAxProveFlags(args)
  if flagsRes.isErr():
    return err(CliError(kind: CliOutcome.INVALID_INPUT, msg: flagsRes.error))
  var flags = flagsRes.get()
  # ── BYO-Agent propositions intake (docs/spec/byo_agent_proposition_contract.md) ──
  # A fail-closed intake gate, not an engine lane: validate the propositions
  # document → resolve its lane-form specIds against the committed catalog
  # (unresolvable/claim-form propositions become INCAPABLE capability seeds,
  # not rejections) → install the runtime registry overlay under
  # $AXIOM_STATE_DIR/specs for the resolvable ones → project the
  # propositions' single target onto the existing --target filter. A
  # document-level rejection is INVALID_INPUT (exit 3); per-proposition
  # INCAPABLE facts ride the intake result into the report's
  # display.propositions[] rollup and the run completes in-contract.
  var propositionIntake = PropositionIntake()
  if flags.proposals.len > 0:
    let intakeRes = ingestPropositionsFile(flags.proposals)
    if intakeRes.isErr():
      return err(CliError(kind: CliOutcome.INVALID_INPUT, msg: intakeRes.error))
    propositionIntake = intakeRes.get()
    var incapableLines: seq[string] = @[]
    for seed in propositionIntake.incapableSeeds:
      incapableLines.add(seed.id & "=" & $seed.reason)
    logInfo("axiom_engine", "PROPOSITIONS_INTAKE: agent=" & propositionIntake.agentId &
      "/" & propositionIntake.agentVersion & " subject=" & propositionIntake.subjectRepository &
      "@" & propositionIntake.subjectCommit & " specs=" & propositionIntake.overlaySpecRelPaths.join(",") &
      " propositions=" & $propositionIntake.propositions.len &
      " incapable=[" & incapableLines.join(",") & "]")
    if flags.target.len == 0:
      flags.target = propositionIntake.target
    elif flags.target != propositionIntake.target:
      return err(CliError(kind: CliOutcome.INVALID_INPUT,
        msg: "--target \"" & flags.target & "\" conflicts with the propositions target \"" &
             propositionIntake.target & "\" — pass one or the other, not both"))
  # ── §10: --project explicit subject root (fail-closed w/o AXIOM_STATE_DIR) ──
  var projectAbs = ""
  var subjectForRuntimeMeta: VerificationSubject
  var usedFallbackForRuntimeMeta = false
  var hasSubmodulesForRuntimeMeta = false
  var stateRootForRuntimeMeta = ""
  if flags.project.len > 0:
    # §10 identity discipline: the subject root is ALWAYS absolutized — a
    # relative spelling that happens to exist from the CWD would otherwise
    # leak into identity-bearing consumers (lane workDir hash, guard-replay
    # harness `include!` which rustc resolves relative to the harness file).
    projectAbs = absolutePath(expandTilde(flags.project))
    if not dirExists(projectAbs):
      return err(CliError(kind: CliOutcome.INVALID_INPUT, msg: "[AXIOM] --project requires an existing directory: " & flags.project))
    # D4 P2: AXIOM_STATE_DIR pairing (inlined env read — proc-budget rule).
    let stateRoot = block:
      let v = getEnv("AXIOM_STATE_DIR", "")
      if v.len > 0: v.strip() else: ""
    if stateRoot.len == 0:
      stderr.writeLine("[AXIOM] --project requires AXIOM_STATE_DIR (fail-closed, §10.3): no state written")
      quit(1)
    # Rust subject lane (feat/rust-lane-live-cli): a Cargo.toml subject is
    # served by the pinned-charon → existing-issuance chain and the ENTIRE
    # Nim pipeline is skipped — the lane returns the report document and the
    # pinned exit projection itself. --project absent or a non-cargo subject
    # never enters this branch (zero behavior change).
    if fileExists(projectAbs / "Cargo.toml"):
      let laneRes = runRustLaneCli(projectAbs, stateRoot, flags.target)
      if laneRes.isErr():
        return err(laneRes.error)
      let lane = laneRes.get()
      return ok(ProofReport(
        outputJson: lane.outputJson,
        logLines: lane.logLines,
        exitCode: lane.exitCode,
        emitJson: not isatty(stdout)))
    let subjRes = buildVerificationSubject(projectAbs)
    if subjRes.isErr():
      return err(CliError(kind: CliOutcome.INVALID_INPUT, msg: "[AXIOM] subject load failed: " & subjRes.error))
    subjectForRuntimeMeta = subjRes.get()
    usedFallbackForRuntimeMeta = collectSubjectFileSet(projectAbs).usedFallback
    hasSubmodulesForRuntimeMeta = subjectFlagHasSubmodules
    stateRootForRuntimeMeta = stateRoot
    discard VerificationRun(
      subject: subjectForRuntimeMeta,
      axiomRevision: AxiomEngineVersionHash,
      environmentIdentity: "fallback=" & (if usedFallbackForRuntimeMeta: "walkDirRec" else: "git-ls-files") &
        ";submodules=" & (if hasSubmodulesForRuntimeMeta: "true" else: "false") & ";stateDir=set",
      stateRoot: stateRoot,
      executionWorkspace: ""
    )
  ## WP2-a: Gate external-subject execution path when --project is active.
  if projectAbs.len > 0:
    setExternalSubjectMode(true)
  # Wire --legacy-uap flag to loop driver
  setLegacyUapMode(flags.legacyUap)
  # AGENT-D: Wire --workers flag to loop driver via env var
  if flags.workers > 0:
    putEnv("AXIOM_PROVE_WORKERS", $flags.workers)
  # Wire --smt-timeout flag to solver via env var (Per-Phase Clamp)
  if flags.smtTimeout > 0:
    putEnv("AXIOM_SMT_TIMEOUT", $flags.smtTimeout)
  # Populate runtime axiom registry from compile-time collected entries
  generateAxiomInit()
  static:
    const MIN_AXIOMS = 150
    when axiomRegistry.len < MIN_AXIOMS:
      {.error: "Axiom Registry Deficit: " & $axiomRegistry.len &
               " axioms, minimum " & $MIN_AXIOMS & " required.".}
  initRegistryLookup()  # Build O(1) lookup table for Task-Injected Pipeline
  # Load config defaults from axiom.toml
  # §1b:40 root resolution (productization contract): AXIOM_ROOT env first,
  # else the anchor walk up from the binary location (first
  # .axiom_root/axiom.toml terminates) — the same strict seam the catalog
  # read uses (findRepoRootStrict, VS-2 §2.3 amendment). A --project subject
  # carrying its own axiom.toml still wins. The CWD-relative join is gone:
  # CWD is convenience, never identity (§10). A tree-external anchor miss
  # yields the optional EMPTY config — every prove-consumed field carries a
  # safe default; fail-closed (§1b:40, Q-013) governs catalog reads, not
  # the optional toml.
  let tomlPath = block:
    if projectAbs.len > 0 and fileExists(projectAbs / "axiom.toml"):
      projectAbs / "axiom.toml"
    else:
      let rootRes = findRepoRootStrict()
      if rootRes.isOk(): rootRes.get() / "axiom.toml" else: ""
  let proveConfig = loadTomlConfigIfPresent(tomlPath).getSection("prove")
  let configVaultDir = proveConfig.getString("vault_dir", "")
  let configBudgetGas = proveConfig.getInt("budget_gas", 0)

  # Bootstrap Leanstral environment from axiom.toml if not set
  let leanstralConfig = loadTomlConfigIfPresent(tomlPath).getSection("leanstral")
  if getAxiomEnv(evLlmApiUrl).len == 0:
    let url = leanstralConfig.getString("api_url", "")
    if url.len > 0:
      putEnv("AXIOM_LLM_API_URL", url)
  if getAxiomEnv(evLlmModel).len == 0:
    let model = leanstralConfig.getString("model", "")
    if model.len > 0:
      putEnv("AXIOM_LLM_MODEL", model)
  if getAxiomEnv(evLlmApiKey).len == 0:
    let key = leanstralConfig.getString("api_key", "")
    if key.len > 0:
      putEnv("AXIOM_LLM_API_KEY", key)

  let emitJson = not isatty(stdout)
  let taskRes = buildProofTask(flags, configVaultDir, configBudgetGas, emitJson)
  if taskRes.isErr():
    return err(CliError(kind: CliOutcome.INVALID_INPUT, msg: taskRes.error))
  var task = taskRes.get()
  task.propositionIntake = propositionIntake

  # §10 source-root precedence: --project-abs-path > cwdOverride > getCurrentDir()
  let effectiveCwdOverride = if projectAbs.len > 0: projectAbs else: cwdOverride

  let pipelineRes = runProofPipeline(task, effectiveCwdOverride, shortcutStatePathOverride, flags.plan)
  if pipelineRes.isErr():
    return err(CliError(kind: CliOutcome.INTERNAL_ERROR, msg: pipelineRes.error))
  var proofReport = pipelineRes.get()

  let cwd = if effectiveCwdOverride.len > 0: effectiveCwdOverride else: getCurrentDir()
  let reportJson = json.parseJson(proofReport.outputJson)
  # LEGACY-LABEL read: summary.vkd was renamed to verifiedRatio (Phase 3 label
  # cleanup). This is the cumulative full-function success rate over |Kernel|=40,
  # NOT canonical VKD (which lives in metrics.vkd, wired in report_cli.nim).
  let asiValue = reportJson{"summary"}{"verifiedRatio"}.getFloat(0.0)
  let vkdFixed4 = exportAsiFixed4(initAsiRatio(asiValue).get(defaultAsiRatio()))
  # P0: reuse the global symbol graph when the GraphInputFingerprint matches a
  # previously validated, materialized snapshot (I1/I2), avoiding the per-run
  # full .nim/.lean walk + hash. `graphReused` tells the commit step that the
  # on-disk snapshot is already current, so it can skip redundant re-materialization
  # while keeping I3 unconditional side effects. Any doubt -> full rebuild (fail-closed).
  let (graph, graphReused) = loadOrBuildGlobalSymbolGraph(cwd)
  # X1 canonical boundary: TrustCommit reads the CANONICAL projection
  # (UniverseIntegrityProjection from the merged rows) instead of the
  # last-wave report — wave-1 verified units now reach the TrustCommit
  # (natural consequence of the canonical boundary migration).
  let commitRes = commitUniverseIntegrityAndLock(cwd, graph, vkdFixed4, caller = AuthorizedLockCaller, updateLock = updateLock or flags.updateLock, graphReused = graphReused, nodeReports = UniverseIntegrityProjection(proofReport.canonicalRunResult))
  if commitRes.isErr():
    return err(CliError(kind: CliOutcome.INTERNAL_ERROR, msg: commitRes.error))

  # §10/D3: subject identity projection in runtimeMeta (excluded from canonical byte-comparison).
  if projectAbs.len > 0:
    let stateRootPresent = stateRootForRuntimeMeta.len > 0
    reportJson["runtimeMeta"] = %*{
      "subject": %*{
        "sourceFingerprint": subjectForRuntimeMeta.sourceFingerprint,
        "lockfileDigest": subjectForRuntimeMeta.lockfileDigest,
        "dependencyFingerprint": subjectForRuntimeMeta.dependencyFingerprint,
        "toolchainFingerprint": subjectForRuntimeMeta.toolchainFingerprint,
        "hasSubmodules": hasSubmodulesForRuntimeMeta,
        "discoveryFallback": usedFallbackForRuntimeMeta,
        "stateRootPresent": stateRootPresent
      }
    }
    proofReport.outputJson = renderJsonMultiline(reportJson)

  ok(proofReport)
{.pop.}
