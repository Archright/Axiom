@generated @critical
Feature: healing_context
  # generated | src/core/application/healing_context.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/application/healing_context" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types HealingContext, loadPromotionFromProofVault, syncRecoveredSourceToModule, writeReproductionArtifact, writeBddFeature, logStage, runSelfHealingLoop
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/application/healing_context" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs validate
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type HealingContext is instantiable
    Given the module "core/application/healing_context" is loaded
    Then type HealingContext should be instantiable

  Scenario: type loadPromotionFromProofVault is instantiable
    Given the module "core/application/healing_context" is loaded
    Then type loadPromotionFromProofVault should be instantiable

  Scenario: type syncRecoveredSourceToModule is instantiable
    Given the module "core/application/healing_context" is loaded
    Then type syncRecoveredSourceToModule should be instantiable

  Scenario: type writeReproductionArtifact is instantiable
    Given the module "core/application/healing_context" is loaded
    Then type writeReproductionArtifact should be instantiable

  Scenario: type writeBddFeature is instantiable
    Given the module "core/application/healing_context" is loaded
    Then type writeBddFeature should be instantiable

  Scenario: type logStage is instantiable
    Given the module "core/application/healing_context" is loaded
    Then type logStage should be instantiable

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
