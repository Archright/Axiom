import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/bmc/bmc_artifacts
import core/boundary/persona_interface
import core/boundary/verification_interface
import core/contracts/universal_pipeline_contract
import core/diagnostics/refactoring_engine
import core/integrity/integrity_refinement_types
import core/logic/universal_translation_types
import core/solver/solver_bridge
import core/types/domain_types
import core/types/lean_lsp_types
import core/types/pipeline_core_types
import std/monotimes
import std/options
import verification/pipeline_effect
type
  PersonaDispatchFn* = proc(
    cmd: PipelineCommand;
    ctx: PipelineContext;
    dispatchCtx: DispatchContext
  ) {.closure, raises: [CatchableError].}
    ## Injected dispatch callback. The pipeline iterator yields PipelineCommand
    ## values; the caller invokes this function which dispatches to the correct
    ## persona proc and writes the result back into ctx.
    ##
    ## dispatchCtx carries the sealed payload for the target persona (Issue 4-A).
    ## pipeline_dispatch.nim reads dispatchCtx fields instead of ctx.goalDeltas.

  PipelineContext* {.acyclic.} = ref object
    ## Shared mutable state between the pipeline iterator and its dispatcher.
    ## The iterator reads pre-persona fields and writes post-persona fields.
    ## The dispatcher (caller) writes persona artifact fields after each yield.

    # ── Input ──
    req*: UniversalPipelineRequest
    translation*: UniversalTranslation
    loopReq*: UniversalPipelineRequest  ## Mutable per-iteration copy

    # ── Pipeline state ──
    currentSource*: string
    currentInvariant*: string
    priorPromotion*: tuple[invariant: string; snapshotPath: string]
    iteration*: int
    maxIterations*: int
    leanstralLeanSource*: string
    bmcProven*: bool

    # ── Dispatch hint: legislator variant ──
    useFeedback*: bool  ## true → legislator_feedback; false → legislator

    # ── K-induction state ──
    kInductionProved*: bool
    kInductionLeanVerified*: bool
    kInductionLeanScript*: string

    # ── Persona artifacts (populated by dispatch caller) ──
    swatArt*: SwatArtifact
    caseArt*: DetectiveArtifact       ## From detective.openCase
    draftArt*: LegislatorArtifact
    scribeArt*: ScribeArtifact
    judgeArt*: JudgeArtifact
    detArt*: DetectiveArtifact        ## From detective.investigate
    bmcArtifact* {.cursor.}: BmcAnalysisArtifact  ## BMC analysis snapshot (non-owning)
    swatOutcome*: Option[SwatStageOutcome]  ## Set by dispatch after runSwatStage

    # ── Detection state (populated by pipeline after openCase) ──
    detected*: DetectedState

    # ── PipelineGuard state ──
    guardNodeId*: string
    guardCurrentStage*: StageKind
    guardTerminalStatus*: StageStatus
    guardExitMessage*: string
    guardStageHistory*: seq[StageKind]
    guardStartTime*: MonoTime

    # ── Output ──
    result*: Option[UniversalPipelineResult]
    error*: Option[AxiomError]
func newPipelineContext*(req: UniversalPipelineRequest): PipelineContext {.raises: [].} =
  ## Factory: create an initialized PipelineContext from the request.
  PipelineContext(
    req: req,
    loopReq: req,
    iteration: 0,
    maxIterations: max(10, req.maxRounds * 10),
    bmcProven: false,
    useFeedback: false,
    kInductionProved: false,
    kInductionLeanVerified: false,
    kInductionLeanScript: "",
    swatOutcome: none(SwatStageOutcome),
    guardCurrentStage: skSwat,
    guardTerminalStatus: ssFailed,
    guardExitMessage: "Abrupt pipeline termination",
    guardStageHistory: @[skSwat]
  )
func applySwatResult*(ctx: PipelineContext; art: SwatArtifact) {.raises: [].} =
  ## Called by dispatcher after swat.executeRaid completes.
  ctx.swatArt = art
func applyDetectiveOpenResult*(ctx: PipelineContext; art: DetectiveArtifact) {.raises: [].} =
  ## Called by dispatcher after detective.openCase completes.
  ctx.caseArt = art
func applyLegislatorResult*(ctx: PipelineContext; art: LegislatorArtifact) {.raises: [].} =
  ## Called by dispatcher after legislator.legislate completes.
  ctx.draftArt = art
func applyScribeResult*(ctx: PipelineContext; art: ScribeArtifact) {.raises: [].} =
  ## Called by dispatcher after scribe.synthesizeLeanTheorem completes.
  ctx.scribeArt = art
func applyJudgeResult*(ctx: PipelineContext; art: JudgeArtifact) {.raises: [].} =
  ## Called by dispatcher after judge.certify completes.
  ctx.judgeArt = art
## ─── LoopAccumulators (for defunctionalized FSM engine) ──────────────────────
func applyPostProcessResult*(ctx: PipelineContext; art: DetectiveArtifact) {.raises: [].} =
  ## Called by dispatcher after detective.investigate completes.
  ctx.detArt = art

## ─── LoopAccumulators (for defunctionalized FSM engine) ──────────────────────
type
  LoopAccumulators* = object
    ## Monotonic accumulators that persist across iterations.
    ## Managed by the orchestrator loop, NOT by stage functions.
    globalRegistry*: InvariantRegistry
    goalDeltas*: seq[GoalDelta]
    visitedStates*: seq[string]
    stagnation*: RefactoringStagnation
    iteration*: int
    ## K-induction pass-through: produced in SWAT, consumed in Scribe.
    ## Sealed payload — stages must not inspect, only forward.
    kInductionPayload*: KInductionResult
    ## Detected state: produced by Detective, consumed by Legislator.
    ## Synced to ctx.detected before cmdRequireLegislator yield.
    detected*: DetectedState
    ## Legislated state: produced by Legislator, consumed by Scribe.
    legislated*: LegislatedState
    ## Scribed state: produced by Scribe, consumed by Judge.
    scribed*: ScribedState
    ## Judged state: produced by Judge, consumed by PostProcess.
    judged*: JudgedState
func extractDispatchResult*(ctx: PipelineContext; cmd: PipelineCommand): DispatchResult {.raises: [].} =
  ## Extract typed DispatchResult from PipelineContext after a dispatch.
  ## Bridges legacy ctx-based dispatch to the new typed system.
  case cmd
  of cmdRequireSwat:
    DispatchResult(target: dtSwat, swatArt: ctx.swatArt, swatOutcome: ctx.swatOutcome)
  of cmdRequireDetective:
    DispatchResult(target: dtDetective, caseArt: ctx.caseArt)
  of cmdRequireLegislator:
    DispatchResult(target: dtLegislator, draftArt: ctx.draftArt)
  of cmdRequireScribe:
    DispatchResult(target: dtScribe, scribeArt: ctx.scribeArt)
  of cmdRequireJudge:
    DispatchResult(target: dtJudge, judgeArt: ctx.judgeArt)
  of cmdRequirePostProcess:
    DispatchResult(target: dtPostProcess, postArt: ctx.detArt)
  of cmdPipelineComplete:
    DispatchResult(target: dtPostProcess, postArt: ctx.detArt)  ## fallback

{.pop.}
