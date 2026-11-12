import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/options
import std/json

import core/application/persona_context
import core/results
import core/domain_types
import core/pipeline_core_types
import verification/pipeline_negative_scan
import verification/pipeline_core_runner
import verification/unified_trajectory
# axiomIoBoundary

func registerScan*(ctx: var PersonaContext) {.raises: [].} =
  ctx.runNegativeInvariantSearch = proc(translation: UniversalTranslation; sourceCode: string; activeInvariant: string): NegativeInvariantScan {.closure, raises: [].} =
    pipeline_negative_scan.runNegativeInvariantSearch(translation, sourceCode, activeInvariant)

  ctx.loadPromotionFromProofVault = proc(req: UniversalPipelineRequest): tuple[invariant: string; snapshotPath: string] {.closure, raises: [CatchableError].} =
    pipeline_negative_scan.loadPromotionFromProofVault(req)

  ctx.syncRecoveredSourceToModule = proc(req: UniversalPipelineRequest; sourceCode: string): Result[string, AxiomError] {.closure, raises: [].} =
    if sourceCode.len == 0:
      err(axiomErrInvalidValue)
    else:
      ok(sourceCode)

  ctx.writeReproductionArtifact = proc(req: UniversalPipelineRequest; hit: Option[AnnotatedHit]; pocSnippet: string): Result[string, AxiomError] {.closure, raises: [].} =
    pipeline_core_runner.writeReproductionArtifact(req, hit, pocSnippet)

  ctx.writeBddFeature = proc(req: UniversalPipelineRequest; initial: NegativeInvariantScan): Result[string, AxiomError] {.closure, raises: [CatchableError].} =
    pipeline_core_runner.writeBddFeature(req, initial)

  ctx.logStage = proc(phase: StageKind; nodeId: string; detail: string; elapsedMs: int; status: StageStatus; extra: JsonNode) {.closure, raises: [].} =
    unified_trajectory.logStage(phase, nodeId, detail, elapsedMs, status, extra)

{.pop.}
