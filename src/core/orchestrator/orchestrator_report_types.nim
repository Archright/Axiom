import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import ../../core/trusted/axiom_pragmas
import core/sorter/sorter_core
type
  OrchestrationNodeStatus* = enum
    orchestrationVerified,              ## Lean 커널 검증 완료 (Hard Truth)
    orchestrationInductiveValid,        ## K-induction 검증 완료 (Soft Truth — 커널 미확인)
    orchestrationProofFailed,
    orchestrationTimedOut,
    orchestrationBlocked,
    orchestrationVacuousContradiction,
    orchestrationPreSievedUnverifiable,  ## Pre-Sieve blocked before UAP execution
    orchestrationSkippedByTheory,        ## vpBmcSkipped-induced UAP failure (theory-level incompatibility)
    orchestrationNotVerifiable,          ## P3: obligation generation could not produce a verifiable obligation (terminal, detail preserved)
    orchestrationNoObligation            ## P4: symbol has no verification obligation (certNoObligation status); not a failure

  OrchestrationNodeReport* = object
    nodeId*: SorterNodeId
    dependencyDepth*: int
    usesDependencyVault*: bool
    readsDependencySource*: bool
    injectedAxioms*: seq[AxiomFormula]
    status*: OrchestrationNodeStatus
    vaultPath*: string
    cacheHit*: bool
    remediationHint*: string
    mathematicalRationale*: string
    timeoutComplexityWeight*: int
    timeoutHotspots*: seq[string]
    selfHealingGuidance*: seq[string]
    smtlib2*: string
    evidenceLogJson*: string
    staleReason*: string
    complexity*: float = 0.0  ## Cyclomatic complexity for VKD metric
    assuranceTier*: string = ""  ## Phase 1 Tier semantics: "z3-verified"|"dual-verified"|"lean-verified"|"none"|"k-induction"|"uf-abstract"|"" (unresolved)
    tierResolution*: string = ""  ## "resolved" | "unavailable" — whether assuranceTier was determinable from evidence

  OrchestrationNodeExecutionStat* = object
    nodeId*: SorterNodeId
    dependencyDepth*: int
    solverElapsedMs*: int64
    wallElapsedMs*: int64
    cacheHit*: bool
    status*: OrchestrationNodeStatus
    timeoutMs*: int
    failureReason*: string

  OrchestrationDepthExecutionStat* = object
    dependencyDepth*: int
    startedAtMs*: int64
    endedAtMs*: int64
    elapsedMs*: int64
    solverElapsedMs*: int64
    parallelOverheadMs*: int64
    activeNodeCount*: int
    workerCount*: int
    speedupRatio*: float
    availableMemoryBytes*: int64
    cpuLoadRatio*: float
    recommendedWorkerCount*: int

  OrchestrationExecutionStats* = object
    nodeStats*: seq[OrchestrationNodeExecutionStat]
    depthStats*: seq[OrchestrationDepthExecutionStat]
    totalWallTimeMs*: int64
    totalSolverTimeMs*: int64
    serialBaselineMs*: int64
    parallelSpeedupRatio*: float
    cpuEfficiency*: float
    cacheHitCount*: int
    solverInvocationCount*: int
    maxWorkerCount*: int
    timeoutCount*: int
    hotspotNodeId*: SorterNodeId
    hotspotElapsedMs*: int64
    ## OGR/PAR runtime counters (P6 — additive fields, backward-compatible)
    obligationGeneratedCount*: int     ## total obligations from ogrGenerated results
    obligationAttemptedCount*: int     ## obligations that proceeded to proof attempt
    targetsWithObligations*: int       ## symbols with ogrGenerated verdict
    eligibleTargets*: int              ## total symbols processed by IR pipeline

  OrchestrationReport* = object
    finalState*: SorterState
    nodeReports*: seq[OrchestrationNodeReport]
    blockedNodes*: seq[SorterNodeId]
    staleDependencyNodes*: seq[SorterNodeId]
    reproofNodes*: seq[SorterNodeId]
    timeoutNodes*: seq[SorterNodeId]
    timeoutImpactNodes*: seq[SorterNodeId]
    executionStats*: OrchestrationExecutionStats
## Node Failure Reason.
func nodeFailureReason*(status: OrchestrationNodeStatus): string {.raises: [], axiom: ["(assert (and orchestrationVerified orchestrationProofFailed orchestrationVacuousContradiction orchestrationTimedOut orchestrationBlocked orchestrationPreSievedUnverifiable orchestrationSkippedByTheory orchestrationNotVerifiable orchestrationNoObligation))", "orchestrationVerified ∧ orchestrationProofFailed ∧ orchestrationVacuousContradiction ∧ orchestrationTimedOut ∧ orchestrationBlocked ∧ orchestrationPreSievedUnverifiable ∧ orchestrationSkippedByTheory ∧ orchestrationNotVerifiable ∧ orchestrationNoObligation"].} =
  case status
  of orchestrationVerified:
    ""
  of orchestrationInductiveValid:
    "inductive_valid"
  of orchestrationProofFailed:
    "proof_failed"
  of orchestrationVacuousContradiction:
    "vacuous_contradiction"
  of orchestrationTimedOut:
    "timeout"
  of orchestrationBlocked:
    "blocked"
  of orchestrationPreSievedUnverifiable:
    "pre_sieved_unverifiable"
  of orchestrationSkippedByTheory:
    "skipped_by_theory"
  of orchestrationNotVerifiable:
    "not_verifiable"
  of orchestrationNoObligation:
    "no_obligation"

{.pop.}
