import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/boundary/persona_interface
import verification/pipeline_state_types
# axiomIoBoundary

func runLegislatorStage*(
  detected: DetectedState;
  draftArt: LegislatorArtifact;
  healedSource: string
): LegislatedState {.raises: [].} =
  ## Legislator stage: transforms LegislatorArtifact into typed LegislatedState.
  toLegislatedState(
    detected,
    draftArt.baselineInvariant,
    draftArt.refinedInvariant,
    draftArt.activeInvariant,
    healedSource,
    draftArt.evolutionReasoning,
    draftArt.logLines
  )

{.pop.}
