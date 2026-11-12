@generated @critical
Feature: refinement_controller
  # generated | src/core/logic/refinement_controller.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/logic/refinement_controller" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/logic/refinement_controller" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs counterExampleSeverity, totalControllerReward, unsatCoreSignature, isStagnating, containsUnsatCoreId, invariantRelevantToUnsatCore, roundReward, operatorScore, deterministicPercent, deterministicChoiceIndex
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func counterExampleSeverity is callable
    Given the module "core/logic/refinement_controller" is loaded
    Then func counterExampleSeverity should return a valid value

  Scenario: func totalControllerReward is callable
    Given the module "core/logic/refinement_controller" is loaded
    Then func totalControllerReward should return a valid value

  Scenario: func unsatCoreSignature is callable
    Given the module "core/logic/refinement_controller" is loaded
    Then func unsatCoreSignature should return a valid value

  Scenario: func isStagnating is callable
    Given the module "core/logic/refinement_controller" is loaded
    Then func isStagnating should return a valid value

  Scenario: func containsUnsatCoreId is callable
    Given the module "core/logic/refinement_controller" is loaded
    Then func containsUnsatCoreId should return a valid value

  Scenario: func invariantRelevantToUnsatCore is callable
    Given the module "core/logic/refinement_controller" is loaded
    Then func invariantRelevantToUnsatCore should return a valid value

  # +4 more scenarios (types+funcs) omitted to stay under 50 lines
