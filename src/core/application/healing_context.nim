import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Healing Context — Bounded context for self-healing & artifact callbacks
##
## Extracted from PersonaContext (Phase 5 decomposition).
## Contains 6 healing/artifact-related proc fields.
## Per AGENTS.md §0.6: Static First Enforcement.

import std/options
import std/json
import core/types/results
import core/types/domain_types
import core/types/pipeline_core_types
from core/boundary/verification_interface import
  StageKind, StageStatus, NegativeInvariantScan

type
  HealingContext* = object
    ## Self-healing & artifact bounded context.
    ## Holds callbacks for healing loops, artifact writing, and logging.
    loadPromotionFromProofVault*: proc(req: UniversalPipelineRequest): tuple[invariant: string; snapshotPath: string] {.closure, raises: [CatchableError].}
    syncRecoveredSourceToModule*: proc(req: UniversalPipelineRequest; sourceCode: string): Result[string, AxiomError] {.closure, raises: [].}
    writeReproductionArtifact*: proc(req: UniversalPipelineRequest; hit: Option[AnnotatedHit]; pocSnippet: string): Result[string, AxiomError] {.closure, raises: [].}
    writeBddFeature*: proc(req: UniversalPipelineRequest; initial: NegativeInvariantScan): Result[string, AxiomError] {.closure, raises: [CatchableError].}
    logStage*: proc(phase: StageKind; nodeId: string; detail: string; elapsedMs: int; status: StageStatus; extra: JsonNode) {.closure, raises: [].}
    runSelfHealingLoop*: proc(sourceCode: string; translation: UniversalTranslation; initial: NegativeInvariantScan; maxRounds: int; activeInvariant: string): tuple[finalSource: string, finalScan: NegativeInvariantScan, rounds: seq[HealingRound]] {.closure, raises: [CatchableError].}

func validate*(ctx: HealingContext) {.raises: [].} =
  doAssert ctx.loadPromotionFromProofVault != nil
  doAssert ctx.syncRecoveredSourceToModule != nil
  doAssert ctx.writeReproductionArtifact != nil
  doAssert ctx.writeBddFeature != nil
  doAssert ctx.logStage != nil
  doAssert ctx.runSelfHealingLoop != nil
{.pop.}
