## PipelineStateTypes — Compile-time type-safe stage states for the 4-Layer Verification Engine.
##
## Illegal reordering (e.g., runJudgeStage before runLegislatorStage) is a
## compile-time type mismatch.
##
## This module is the foundation of the data-flow refactor (Phase 0).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import core/boundary/persona_interface
import core/contracts/universal_pipeline_contract
import core/domain_types
import core/lean_lsp_types
import core/orchestrator/cegar_bmc_types
import core/pipeline_core_types
import core/solver/solver_bridge
import std/options
import verification/unified_trajectory
# axiomIoBoundary

type
  DetectiveContext* = object
    ## Everything Detective needs, plus sealed pass-through data for Scribe.
    ## Detective reads `detectiveInput` only; `kInductionPayload` is forwarded
    ## to Scribe without inspection.
    detectiveInput*: DetectiveArtifact
    kInductionPayload*: KInductionResult

  SwatStageResultKind* = enum
    ssrBmcSuccess       ## SWAT fast-path proven → pipeline terminates immediately
    ssrFallbackRequired ## Fast-path failed → continue with K-induction + CEGAR

  SwatStageOutcome* = object
    ## ADT representing the SWAT stage result.
    ## Zero type pollution: each variant carries ONLY the data it needs.
    case kind*: SwatStageResultKind
    of ssrBmcSuccess:
      pipelineResult*: UniversalPipelineResult
    of ssrFallbackRequired:
      kInductionResult*: KInductionResult
      cegarBmcResult*: CegarBmcResult
      priorInvariant*: string

  PipelineInput* = object
    ## Base input to the pipeline. Immutable after construction.
    req*: UniversalPipelineRequest
    translation*: UniversalTranslation

  DetectedState* = object
    ## After Detective (Layer 1): topology scan + BMC prefilter + case opening.
    req*: UniversalPipelineRequest
    translation*: UniversalTranslation
    priorPromotion*: tuple[invariant: string; snapshotPath: string]
    initialScan*: NegativeInvariantScan
    evolutionHit*: Option[AnnotatedHit]
    traceReport*: TraceReport
    ## Feedback accumulation fields (for ProofState[S] integration)
    cxHistory*: seq[CounterExamplePayload]
    unsatCoreVars*: seq[string]
    cegarCounterexample*: bool
    ## Goal deltas from tactic backtracking (for goal-aware feedback)
    goalDeltas*: seq[GoalDelta]

  LegislatedState* = object
    ## After Legislator (Layer 2.5): invariant drafting + self-healing.
    req*: UniversalPipelineRequest
    translation*: UniversalTranslation
    priorPromotion*: tuple[invariant: string; snapshotPath: string]
    initialScan*: NegativeInvariantScan
    evolutionHit*: Option[AnnotatedHit]
    traceReport*: TraceReport
    baselineInvariant*: string
    refinedInvariant*: string
    activeInvariant*: string
    healedSource*: string
    evolutionReasoning*: string
    logLines*: seq[string]
## Convenience constructors to reduce boilerplate when enriching state.

func toDetectedState*(
  input: PipelineInput;
  priorPromotion: tuple[invariant: string; snapshotPath: string];
  initialScan: NegativeInvariantScan;
  evolutionHit: Option[AnnotatedHit];
  traceReport: TraceReport;
  cxHistory: seq[CounterExamplePayload] = @[];
  unsatCoreVars: seq[string] = @[];
  cegarCounterexample: bool = false;
  goalDeltas: seq[GoalDelta] = @[]
): DetectedState {.raises: [].} =
  DetectedState(
    req: input.req,
    translation: input.translation,
    priorPromotion: priorPromotion,
    initialScan: initialScan,
    evolutionHit: evolutionHit,
    traceReport: traceReport,
    cxHistory: cxHistory,
    unsatCoreVars: unsatCoreVars,
    cegarCounterexample: cegarCounterexample,
    goalDeltas: goalDeltas
  )
func toLegislatedState*(
  detected: DetectedState;
  baselineInvariant, refinedInvariant, activeInvariant, healedSource, evolutionReasoning: string;
  logLines: seq[string]
): LegislatedState {.raises: [].} =
  LegislatedState(
    req: detected.req,
    translation: detected.translation,
    priorPromotion: detected.priorPromotion,
    initialScan: detected.initialScan,
    evolutionHit: detected.evolutionHit,
    traceReport: detected.traceReport,
    baselineInvariant: baselineInvariant,
    refinedInvariant: refinedInvariant,
    activeInvariant: activeInvariant,
    healedSource: healedSource,
    evolutionReasoning: evolutionReasoning,
    logLines: logLines
  )
type
  ScribedState* = object
    ## After Scribe (Layer 3): Lean theorem synthesis + tactic trace.
    ## Carries the synthesized Lean source and verification status.
    req*: UniversalPipelineRequest
    translation*: UniversalTranslation
    healedSource*: string
    seededInvariant*: string
    leanstralLeanSource*: string      ## Pre-synthesized Lean source (may be empty)
    theoremSource*: string
    tacticTrace*: string
    verified*: bool

  JudgedState* = object
    ## After Judge (Layer 4): certification result + solver evidence.
    ## Contains the final invariant, source, and diagnostic information.
    req*: UniversalPipelineRequest
    translation*: UniversalTranslation
    healedSource*: string
    finalInvariant*: string
    finalSource*: string
    nearestDiagnostic*: string
    failedReplayAttempts*: int
    leanKernelVerified*: bool
    proofDepth*: int
    vacuityProven*: bool          ## Anti-vacuity linter result — derived from negative mutation test
    negativeMutationPass*: bool   ## Negative mutation test passed (genuine, not vacuous)

  ProcessedState* = object
    ## After Post-Process (Layer 4.5): investigation + refinement.
    ## Final state before pipeline completion.
    req*: UniversalPipelineRequest
    translation*: UniversalTranslation
    refinedSource*: string
    activeInvariant*: string
    refinedInvariant*: string

  PipelineOutput* = object
    ## Terminal output of the pipeline.
    ## Either a successful result or failure information.
    result*: Option[UniversalPipelineResult]
    error*: Option[AxiomError]
    guardExitMessage*: string
    guardTerminalStatus*: StageStatus
## Conversion constructors for the type chain.

func toScribedState*(
  legislated: LegislatedState;
  leanstralLeanSource: string;
  theoremSource: string;
  tacticTrace: string;
  verified: bool
): ScribedState {.raises: [].} =
  ScribedState(
    req: legislated.req,
    translation: legislated.translation,
    healedSource: legislated.healedSource,
    seededInvariant: legislated.activeInvariant,
    leanstralLeanSource: leanstralLeanSource,
    theoremSource: theoremSource,
    tacticTrace: tacticTrace,
    verified: verified
  )
func toJudgedState*(
  scribed: ScribedState;
  finalInvariant, finalSource, nearestDiagnostic: string;
  failedReplayAttempts: int;
  leanKernelVerified: bool;
  proofDepth: int;
  vacuityProven: bool = false;
  negativeMutationPass: bool = false
): JudgedState {.raises: [].} =
  JudgedState(
    req: scribed.req,
    translation: scribed.translation,
    healedSource: scribed.healedSource,
    finalInvariant: finalInvariant,
    finalSource: finalSource,
    nearestDiagnostic: nearestDiagnostic,
    failedReplayAttempts: failedReplayAttempts,
    leanKernelVerified: leanKernelVerified,
    proofDepth: proofDepth,
    vacuityProven: vacuityProven,
    negativeMutationPass: negativeMutationPass
  )
func toProcessedState*(
  judged: JudgedState;
  refinedSource, activeInvariant, refinedInvariant: string
): ProcessedState {.raises: [].} =
  ProcessedState(
    req: judged.req,
    translation: judged.translation,
    refinedSource: refinedSource,
    activeInvariant: activeInvariant,
    refinedInvariant: refinedInvariant
  )

## ──────────────────────────────────────────────────────────────────────────────
## Algebraic Verification Outcome — Pipeline Status / Verification Result 분리
## ──────────────────────────────────────────────────────────────────────────────
type
  VerificationVerdict* = enum
    vvSafe       ## 완벽히 증명됨 (leanKernelVerified = true)
    vvUnsafe     ## 버그 발견 (counter-example 존재)
    vvUnknown    ## 증명 불가 (Leanstral 실패, budget 초과 등)

  PipelineExitKind* = enum
    pekSuccess   ## 파이프라인 크래시 없이 정상 종료
    pekFailure   ## 파이프라인 자체의 런타임 에러

  VerificationOutcome* = object
    ## Pipeline execution status와 verification result를 분리하는 algebraic type.
    ## pekSuccess: 파이프라인이 정상 완료 → verdict + provenLayer + result
    ## pekFailure: 파이프라인 자체 실패 → error code + message
    case exitKind*: PipelineExitKind
    of pekSuccess:
      verdict*: VerificationVerdict
      provenLayer*: ProvenLayerKind
      result*: UniversalPipelineResult
    of pekFailure:
      error*: AxiomError
      failureMessage*: string
func exitCode*(outcome: VerificationOutcome): int {.raises: [].} =
  ## CLI exit code 매핑
  case outcome.exitKind
  of pekSuccess:
    case outcome.verdict
    of vvSafe: 0
    of vvUnknown: 2
    of vvUnsafe: 3
  of pekFailure: 1

