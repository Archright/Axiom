import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/boundary/persona_interface
import core/lean_lsp_types
import verification/pipeline_state_types
# axiomIoBoundary

func runDetectiveStage*(
  input: PipelineInput;
  caseArt: DetectiveArtifact;
  priorCxHistory: seq[CounterExamplePayload];
  goalDeltas: seq[GoalDelta]
): DetectedState {.raises: [].} =
  ## Detective stage: transforms DetectiveArtifact into typed DetectedState.
  toDetectedState(
    input,
    caseArt.priorPromotion,
    caseArt.initialScan,
    caseArt.evolutionHit,
    caseArt.traceReport,
    cxHistory = priorCxHistory,
    unsatCoreVars = caseArt.unsatCoreVars,
    cegarCounterexample = caseArt.cegarCounterexample,
    goalDeltas = goalDeltas
  )
{.pop.}
