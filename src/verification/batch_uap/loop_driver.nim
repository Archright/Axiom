import core/trusted/layer_declaration
axiomLayer "infrastructure"
import cli/selection_state
import core/axiom_pragmas
import core/contracts/universal_pipeline_contract
import core/function_verification_summary
import core/orchestration/pipeline_dispatch
import core/orchestrator/orchestrator_types
import core/orchestrator/orchestrator_vault
import core/parsers/safe_parsers
import std/math
import core/pipeline_core_types
import core/proof/proof_budget
import core/proof/source_fingerprint
import core/results
import core/sorter/sorter_core
import core/sync/sync_utils_resource
import core/topology/topology_engine
import core/trusted/stdlib_shield
import core/trusted/verification_result_types
import core/types/refactor_task_types
import core/types/solver_types
import core/utils/constants
import core/crypto/hash_kernel
import infrastructure/process_utils
import sieve/sieve_refactor_bridge
import std/algorithm
import std/json
import std/monotimes
import std/options
import std/os
import std/sets
import std/strutils
import std/tables
import checksums/sha2
import verification/batch_uap/certificate_hydration_runner
import verification/obligation/lean_kernel_boundary
import verification/batch_uap/ir_pipeline_runner
import verification/batch_uap/loop_depth_scheduler
import verification/batch_uap/loop_topology
import verification/batch_uap/private/request_builder
import verification/batch_uap/private/types
import verification/batch_uap/stages  # Phase 3: extracted pipeline stages
import verification/certificate_hydration
import verification/cert_promotion  ## R8: mandatory canonical promotion + promotion-eligibility status gate
import verification/certificate_eligibility  ## P4: hasSemanticEvidence for 4-way promotion classification
import verification/cert_writer
import verification/io_axiom_builder
import verification/pipeline_state_types
import verification/solver/z3_pool  ## pool sizing: maxWorkers >= AXIOM_PROVE_WORKERS
import verification/unified_trajectory
import verification/universal_pipeline
import infrastructure/logging_facade
import verification/batch_uap/instrumentation
import verification/batch_uap/pbt_adapter
import verification/obligation/obligation_ir  ## P3: ObligationGenerationResultKind
import verification/obligation/obligation_types  ## DEBT#422: canonical ObligationSkipReason
import verification/obligation/lean_evidence  ## P4: kernel acceptance + evidence validation chain
import verification/obligation/kernel_acceptance_authority  ## S2: CanonicalLeanEvidence
import verification/lean_lsp_compiler

import engine/proof_aggregator  ## AGENT-C: ProofCertificate batch aggregation

export types.BatchUapReport, types.BatchUapProgressSink
export loop_depth_scheduler.FingerprintWorkItem, loop_depth_scheduler.FingerprintResult

# ── Phase 3C: Legacy UAP routing flag ────────────────────────────────
var useLegacyUap* = false
proc setLegacyUapMode*(enabled: bool)  = useLegacyUap = enabled

# ── Batch UAP Typestate Pipeline (Phase 3B) ──────────────────────────
## Typestate pipeline for per-node verification. Each stage transforms
## a payload through a linear state machine: UnverifiedInput →
## CachedPayload → BudgetedPayload → ProvenOutput.
## Early exits (cache hit, pre-sieve block, timeout) are encoded as flags
## in the payload, checked by runBatchUapOrchestration for side effects.

type
  UnverifiedInput* = object
    item*: SorterWorkItem
    nodeIdStr*: string
    matchingReq*: OrchestrationProofRequest
    parts*: NodeIdParts
    nodeTf*: string

  CachedPayload* {.requiresInit.} = object
    nodeId*: SorterNodeId
    nodeIdStr*: string
    uapReq*: UniversalPipelineRequest
    nodeTf*: string
    cacheHit*: bool
    blocked*: bool
    verified*: bool
    summary*: FunctionVerificationSummary
    uapOutput*: UniversalPipelineResult
    sieveProbability*: float
    nestingDepth*: int
    refactorTrigger*: RefactorTask
    hasRefactorTrigger*: bool
    ## VS-1: the shared pre-sieve/blocked decision (stages.decidePreSieveNode),
    ## computed once in stage1CacheCheck and consumed by the driver below —
    ## the driver re-derives nothing, so the sequential and parallel paths
    ## cannot diverge on the admission rule.
    preSieveDecision*: PreSieveNodeDecision

  BudgetedPayload* {.requiresInit.} = object
    nodeId*: SorterNodeId
    nodeIdStr*: string
    uapReq*: UniversalPipelineRequest
    uapOutput*: UniversalPipelineResult
    summary*: FunctionVerificationSummary
    verified*: bool
    timedOut*: bool
    skipReason*: ObligationSkipReason  ## canonical skip classification (DEBT#422)
    skipDetail*: string  ## detail payload for osrObligationTerminal (ogr reason); "" otherwise
    solverMs*: int64
    complexity*: float  ## Cyclomatic complexity from IR pipeline
    obligationVerdict*: Option[ObligationVerdictInfo]  ## P6: carries the actual
      ## obligation-generation verdict (ogrGenerated with real count, or a
      ## terminal/non-generated verdict) into the final node report and the
      ## persisted certificate. Preserved so UAP-verified certs are honest
      ## about WHAT obligation set was proven (missing obligation ≠ PASS).
    ## S2: canonical evidence — populated only when the canonical Lean
    ## verification path produced a genuine KAA.  None on all other paths.
    evidence*: Option[CanonicalLeanEvidence] = none(CanonicalLeanEvidence)

  ProvenOutput* {.requiresInit.} = object
    nodeId*: SorterNodeId
    nodeIdStr*: string
    report*: OrchestrationNodeReport
    summary*: FunctionVerificationSummary
    uapOutput*: UniversalPipelineResult
    verified*: bool
    complexity*: float  ## Cyclomatic complexity from IR pipeline
    certInput*: FinalReportCertInput

proc normalizeScopeModulePath*(rawPath: string): string {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Repo-relative module-path normalization for IR-result attribution —
  ## mirrors scopeRelativeModulePath (axiom_engine vault sync): kernel entries
  ## registered via {.axiom.} carry line-info filenames that may be absolute,
  ## while node ids and synthesized overlay entries carry repo-relative paths.
  ## An absolute path outside the current repo root normalizes to "" (no
  ## attribution — fail-closed direction: unmatched evidence never attaches).
  ## A bare subject-relative module name ("absval.nim") IS a module identity:
  ## external subjects are discovered by file name and the external
  ## materializer records exactly that sourcePath, so it passes through —
  ## attribution still requires the normalized path to equal the node's
  ## module, so a foreign non-module string keeps failing to attach.
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
    if not modulePath.endsWith(".nim"):
      modulePath = ""
  modulePath

proc scopedIrResultForNode(
    irResultMap: Table[string, IrPipelineResult];
    nodeIdStr: string
): IrPipelineResult {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Claim-scoped IR-result attribution. The map is keyed by bare function
  ## name (the wave-facing entry name), but a claim's identity is
  ## (modulePath, functionName) — never the bare name alone. A result attaches
  ## to a node only when its modulePath agrees with the node's module: an
  ## overlay composite's evidence is scoped to its subject module, and a
  ## kernel registry entry's evidence to its own module. Without this guard a
  ## same-named symbol in any other module consumes foreign evidence and mints
  ## a certificate claiming a claim that was never made about it.
  let bareFuncName = extractBareFuncName(sorterNodeId(nodeIdStr))
  var irResult = irResultMap.getOrDefault(bareFuncName)
  if irResult.funcName.len == 0:
    return irResult
  let nodeModule = parseNodeIdParts(nodeIdStr).modulePath
  let resultModule = normalizeScopeModulePath(irResult.modulePath)
  if resultModule.len == 0 or resultModule != nodeModule:
    return IrPipelineResult()
  irResult

proc stage1CacheCheck*(
    input: sink UnverifiedInput;
    vaultDir: string;
    topologyAnalysis: TopologyAnalysis;
    blockThreshold: float;
    maxRounds: int;
    state: var SorterState;
    summarySnapshot: SummaryCache;
    budget: var ProofBudget;
    ioAxiomCount: int;
    irResultMap: Table[string, IrPipelineResult] = initTable[string, IrPipelineResult]()
): CachedPayload {.raises: [CatchableError, IOEffect], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Stage 1: Cache check — type-directed proof, pre-sieve, UAP request
  ## construction, and summary cache lookup. Returns CachedPayload with
  ## flags indicating whether verification was resolved (type-directed,
  ## pre-sieve block, or cache hit) or whether to proceed to stage 2.
  let nodeId = input.item.nodeId
  let nodeIdStr = input.nodeIdStr
  let matchingReq = input.matchingReq
  let parts = input.parts
  let nodeTf = input.nodeTf

  # Look up isKernel/irHash from runtime axiom registry
  var entryIsKernel = false
  var entryIrHash = ""
  if registryLookup.hasKey(parts.functionName):
    let entry = registryLookup[parts.functionName]
    entryIsKernel = entry.isKernel
    entryIrHash = entry.irHash

  # Synthetic irHash for opaque/tryImpl functions without IR
  if entryIrHash.len == 0:
    entryIrHash = $secureHash(Sha_256, parts.modulePath & "::" & parts.functionName)

  # Stage 1a: Type-directed proof (Phase 0)
  let tdResult = tryTypeDirectedProof(
    nodeIdStr, matchingReq.sourceCode, parts.modulePath, parts.functionName,
    vaultDir, nodeTf
  )
  if tdResult.verified:
    return CachedPayload(
      nodeId: nodeId, nodeIdStr: nodeIdStr,
      uapReq: default(UniversalPipelineRequest), nodeTf: "",
      cacheHit: false, blocked: false, verified: true,
      summary: tdResult.summary,
      uapOutput: default(UniversalPipelineResult),
      sieveProbability: 0.0, nestingDepth: 0,
      refactorTrigger: default(RefactorTask), hasRefactorTrigger: false,
      preSieveDecision: psndProceed)

  # Stage 1b: Pre-Sieve Interceptor
  let sieveResult = runPreSieveStage(
    input.item, matchingReq, topologyAnalysis,
    parts.modulePath, parts.functionName,
    blockThreshold = blockThreshold
  )
  let sieveProbability = sieveResult.sieveVerdict.probabilityScore
  let nestingDepth = sieveResult.topoMetric.nestingDepth

  # ── VS-1: the ONE shared admission decision ──────────────────────────
  # stages.decidePreSieveNode encodes the full pre-sieve/blocked rule —
  # deterministic threshold relaxation, the WP4-j C4 fatal-only gate, and
  # the P4 disproof carve-out — and is the SAME rule the parallel worker
  # applies (loop_depth_scheduler stage-5). It is computed once here and
  # recorded on the payload; the driver below re-derives nothing.
  # Claim scoping is the same lookup stage2Budget consumes
  # (scopedIrResultForNode), so the disproof observed here is exactly the
  # one that terminal acts on. Fail-closed: only vsDisproved (the P4
  # finalizer's cvConfirmed promotion) carves out; every demotion
  # (cvSpurious/cvUnresolved, incl. replay disagreement) stays
  # vsInconclusive and keeps the pre-sieve verdict.
  let attemptIR = scopedIrResultForNode(irResultMap, nodeIdStr)
  let preSieveDecision = decidePreSieveNode(
    sieveResult.sieveVerdict, blockThreshold,
    attemptIR.funcName.len > 0,
    attemptIR.verification.status == vsDisproved)

  if sieveResult.sieveVerdict.blocked:
    ## Stage 1b Pre-Sieve Interceptor — Pre-Sieve Admission Boundary (WP4-j C4).
    ## A block is terminal ONLY when it is a genuine fatal input/symbol fault
    ## (non-Nim file, empty source, non-routine symbol). A block that arises
    ## purely from structural opinion fusion (evaluateTopology/evaluateAst)
    ## must not veto a valid Nim routine: obligation synthesis happens in the
    ## IR pipeline AFTER this gate, so gate-on-obligation is impossible here.
    ## Pattern mismatch on the structural opinion is a strategy failure, not a
    ## candidate failure — the routine is handed downstream for obligation-aware
    ## execution instead of being scraped.
    if preSieveDecision == psndPreSieved:
      # S3: Capture refactoring trigger for genuinely fatal pre-sieved nodes
      let refTask = sieveVerdictToRefactorTask(
        nodeId, parts.modulePath, parts.functionName,
        matchingReq.sourceCode, sieveResult.sieveVerdict)
      return CachedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: default(UniversalPipelineRequest), nodeTf: "",
        cacheHit: false, blocked: true, verified: false,
        summary: default(FunctionVerificationSummary),
        uapOutput: default(UniversalPipelineResult),
        sieveProbability: 0.0, nestingDepth: 0,
        refactorTrigger: refTask, hasRefactorTrigger: true,
        preSieveDecision: preSieveDecision)
    # else: carved out — either the block was opinion-only, or it was fatal
    # but a scoped vsDisproved overrides it (P4 disproof carve-out); the node
    # falls through to obligation synthesis + execution.
    if preSieveDecision == psndProceed:
      logInfo("loop_driver", "[PRE-SIEVE CARVE-OUT] " & parts.functionName &
        " — opinion-fusion block overridden, proceeding to obligation pipeline")

  # Stage 1c: Build UAP request with dependency pre-conditions
  let reqResult = buildUapRequestWithDeps(
    matchingReq, vaultDir, maxRounds, state, summarySnapshot
  )
  if not reqResult.success:
    return CachedPayload(
      nodeId: nodeId, nodeIdStr: nodeIdStr,
      uapReq: default(UniversalPipelineRequest), nodeTf: "",
      cacheHit: false, blocked: true, verified: false,
      summary: default(FunctionVerificationSummary),
      uapOutput: default(UniversalPipelineResult),
      sieveProbability: 0.0, nestingDepth: 0,
      refactorTrigger: default(RefactorTask), hasRefactorTrigger: false,
      preSieveDecision: decideBlockedNodeTerminal(
        attemptIR.funcName.len > 0,
        attemptIR.verification.status == vsDisproved))

  let uapReq = reqResult.uapReq

  # Stage 1d: Summary cache check
  let cacheKey = makeCacheKey(uapReq.modulePath, uapReq.functionName)
  if summarySnapshot.hasKey(cacheKey):
    let cached = summarySnapshot[cacheKey]
    if cached.checksum == nodeTf:
      return CachedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, nodeTf: nodeTf,
        cacheHit: true, blocked: false, verified: true, summary: cached,
        uapOutput: default(UniversalPipelineResult),
        sieveProbability: 0.0, nestingDepth: 0,
        refactorTrigger: default(RefactorTask), hasRefactorTrigger: false,
        preSieveDecision: psndProceed)

  CachedPayload(
    nodeId: nodeId, nodeIdStr: nodeIdStr,
    uapReq: uapReq, nodeTf: nodeTf,
    cacheHit: false, blocked: false, verified: false,
    summary: default(FunctionVerificationSummary),
    uapOutput: default(UniversalPipelineResult),
    sieveProbability: sieveProbability,
    nestingDepth: nestingDepth,
    refactorTrigger: default(RefactorTask), hasRefactorTrigger: false,
    preSieveDecision: preSieveDecision)

proc runLeanVerification(leanSource: string, kernelName: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## P4 evidence chain: Obligation binding → Lean kernel acceptance →
  ## Axiom-owned validation (artifact pin, sorry absence, axiom profile,
  ## negative-mutation non-vacuity). `true` is returned only when the full
  ## validation pipeline would emit a LeanEvidence — never on text inference.
  if leanSource.len == 0:
    return false
  if leanSource.contains("sorry"):
    logWarn("loop_driver", "[LEAN SORRY] " & kernelName & ": source contains sorry")
    return false
  let theoremName = extractTheoremName(leanSource)
  # L3 Binding: the artifact's theorem name IS the obligation handle at this
  # integration point (irToLeanModule emits `theorem <fn>_post<N>` or
  # `<fn>`). Binding to the extracted name keeps the artifact↔obligation link
  # one-to-one; validateEvidence re-checks it against the artifact.
  let binding = bindObligation(theoremName, "", leanSource)
  let kernelR = canonicalLeanKernelCheck(leanSource, timeoutMs = 120_000)
  if kernelR.isErr:
    logWarn("loop_driver", "[LEAN ERROR] " & kernelName & ": " & kernelR.error)
    return false
  let kernelReceipt = kernelR.get
  let kernel = LeanKernelResult(
    kernelAccepted: true,
    exitStatus: 0,
    diagnostics: receiptKernelObservation(kernelReceipt),
    diagnosticsHash: sha256Hex(receiptKernelObservation(kernelReceipt))
  )
  if not kernel.kernelAccepted:
    let lines = kernel.diagnostics.splitLines()
    logWarn("loop_driver", "[LEAN ERROR] " & kernelName & ": " &
      lines[0 ..< min(3, lines.len)].join(" | "))
    return false
  let evR = validateEvidence(
      binding, kernel, leanSource,
      axiomTarget = theoremName,
      expectedArtifactHash = sha256Hex(leanSource),
      timeoutMs = 120_000)
  if evR.isErr:
    let reason = evR.error
    let brief = if reason.len > 200: reason[0 ..< 200] & "..." else: reason
    if reason.contains("sorry"):
      logWarn("loop_driver", "[LEAN SORRY IN OUTPUT] " & kernelName & ": " & brief)
    elif reason.contains("negative mutation") or reason.contains("vacuous") or
         reason.contains("trivial"):
      logWarn("loop_driver", "[VACUOUS] " & kernelName & ": " & brief)
    else:
      logWarn("loop_driver", "[LEAN ERROR] " & kernelName & ": " & brief)
    return false
  result = true

proc stage2Budget*(
    prev: sink CachedPayload;
    budget: var ProofBudget;
    matchingReq: OrchestrationProofRequest;
    irResultMap: Table[string, IrPipelineResult] = initTable[string, IrPipelineResult]()
): BudgetedPayload {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Stage 2: Budget and proof — consume gas, attempt spacer CHC bypass,
  ## run UAP pipeline. Returns BudgetedPayload with verification result
  ## or timeout flag.
  let nodeId = prev.nodeId
  let nodeIdStr = prev.nodeIdStr
  let uapReq = prev.uapReq
  let nodeTf = prev.nodeTf

  # Check IR pipeline results for short-circuit (claim-scoped — module+name,
  # never the bare name alone)
  let bareFuncName = extractBareFuncName(nodeId)
  let irResult = scopedIrResultForNode(irResultMap, nodeIdStr)
  let irComplexity = if irResult.funcName.len > 0: irResult.complexity else: 0.0
  if irResult.funcName.len > 0:
    # S2 rev.4: canonical-success terminal branch — FORWARD-ONLY. The typed
    # CanonicalLeanEvidence object is created exactly once inside
    # executeCanonicalVerification (after genuine kernel ACCEPT → bindReceipt →
    # KAA), so its EXISTENCE is the verified state. stage2 does not re-derive
    # verified=true from backend/provenance tag patterns here; it propagates
    # the immutable evidence object downstream. Z3 evidence is forwarded only
    # when the pipeline actually ran the solver leg on the same postcondition
    # (irResult.z3Sat + non-empty smtScript); an absent leg stays absent.
    if irResult.evidence.isSome():
      var uapOutput = default(UniversalPipelineResult)
      uapOutput.leanTrack.verified = true
      uapOutput.leanTrack.theoremSource = irResult.evidence.get().cleLeanSource
      if irResult.z3Sat and irResult.smtScript.len > 0:
        uapOutput.translation.smt2 = irResult.smtScript
        uapOutput.smtTrack.solverStatus = "unsat"
        uapOutput.smtTrack.verified = true
      return BudgetedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, uapOutput: uapOutput,
        summary: default(FunctionVerificationSummary), verified: true,
        timedOut: false, skipReason: osrNone, skipDetail: "", solverMs: 0, complexity: irComplexity,
        obligationVerdict: some(irResult.obligationVerdict),
        evidence: irResult.evidence)
    if irResult.verification.reason == rkNoObligation:
      # Genuinely nothing to prove: no postcondition/property and no semantic
      # obligation. Distinct from "not encodable" (rkNotEncodable) — this is a
      # vacuous-by-contract skip, not a backend inability. Kept out of the
      # bmc_skipped group so VKD telemetry can distinguish "no property exists"
      # from "property exists but encoding failed".
      return BudgetedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, uapOutput: default(UniversalPipelineResult),
        summary: default(FunctionVerificationSummary), verified: false,
        timedOut: false, skipReason: osrNoObligation, skipDetail: "", solverMs: 0, complexity: irComplexity,
        obligationVerdict: some(irResult.obligationVerdict),
        evidence: none(CanonicalLeanEvidence))
    # P3: Obligation generation verdict — handle non-generated branches.
    # ogrNoApplicableObligation maps to the existing no_obligation path
    # (same semantics as rkNoObligation — proven absence of obligations).
    if irResult.obligationVerdict.kind == ogrNoApplicableObligation:
      return BudgetedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, uapOutput: default(UniversalPipelineResult),
        summary: default(FunctionVerificationSummary), verified: false,
        timedOut: false, skipReason: osrNoObligation, skipDetail: "", solverMs: 0, complexity: irComplexity,
        obligationVerdict: some(irResult.obligationVerdict),
        evidence: none(CanonicalLeanEvidence))
    # ogrUnsupported / ogrIllFormed — terminal: obligation generator
    # could not produce a verifiable obligation. Use a distinctive
    # skipReason so the main loop maps to orchestrationNotVerifiable.
    # The reason detail is carried in skipDetail for downstream logging.
    if irResult.obligationVerdict.kind in {ogrUnsupported, ogrIllFormed}:
      return BudgetedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, uapOutput: default(UniversalPipelineResult),
        summary: default(FunctionVerificationSummary), verified: false,
        timedOut: false, skipReason: osrObligationTerminal, skipDetail: irResult.obligationVerdict.reason, solverMs: 0, complexity: irComplexity,
        obligationVerdict: some(irResult.obligationVerdict),
        evidence: none(CanonicalLeanEvidence))
    if irResult.verification.reason in {rkNotEncodable, rkNoProperty, rkUnsupportedTheory}:
      # BMC-skipped: string/float functions — do NOT fall through to legacy UAP
      return BudgetedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, uapOutput: default(UniversalPipelineResult),
        summary: default(FunctionVerificationSummary), verified: false,
        timedOut: false, skipReason: osrBmcSkipped, skipDetail: "", solverMs: 0, complexity: irComplexity,
        obligationVerdict: some(irResult.obligationVerdict),
        evidence: none(CanonicalLeanEvidence))
    if isUnboundedProved(irResult.verification):
      # Spacer/CHC verified an inductive invariant for a symbolic-bound loop.
      # Loop soundness is established by the CHC solver, so treat as verified
      # (analogous to the Z3-unsat path) — no legacy UAP fallback needed.
      # CHC-verified loops carry no Lean source (leanSource == ""), so Lean
      # replay is intentionally skipped for this path.
      let leanOk = runLeanVerification(irResult.leanSource, bareFuncName)
      var uapOutput = default(UniversalPipelineResult)
      uapOutput.smtTrack.solverStatus = "sat"
      uapOutput.smtTrack.verified = true
      uapOutput.leanTrack.verified = leanOk
      uapOutput.provenLayer = if leanOk: plkL4Judge else: plkL1Bmc
      let summary = FunctionVerificationSummary(
        functionName: uapReq.functionName,
        modulePath: uapReq.modulePath,
        preConditions: uapReq.preConditions,
        postConditions: uapReq.postConditions,
        provenLayer: uapOutput.provenLayer,
        checksum: nodeTf,
        complexityClass: buapClassifySourceComplexity(uapReq.sourceCode, uapReq.functionName),
        vacuityProven: false,
        vkdFixed4: ""
      )
      return BudgetedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, uapOutput: uapOutput,
        summary: summary, verified: true,
        timedOut: false, skipReason: osrNone, skipDetail: "", solverMs: 0, complexity: irComplexity,
        obligationVerdict: some(irResult.obligationVerdict),
        evidence: none(CanonicalLeanEvidence))
    if irResult.verification.status == vsDisproved:
      # P4-promoted disproof (cvConfirmed → vsDisproved, I3 binding) — the
      # claim is REFUTED: the same hard-failure terminal the solver-lane
      # branch below issues, reached through the C20 route where the verdict
      # authority is the P4 witness admission (BMC SAT leaves provenance
      # pkNone, so that branch can no longer see this outcome). Without this
      # terminal a refuted claim silently falls to the legacy UAP path and
      # misclassifies as no-obligation (observed 2026-10-10, base36 C_out
      # spin). Fail-closed direction: only the P4 finalizer's cvConfirmed
      # promotion produces vsDisproved (counterexample_validator.nim) — every
      # demotion (cvSpurious/cvUnresolved, incl. replay disagreement) stays
      # vsInconclusive and keeps the legacy fall-through.
      return BudgetedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, uapOutput: default(UniversalPipelineResult),
        summary: default(FunctionVerificationSummary), verified: false,
        timedOut: false, skipReason: osrNone, skipDetail: "", solverMs: 0, complexity: irComplexity,
        obligationVerdict: some(irResult.obligationVerdict),
        evidence: none(CanonicalLeanEvidence))
    if irResult.provenance == vpZ3Bmc and not irResult.z3Sat:
      # Z3 returned SAT (counterexample found) — hard failure, do not proceed to legacy UAP
      return BudgetedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, uapOutput: default(UniversalPipelineResult),
        summary: default(FunctionVerificationSummary), verified: false,
        timedOut: false, skipReason: osrNone, skipDetail: "", solverMs: 0, complexity: irComplexity,
        obligationVerdict: some(irResult.obligationVerdict),
        evidence: none(CanonicalLeanEvidence))
    if irResult.obligationVerdict.kind == ogrGenerated and
        irResult.verification.solverStatus == solverSat:
      # A generated obligation set whose Z3 verdict is SAT is a deterministic
      # counterexample — a falsified declared contract — not an inconclusive.
      # Fail the node here instead of falling through to the legacy UAP path,
      # which would reclassify a refuted claim (the same misclassification the
      # vsDisproved and BMC-SAT terminals above exist for). Scoped to
      # obligation-bearing results so solver-layer SAT elsewhere is untouched.
      return BudgetedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, uapOutput: default(UniversalPipelineResult),
        summary: default(FunctionVerificationSummary), verified: false,
        timedOut: false, skipReason: osrNone, skipDetail: "", solverMs: 0, complexity: irComplexity,
        obligationVerdict: some(irResult.obligationVerdict),
        evidence: none(CanonicalLeanEvidence))
    if irResult.z3Sat:
      # IR pipeline confirmed Z3 unsat — run Lean verification
      let leanOk = runLeanVerification(irResult.leanSource, bareFuncName)
      var uapOutput = default(UniversalPipelineResult)
      uapOutput.smtTrack.solverStatus = "unsat"
      # Carry the actual Z3 SMT-LIB script forwarded to the solver into the
      # translation evidence so the honest cert writer binds real solver input
      # (solverHasExecuted => z3Executed=true) instead of a blank-input digest.
      uapOutput.translation.smt2 = irResult.smtScript
      uapOutput.smtTrack.verified = true
      uapOutput.leanTrack.verified = leanOk
      uapOutput.provenLayer = if leanOk: plkL4Judge else: plkL1Bmc
      let summary = FunctionVerificationSummary(
        functionName: uapReq.functionName,
        modulePath: uapReq.modulePath,
        preConditions: uapReq.preConditions,
        postConditions: uapReq.postConditions,
        provenLayer: uapOutput.provenLayer,
        checksum: nodeTf,
        complexityClass: buapClassifySourceComplexity(uapReq.sourceCode, uapReq.functionName),
        vacuityProven: false,
        vkdFixed4: ""
      )
      return BudgetedPayload(
        nodeId: nodeId, nodeIdStr: nodeIdStr,
        uapReq: uapReq, uapOutput: uapOutput,
        summary: summary, verified: true,
        timedOut: false, skipReason: osrNone, skipDetail: "", solverMs: 0, complexity: irComplexity,
        obligationVerdict: some(irResult.obligationVerdict),
        evidence: none(CanonicalLeanEvidence))

  # Stage 2a: Gas cost computation and per-unit budget check.
  # Each unit's budget is derived from its own complexity signals
  # (topologyScore, sieveProbability, nestingDepth) — independent
  # of the run-global frontier size.  The shared budget is
  # consumed here for aggregate reporting only; verdicts are
  # driven by the per-unit budget.
  let gasResult = computeGasCost(
    matchingReq.topologyScore, prev.sieveProbability, prev.nestingDepth
  )
  let entropySignals = ComplexitySignals(
    topologyScore: float(clamp(matchingReq.topologyScore, 0, 100)) / 100.0,
    sieveProbability: prev.sieveProbability,
    cegarIterations: 0,
    cegarStagnationCount: 0,
    z3RejectionCount: 0,
    synergyGeometricMean: 1.0,
    historicalAvgGas: 0.0
  )
  let entropy = computeComplexityEntropy(entropySignals)
  let unitBudget = initPerUnitBudget(
    matchingReq.topologyScore, entropy, prev.nestingDepth,
    getMonoTime().ticks
  )
  let budgetVerdict = checkBudget(unitBudget)
  if budgetVerdict != pbvContinue:
    # Gas/rlimit exhaustion is a deterministic verification FAILURE and travels
    # the `not verified` path (orchestrationProofFailed).  Wall-clock expiry is a
    # hang-guard: the run aborts for this node without a verification verdict.
    return BudgetedPayload(
      nodeId: nodeId, nodeIdStr: nodeIdStr,
      uapReq: uapReq, uapOutput: default(UniversalPipelineResult),
      summary: default(FunctionVerificationSummary), verified: false,
      timedOut: not isDeterministicFailure(budgetVerdict),
      skipReason: osrNone, skipDetail: "", solverMs: 0, complexity: irComplexity,
      obligationVerdict: if irResult.funcName.len > 0: some(irResult.obligationVerdict) else: none(ObligationVerdictInfo),
      evidence: none(CanonicalLeanEvidence))
  discard consumeGas(budget, gasResult.gasCost)

  # Unified solver timing (spacer + UAP)
  let solverStartMono = getMonoTime().ticks

  # Stage 2b: Spacer CHC bypass
  let spacerResult = trySpacerBypass(uapReq, matchingReq, nodeIdStr, nodeTf)
  if spacerResult.bypassed:
    let solverMs = (getMonoTime().ticks - solverStartMono) div 1_000_000
    return BudgetedPayload(
      nodeId: nodeId, nodeIdStr: nodeIdStr,
      uapReq: uapReq, uapOutput: spacerResult.output,
      summary: spacerResult.summary, verified: true,
      timedOut: false, skipReason: osrNone, skipDetail: "", solverMs: solverMs, complexity: irComplexity,
      obligationVerdict: if irResult.funcName.len > 0: some(irResult.obligationVerdict) else: none(ObligationVerdictInfo),
      evidence: none(CanonicalLeanEvidence))

  # Stage 2c: Run UAP pipeline with timeout guard
  let uapOutcome = runUniversalAcceptancePipeline(
    uapReq, createDefaultPipelineDispatch())
  let nodeElapsedMs = (getMonoTime().ticks - solverStartMono) div 1_000_000

  if nodeElapsedMs > nodeWallClockTimeoutMs:
    return BudgetedPayload(
      nodeId: nodeId, nodeIdStr: nodeIdStr,
      uapReq: uapReq, uapOutput: default(UniversalPipelineResult),
      summary: default(FunctionVerificationSummary), verified: false,
      timedOut: true, skipReason: osrNone, skipDetail: "", solverMs: nodeElapsedMs, complexity: irComplexity,
      obligationVerdict: if irResult.funcName.len > 0: some(irResult.obligationVerdict) else: none(ObligationVerdictInfo),
      evidence: none(CanonicalLeanEvidence))

  case uapOutcome.exitKind
  of pekSuccess:
    let uapOutput = uapOutcome.result
    # P3b: Only Lean kernel ACCEPTANCE (leanTrack.verified) constitutes
    # a proven result. provenLayer reflects solver-layer success only
    # and is NOT kernel acceptance — using it as isProven was the
    # authority-bypassing path that allowed VACUOUS nodes to be
    # counted as verified. Fail-closed: no kernel acceptance → not proven.
    let isProven = uapOutput.leanTrack.verified
    let summary = FunctionVerificationSummary(
      functionName: uapReq.functionName,
      modulePath: uapReq.modulePath,
      preConditions: uapReq.preConditions,
      postConditions: uapReq.postConditions,
      invariant: uapOutput.activeInvariant,
      provenLayer: uapOutput.provenLayer,
      checksum: nodeTf,
      complexityClass: buapClassifySourceComplexity(
        uapReq.sourceCode, uapReq.functionName),
      vacuityProven: uapOutput.leanTrack.vacuityProven,
      vkdFixed4: ""
    )
    BudgetedPayload(
      nodeId: nodeId, nodeIdStr: nodeIdStr,
      uapReq: uapReq, uapOutput: uapOutput,
      summary: summary, verified: isProven,
      timedOut: false, skipReason: osrNone, skipDetail: "", solverMs: nodeElapsedMs, complexity: irComplexity,
      obligationVerdict: if irResult.funcName.len > 0: some(irResult.obligationVerdict) else: none(ObligationVerdictInfo),
      evidence: none(CanonicalLeanEvidence))
  of pekFailure:
    BudgetedPayload(
      nodeId: nodeId, nodeIdStr: nodeIdStr,
      uapReq: uapReq, uapOutput: default(UniversalPipelineResult),
      summary: default(FunctionVerificationSummary), verified: false,
      timedOut: false, skipReason: osrNone, skipDetail: "", solverMs: nodeElapsedMs, complexity: irComplexity,
      obligationVerdict: if irResult.funcName.len > 0: some(irResult.obligationVerdict) else: none(ObligationVerdictInfo),
      evidence: none(CanonicalLeanEvidence))

proc stage3Proof*(
    prev: sink BudgetedPayload;
    vaultDir: string
  ): ProvenOutput {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Stage 3: Build final node report from verified payload.
  ## Certificate writing is deferred to main thread for I/O safety.
  let nodeId = prev.nodeId
  let nodeIdStr = prev.nodeIdStr
  let uapReq = prev.uapReq
  let uapOutput = prev.uapOutput

  if not prev.verified or prev.timedOut:
    return ProvenOutput(
      nodeId: nodeId, nodeIdStr: nodeIdStr,
      report: default(OrchestrationNodeReport),
      summary: default(FunctionVerificationSummary),
      uapOutput: uapOutput,
      verified: false, complexity: prev.complexity,
      certInput: FinalReportCertInput(
        status: orchestrationProofFailed,
        modulePath: "", functionName: "", sourceCode: "",
        kernelVerified: false, smtlib2: "", solverStatus: "failed",
        vacuityProven: false, irHash: "", leanProposition: ""
      ))

  let ovKind = if prev.obligationVerdict.isSome:
                 some(prev.obligationVerdict.get.kind)
               else:
                 none(ObligationGenerationResultKind)
  let reportResult = buildFinalNodeReport(nodeId, uapReq, uapOutput, ovKind, prev.evidence)
  var finalReport = reportResult.report
  finalReport.complexity = prev.complexity

  # P3b: Only orchestrationVerified (Lean kernel ACCEPT) is treated as
  # a fully verified success. Z3-only candidate evidence is a success
  # in the sense that evidence was produced, but it is NOT consumed as
  # a verified result downstream. Both statuses enter the success path
  # so the report is recorded and circuit-breaker logic runs; only
  # orchestrationVerified triggers cert write.
  let isSuccess = finalReport.status in {orchestrationVerified}

  var ctx = ProvenOutput(
    nodeId: nodeId, nodeIdStr: nodeIdStr,
    report: finalReport,
    summary: prev.summary,
    uapOutput: uapOutput,
    verified: isSuccess, complexity: prev.complexity,
    certInput: reportResult.certInput
  )
  result = move(ctx)

proc verifyInfrastructure*(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Pre-flight: probe actual Z3/Lean solver execution (not just version check)
  if getEnv("AXIOM_SKIP_SOLVER_CHECK") == "1":
    return true
  logInfo("loop_driver", "Axiom Pre-flight: Probing verification sandbox...")

  # 1. Z3 actual query probe via temp file + execCmdEx
  let z3TmpIn = getTempDir() / "axiom_z3_probe.smt2"
  writeFile(z3TmpIn, "(assert true)\n(check-sat)\n")
  let z3Result = execCmdWithTimeout("z3 " & z3TmpIn, timeoutMs = 30_000)
  safeRemoveFile(z3TmpIn)
  let z3Out = z3Result[0]
  let z3Code = z3Result[1]
  if z3Code != 0 or not z3Out.contains("sat"):
    logError("loop_driver", "CRITICAL: Z3 solver dysfunctional")
    return false

  # 2. Lean lightweight compile probe
  let tmpLean = getTempDir() / "axiom_probe.lean"
  writeFile(tmpLean, "theorem axiomPreFlightProbe : True := trivial\n")
  let leanResult = execCmdWithTimeout("lake env lean " & tmpLean, timeoutMs = 120_000)
  safeRemoveFile(tmpLean)
  let leanCode = leanResult[1]
  if leanCode != 0:
    logError("loop_driver", "CRITICAL: Lean compiler dysfunctional")
    return false

  logInfo("loop_driver", "Axiom Pre-flight: Sandbox probe successful")
  true

proc runBatchUapOrchestration*(
  initialState: SorterState;
  requests: seq[OrchestrationProofRequest];
  vaultDir: string;
 topologyAnalysis: TopologyAnalysis = TopologyAnalysis();
  maxRounds: int = 6;
  progressSink: BatchUapProgressSink = nil;
  gasLimit: int = 0;
  stallCount: int = 0;
  preComputedIrResults: seq[IrPipelineResult] = @[];
  sharedIrMemoCache: Table[string, IrPipelineResult] = initTable[string, IrPipelineResult]();
  skipIrPipeline: bool = false;
  kernelTotal: int = 0;
  targetVkd: string = ""
): BatchUapReport {.raises: [CatchableError, IOEffect], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  if not verifyInfrastructure():
    logError("loop_driver", "Pre-flight check failed. Set AXIOM_SKIP_SOLVER_CHECK=1 to bypass.")
    return BatchUapReport(
      orchestrationReport: OrchestrationReport(),
      uapResults: initTable[string, UniversalPipelineResult](),
      budget: initProofBudget(),
      refactorTasks: @[])

  generatePbtRegistry()
  logInfo("loop_driver", "PBT Registry: " & $getPbtRegistrySize() & " properties registered")
  if getPbtRegistrySize() == 0:
    logWarn("loop_driver", "PBT Registry empty — empirical functions will be skipped")

  var irResultMap = initTable[string, IrPipelineResult]()
  ## IR pipeline failures collected during candidate selection; folded into the
  ## deterministic outcome state (promoFailedCount + persistFailures) below so
  ## they can never be swallowed as an unobserved integrity-breach log line.
  var irPipelineFailures: seq[string] = @[]

  if not useLegacyUap:
    if skipIrPipeline:
      logInfo("loop_driver", "batch-uap: IR pipeline skipped (parallel background path)")
    elif preComputedIrResults.len > 0:
      logInfo("loop_driver", "batch-uap: IR pipeline — using " & $preComputedIrResults.len &
        " pre-computed results (parallel path)")
      let irResults = preComputedIrResults
      for irResult in irResults:
        if irResult.funcName.len > 0:
          if irResult.funcName in irResultMap:
            logWarn("loop_driver", "Duplicate IR result key (skipping): " & irResult.funcName)
          else:
            irResultMap[irResult.funcName] = irResult
      let irBatch = irResults.toCertificateBatch()
      for cert in irBatch.certificates:
        if cert.status == psSkip:
          logInfo("loop_driver", "IR pipeline skip: " & cert.functionName &
            " status=psSkip provenance=" & cert.provenance &
            " (expected — type not BMC-representable or loop bound unresolved)")
        elif cert.status != psPass:
          logError("loop_driver", "IR pipeline FAIL: " & cert.functionName &
            " status=" & $cert.status & " provenance=" & cert.provenance)
      logInfo("loop_driver", "batch-uap: IR pipeline completed — " & irBatch.formatSummary())
    else:
      let limit = requests.len
      let targetEntries = selectProofCandidates(limit, kernelTotal, targetVkd)
      logInfo("loop_driver", "batch-uap: IR pipeline — processing " & $targetEntries.len &
        "/" & $runtimeAxiomRegistry.len & " registry entries (limit=" & $limit &
        ", sharedCacheKeys=" & $sharedIrMemoCache.len & ")")
      # Seed the CAS-keyed memo cache with the same-run shared results so IR
      # already computed earlier in THIS run (identical inlined funcDef) is
      # reused instead of recomputed. Same-run deterministic-derivation memo
      # only — not persistent, not cross-invocation, not a truth authority.
      var irMemoCache = sharedIrMemoCache
      let irResults = runIrPipelinesFor(targetEntries, irMemoCache)
      let irBatch = irResults.toCertificateBatch()
      for cert in irBatch.certificates:
        if cert.status == psSkip:
          logInfo("loop_driver", "IR pipeline skip: " & cert.functionName &
            " status=psSkip provenance=" & cert.provenance &
            " (expected — type not BMC-representable or loop bound unresolved)")
        elif cert.status != psPass:
          logError("loop_driver", "IR pipeline FAIL: " & cert.functionName &
            " status=" & $cert.status & " provenance=" & cert.provenance)
      logInfo("loop_driver", "batch-uap: IR pipeline completed — " & irBatch.formatSummary())
      ## IR pipeline failures are folded into the promotion classification as
      ## psFail/persist-eligible failures rather than swallowed by a log-only
      ## stub. The symbolic status is already produced by toProofCertificate
      ## (r.success == false → psFail/psError); this records the failed kernels
      ## explicitly so they surface in the state mesh, never as an unobserved
      ## "Integrity Breach" log line.
      for idx in 0 ..< targetEntries.len:
        if idx < irResults.len:
          let irResult = irResults[idx]
          if not irResult.success:
            irPipelineFailures.add(targetEntries[idx].entry.name)
            logError("loop_driver", "IR pipeline FAILED for kernel: " & targetEntries[idx].entry.name &
              " — recorded as verification failure (status=" & $irResult.verification.status & ")")
      for idx in 0 ..< targetEntries.len:
        if idx < irResults.len and irResults[idx].success:
          let mapKey = targetEntries[idx].entry.name
          if mapKey in irResultMap:
            logWarn("loop_driver", "Duplicate IR result key (skipping): " & mapKey)
          else:
            irResultMap[mapKey] = irResults[idx]
  else:
    logInfo("loop_driver", "batch-uap: using LEGACY path (--legacy-uap)")

  # ── P6: OGR/PAR runtime counter aggregation ────────────────
  # Walk irResultMap once to compute additive counters.
  # These are recorded in report.executionStats for JSON output.
  var ogrGeneratedCount = 0
  var ogrAttemptedCount = 0
  var ogrTargetsWithObligations = 0
  var ogrEligibleTargets = irResultMap.len
  for irResult in irResultMap.values:
    if irResult.obligationVerdict.kind == ogrGenerated:
      inc ogrTargetsWithObligations
      ogrGeneratedCount += irResult.obligationVerdict.obligationCount

  var promoVerifiedCount = 0
  var promoNoObligationCount = 0
  var promoUnverifiableCount = 0
  var promoFailedCount = 0
  var nodePromoStatus = orchestrationVerified
  ## IR pipeline failures are verification failures in the state mesh: fold them
  ## into the failed classification and the aggregate node status so a swallowed
  ## IR failure can never present as orchestrationVerified. This is the single
  ## place IR-level failures enter the deterministic outcome state.
  for failedKernel in irPipelineFailures:
    inc promoFailedCount
    nodePromoStatus = orchestrationProofFailed

  var state = initialState
  var report = OrchestrationReport()
  var persistFailures: seq[string] = @[]  ## R8: promotable-cert promotion failures (persist FAIL accumulator)
  ## IR pipeline failures are verification failures of their own kernel units,
  ## NOT persist failures: R8's persist leg covers a VERIFIED node whose
  ## certificate write/canonical promotion failed — an IR-failed kernel produced
  ## no verified node and no promotable certificate, so there is nothing whose
  ## persistence failed. Folding them here reclassified unrelated units'
  ## verification failures onto the persist axis (persistFailed=true, exit 2
  ## INTERNAL_ERROR) and contaminated every other claim's run outcome. They stay
  ## surfaced on the verification axis: promoFailedCount/promotionClassifications
  ## above, the IR batch summary, ERROR logs, and report.irPipelineFailures
  ## (wired by the engine from BatchUapReport.irPipelineFailures).
  var collectedRefactorTasks: seq[RefactorTask]
  var budget = if gasLimit > 0: initProofBudget(gasLimit = gasLimit) else: initProofBudget()
  var uapResults = initTable[string, UniversalPipelineResult]()
  let blockThreshold = computeRelaxedThreshold(stallCount)

  # Transitive source cache for deterministic dependency-aware memoization.
  # Seed with the request table; dependency sources are read on demand and
  # cached across all nodes in this batch.
  var tfSourceCache = initTable[string, string]()
  for r in requests:
    tfSourceCache[sorterNodeIdString(r.nodeId)] = computeStableSourceFingerprint(r.sourceCode)
  var tfMemo = initTable[string, string]()

  # Circuit Breaker: Leanstral supply chain collapse detection
  # Bounded step function: deterministic thresholds by batch size
  let circuitBreakerThreshold = if requests.len <= 4: 2
                                 elif requests.len <= 20: 5
                                 else: 10
  var leanstralFailureStreak = 0
  var circuitBroken = false

  # AGENT-D: Deterministic scheduler timing instrumentation
  var timingLog = initTimingLog()

  # Load I/O axiom table once at pipeline initialization
  let ioAxiomTable = loadIoAxiomTable()

  # Phase 2: AXIOM_PROVE_WORKERS env var controls parallelism (default 1)
  var workerCount = 1
  let workersEnv = getEnv("AXIOM_PROVE_WORKERS", "1")
  let parsedWorkers = safeParseInt(workersEnv)
  if parsedWorkers.isErr():
    workerCount = 1
  else:
    workerCount = parsedWorkers.get()
  if workerCount < 1:
    workerCount = 1
  # Size the Z3 pool to the actual parallelism before the depth loop: each
  # worker thread leases a distinct z3 process per query (z3_pool lease), so
  # a pool smaller than the thread count would serialize every thread onto
  # one z3 pipe.
  z3EnsurePersistentPool(workerCount)

  # Step 1: Incremental verification — skip already-proven nodes
  logInfo("loop_driver", "priming fingerprint cache (" & $requests.len & " nodes)...")
  ## R7 determinism: the "ready" line carries no wall-clock timing; priming
  ## duration is captured in executionStats/JSON only.
  primeTransitiveFingerprintCache(state, report, requests, vaultDir, nil)
  logInfo("loop_driver", "fingerprint cache ready")

  # Step 2: Build work plan from topological sort
  let plan = buildSorterPlan(state)

  # Step 2b: Content-Addressed Certificate Hydration Pre-Pass
  # Delegated to certificate_hydration_runner to keep this module under the
  # 500-line limit.
  runCertificateHydrationPrePass(state, plan, requests, report, progressSink)

  # Step 3: Process by dependency depth (topological order)
  let effectiveNodeLimit = requests.len
  ## D1 fix: snapshot primed count so depth-loop limit counts only NEW reports.
  ## primeTransitiveFingerprintCache + runCertificateHydrationPrePass add reports
  ## to report.nodeReports before this loop; those must not count toward the limit.
  let primedReportCount = report.nodeReports.len
  logInfo("loop_driver", "verifying " & $effectiveNodeLimit & " nodes (primed=" & $primedReportCount & ")...")

  # W3-D: Build immutable depth plan via loop_topology
  let depthPlan = buildDepthPlan(plan.workItems, primedReportCount, effectiveNodeLimit)

  # Build request lookup table for O(1) access across all depths
  let requestMap = buildRequestMap(requests)

  ## Fuel counter: deterministic, CPU-independent termination bound.
  ## Complements wall-clock timeout with a step-count guarantee.
  var remainingFuel = DefaultOrchestratorFuel

  for depth in 0 .. depthPlan.maxDepth:
    ## Deterministic termination via loop_topology predicate
    let newReportCount = report.nodeReports.len - depthPlan.primedReportCount
    if not shouldContinueDepth(newReportCount, depthPlan.effectiveNodeLimit, remainingFuel):
      break
    let depthItems = depthPlan.depthToItems.getOrDefault(depth, @[])
    var depthFailed = false
    let depthStartMs = getMonoTime().ticks div 1_000_000
    var depthSolverMs = 0'i64
    var maxNodeMs = 0'i64

    if workerCount > 1 and depthItems.len > 1:
      # AGENT-D: Deterministic scheduler — sort depth items for deterministic parallel dispatch.
      # Sort by nodeId string to guarantee identical processing order regardless of
      # topological insertion order within the same dependency depth level.
      var sortedDepthItems = depthItems
      sortedDepthItems.sort(proc(a, b: SorterWorkItem): int =
        cmp(sorterNodeIdString(a.nodeId), sorterNodeIdString(b.nodeId))
      )
      logInfo("loop_driver", "deterministic-scheduler: depth=" & $depth &
        " items=" & $sortedDepthItems.len & " workers=" & $workerCount)

      # Phase 2: Parallel execution via createThread + Channel (deterministic order)
      let parallelStartMs = getMonoTime().ticks
      block parallelExec:
        var parallelResult = false
        try:
          # P3b mirror input: nodes whose scoped IR evidence carries generated
          # obligations must not be terminated by the contract-blind
          # type-directed stage in the parallel path either — the same gate
          # the sequential path applies at its stage-1 early exits.
          # VS-1 parity inputs are derived from the SAME claim-scoped lookup
          # the sequential path consumes (scopedIrResultForNode): the
          # P4 confirmed-disproof nodes (disprovedNodes — the carve-out set,
          # derived deterministically in string-sorted order) and the
          # per-node obligation counts the parallel aggregation needs to
          # mirror the sequential P6 attempt accounting.
          var obligationBearingNodes = initHashSet[string]()
          var obligationAttemptCounts = initTable[string, int]()
          var disprovedNodeStrs: seq[string] = @[]
          for item in sortedDepthItems:
            let itemNodeStr = sorterNodeIdString(item.nodeId)
            let itemIR = scopedIrResultForNode(irResultMap, itemNodeStr)
            if itemIR.funcName.len > 0:
              if itemIR.obligationVerdict.kind == ogrGenerated:
                obligationBearingNodes.incl itemNodeStr
                obligationAttemptCounts[itemNodeStr] =
                  itemIR.obligationVerdict.obligationCount
              if itemIR.verification.status == vsDisproved:
                disprovedNodeStrs.add(itemNodeStr)
          disprovedNodeStrs.sort()  # deterministic string-sorted derivation
          var disprovedNodes = initHashSet[string]()
          for ds in disprovedNodeStrs:
            disprovedNodes.incl(ds)
          parallelResult = runParallelDepthBatchUap(
            state, report, uapResults, sortedDepthItems, obligationBearingNodes,
            disprovedNodes, obligationAttemptCounts,
            requests,
            vaultDir, topologyAnalysis, maxRounds, budget, ogrAttemptedCount,
            leanstralFailureStreak, circuitBroken, circuitBreakerThreshold,
            tfSourceCache, tfMemo, ioAxiomTable.len, blockThreshold,
            workerCount, progressSink,
            collectedRefactorTasks
          )
        except CatchableError as e:
          raise (ref CatchableError)(msg: e.msg)
        depthFailed = not parallelResult
      let parallelElapsedMs = float(getMonoTime().ticks - parallelStartMs) / 1_000_000
      timingLog.recordEntry("depth-" & $depth & "-parallel", parallelElapsedMs)
    else:
      # Sequential execution via typestate pipeline
      # Build HashSet via loop_topology for O(1) "already verified" lookups
      var verifiedIds = computeVerifiedIds(report.nodeReports)
      for item in depthItems:
        let nodeIdStr = sorterNodeIdString(item.nodeId)

        # Check if already verified by cache — O(1) lookup
        if string(item.nodeId) in verifiedIds:
          inc report.executionStats.cacheHitCount
          continue

        # Node limit: count only NEW reports (total - primed).
        if effectiveNodeLimit > 0 and (report.nodeReports.len - primedReportCount) >= effectiveNodeLimit:
          break

        # Find matching request
        let (matchingReq, found) = findMatchingRequest(item.nodeId, requestMap)
        if not found:
          continue

        # Parse node ID parts
        let parts = parseNodeIdParts(nodeIdStr)

        # Compute transitive fingerprint once
        let nodeTf = computeTransitiveFingerprintWithCaches(
          state, nodeIdStr, tfSourceCache, tfMemo, engineSalt="")

        # ── Typestate pipeline: Stage 1 (Cache Check) ──────────
        var unverified = UnverifiedInput(
          item: item, nodeIdStr: nodeIdStr,
          matchingReq: matchingReq, parts: parts, nodeTf: nodeTf)
        var cached = stage1CacheCheck(move(unverified),
          vaultDir, topologyAnalysis, blockThreshold, maxRounds,
          state, summaryCache, budget, ioAxiomTable.len, irResultMap)

        # ── P6: obligation attempt accounting ──────────────
        # A node counts as attempted when its generated obligations are
        # dispatched toward a proof-resolution path IN THIS RUN: type-directed
        # arithmetic proofs, stage-2 CHC/lean attempts, and replay of a
        # persisted verdict (cache-hit) all resolve obligations with
        # evidence. Nodes terminated by the shared admission rule as PRE-SIEVED
        # are excluded — they are classified unverifiable without dispatching
        # their obligations. Placing the count before all early exits keeps
        # OGR/PAR stable regardless of cache warmth (deterministic metrics,
        # not just deterministic logs).
        # Attribution is decided once and shared: the P6 attempt accounting
        # and the stage-1 termination gate below both key off the SAME
        # decision stage1CacheCheck recorded on the payload (VS-1 shared
        # rule), and the parallel aggregation mirrors exactly this predicate.
        let attemptIR = scopedIrResultForNode(irResultMap, nodeIdStr)
        let preSieveDecision = cached.preSieveDecision

        # A carved-out node reaches the disproof terminal, so its generated
        # obligations ARE attempted: the P6 accounting counts them (the
        # `not cached.blocked` guard predates the carve-out and silently
        # dropped them).
        if preSieveAttemptsObligations(preSieveDecision):
          if attemptIR.funcName.len > 0 and
              attemptIR.obligationVerdict.kind == ogrGenerated:
            ogrAttemptedCount += attemptIR.obligationVerdict.obligationCount

        # Handle stage 1 early exits
        if cached.verified and cached.cacheHit:
          # Summary cache hit
          uapResults[nodeIdStr] = buildCachedResult(nodeTf,
            cached.summary, nodeIdStr)
          inc report.executionStats.cacheHitCount
          inc report.executionStats.solverInvocationCount
          if progressSink != nil:
            progressSink(nodeIdStr, "CACHE-HIT")
          continue

        if cached.verified and not (attemptIR.funcName.len > 0 and
            attemptIR.obligationVerdict.kind == ogrGenerated):
          # Type-directed proof succeeded — arithmetic proof, not z3/lean tier.
          # P3b: No Lean kernel acceptance evidence → fail-closed.
          # This is a candidate proof, not orchestrationVerified.
          # A type-directed result alone never terminates an obligation-
          # bearing node: the stage-1a self-equivalence query is contract-
          # blind (the declared post is not part of the query), so its
          # verdict cannot adjudicate a declared contract. Obligation-bearing
          # nodes fall through to stage-2Budget, which adjudicates from the
          # IR obligation evidence and never reads this cached.verified.
          report.nodeReports.add(OrchestrationNodeReport(
            nodeId: item.nodeId,
            status: orchestrationProofFailed,
            evidenceLogJson: "TYPE-DIRECTED (candidate only, no kernel acceptance): arithmetic proof",
            assuranceTier: "unknown",
            tierResolution: "unavailable"
          ))
          report.executionStats.solverInvocationCount += 1
          if progressSink != nil:
            progressSink(nodeIdStr, "TYPE-DIRECTED-CANDIDATE")
          logInfo("loop_driver", "  [" & $report.nodeReports.len &
            "/" & $requests.len & "] " & nodeIdStr & " — candidate (no kernel acceptance)")
          continue

        if preSieveDecision == psndPreSieved:
          # Shared-rule terminal: fatal pre-sieve block (or UAP request build
          # failure) with no scoped disproof — VS-1 keeps this gate and the
          # P6 accounting above keyed to the ONE recorded decision, and the
          # parallel worker applies the identical rule at its stage-5.
          report.nodeReports.add(OrchestrationNodeReport(
            nodeId: item.nodeId,
            status: orchestrationPreSievedUnverifiable,
            evidenceLogJson: "PRE-SIEVED",
            assuranceTier: "unknown",
            tierResolution: "unavailable"
          ))
          # S3: Collect refactoring triggers from PRE-SIEVED nodes
          if cached.hasRefactorTrigger:
            collectedRefactorTasks.add(cached.refactorTrigger)
          if progressSink != nil:
            progressSink(nodeIdStr, "PRE-SIEVED")
          logInfo("loop_driver", "  [" & $report.nodeReports.len &
            "/" & $requests.len & "] " & nodeIdStr & " — pre-sieved")
          continue

        # ── Typestate pipeline: Stage 2 (Budget & Proof) ─────
        if progressSink != nil:
          progressSink(nodeIdStr, "verifying")
        logStage(skSwat, nodeIdStr, "verifying", status=ssStarted)
        inc report.executionStats.solverInvocationCount

        var budgeted = stage2Budget(move(cached), budget, matchingReq, irResultMap)

        # Accumulate solver timing for depth stats
        depthSolverMs += budgeted.solverMs
        if budgeted.solverMs > maxNodeMs:
          maxNodeMs = budgeted.solverMs

        if budgeted.timedOut:
          report.nodeReports.add(OrchestrationNodeReport(
            nodeId: item.nodeId,
            status: orchestrationTimedOut,
            evidenceLogJson: "node timeout during UAP",
            assuranceTier: "unknown",
            tierResolution: "unavailable"
          ))
          logInfo("loop_driver", "  [" & $report.nodeReports.len &
            "/" & $requests.len & "] " & nodeIdStr & " — timed out")
          continue

        if not budgeted.verified:
          # UAP failed, skipped by theory, or obligation terminal.
          # P3: osrObligationTerminal maps to orchestrationNotVerifiable
          # (terminal but preserves reproduction detail in evidenceLogJson).
          let status = if budgeted.skipReason == osrBmcSkipped:
              orchestrationSkippedByTheory
            elif budgeted.skipReason == osrObligationTerminal:
              orchestrationNotVerifiable
            else:
              orchestrationProofFailed
          logStage(skSwat, nodeIdStr,
            if status == orchestrationSkippedByTheory:
              "Skipped by theory (BMC incompatible)"
            elif status == orchestrationNotVerifiable:
              "Obligation terminal — not verifiable"
            else:
              "UAP failed",
            status = ssFailed)
          report.nodeReports.add(OrchestrationNodeReport(
            nodeId: item.nodeId,
            status: status,
            evidenceLogJson: if status == orchestrationSkippedByTheory:
                "UAP skipped by theory (BMC incompatible)"
              elif status == orchestrationNotVerifiable:
                if budgeted.skipDetail.len > 0: budgeted.skipDetail else: $budgeted.skipReason
              else:
                "UAP failed",
            assuranceTier: "unknown",
            tierResolution: "unavailable"
          ))
          logError("loop_driver", "  [" & $report.nodeReports.len &
            "/" & $requests.len & "] " & nodeIdStr &
            (if status == orchestrationSkippedByTheory:
                " — skipped by theory"
              elif status == orchestrationNotVerifiable:
                if budgeted.skipDetail.len > 0: " — obligation terminal: " & budgeted.skipDetail
                else: " — obligation terminal"
              else:
                " — failed"))
          continue

        # ── Typestate pipeline: Stage 3 (Proven Output) ──────
        let proven = stage3Proof(move(budgeted), vaultDir)

        if proven.verified:
          # UAP success — store result and update circuit breaker
          uapResults[nodeIdStr] = proven.uapOutput
          storeSummary(summaryCache, proven.summary)

          # Circuit Breaker: track verification success/failure
          if proven.summary.provenLayer in {
              plkL1Bmc, plkL2Cegar, plkL2Pdr, plkL3Scribe, plkL4Judge}:
            leanstralFailureStreak = 0
          else:
            inc leanstralFailureStreak
          if leanstralFailureStreak >= circuitBreakerThreshold:
            logStage(skReport, "",
              "CIRCUIT BREAKER: Leanstral 0/" &
              $circuitBreakerThreshold &
              " success — upstream supply chain collapse",
              status=ssSkipped)
            circuitBroken = true
            break

          # Write certificate from main thread (I/O safety, single-threaded vault writes)
          if proven.certInput.status == orchestrationVerified:
            let certDir = vaultDir
            var certLogLines: seq[string] = @[]
            let irHash = sha256Hex(proven.certInput.modulePath & proven.certInput.functionName & proven.certInput.sourceCode)
            let wroteOk = writeCertificateFromUapResult(
              certDir,
              proven.certInput.modulePath,
              proven.certInput.functionName,
              proven.certInput.sourceCode,
              proven.certInput.kernelVerified,
              proven.certInput.smtlib2,
              proven.certInput.solverStatus,
              certLogLines,
              proven.certInput.vacuityProven,
              irHash = irHash,
              leanProposition = proven.certInput.leanProposition,
              negativeTestResult = false,
              obligationVerdict = proven.certInput.obligationVerdict,
              evidence = proven.certInput.evidence
            )
            if not wroteOk:
              # R8 persist leg: the verified node produced NO durable certificate
              # artifact (journalled cert write failed). This is a persist FAIL —
              # the old best-effort `discard` is forbidden; the in-memory verdict
              # alone does not constitute persistence.
              persistFailures.add(nodeIdStr & ": certificate write failed for " & certDir / (irHash & ".json"))
              logError("loop_driver", "PERSIST FAIL: " & nodeIdStr &
                " — verified but certificate not written to " & certDir)
            else:
              # R8 persist leg: a promotable v3 cert written in this run MUST be
              # promoted to the runtime canonical vault (data/trusted/certificates/).
              # Promotion failure on a promotion-eligible cert is a persist FAIL
              # surfaced in the batch report → prove report/exit — never silently
              # swallowed. A genuinely unverifiable node (no promotable cert)
              # stays a verification failure, NOT a persist failure.
              let candidatePath = certDir / (irHash & ".json")
              var certStatus = ""
              var certNode: JsonNode = nil
              try:
                let content = readFile(candidatePath)
                certNode = parseJson(content)
                if certNode.kind == JObject:
                  certStatus = certNode{"status"}.getStr("")
              except CatchableError:
                certStatus = ""
                certNode = nil
              if certNode.isNil or certNode.kind != JObject:
                # Malformed: written but unreadable or not a JSON object → FAIL
                # (fail-closed — structurally malformed candidates are a
                # genuine persistence failure, not a classification issue).
                persistFailures.add(nodeIdStr & ": certificate written but unreadable at " & candidatePath & " — canonical promotion not attempted")
                logError("loop_driver", "PERSIST FAIL: " & nodeIdStr &
                  " — certificate written but unreadable at " & candidatePath)
                inc promoFailedCount
                nodePromoStatus = orchestrationProofFailed
              elif certStatus == "certNoObligation":
                # Explicitly classified as noObligation — not a failure.
                # certNoObligation means the symbol has no verification
                # obligation; it is in the kernel scope but has no evidence
                # to promote. Promotion eligibility ≠ kernel scope membership.
                logInfo("loop_driver", "node " & nodeIdStr &
                  " — certNoObligation; no obligation, not a persist failure")
                inc promoNoObligationCount
                nodePromoStatus = orchestrationNoObligation
              elif not hasSemanticEvidence(certNode):
                # No semantic evidence (no Z3 passed, no Lean verified) →
                # unverifiable/unsupported. NOT a persist failure — the
                # symbol has nothing to prove, but that is not a structural
                # failure of the pipeline.
                logInfo("loop_driver", "node " & nodeIdStr &
                  " — no semantic evidence; unverifiable/unsupported; cert retained, not a persist failure")
                inc promoUnverifiableCount
                nodePromoStatus = orchestrationNotVerifiable
              elif isPromotionAllowedStatus(certStatus):
                # Evidence-ready and status promotion-eligible → promote.
                let promoRes = promoteToCanonical(candidatePath, candidateRoot = certDir)
                if promoRes.isErr:
                  persistFailures.add(nodeIdStr & ": canonical promotion failed for " & candidatePath & ": " & promoRes.error)
                  logError("loop_driver", "PERSIST FAIL: " & nodeIdStr & " — " & promoRes.error)
                  inc promoFailedCount
                  nodePromoStatus = orchestrationProofFailed
                else:
                  logInfo("loop_driver", "node " & nodeIdStr &
                    " — promoted to canonical")
                  inc promoVerifiedCount
                  nodePromoStatus = orchestrationVerified
              else:
                # Has evidence but status not promotion-eligible → transient
                # cert retained. Not a failure — the cert exists but its
                # status doesn't permit promotion (e.g. certZ3Candidate).
                # certNotCurrent / certStale are retained as legacy; they
                # are not promoted and not a failure — they simply lack
                # a current evidence path.
                logWarn("loop_driver", "node " & nodeIdStr &
                  " — cert status " & certStatus & " not promotion-eligible; transient cert retained (not a persist failure)")
                inc promoUnverifiableCount
                nodePromoStatus = orchestrationNotVerifiable

          # P4: Apply the promotion classification to the node report
          # so the status label is honest about the promotion outcome
          # (verified/failed/noObligation/unverifiable), not just the
          # UAP pipeline result. Promotion eligibility ≠ kernel scope
          # membership — a symbol being in scope does not mean it has
          # evidence to promote.
          var finalReport = proven.report
          finalReport.status = nodePromoStatus
          report.nodeReports.add(finalReport)
          # P3b/R3: the stage-3 log label MUST mirror the actual node status, not a
          # blanket "verified". A Z3-only candidate is NOT a lean-kernel VERIFIED.
          # oracleVerificationVerified is the only final VERIFIED.
          let finalStatus = finalReport.status
          logInfo("loop_driver", "  [" & $report.nodeReports.len &
            "/" & $requests.len & "] " & nodeIdStr &
            (if finalStatus == orchestrationVerified: " — verified"
             else: " — " & $finalStatus))
          
          # PBT adapter hook for non-kernel (empirical) functions
          var entryIsKernel = false
          if registryLookup.hasKey(parts.functionName):
            entryIsKernel = registryLookup[parts.functionName].isKernel
          if not entryIsKernel and registryLookup.hasKey(parts.functionName):
            let repoRoot = parentDir(parentDir(vaultDir))
            try:
              executePbtAndWriteCert(registryLookup[parts.functionName], repoRoot)
            except CatchableError as e:
              raise (ref CatchableError)(msg: e.msg)
        else:
          logStage(skSwat, nodeIdStr, "final report build failed",
            status=ssFailed)
          report.nodeReports.add(OrchestrationNodeReport(
            nodeId: item.nodeId,
            status: orchestrationProofFailed,
            evidenceLogJson: "final report build failed"
          ))

    let depthEndMs = getMonoTime().ticks div 1_000_000
    # AGENT-D: Record depth-level timing
    if workerCount <= 1 or depthItems.len <= 1:
      timingLog.recordEntry("depth-" & $depth & "-sequential",
        float(depthEndMs - depthStartMs))
    addDepthExecutionStat(
      report,
      dependencyDepth = depth,
      startedAtMs = depthStartMs,
      endedAtMs = depthEndMs,
      solverElapsedMs = depthSolverMs,
      maxSolverElapsedMs = maxNodeMs,
      activeNodeCount = depthItems.len,
      workerCount = (if workerCount > 1: workerCount else: 1),
      resourceSnapshot = ResourceSnapshot(availableMemoryBytes: 0, cpuLoadRatio: 0.0, recommendedLimit: 0)
    )
    ## Decrement fuel after processing each depth level
    remainingFuel -= FuelPerDepthLevel
    if depthFailed or circuitBroken:
      break

  # AGENT-D: Record total wall time and log timing report.
  # R7 determinism: the full timing report (depth-*, Pipeline total) is
  # profiling output with wall-clock values — emitted only when AXIOM_PROFILE
  # is set, so default runs produce byte-identical logs. Wall-clock totals
  # remain in executionStats (JSON runtimeMeta).
  report.executionStats.totalWallTimeMs = int64(timingLog.pipelineElapsedMs())
  if existsEnv("AXIOM_PROFILE"):
    logInfo("loop_driver", "batch-uap: " & timingLog.formatTimingReport())

  # Verification-Gate (post-execution): verify UAP produced results
  let verifiedCount = uapResults.len
  if requests.len == 0:
    logInfo("loop_driver", "Verification-Gate: 0 UAP requests — UAP execution skipped")
  elif verifiedCount > 0:
    logInfo("loop_driver", "Verification-Gate: " & $verifiedCount & " entries processed by UAP pipeline")
  else:
    logWarn("loop_driver", "Verification-Gate: UAP produced 0 results (requests=" & $requests.len & ")")

  # ── P6: Wire OGR/PAR counters into execution stats ─────────
  # B3: The canonical obligation metrics file (data/metrics/obligation_metrics.json)
  # is NO LONGER written on the prove path. The counters below are preserved on
  # report.executionStats (and serialized into the canonical report document by
  # wf_render), so the canonical verification result is lossless. Persistence of
  # the derived obligation metrics is delegated to the internal MEAS materializer,
  # which consumes a completed report snapshot — prove itself performs no tracked
  # repository mutation (STATE/R6: zero uncontrolled tracked writes).
  report.executionStats.obligationGeneratedCount = ogrGeneratedCount
  report.executionStats.obligationAttemptedCount = ogrAttemptedCount
  report.executionStats.targetsWithObligations = ogrTargetsWithObligations
  report.executionStats.eligibleTargets = ogrEligibleTargets

  BatchUapReport(
    orchestrationReport: report,
    uapResults: uapResults,
    budget: budget,
    refactorTasks: collectedRefactorTasks,
    persistFailures: persistFailures,
    irPipelineFailures: irPipelineFailures,
    promotionClassifications: PromotionClassificationCounts(
      verified: promoVerifiedCount,
      noObligation: promoNoObligationCount,
      unverifiable: promoUnverifiableCount,
      failed: promoFailedCount
    )
  )
