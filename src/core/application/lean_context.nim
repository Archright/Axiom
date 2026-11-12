import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Lean Context — Bounded context for Lean prover callbacks
##
## Extracted from PersonaContext (Phase 5 decomposition).
## Contains 4 Lean-related proc fields.
## Per AGENTS.md §0.6: Static First Enforcement.

import core/types/results
import core/judge/lean_replay
import core/logic/universal_translation_types
import core/types/pipeline_core_types
from core/boundary/verification_interface import
  LeanstralResult, LeanSpecInference

type
  LeanContext* = object
    ## Lean prover bounded context.
    ## Holds callbacks for Lean interaction, replay, and spec inference.
    callLeanstral*: proc(prompt: string): LeanstralResult {.closure, raises: [].}
    runLeanReplay*: proc(nodeId: string; leanSource: string): Result[LeanReplayResult, string] {.closure, raises: [].}
    runLeanProofRefinementLoop*: proc(req: UniversalPipelineRequest; translation: UniversalTranslation; sourceCode: string; activeInvariant: string; maxRounds: int): tuple[finalSource: string, finalInvariant: string, rounds: seq[HealingRound], nearestDiagnostic: string, failedReplayAttempts: int, leanKernelVerified: bool, vacuityProven: bool] {.closure, raises: [CatchableError].}
    inferLeanSpec*: proc(modulePath: string; functionName: string; translation: UniversalTranslation; sourceCode: string; activeInvariant: string; verificationVerdict: string): LeanSpecInference {.closure, raises: [].}

func validate*(ctx: LeanContext) {.raises: [].} =
  doAssert ctx.callLeanstral != nil
  doAssert ctx.runLeanReplay != nil
  doAssert ctx.runLeanProofRefinementLoop != nil
  doAssert ctx.inferLeanSpec != nil
{.pop.}
