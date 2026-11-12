import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/contracts/universal_pipeline_contract
import core/domain_types
import core/gateway/gateway
import core/logic/pipeline_fingerprint_engine
import core/logic/pipeline_verdict_engine
import core/orchestration/pipeline_config
import core/orchestration/pipeline_types
import std/json
import std/monotimes
import std/options
import std/sequtils
import std/times
import verification/pipeline_effect
import verification/pipeline_phase
import verification/pipeline_state_types
import verification/pipeline_transition
import verification/pipeline_transition_engine
import verification/unified_trajectory
import verification/unified_trajectory_types
import ../core/trusted/axiom_pragmas_lite
export pipeline_types

## Compile-time Command→Stage mapping for guard logging.
const CommandToStage*: array[PipelineCommand, StageKind] = [
  cmdRequireSwat:        skSwat,
  cmdRequireDetective:   skCegar,
  cmdRequireLegislator:  skLegislator,
  cmdRequireScribe:      skScribe,
  cmdRequireJudge:       skJudge,
  cmdRequirePostProcess: skCertificate,
  cmdPipelineComplete:   skCertificate,
]

## ──────────────────────────────────────────────────────────────────────────────
## FSM Helpers
## ──────────────────────────────────────────────────────────────────────────────
proc extractPipelineInput*(ctx: PipelineContext): PipelineInput {.raises: [].} =
  PipelineInput(req: ctx.req, translation: ctx.translation)
proc extractPipelineConfig*(ctx: PipelineContext): PipelineConfig {.raises: [].} =
  PipelineConfig(
    req: ctx.req,
    translation: ctx.translation,
    priorPromotion: ctx.priorPromotion,
    maxIterations: ctx.maxIterations,
    guardNodeId: ctx.guardNodeId,
    guardStartTime: ctx.guardStartTime
  )
## ──────────────────────────────────────────────────────────────────────────────
## [I-2] Single vvSafe projection site
## ──────────────────────────────────────────────────────────────────────────────
## The ONLY place in the repo where a `vvSafe` value may be produced.
## Precondition: an authority decision `vdVerified` from
## VerificationDecisionAuthority.evaluate (which itself requires a
## KernelAcceptanceAttestation bound to an actual canonical Lean kernel
## receipt). The pipeline does not yet carry a KAA-backed decision, so the
## precondition is unsatisfiable today → vvUnknown (fail-closed, documented).
## When KAA wiring lands, this function is the single site that must consult
## evaluate(); no other code may construct vvSafe.

func projectVerdict(r: UniversalPipelineResult): VerificationVerdict {.raises: [].} =
  discard r  # projection input reserved for the KAA-backed authority decision
  vvUnknown

## ──────────────────────────────────────────────────────────────────────────────
## Dispatch Runner — connects iterator to PersonaDispatchFn
## ──────────────────────────────────────────────────────────────────────────────
proc runPipelineWithDispatch*(
  req: UniversalPipelineRequest;
  dispatch: PersonaDispatchFn
): VerificationOutcome {.raises: [].} =
  ## IoC entry point: runs the pipeline iterator with injected persona dispatch.
  ## This is the canonical way to execute the Universal Acceptance Pipeline.
  var ctx = newPipelineContext(req)
  ctx.guardNodeId = req.modulePath & "::" & req.functionName
  ctx.guardStartTime = getMonoTime()

  ## Defunctionalized FSM loop — replaces the old closure-iterator `newPipeline`.
  var phase = PipelinePhase(kind: pkInit)
  var accum = LoopAccumulators()
  var dispatchRes = none(DispatchResult)

  try:
    while true:
      let input = extractPipelineInput(ctx)
      let config = extractPipelineConfig(ctx)
      let (trans, nextAccum) = transition(phase, input, config, accum, dispatchRes)
      accum = nextAccum

      case trans.kind
      of tk2Suspend:
        let cmd = trans.cmd
        if cmd == cmdPipelineComplete:
          break
        try:
          dispatch(cmd, ctx, trans.dispatchCtx)
        except CatchableError as e:
          ctx.error = some(axiomErrInconsistentState)
          ctx.guardExitMessage = "Dispatch exception: " & e.msg
        if ctx.error.isSome:
          ctx.guardExitMessage = "Pipeline dispatch error: " & $ctx.error.get()
          break
        dispatchRes = some(extractDispatchResult(ctx, cmd))
        phase = defaultPhase(PhaseMapping[cmd])
        ctx.guardCurrentStage = CommandToStage[cmd]
        ctx.guardStageHistory.add(ctx.guardCurrentStage)

      of tk2Continue:
        phase = trans.nextPhase
        dispatchRes = none(DispatchResult)

      of tk2Terminal:
        if trans.finalResult.isSome:
          ctx.result = trans.finalResult
        if trans.finalError.isSome:
          ctx.error = trans.finalError
        break

  except CatchableError as e:
    ctx.guardExitMessage = "Pipeline exception: " & e.msg

  # PipelineGuard cleanup logging (replaces defer in the old monolithic version)
  let totalElapsedMs = int((getMonoTime() - ctx.guardStartTime).inMilliseconds)
  logStage(
    phase = ctx.guardCurrentStage,
    nodeId = ctx.guardNodeId,
    detail = ctx.guardExitMessage,
    elapsedMs = totalElapsedMs,
    status = ctx.guardTerminalStatus,
    extra = %*{"stageTrace": ctx.guardStageHistory.mapIt($it)}
  )

  if ctx.error.isSome:
    return VerificationOutcome(exitKind: pekFailure, error: ctx.error.get(), failureMessage: ctx.guardExitMessage)
  if ctx.result.isSome:
    let r = ctx.result.get()
    # [I-2] Direct vvSafe construction is FORBIDDEN. vvSafe may only be
    # projected from `vdVerified` produced by
    # VerificationDecisionAuthority.evaluate over a KernelAcceptanceAttestation.
    # provenLayer (Layer1-4 solver evidence) is NOT kernel acceptance — the
    # old `provenLayer != plkUnknown → vvSafe` shortcut was a second,
    # authority-bypassing verdict path and has been removed. Until the
    # pipeline carries a KAA-backed authority decision, the projection
    # precondition cannot be satisfied → fail-closed to vvUnknown.
    let v = projectVerdict(r)
    return VerificationOutcome(exitKind: pekSuccess, verdict: v, provenLayer: r.provenLayer, result: r)
  return VerificationOutcome(exitKind: pekFailure, error: axiomErrEmptyString, failureMessage: "empty pipeline result")

## ──────────────────────────────────────────────────────────────────────────────
## Backward-Compatibility Wrappers
## ──────────────────────────────────────────────────────────────────────────────

## Run Universal Acceptance Pipeline.
proc runUniversalAcceptancePipeline*(
  req: UniversalPipelineRequest;
  dispatch: PersonaDispatchFn
): VerificationOutcome {.raises: [], axiom: ["(assert (and (> (str.len refinedInvariant) 0)))", "refinedInvariant.length > 0"].} =
  ## Backward-compat entry point for batch_uap_orchestrator.nim.
  ## Delegates to runPipelineWithDispatch with injected dispatch.
  runPipelineWithDispatch(req, dispatch)

## Run Universal Acceptance Workflow.
proc runUniversalAcceptanceWorkflow*(
  req: UniversalPipelineRequest;
  dispatch: PersonaDispatchFn
): VerificationOutcome {.raises: [], axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  ## Backward-compat wrapper. Delegates to runPipelineWithDispatch.
  runPipelineWithDispatch(req, dispatch)
{.pop.}

