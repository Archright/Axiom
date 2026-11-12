import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/application/persona_context
import core/application/persona_context_init
import core/bmc/bmc_types
import core/boundary/persona_interface
import core/boundary/verification_interface
import core/logic/pipeline_healing_logic
import core/orchestration/pipeline_config
import core/orchestration/pipeline_types
import verification/pipeline_effect
import core/parsers/expression_parser
import core/trusted/axiom_pragmas
import core/types/pipeline_core_types
import core/types/results
import personas/detective
import personas/judge
import personas/legislator
import personas/legislator_feedback
import personas/scribe
import std/monotimes
import std/options
import core/interfaces/logging_hub
import core/interfaces/git_ops_hub
import infrastructure/bypass_audit
## DEBT#415: No module-level shared PersonaContext.
## A module-global `let pdCtx = initPersonaContext()` was concurrently deref'd by
## worker threads calling runUniversalAcceptancePipeline (SIGSEGV risk). Each
## createDefaultPipelineDispatch() invocation now allocates a fresh PersonaContext
## captured by its returned closure, so concurrent workers never share a heap object.

# IoC Composition Root — inject concrete implementations into abstract hubs
# Runs once at module load time (before any pipeline execution)
proc iocLogger(level, msg: string) {.nimcall, gcsafe, raises: [].} =
  case level
  of "ERROR": logging_hub.logError(msg)
  of "WARN": logging_hub.logInfo(msg)
  of "DEBUG": logging_hub.logInfo(msg)
  else: logging_hub.logInfo(msg)

proc iocGetCommitHash(): string {.nimcall, gcsafe, raises: [CatchableError].} =
  bypass_audit.getCommitHash()

logging_hub.injectLogger(iocLogger)
logging_hub.logErrorAction = iocLogger
git_ops_hub.injectGitOps(iocGetCommitHash)

## StageHandler: uniform signature for all pipeline stage handlers.
## {.nimcall.} (thin C function pointer) enables const array storage.
## The isolated per-dispatch PersonaContext is passed as the first argument so
## handlers never reference a module-global context (DEBT#415).
type StageHandler = proc(persona: PersonaContext; ctx: PipelineContext; dispatchCtx: DispatchContext) {.nimcall, raises: [CatchableError].}
## RuleBundle — Extracted structured rules from semantic translator.
## Provides Option[TransitionRule] and Option[InvariantRule] for k-induction.
type RuleBundle = object
  transition: Option[TransitionRule]
  invariant: Option[InvariantRule]
func extractRuleBundle(
  translation: UniversalTranslation;
  guardNodeId: string;
  currentSource: string
): RuleBundle {.raises: [].} =
  ## Phase 1: extract structured rules from semantic translator.
  ## Parses transition relation and invariant from the translation's
  ## string-based fields into typed Rule objects.
  result = RuleBundle(
    transition: none(TransitionRule),
    invariant: none(InvariantRule)
  )
  if translation.transitionRelation.len > 0:
    let ruleRes = parseUserCodeToRule(translation.transitionRelation[0])
    if ruleRes.isOk:
      result.transition = some(ruleRes.get())
  if translation.transitionInvariants.len > 0:
    let invRes = parseNaturalConstraintToInvariant(translation.transitionInvariants[0])
    if invRes.isOk:
      result.invariant = some(invRes.get())
proc handleSwatStage(persona: PersonaContext; ctx: PipelineContext; dispatchCtx: DispatchContext) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  let input = PipelineInput(
    req: ctx.loopReq,
    translation: ctx.translation
  )
  let config = PipelineConfig(
    req: ctx.loopReq,
    translation: ctx.translation,
    priorPromotion: ctx.priorPromotion,
    maxIterations: ctx.maxIterations,
    guardNodeId: ctx.guardNodeId,
    guardStartTime: ctx.guardStartTime
  )
  # Phase 1: extract structured rules from semantic translator.
  let ruleBundle = extractRuleBundle(ctx.translation, ctx.guardNodeId, ctx.currentSource)
  let kInductRes = persona.runKInductionStage(config, ruleBundle.transition, ruleBundle.invariant)
  let outcome = persona.runSwatStage(input, ctx.swatArt, ctx.priorPromotion, kInductRes)
  ctx.swatOutcome = some(outcome)
proc handleDetectiveStage(persona: PersonaContext; ctx: PipelineContext; dispatchCtx: DispatchContext) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  let artRes = detective.openCase(ctx.loopReq, ctx.translation)
  if artRes.isErr:
    ctx.error = some(artRes.error)
    return
  ctx.applyDetectiveOpenResult(artRes.get())
proc handleLegislatorStage(persona: PersonaContext; ctx: PipelineContext; dispatchCtx: DispatchContext) {.raises: [CatchableError].} =
  if ctx.useFeedback:
    let goalDeltaStrings = legislator_feedback.goalDeltaToFeedbackStrings(dispatchCtx.currentDeltas)
    let artRes = legislator_feedback.legislateWithFeedback(
      ctx.loopReq, ctx.translation,
      ctx.detected.initialScan, ctx.detected.priorPromotion,
      ctx.currentSource, ctx.detected.cxHistory,
      ctx.detected.unsatCoreVars,
      goalDelta = goalDeltaStrings,
      failingLeanSource = ctx.judgeArt.inferredSpec.theoremSource
    )
    if artRes.isErr:
      ctx.error = some(artRes.error)
      return
    ctx.applyLegislatorResult(artRes.get())
  else:
    let artRes = legislator.legislate(
      ctx.loopReq, ctx.translation,
      ctx.detected.initialScan, ctx.detected.priorPromotion,
      ctx.currentSource
    )
    if artRes.isErr:
      ctx.error = some(artRes.error)
      return
    ctx.applyLegislatorResult(artRes.get())
proc handleScribeStage(persona: PersonaContext; ctx: PipelineContext; dispatchCtx: DispatchContext) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  let seededInvariant =
    if ctx.draftArt.baselineInvariant.len > 0: ctx.draftArt.baselineInvariant
    else: ctx.detected.priorPromotion.invariant
  let artRes = scribe.synthesizeLeanTheorem(
    ctx.loopReq, ctx.translation,
    ctx.swatArt.healedSource, seededInvariant
  )
  if artRes.isErr:
    let convertedErr = case artRes.error.kind
      of scribe.ScribeErrorKind.ArtifactGenerationFailed: axiomErrInconsistentState
      of scribe.ScribeErrorKind.IOError: axiomErrFileSystemError
      of scribe.ScribeErrorKind.LlmConnectionFailed: axiomErrNetworkFailure
    ctx.error = some(convertedErr)
    return
  ctx.applyScribeResult(artRes.get())
proc handleJudgeStage(persona: PersonaContext; ctx: PipelineContext; dispatchCtx: DispatchContext) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [TimeEffect, AxiomIOEffect, IOEffect, RootEffect].} =
  let seededInvariant =
    if ctx.draftArt.baselineInvariant.len > 0: ctx.draftArt.baselineInvariant
    else: ctx.detected.priorPromotion.invariant
  let elapsedNs = getMonoTime().ticks - ctx.guardStartTime.ticks
  let elapsedMs = int(elapsedNs div 1_000_000)
  let artRes = judge.certify(
    ctx.loopReq, ctx.translation,
    ctx.swatArt.healedSource, seededInvariant,
    "proven_by_induction", ctx.loopReq.maxRounds,
    preSynthesizedLeanSource = ctx.leanstralLeanSource,
    cxHistory = ctx.detected.cxHistory,
    smtUnsatCoreVars = ctx.detected.unsatCoreVars,
    elapsedMs = elapsedMs,
    iterations = ctx.iteration,
    stagnationEscalated = dispatchCtx.stagnationEscalated,
    goalDeltas = dispatchCtx.goalDeltas
  )
  if artRes.isErr:
    ctx.error = some(artRes.error)
    return
  ctx.applyJudgeResult(artRes.get())
proc handlePostProcessStage(persona: PersonaContext; ctx: PipelineContext; dispatchCtx: DispatchContext) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  let refinedInvariant =
    if ctx.draftArt.baselineInvariant.len > 0:
      if ctx.judgeArt.finalInvariant.len > 0: ctx.judgeArt.finalInvariant
      else: ctx.draftArt.baselineInvariant
    elif ctx.judgeArt.finalInvariant.len > 0 and
         ctx.judgeArt.finalInvariant != ctx.detected.priorPromotion.invariant:
      ctx.judgeArt.finalInvariant
    else:
      ""
  let activeInvariant =
    if refinedInvariant.len > 0:
      mergeInvariantClauses(ctx.detected.priorPromotion.invariant, refinedInvariant)
    elif ctx.judgeArt.finalInvariant.len > 0:
      mergeInvariantClauses(ctx.detected.priorPromotion.invariant, ctx.judgeArt.finalInvariant)
    else:
      ctx.detected.priorPromotion.invariant

  let artRes = detective.investigate(
    ctx.loopReq, ctx.translation,
    ctx.detected.priorPromotion, ctx.detected.initialScan,
    ctx.judgeArt.finalSource, activeInvariant,
    ctx.judgeArt.nearestDiagnostic, ctx.judgeArt.failedReplayAttempts
  )
  if artRes.isErr:
    ctx.error = some(artRes.error)
    return
  ctx.applyPostProcessResult(artRes.get())
func handleCompleteStage(persona: PersonaContext; ctx: PipelineContext; dispatchCtx: DispatchContext) {.raises: [CatchableError].} =
  discard  # No action needed; iterator is done
# Exhaustive: adding a PipelineCommand without a handler causes compile error.

const DispatchTable: array[PipelineCommand, StageHandler] = [
  cmdRequireSwat: handleSwatStage,
  cmdRequireDetective: handleDetectiveStage,
  cmdRequireLegislator: handleLegislatorStage,
  cmdRequireScribe: handleScribeStage,
  cmdRequireJudge: handleJudgeStage,
  cmdRequirePostProcess: handlePostProcessStage,
  cmdPipelineComplete: handleCompleteStage
]

# ── Stage Handlers ──────────────────────────────────────────────────────────

proc createDefaultPipelineDispatch*(): PersonaDispatchFn =
  ## Factory: returns a PersonaDispatchFn that routes PipelineCommand values
  ## to the correct stage handler via compile-time dispatch table.
  ## DEBT#415: a fresh PersonaContext is allocated per invocation and captured by
  ## the returned closure. Concurrent worker threads therefore each dereference
  ## their own heap object — no shared module-global context is used.
  let persona = initPersonaContext()
  return proc(cmd: PipelineCommand; ctx: PipelineContext; dispatchCtx: DispatchContext) {.closure, raises: [CatchableError].} =
    DispatchTable[cmd](persona, ctx, dispatchCtx)

{.pop.}
