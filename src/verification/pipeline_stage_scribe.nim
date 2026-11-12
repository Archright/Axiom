import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/boundary/persona_interface
import core/solver/solver_bridge
import verification/pipeline_state_types
# axiomIoBoundary

func runScribeStage*(
  legislated: LegislatedState;
  scribeArt: ScribeArtifact;
  kInductionResult: KInductionResult
): ScribedState {.raises: [].} =
  ## Scribe stage: transforms ScribeArtifact into typed ScribedState.
  ## Handles K-induction fallback when Scribe fails.

  var leanstralSource = ""
  if scribeArt.verified and scribeArt.theoremSource.len > 0:
    leanstralSource = scribeArt.theoremSource

  # K-induction fallback: if Scribe failed but K-induction produced verified Lean proof
  if leanstralSource.len == 0 and
     kInductionResult.leanProofScript.len > 0:
    leanstralSource = kInductionResult.leanProofScript

  toScribedState(
    legislated,
    leanstralLeanSource = leanstralSource,
    theoremSource = scribeArt.theoremSource,
    tacticTrace = "",  # scribeArt.tacticTrace is seq[string], not string
    verified = scribeArt.verified
  )
{.pop.}
