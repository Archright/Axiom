import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/application/persona_context
import core/pipeline_core_types
import core/types/translation_types
import verification/healing_orchestrator
# axiomIoBoundary

func registerHealing*(ctx: var PersonaContext) {.raises: [].} =
  ctx.runSelfHealingLoop = proc(sourceCode: string; translation: UniversalTranslation; initial: NegativeInvariantScan; maxRounds: int; activeInvariant: string): tuple[finalSource: string, finalScan: NegativeInvariantScan, rounds: seq[HealingRound]] {.closure, raises: [CatchableError].} =
    healing_orchestrator.runSelfHealingLoop(sourceCode, translation, initial, maxRounds, activeInvariant)

  ctx.runLeanProofRefinementLoop = proc(req: UniversalPipelineRequest; translation: UniversalTranslation; sourceCode: string; activeInvariant: string; maxRounds: int): tuple[finalSource: string, finalInvariant: string, rounds: seq[HealingRound], nearestDiagnostic: string, failedReplayAttempts: int, leanKernelVerified: bool, vacuityProven: bool] {.closure, raises: [CatchableError].} =
    healing_orchestrator.runLeanProofRefinementLoop(req, translation, sourceCode, activeInvariant, maxRounds)

{.pop.}
