@generated @critical
Feature: universal_pipeline_contract
  # generated | src/core/contracts/universal_pipeline_contract.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/contracts/universal_pipeline_contract" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types SemanticProofGoal, SemanticEqualityPayload, schemaVersion, modulePath, functionName, enumTypeName, leftSymbol, rightSymbol, throwsSymbol, enumValues, proofGoal, unsatCore, UniversalPipelineResult, translation, inferredSpec, provenance, dependencyContext, fingerprints, smtTrack, leanTrack, initialScan, finalScan, healedSource, rounds, asiFixed4, refinedInvariant, evolutionReasoning, pocSnippet, activeInvariant, verificationVerdict, verificationVerdictReport, traceReport, personaLogs, proofArtifactPath, proofSummaryPath, evolutionHit, bddFeaturePath, reproductionPath, promotionSnapshotPath, provenLayer, synergyMetrics, nearestDiscontinuities, structuredRemediation, proofArtifact, preConditions, postConditions, remediationJson
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/contracts/universal_pipeline_contract" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs isSemanticPayloadSchemaVersion, isValidSmtIdentifier, extractBaseName, buildSemanticLeanTheoremName, latestSemanticReplayFeedback, semanticReplayFailureCount
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type SemanticProofGoal is instantiable
    Given the module "core/contracts/universal_pipeline_contract" is loaded
    Then type SemanticProofGoal should be instantiable

  Scenario: type SemanticEqualityPayload is instantiable
    Given the module "core/contracts/universal_pipeline_contract" is loaded
    Then type SemanticEqualityPayload should be instantiable

  Scenario: type schemaVersion is instantiable
    Given the module "core/contracts/universal_pipeline_contract" is loaded
    Then type schemaVersion should be instantiable

  Scenario: type modulePath is instantiable
    Given the module "core/contracts/universal_pipeline_contract" is loaded
    Then type modulePath should be instantiable

  Scenario: type functionName is instantiable
    Given the module "core/contracts/universal_pipeline_contract" is loaded
    Then type functionName should be instantiable

  Scenario: type enumTypeName is instantiable
    Given the module "core/contracts/universal_pipeline_contract" is loaded
    Then type enumTypeName should be instantiable

  # +47 more scenarios (types+funcs) omitted to stay under 50 lines
