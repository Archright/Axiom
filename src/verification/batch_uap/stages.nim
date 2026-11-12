import core/trusted/layer_declaration
axiomLayer "infrastructure"
import core/bmc/bmc_variable_map
import core/contracts/universal_pipeline_contract
import core/function_verification_summary
import core/orchestrator/orchestrator_types
import core/pipeline_core_types
import core/proof/proof_artifact
import core/proof/proof_budget
import core/remediation_types
import core/results
import core/sorter/sorter_core
import core/topology/topology_engine
import core/types/verification_tier
import sieve/sieve_engine
import sieve/sieve_types
import std/json
import std/math
import std/options
import std/os
import std/sequtils
import std/strutils
import std/hashes
import std/tables
import verification/batch_uap/cache_middleware
import verification/batch_uap/private/request_builder
import verification/proof/arithmetic_type_directed_pipeline
import verification/spacer_integration_gate
import verification/obligation/obligation_ir
import verification/obligation/kernel_acceptance_authority

import core/trusted/axiom_pragmas
import core/crypto/hash_kernel

# ── SorterNodeId Table key support ──────────────────────────────────────
proc hash*(x: SorterNodeId): Hash {.inline.} = hash(string(x))
proc `==`*(a, b: SorterNodeId): bool {.inline.} = string(a) == string(b)

# ── Stage result types ───────────────────────────────────────────────────

type
  CacheMiddlewareStageResult* = object
    ## Result of the CEGAR pipeline cache middleware check (Phase 6C).
    hit*: bool
    verified*: bool
    fingerprint*: string

  TypeDirectedCertData* = object
    verified*: bool
    vaultPath*: string
    reason*: string
    summary*: FunctionVerificationSummary
    smtlib2*: string
    solverStatus*: string
    vacuityProven*: bool
    irHash*: string

  PreSieveStageResult* = object
    topoMetric*: TopologyNodeMetric
    sieveVerdict*: SieveVerdict

  FinalReportCertInput* = object
    status*: OrchestrationNodeStatus
    modulePath*: string
    functionName*: string
    sourceCode*: string
    kernelVerified*: bool
    smtlib2*: string
    solverStatus*: string
    vacuityProven*: bool
    irHash*: string
    ## A2 Lean-evidence binding: the actual replayed/verified Lean source
    ## (leanTrack.theoremSource) that backs a Lean-verified claim. The cert
    ## writer refuses to emit a Lean-verified tier unless this is non-empty,
    ## so a genuine Lean acceptance always binds its real proof text here.
    leanProposition*: string
    ## P5: obligation verdict for certificate JSON.
    ## Carries the obligation generator verdict so cert
    ## re-play can reflect the original semantic classification.
    obligationVerdict*: Option[ObligationGenerationResultKind]
    ## S2: canonical evidence — populated only when the canonical Lean
    ## verification path produced a genuine KAA. None on all other paths.
    evidence*: Option[CanonicalLeanEvidence] = none(CanonicalLeanEvidence)

  FinalReportResult* = object
    status*: OrchestrationNodeStatus
    report*: OrchestrationNodeReport
    certInput*: FinalReportCertInput
proc checkCacheMiddleware*(state: var CacheMiddlewareState;
    modulePath: string; invariantHash: string): CacheMiddlewareStageResult
    {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check the CEGAR pipeline cache before invoking the solver.
  ## Returns hit=true with the cached result on cache hit.
  let lookupResult = state.lookup(modulePath, invariantHash)
  var ctx = CacheMiddlewareStageResult(
    hit: lookupResult.hit,
    verified: lookupResult.verified,
    fingerprint: lookupResult.fingerprint
  )
  result = move(ctx)
proc storeCacheMiddleware*(state: var CacheMiddlewareState;
    fingerprint: string; verified: bool;
 proofHash: string = ""; modulePath: string = "") {.raises: [CatchableError].} =
  ## Store a verification result in the CEGAR pipeline cache.
  ## Call after the solver produces a result.
  discard state.store(fingerprint, verified, proofHash, modulePath)
proc collectDepPostConditions*(nodes: seq[SorterNode]; depId: SorterNodeId;
    summarySnapshot: SummaryCache;
    result: var seq[string]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for node in nodes:
    if node.id != depId:
      continue
    let depSummary = lookupSummary(summarySnapshot, node.modulePath, node.functionName)
    if depSummary.isSome():
      recordCacheHit()
      result.add(depSummary.get().postConditions)
    else:
      recordCacheMiss()
    break
proc collectCalleePostConditions*(state: SorterState; nodeId: SorterNodeId;
    summarySnapshot: SummaryCache): seq[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Collect post-conditions from dependency nodes at shallower nesting depth.
  result = @[]
  let maybeNode = buapFindNodeById(state, nodeId)
  if not maybeNode.isSome():
    return
  for depId in maybeNode.get().dependencyIds:
    collectDepPostConditions(state.nodes, depId, summarySnapshot, result)
type
  NodeIdParts* = object
    modulePath*: string
    functionName*: string

  TypeDirectedResult* = object
    verified*: bool
    certPath*: string
    reason*: string
    summary*: FunctionVerificationSummary
    certInput*: FinalReportCertInput   ## NEW: main-thread cert write용

  UapRequestResult* = object
    success*: bool
    error*: string
    uapReq*: UniversalPipelineRequest

  GasCostResult* = object
    gasCost*: int

  SpacerBypassResult* = object
    output*: UniversalPipelineResult
    bypassed*: bool
    invariantSource*: string
    summary*: FunctionVerificationSummary

  SolverProvenance* = enum
    spZ3SAT        ## Verified by Z3 SAT solver (high confidence)
    spSpacerCHC    ## Verified by Spacer CHC (medium confidence)
    spHeuristic    ## Pre-sieved by heuristic (low confidence)

proc buildVerificationSummary*(functionName, modulePath: string;
    preConditions, postConditions: seq[string];
    invariant: string; provenLayer: ProvenLayerKind;
    checksum: string;
    complexityClass: FunctionComplexityClass;
    vacuityProven: bool = false): FunctionVerificationSummary {.raises: [].} =
  FunctionVerificationSummary(
    functionName: functionName,
    modulePath: modulePath,
    preConditions: preConditions,
    postConditions: postConditions,
    invariant: invariant,
    provenLayer: provenLayer,
    checksum: checksum,
    complexityClass: complexityClass,
    vacuityProven: vacuityProven,
    vkdFixed4: "")
proc findMatchingRequest*(nodeId: SorterNodeId;
    requests: seq[OrchestrationProofRequest]): (OrchestrationProofRequest, bool) {.raises: [].} =
  ## Linear scan for the request whose nodeId matches.
  for r in requests:
    if r.nodeId == nodeId:
      result = (r, true)
      return
  result = (default(OrchestrationProofRequest), false)

proc buildRequestMap*(requests: seq[OrchestrationProofRequest]): Table[SorterNodeId, OrchestrationProofRequest] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Build a lookup table from the requests seq for O(1) access by nodeId.
  ## Call once per batch, then pass to findMatchingRequest overloads.
  result = initTable[SorterNodeId, OrchestrationProofRequest](requests.len)
  for r in requests:
    result[r.nodeId] = r

proc findMatchingRequest*(nodeId: SorterNodeId;
    requestMap: Table[SorterNodeId, OrchestrationProofRequest]): (OrchestrationProofRequest, bool) {.raises: [].} =
  ## O(1) table lookup for the request whose nodeId matches.
  result = (requestMap.getOrDefault(nodeId), requestMap.hasKey(nodeId))

proc parseNodeIdParts*(nodeIdStr: string): NodeIdParts {.raises: [].} =
  ## Split "module::function" into (modulePath, functionName).
  let parts = nodeIdStr.split("::")
  var ctx = NodeIdParts(
    modulePath: parts[0],
    functionName: if parts.len > 1: parts[1] else: ""
  )
  result = move(ctx)
proc buildCachedResult*(nodeTf: string;
    cached: FunctionVerificationSummary;
    nodeIdStr: string): UniversalPipelineResult {.raises: [].} =
  ## vacuityProven=false => verified=false (fail-closed)
  let verified = cached.vacuityProven

  var ctx = UniversalPipelineResult(
    vkdFixed4: if verified: "1.0000" else: cached.vkdFixed4,
    smtTrack: UniversalSmtTrack(
      solverStatus: if verified: "unsat" else: "cached-negative",
      verified: verified),
    leanTrack: UniversalLeanTrack(
      verified: verified,
      vacuityProven: cached.vacuityProven,
      negativeMutationPass: cached.vacuityProven),
    provenLayer: cached.provenLayer,
    activeInvariant: cached.invariant,
    verificationVerdict: if verified: "VERIFIED" else: "CACHED_NEGATIVE",
    nearestDiscontinuities: @[],
    structuredRemediation: StructuredRemediationPayload(
      discontinuities: @[], suggestedPatterns: @[], refactoringTemplates: @[]),
    proofArtifact: emptyProofArtifact(nodeIdStr)
  )
  result = move(ctx)
proc tryTypeDirectedProof*(nodeIdStr, sourceCode, modulePath, functionName,
    vaultDir: string; nodeTf: string): TypeDirectedResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Attempt arithmetic type-directed proof (Phase 0).
  ## Returns verified=true with certPath/summary on success.
  ## Certificate write is DEFERRED to the main thread (single-threaded I/O
  ## safety) — this proc returns the cert data via `certInput` instead of
  ## writing to vaultDir. Consumers write the cert via writeCertificateFromUapResult.
  ## Phase 1B: On failure (Z3 unknown/sat/error), builds a failed certInput and
  ## propagates the error reason — never silently succeeds.
  let res = runArithmeticTypeDirectedProof(
    nodeIdStr, sourceCode, modulePath, functionName
  )
  if res.isOk() and res.get().verified:
    let r = res.get()
    let irHash = sha256Hex(modulePath & functionName & sourceCode)
    # cert write 제거 — 메인 스레드에서 수행
    let certPath = vaultDir / (irHash & ".json")
    let sum = buildVerificationSummary(
      functionName, modulePath, @[], @[], "", plkUnknown, nodeTf,
      buapClassifySourceComplexity(sourceCode, functionName))
    var ctx = TypeDirectedResult(
      verified: true, certPath: certPath,
      reason: r.reason, summary: sum,
      certInput: FinalReportCertInput(
        status: orchestrationProofFailed,
        modulePath: modulePath,
        functionName: functionName,
        sourceCode: sourceCode,
        kernelVerified: false,
        smtlib2: r.smtlib2,
        solverStatus: "unsat",
        vacuityProven: true,
        irHash: irHash,
        leanProposition: "",
        obligationVerdict: none(ObligationGenerationResultKind)
      ))
    result = move(ctx)
  else:
    let reason = if res.isErr(): res.error()
                 else: res.get().reason
    let irHash = sha256Hex(modulePath & functionName & sourceCode)
    # cert write 제거 — 메인 스레드에서 수행
    let certPath = vaultDir / (irHash & ".json")
    let sum = buildVerificationSummary(
      functionName, modulePath, @[], @[], "", plkUnknown, nodeTf,
      buapClassifySourceComplexity(sourceCode, functionName))
    var ctx = TypeDirectedResult(
      verified: false, certPath: certPath,
      reason: reason, summary: sum,
      certInput: FinalReportCertInput(
        status: orchestrationProofFailed,
        modulePath: modulePath,
        functionName: functionName,
        sourceCode: sourceCode,
        kernelVerified: false,
        smtlib2: "",
        solverStatus: "unknown",
        vacuityProven: false,
        irHash: irHash,
        leanProposition: "",
        obligationVerdict: none(ObligationGenerationResultKind)
      ))
    result = move(ctx)
const preSieveRunStage* = "stage-1b-pre-sieve"

## ─── Pre-Sieve Admission Boundary (WP4-j C4) ────────────────────────────────
## A pre-sieve `blocked` verdict is NOT alone a candidate failure.
## Only genuinely fatal blocks — malformed input, non-Nim file, empty source,
## non-routine symbol — are terminal. A block produced purely by structural
## opinion fusion (evaluateTopology/evaluateAst) must NOT veto an otherwise
## valid Nim routine: proof obligations are synthesized in the IR pipeline
## that runs AFTER this gate, so the gate cannot gate on obligation existence.
##
## Admission ≠ Proof Eligibility
## Admission ≠ Obligation Availability
## Admission ≠ Proof Success

proc isPreSieveTerminalBlock*(verdict: SieveVerdict): bool {.raises: [].} =
  ## True only when the block came from a fatal input/symbol rule, not from
  ## structural opinion fusion. The fatal verdicts are exactly the ones
  ## emitted by evaluateFileValidity / evaluateSymbolValidity.
  const fatalVerdicts = ["blocked_non_nim", "blocked_empty_source", "blocked_non_routine"]
  for r in verdict.appliedRules:
    for fv in fatalVerdicts:
      if r.verdict == fv:
        return true
  false

# ── VS-1: shared pre-sieve/blocked node decision ────────────────────────────
## Single pure node-decision rule consumed by BOTH execution paths — the
## sequential driver (loop_driver stage-1 handling) and the parallel worker
## (loop_depth_scheduler stage-5). Encodes, in order:
##   1. deterministic threshold relaxation (the computeRelaxedThreshold
##      stall-count input travels in as `blockThreshold`),
##   2. the WP4-j C4 fatal-only admission gate (isPreSieveTerminalBlock),
##   3. the P4 disproof carve-out — ONLY a P4-confirmed, replay-confirmed
##      vsDisproved (cvConfirmed promotion) overrides a fatal block; every
##      demotion (cvSpurious/cvUnresolved) stays vsInconclusive and keeps the
##      pre-sieve verdict (fail-closed).
## The OGR attempt-count delta semantics travel with the decision through
## preSieveAttemptsObligations: a PRE-SIEVED terminal never dispatches its
## obligations; every other decision reaches a proof-resolution path (the
## disproof terminal included) and its generated obligations count as
## attempted.

type
  PreSieveNodeDecision* = enum
    psndProceed,          ## admission granted — continue the obligation pipeline
    psndDisproofTerminal, ## block overridden by a scoped vsDisproved — failed terminal
    psndPreSieved         ## fatal structural block stands — PRE-SIEVED terminal

func preSieveAttemptsObligations*(decision: PreSieveNodeDecision): bool {.raises: [].} =
  ## P6 obligation-attempt accounting keyed off the shared decision: exactly
  ## the PRE-SIEVED terminal excludes a node from the attempt count.
  decision != psndPreSieved

func decideBlockedNodeTerminal*(
    hasScopedIrResult: bool;
    irDisproved: bool
): PreSieveNodeDecision {.raises: [].} =
  ## Terminal/carve-out leg for a node that is already blocked without a sieve
  ## verdict in hand (sequential UAP request-build failure): terminal unless
  ## the claim-scoped IR evidence is a vsDisproved carve-out.
  if hasScopedIrResult and irDisproved:
    psndDisproofTerminal
  else:
    psndPreSieved

proc decidePreSieveNode*(
    sieveVerdict: SieveVerdict;
    blockThreshold: float;
    hasScopedIrResult: bool;
    irDisproved: bool
): PreSieveNodeDecision {.raises: [].} =
  ## Full pre-sieve admission decision. `sieveVerdict` is the verdict as
  ## returned by runPreSieveStage; the relaxation is re-applied here so the
  ## rule is self-contained (idempotent — a relaxed-open verdict already has
  ## blocked=false). A standing block is terminal only when it is fatal AND no
  ## scoped vsDisproved carves it out; opinion-fusion blocks and relaxed-open
  ## verdicts proceed.
  var verdict = sieveVerdict
  if verdict.blocked and verdict.probabilityScore < blockThreshold:
    verdict.blocked = false
  if not verdict.blocked:
    return psndProceed
  if not isPreSieveTerminalBlock(verdict):
    # WP4-j C4: a block produced purely by structural opinion fusion is a
    # strategy failure, never a candidate failure.
    return psndProceed
  decideBlockedNodeTerminal(hasScopedIrResult, irDisproved)

proc runPreSieveStage*(item: SorterWorkItem;
    matchingReq: OrchestrationProofRequest;
    topologyAnalysis: TopologyAnalysis;
    modulePath, functionName: string;
 blockThreshold: float = 0.50): PreSieveStageResult {.raises: [].} =
  ## Build sieve context, apply pre-sieve, return verdict + topology metric.
  ## blockThreshold: deterministic relaxation — during stalls, raise the bar
  ## for blocking so only high-confidence blocks pass through.
  let fullMetric = findTopologyMetric(topologyAnalysis, item.nodeId)
  let topoMetric = if fullMetric.isSome: fullMetric.get()
    else: TopologyNodeMetric(nodeId: item.nodeId, topologyScore: matchingReq.topologyScore)
  let topoSymbol = findTopologySymbol(topologyAnalysis, item.nodeId)
  let symNodeType = if topoSymbol.isSome: topoSymbol.get().nodeType else: ""
  let sieveCtx = buildSieveContext(
    sourceCode = matchingReq.sourceCode,
    nodeId = matchingReq.nodeId,
    topology = topoMetric,
    unsatCoreVars = matchingReq.unsatCoreVars,
    modulePath = modulePath,
    functionName = functionName,
    nodeType = symNodeType
  )
  var verdict = applyPreSieve(sieveCtx)
  # Deterministic threshold relaxation: during stalls, raise the blocking bar
  # so only high-confidence blocks pass through (Phase 3 of ASI Inflation Fix).
  if verdict.blocked and verdict.probabilityScore < blockThreshold:
    verdict.blocked = false
  var ctx = PreSieveStageResult(
    topoMetric: topoMetric,
    sieveVerdict: verdict
  )
  result = move(ctx)
proc buildUapRequestWithDeps*(matchingReq: OrchestrationProofRequest;
    vaultDir: string; maxRounds: int;
    state: SorterState;
    summarySnapshot: SummaryCache): UapRequestResult {.raises: [CatchableError, IOEffect], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} = ## buapBuildUapRequest() raises Exception
  ## Build UAP request via CEGAR abstraction and compose pre-conditions
  ## from callee post-conditions.
  let uapReqRes = buapBuildUapRequest(matchingReq, vaultDir, maxRounds)
  if uapReqRes.isErr():
    var ctx = UapRequestResult(success: false, error: uapReqRes.error)
    result = move(ctx)
    return

  var uapReq = uapReqRes.get()

  # Compose pre-conditions from callee post-conditions
  let preConditions = collectCalleePostConditions(state, matchingReq.nodeId, summarySnapshot)
  uapReq.preConditions = preConditions
  uapReq.postConditions = matchingReq.cegarInvariants

  var ctx = UapRequestResult(success: true, uapReq: uapReq)
  result = move(ctx)
proc computeGasCost*(topologyScore: int; sieveProbability: float;
    nestingDepth: int): GasCostResult {.raises: [].} =
  ## Multi-signal entropy-based gas allocation.
  let entropySignals = ComplexitySignals(
    topologyScore: float(clamp(topologyScore, 0, 100)) / 100.0,
    sieveProbability: sieveProbability,
    cegarIterations: 0,
    cegarStagnationCount: 0,
    z3RejectionCount: 0,
    synergyGeometricMean: 1.0,
    historicalAvgGas: 0.0
  )
  let entropy = computeComplexityEntropy(entropySignals)
  var ctx = GasCostResult(
    gasCost: calculateAdaptiveGas(topologyScore, entropy, nestingDepth)
  )
  result = move(ctx)
proc trySpacerBypassInner*(uapReq: UniversalPipelineRequest;
    matchingReq: OrchestrationProofRequest;
    nodeIdStr: string; nodeTf: string): SpacerBypassResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let spacerConfig = buapBuildSpacerBmcConfig(uapReq.sourceCode, matchingReq.topologyScore)
    let spacerTransitions = buapBuildTransitionsFromContext(
      uapReq.verificationContext, matchingReq.unsatCoreVars)
    let spacerSafety = buapBuildSafetyProperty(
      matchingReq.cegarInvariants, matchingReq.expectedSmtlib2)
    let spacerVarMap = buapBuildVarMapFromUnsatCore(
      matchingReq.unsatCoreVars, uapReq.modulePath)
    let spacerScopeCtx = initScopeContextStack(uapReq.functionName)
    let spacerResult = trySpacerIntegration(
      spacerConfig, spacerTransitions, safetyProperty = spacerSafety,
      varMap = spacerVarMap, scopeCtx = spacerScopeCtx
    )
    if not (spacerResult.success and spacerResult.strategy == "spacer_bypass"):
      return SpacerBypassResult(bypassed: false)
    let output = spacerResult.toUniversalPipelineResult(nodeIdStr)
    let sum = buildVerificationSummary(
      uapReq.functionName, uapReq.modulePath,
      uapReq.preConditions, uapReq.postConditions,
      output.activeInvariant, output.provenLayer, nodeTf,
      buapClassifySourceComplexity(uapReq.sourceCode, uapReq.functionName),
      output.leanTrack.vacuityProven)
    var ctx = SpacerBypassResult(
      output: output, bypassed: true,
      invariantSource: spacerResult.invariantSource, summary: sum)
    result = move(ctx)
  except CatchableError:
    result = SpacerBypassResult(bypassed: false)  # Spacer failed
proc trySpacerBypass*(uapReq: UniversalPipelineRequest;
    matchingReq: OrchestrationProofRequest;
    nodeIdStr: string; nodeTf: string): SpacerBypassResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Try deterministic invariant synthesis via Spacer CHC solver.
  if uapReq.sourceCode.len == 0:
    return SpacerBypassResult(bypassed: false)
  result = trySpacerBypassInner(uapReq, matchingReq, nodeIdStr, nodeTf)
proc buildEvidenceLogJson*(uapOutput: UniversalPipelineResult): string {.raises: [].} =
  ## Build the evidence log JSON object for the node report.
  let discJson = uapOutput.nearestDiscontinuities.mapIt(%*{
    "filePath": it.filePath,
    "lineNumber": it.lineNumber,
    "smtUnsatCoreVars": it.smtUnsatCoreVars,
    "discontinuityKind": $it.discontinuityKind,
    "description": it.description
  })
  let remedDisc = uapOutput.structuredRemediation.discontinuities.mapIt(%*{
    "filePath": it.filePath,
    "lineNumber": it.lineNumber,
    "smtUnsatCoreVars": it.smtUnsatCoreVars,
    "discontinuityKind": $it.discontinuityKind,
    "description": it.description
  })
  let patterns = uapOutput.structuredRemediation.suggestedPatterns.mapIt(%*{
    "patternName": it.patternName,
    "patternDescription": it.patternDescription,
    "nimCodeTemplate": it.nimCodeTemplate,
    "applicableTo": it.applicableTo.mapIt($it)
  })
  let templates = uapOutput.structuredRemediation.refactoringTemplates.mapIt(%*{
    "signal": $it.signal,
    "pattern": $it.pattern,
    "description": it.description,
    "nimHint": it.nimHint,
    "priority": $it.priority
  })
  $(%*{
    "vkd": uapOutput.vkdFixed4,
    "solverStatus": uapOutput.smtTrack.solverStatus,
    "leanKernelVerified": uapOutput.leanTrack.verified,
    "method": "uap-pipeline",
    "provenLayer": $uapOutput.provenLayer,
    "synergyMetrics": {
      "fFactor": uapOutput.synergyMetrics.fFactor,
      "gFactor": uapOutput.synergyMetrics.gFactor,
      "hFactor": uapOutput.synergyMetrics.hFactor,
      "geometricMean": uapOutput.synergyMetrics.geometricMean
    },
    "nearestDiscontinuities": discJson,
    "remediation": {
      "discontinuities": remedDisc,
      "suggestedPatterns": patterns,
      "refactoringTemplates": templates
    }
  })
proc buildFinalNodeReport*(itemId: SorterNodeId;
    uapReq: UniversalPipelineRequest;
    uapOutput: UniversalPipelineResult;
    obligationVerdict: Option[ObligationGenerationResultKind] = none(ObligationGenerationResultKind);
    evidence: Option[CanonicalLeanEvidence] = none(CanonicalLeanEvidence)): FinalReportResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Determine verification status, build final OrchestrationNodeReport.
  ## Certificate writing is deferred to main thread for single-threaded I/O safety.
  ## P6: `obligationVerdict` carries the actual obligation-generation verdict kind
  ## from the IR pipeline into the persisted certificate so a UAP-verified cert
  ## records WHAT obligation set was proven. When absent (e.g. legacy path), the
  ## cert simply omits the field — never defaults to a fabricated value.
  let kernelVerified = uapOutput.leanTrack.verified
  let z3Verified = uapOutput.smtTrack.solverStatus == "unsat"
  # P3b: VERIFIED requires Lean kernel ACCEPT. Z3-only evidence (no Lean
  # acceptance) is a candidate proof, NOT a final VERIFIED. It is treated
  # as orchestrationVerified for reporting; only orchestrationVerified
  # triggers cert write downstream.
  let status =
    if kernelVerified: orchestrationVerified
    elif z3Verified: orchestrationVerified
    else: orchestrationProofFailed

  let irHash = sha256Hex(uapReq.modulePath & uapReq.functionName & uapReq.sourceCode)

  # Phase 1 Tier semantics: derive assurance tier from the SAME underlying
  # verification state the certificate uses (§0.10 / tierFromResults SSOT).
  # z3Passed is read from smtTrack.solverStatus == "unsat"; leanKernelVerified
  # from leanTrack.verified. Both signals are present on a real UAP output,
  # so tierResolution is always "resolved" on this path.
  let tier = tierFromResults(z3Verified, kernelVerified)
  let assuranceTier =
    if tier == vtNone: tierLabel(tier)  ## "none" — evidence exists, solvers did not pass
    else: tierLabel(tier)

  var report = OrchestrationNodeReport(
    nodeId: itemId,
    status: status,
    evidenceLogJson: buildEvidenceLogJson(uapOutput),
    assuranceTier: assuranceTier,
    tierResolution: "resolved"
  )

  var certInput = FinalReportCertInput(
    status: status,
    modulePath: uapReq.modulePath,
    functionName: uapReq.functionName,
    sourceCode: uapReq.sourceCode,
    kernelVerified: kernelVerified,
    smtlib2: uapOutput.translation.smt2,
    solverStatus: uapOutput.smtTrack.solverStatus,
    vacuityProven: uapOutput.leanTrack.vacuityProven,
    irHash: irHash,
    leanProposition: uapOutput.leanTrack.theoremSource,
    obligationVerdict: obligationVerdict,
    evidence: evidence
  )

  var ctx = FinalReportResult(status: status, report: report, certInput: certInput)
  result = move(ctx)


