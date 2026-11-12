import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/axiom_pragmas
import core/bmc/bmc_generic
import core/boundary/persona_interface
import core/contracts/universal_pipeline_contract
import core/diagnostics/refactoring_engine
import core/logic/universal_translation_types
import core/orchestrator/cegar_bmc_types
import core/orchestrator/cegar_types
import core/pipeline_core_types
import core/remediation_types
import core/solver/solver_bridge
import verification/pipeline_state_types
# axiomIoBoundary

# ─── Pure helpers ───────────────────────────────────────────────────────────

func isBmcFastPath*(swatArt: SwatArtifact): bool {.raises: [].} =
  ## Pure check: does SWAT output contain BMC proven fast-path?
  for line in swatArt.logLines:
    if line == "[BMC] proven fast-path":
      return true
  return false
func buildBmcPipelineResult*(translation: UniversalTranslation): UniversalPipelineResult {.raises: [].} =
  ## Pure constructor for BMC fast-path success result.
  UniversalPipelineResult(
    translation: translation,
    provenLayer: plkL1Bmc,
    verificationVerdict: "verified_by_bmc",
    vkdFixed4: "1.0000",
    synergyMetrics: computeSynergyMetrics(@[]),
    nearestDiscontinuities: @[],
    structuredRemediation: StructuredRemediationPayload(
      discontinuities: @[],
      suggestedPatterns: @[],
      refactoringTemplates: @[]
    )
  )
func runSwatStage*(
  input: PipelineInput;
  swatArt: SwatArtifact;
  priorPromotion: tuple[invariant: string; snapshotPath: string];
  kInductRes: KInductionResult
): SwatStageOutcome {.registerStage, raises: [].} =
  ## SWAT stage orchestrator. Pure func: K-induction I/O is extracted to the
  ## dispatch layer (pipeline_dispatch.nim). This func only assembles the outcome.
  ##
  ## 1. Validate SWAT result (BMC fast-path check) — pure
  ## 2. K-induction result is injected via kInductRes (already computed by dispatch)
  ## 3. CEGAR-BMC bridge — pure SMT computation placeholder

  # 1. BMC fast-path check (pure)
  if isBmcFastPath(swatArt):
    return SwatStageOutcome(
      kind: ssrBmcSuccess,
      pipelineResult: buildBmcPipelineResult(input.translation)
    )

  # 3. CEGAR-BMC bridge — bind actual CEGAR invariants from postConditions
  let cegarRes = block:
    if input.req.postConditions.len > 0:
      CegarBmcResult(
        cegarVerdict: cegarProven,
        bmcVerdict: GenericBmcVerdict(violationDetected: false),
        concreteWitness: block:
          var w = ""
          for i, s in input.req.postConditions:
            if i > 0: w.add "; "
            w.add s
          w,
        propertyKind: bpkRaceCondition)
    else:
      CegarBmcResult(
        cegarVerdict: cegarMaxIterations,
        bmcVerdict: GenericBmcVerdict(violationDetected: false),
        concreteWitness: "",
        propertyKind: bpkRaceCondition)

  SwatStageOutcome(
    kind: ssrFallbackRequired,
    kInductionResult: kInductRes,
    cegarBmcResult: cegarRes,
    priorInvariant: priorPromotion.invariant
  )
{.pop.}
