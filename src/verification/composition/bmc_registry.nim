import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/options
import core/application/persona_context
import core/contract/verification_interface
import core/orchestration/pipeline_config
import core/bmc/bmc_types
import verification/layer1_bmc
import verification/pipeline_stage_swat
import verification/pipeline_stage_k_induction
# axiomIoBoundary

func registerBmc*(ctx: var PersonaContext) {.raises: [].} =
  ctx.runLayer1Bmc = proc(req: verification_interface.UniversalPipelineRequest): verification_interface.Layer1BmcResult {.closure, raises: [].} =
    let gw = layer1_bmc.runLayer1Bmc(req)
    verification_interface.Layer1BmcResult(
      verdict: verification_interface.Layer1BmcVerdict(gw.verdict.ord),
      provenLayer: gw.provenLayer,
      witnessTrace: gw.witnessTrace,
      elapsedMs: gw.elapsedMs
    )

  ctx.runSwatStage = proc(input: verification_interface.PipelineInput; swatArt: verification_interface.SwatArtifact; priorPromotion: tuple[invariant: string; snapshotPath: string]; kInductRes: verification_interface.KInductionResult): verification_interface.SwatStageOutcome {.closure, raises: [].} =
    pipeline_stage_swat.runSwatStage(input, swatArt, priorPromotion, kInductRes)

  ctx.runKInductionStage = proc(config: PipelineConfig; transitionRule: Option[TransitionRule]; invariantRule: Option[InvariantRule]): verification_interface.KInductionResult {.closure, raises: [].} =
    pipeline_stage_k_induction.runKInductionStage(config, transitionRule, invariantRule)

{.pop.}
