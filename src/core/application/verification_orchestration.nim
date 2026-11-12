import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Verification Orchestration — Pure delegation procs for VerificationUnit.
##
## Extracted from core/types/verification_unit.nim (DEBT#232 SoC fix).
## These procs are orchestration logic, not type definitions.
## They delegate to callbacks injected via VerificationUnit — zero direct
## Infrastructure dependencies.

import core/types/verification_unit
import core/types/pipeline_core_types
import core/types/domain_types
import core/trusted/axiom_pragmas

proc runSelfHealing*(
  unit: VerificationUnit;
  sourceCode: string;
  translation: UniversalTranslation;
  initialScan: NegativeInvariantScan;
  priorInvariant: string
): tuple[finalSource: string, finalScan: NegativeInvariantScan, rounds: seq[HealingRound]] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  ## Pure function: source code + invariant → healed source + healing rounds.
  ## Behavior injected via callback — Domain은 Infrastructure를 모름.
  unit.doHeal(sourceCode, translation, initialScan, unit.maxRounds, priorInvariant)

proc runLeanProofRefinement*(
  unit: VerificationUnit;
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  sourceCode: string;
  activeInvariant: string
): tuple[
  finalSource: string;
  finalInvariant: string;
  rounds: seq[HealingRound];
  nearestDiagnostic: string;
  failedReplayAttempts: int;
  leanKernelVerified: bool;
  vacuityProven: bool
] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  ## Pure function: source + invariant → Lean-verified source + refined invariant.
  ## Behavior injected via callback.
  unit.doRefine(req, translation, sourceCode, activeInvariant, unit.maxRounds)

proc runFullVerificationCycle*(
  unit: VerificationUnit;
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  sourceCode: string;
  priorInvariant: string
): tuple[
  finalSource: string;
  finalInvariant: string;
  activeInvariant: string;
  rounds: seq[HealingRound];
  nearestDiagnostic: string;
  failedReplayAttempts: int
] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  ## Orchestrates self-healing → Lean refinement → invariant merge.
  ## All behavior injected — zero direct Infrastructure dependencies.
  let initialScan = unit.doScan(translation, sourceCode, priorInvariant)
  let healed = unit.runSelfHealing(sourceCode, translation, initialScan, priorInvariant)
  let refined = unit.runLeanProofRefinement(req, translation, healed.finalSource, priorInvariant)

  let activeInvariant =
    if refined.finalInvariant.len > 0:
      unit.doMerge(priorInvariant, refined.finalInvariant)
    else:
      priorInvariant

  result.finalSource = refined.finalSource
  result.finalInvariant = refined.finalInvariant
  result.activeInvariant = activeInvariant
  result.rounds = healed.rounds & refined.rounds
  result.nearestDiagnostic = refined.nearestDiagnostic
  result.failedReplayAttempts = refined.failedReplayAttempts

{.pop.}
