import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/boundary/persona_interface
import verification/pipeline_state_types
# axiomIoBoundary

func runJudgeStage*(
  scribed: ScribedState;
  judgeArt: JudgeArtifact
): JudgedState {.raises: [].} =
  ## Judge stage: transforms JudgeArtifact into typed JudgedState.
  toJudgedState(
    scribed,
    judgeArt.finalInvariant,
    judgeArt.finalSource,
    judgeArt.nearestDiagnostic,
    judgeArt.failedReplayAttempts,
    judgeArt.leanKernelVerified,
    judgeArt.proofDepth,
    judgeArt.vacuityProven,
    judgeArt.negativeMutationPass
  )

{.pop.}
