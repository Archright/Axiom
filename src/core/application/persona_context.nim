import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/bmc/bmc_types
import core/boundary/persona_interface
import core/judge/lean_replay
import core/orchestration/pipeline_config
import core/orchestrator/cegar_types
import core/orchestrator/cfg_builder
import core/solver/solver_bridge
import core/types/domain_types
import core/types/pipeline_core_types
import core/types/results
import core/symbolic/symbolic_types_expr
import std/json
import std/options
import std/tables
# Domain contract hub (DIP boundary).
from core/boundary/verification_interface import
  LeanstralResult, Layer1BmcResult, Layer1BmcVerdict,
  StageKind, StageStatus, AbstractContext, Interval, FixedpointResult,
  SwatStageOutcome, PipelineInput, LeanSpecInference

# PersonaZ3CheckFn — renamed to avoid collision with verification_interface.Z3CheckFn.
# Proc types are structural in Nim, so any closure with this shape can be assigned.
type PersonaZ3CheckFn* = proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].}
type
  PersonaContext* = object
    ## Plain data object holding verification callbacks for personas.
    ## No logic, no I/O, no re-exports. Initialization is performed by
    ## persona_context_init.nim via per-bounded-context composition modules.
    ##
    ## NOTE: This object currently mixes callbacks from multiple bounded
    ## contexts (Lean, CEGAR, BMC, healing, etc.). A future refactor
    ## (ADR-015) should decompose it into LeanContext, VerificationContext,
    ## and HealingContext once the composition modules are proven stable.

    callLeanstral*: proc(prompt: string): LeanstralResult {.closure, raises: [].}
    runLeanReplay*: proc(nodeId: string; leanSource: string): Result[LeanReplayResult, string] {.closure, raises: [].}
    runNegativeInvariantSearch*: proc(translation: UniversalTranslation; sourceCode: string; activeInvariant: string): NegativeInvariantScan {.closure, raises: [].}
    runLayer1Bmc*: proc(req: UniversalPipelineRequest): Layer1BmcResult {.closure, raises: [].}
    runSwatStage*: proc(input: PipelineInput; swatArt: SwatArtifact; priorPromotion: tuple[invariant: string; snapshotPath: string]; kInductRes: KInductionResult): SwatStageOutcome {.closure, raises: [].}
    runKInductionStage*: proc(config: PipelineConfig; transitionRule: Option[TransitionRule]; invariantRule: Option[InvariantRule]): KInductionResult {.closure, raises: [].}
    z3CheckViaProcess*: proc(solverCmd: string; solverArgs: seq[string]): PersonaZ3CheckFn {.closure, raises: [].}
    runCegarLoop*: proc(cfg: ControlFlowGraph; headerId: int; z3Check: PersonaZ3CheckFn; maxIterations: int; budgetMs: int64): CegarEngineResult {.closure, raises: [CatchableError].}
    proveWithFixedpoint*: proc(cfg: ControlFlowGraph; headerId: int; variables: seq[string]): FixedpointResult {.closure, raises: [].}
    encodeProvedInvariantsSmtlib2*: proc(invariants: seq[SymSExpr]): string {.closure, raises: [].}
    loadPromotionFromProofVault*: proc(req: UniversalPipelineRequest): tuple[invariant: string; snapshotPath: string] {.closure, raises: [CatchableError].}
    syncRecoveredSourceToModule*: proc(req: UniversalPipelineRequest; sourceCode: string): Result[string, AxiomError] {.closure, raises: [].}
    writeReproductionArtifact*: proc(req: UniversalPipelineRequest; hit: Option[AnnotatedHit]; pocSnippet: string): Result[string, AxiomError] {.closure, raises: [].}
    writeBddFeature*: proc(req: UniversalPipelineRequest; initial: NegativeInvariantScan): Result[string, AxiomError] {.closure, raises: [CatchableError].}
    logStage*: proc(phase: StageKind; nodeId: string; detail: string; elapsedMs: int; status: StageStatus; extra: JsonNode) {.closure, raises: [].}
    analyzeVariableIntervalsAtLoopHeader*: proc(cfg: ControlFlowGraph; headerId: int): Table[string, Interval] {.closure, raises: [].}
    detectInductionVariables*: proc(cfg: ControlFlowGraph; headerId: int): seq[string] {.closure, raises: [].}
    deriveInvariantCandidates*: proc(ctx: AbstractContext): seq[SymSExpr] {.closure, raises: [].}
    extractLoopConditionFromHeader*: proc(cfg: ControlFlowGraph; headerId: int): Option[SymSExpr] {.closure, raises: [].}
    runSelfHealingLoop*: proc(sourceCode: string; translation: UniversalTranslation; initial: NegativeInvariantScan; maxRounds: int; activeInvariant: string): tuple[finalSource: string, finalScan: NegativeInvariantScan, rounds: seq[HealingRound]] {.closure, raises: [CatchableError].}
    runLeanProofRefinementLoop*: proc(req: UniversalPipelineRequest; translation: UniversalTranslation; sourceCode: string; activeInvariant: string; maxRounds: int): tuple[finalSource: string, finalInvariant: string, rounds: seq[HealingRound], nearestDiagnostic: string, failedReplayAttempts: int, leanKernelVerified: bool, vacuityProven: bool] {.closure, raises: [CatchableError].}
    inferLeanSpec*: proc(modulePath: string; functionName: string; translation: UniversalTranslation; sourceCode: string; activeInvariant: string; verificationVerdict: string): LeanSpecInference {.closure, raises: [].}
func validate*(ctx: PersonaContext) {.raises: [].} =
  ## Fail-fast guard: every callback must be wired before the context is used.
  ## If a new field is added and a composition module forgets to set it,
  ## initPersonaContext() will abort immediately instead of passing a nil
  ## callback to a persona.
  doAssert ctx.callLeanstral != nil
  doAssert ctx.runLeanReplay != nil
  doAssert ctx.runNegativeInvariantSearch != nil
  doAssert ctx.runLayer1Bmc != nil
  doAssert ctx.runSwatStage != nil
  doAssert ctx.runKInductionStage != nil
  doAssert ctx.z3CheckViaProcess != nil
  doAssert ctx.runCegarLoop != nil
  doAssert ctx.proveWithFixedpoint != nil
  doAssert ctx.encodeProvedInvariantsSmtlib2 != nil
  doAssert ctx.loadPromotionFromProofVault != nil
  doAssert ctx.syncRecoveredSourceToModule != nil
  doAssert ctx.writeReproductionArtifact != nil
  doAssert ctx.writeBddFeature != nil
  doAssert ctx.logStage != nil
  doAssert ctx.analyzeVariableIntervalsAtLoopHeader != nil
  doAssert ctx.detectInductionVariables != nil
  doAssert ctx.deriveInvariantCandidates != nil
  doAssert ctx.extractLoopConditionFromHeader != nil
  doAssert ctx.runSelfHealingLoop != nil
  doAssert ctx.runLeanProofRefinementLoop != nil
  doAssert ctx.inferLeanSpec != nil
{.pop.}
