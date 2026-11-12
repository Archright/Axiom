import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/boundary/persona_interface
import core/contracts/universal_pipeline_contract
import core/diagnostics/refactoring_engine
import core/domain_types
import core/logic/universal_translation_types
import core/pipeline_core_types
import core/remediation_types
import core/verification_unit
import std/options
import std/strutils
import verification/cegar_bmc_bridge
# axiomIoBoundary

proc runCegarBridgeStage*(
  sourceCode: string;
  caseArt: DetectiveArtifact;
  translation: UniversalTranslation;
  modulePath: string;
  functionName: string
): Option[UniversalPipelineResult] {.raises: [].} =
  ## CEGAR-BMC bridge stage.
  ##
  ## Returns Some(result) if CEGAR counterexample + BMC violation detected.
  ## Returns None if no counterexample or no violation.

  if not caseArt.cegarCounterexample:
    return none(UniversalPipelineResult)

  let bridgeResult = bridgeCegarToBmc(sourceCode)
  if not bridgeResult.bmcVerdict.violationDetected:
    return none(UniversalPipelineResult)

  some(UniversalPipelineResult(
    translation: translation,
    provenLayer: plkL2Cegar,
    verificationVerdict: "cegar_counterexample",
    vkdFixed4: "0.0000",
    synergyMetrics: SynergyMetrics(
      fFactor: 0.0, gFactor: 0.0, hFactor: 0.0, geometricMean: 0.0
    ),
    nearestDiscontinuities: @[MathematicalDiscontinuity(
      filePath: modulePath,
      lineNumber: 0,
      smtUnsatCoreVars: caseArt.unsatCoreVars,
      discontinuityKind: dkMissingInvariant,
      description: bridgeResult.concreteWitness
    )],
    structuredRemediation: StructuredRemediationPayload(
      discontinuities: @[MathematicalDiscontinuity(
        filePath: modulePath,
        lineNumber: 0,
        smtUnsatCoreVars: caseArt.unsatCoreVars,
        discontinuityKind: dkMissingInvariant,
        description: bridgeResult.concreteWitness
      )],
      suggestedPatterns: @[],
      refactoringTemplates: generateTemplates(classifySignals(
        0, 0, 0, 0,
        sourceCode.contains("while ") or sourceCode.contains("for "),
        functionName.len > 0 and sourceCode.contains(functionName & "(")
      ))
    ),
    remediationJson: ""
  ))
{.pop.}
