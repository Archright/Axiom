import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
from core/boundary/verification_interface import
  Layer1BmcResult, StageKind, StageStatus, AbstractContext,
  Interval, FixedpointResult, SwatStageOutcome, PipelineInput
import core/bmc/bmc_types
import core/boundary/persona_interface
import core/orchestration/pipeline_config
import core/orchestrator/cegar_types
import core/orchestrator/cfg_builder
import core/solver/solver_bridge
import core/types/pipeline_core_types
import core/symbolic/symbolic_types_expr
import std/options
import std/tables

# PersonaZ3CheckFn — SSOT is persona_context.nim
from core/application/persona_context import PersonaZ3CheckFn
export PersonaZ3CheckFn

type
  VerificationContext* = object
    ## BMC/CEGAR/SMT bounded context.
    ## Holds callbacks for layered verification pipeline.
    runLayer1Bmc*: proc(req: UniversalPipelineRequest): Layer1BmcResult {.closure, raises: [].}
    runSwatStage*: proc(input: PipelineInput; swatArt: SwatArtifact; priorPromotion: tuple[invariant: string; snapshotPath: string]; kInductRes: KInductionResult): SwatStageOutcome {.closure, raises: [].}
    runKInductionStage*: proc(config: PipelineConfig; transitionRule: Option[TransitionRule]; invariantRule: Option[InvariantRule]): KInductionResult {.closure, raises: [].}
    z3CheckViaProcess*: proc(solverCmd: string; solverArgs: seq[string]): PersonaZ3CheckFn {.closure, raises: [].}
    runCegarLoop*: proc(cfg: ControlFlowGraph; headerId: int; z3Check: PersonaZ3CheckFn; maxIterations: int; budgetMs: int64): CegarEngineResult {.closure, raises: [CatchableError].}
    proveWithFixedpoint*: proc(cfg: ControlFlowGraph; headerId: int; variables: seq[string]): FixedpointResult {.closure, raises: [].}
    encodeProvedInvariantsSmtlib2*: proc(invariants: seq[SymSExpr]): string {.closure, raises: [].}
    analyzeVariableIntervalsAtLoopHeader*: proc(cfg: ControlFlowGraph; headerId: int): Table[string, Interval] {.closure, raises: [].}
    detectInductionVariables*: proc(cfg: ControlFlowGraph; headerId: int): seq[string] {.closure, raises: [].}
    deriveInvariantCandidates*: proc(ctx: AbstractContext): seq[SymSExpr] {.closure, raises: [].}
    extractLoopConditionFromHeader*: proc(cfg: ControlFlowGraph; headerId: int): Option[SymSExpr] {.closure, raises: [].}
func validate*(ctx: VerificationContext) {.raises: [].} =
  doAssert ctx.runLayer1Bmc != nil
  doAssert ctx.runSwatStage != nil
  doAssert ctx.runKInductionStage != nil
  doAssert ctx.z3CheckViaProcess != nil
  doAssert ctx.runCegarLoop != nil
  doAssert ctx.proveWithFixedpoint != nil
  doAssert ctx.encodeProvedInvariantsSmtlib2 != nil
  doAssert ctx.analyzeVariableIntervalsAtLoopHeader != nil
  doAssert ctx.detectInductionVariables != nil
  doAssert ctx.deriveInvariantCandidates != nil
  doAssert ctx.extractLoopConditionFromHeader != nil
{.pop.}
