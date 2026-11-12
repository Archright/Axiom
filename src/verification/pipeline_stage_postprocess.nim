import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/boundary/persona_interface
import core/contracts/universal_pipeline_contract
import core/pipeline_core_types
import core/proof/proof_artifact
import verification/pipeline_state_types
# axiomIoBoundary

func runPostProcessStage*(
  judged: JudgedState;
  postArt: DetectiveArtifact
): UniversalPipelineResult {.raises: [].} =
  ## Post-process stage: assembles final UniversalPipelineResult from judged state.
  let invariantId = "postprocess-" & judged.finalInvariant
  UniversalPipelineResult(
    translation: judged.translation,
    healedSource: judged.healedSource,
    refinedInvariant: judged.finalInvariant,
    activeInvariant: judged.finalInvariant,
    provenLayer: plkL3Scribe,
    leanTrack: UniversalLeanTrack(
      theoremSource: judged.finalSource,
      verified: judged.leanKernelVerified,
      vacuityProven: judged.vacuityProven,
      negativeMutationPass: judged.negativeMutationPass
    ),
    proofArtifact: ProofArtifact(
      nodeId: invariantId,
      kind: pakProven,
      provenLayer: "l3-scribe"
    )
  )
{.pop.}
