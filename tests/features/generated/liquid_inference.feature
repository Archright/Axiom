@generated @critical
Feature: liquid_inference
  # generated | src/core/type_system/liquid_inference.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/type_system/liquid_inference" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types InferenceState, env, loopVars, mutatedVars
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/type_system/liquid_inference" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs extractLoopBound, inferLiquidTypeEnv, getRefinementType, hasRefinementType, envToJson, envToInvariantCandidates, envToLiquidSmtAsserts
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type InferenceState is instantiable
    Given the module "core/type_system/liquid_inference" is loaded
    Then type InferenceState should be instantiable

  Scenario: type env is instantiable
    Given the module "core/type_system/liquid_inference" is loaded
    Then type env should be instantiable

  Scenario: type loopVars is instantiable
    Given the module "core/type_system/liquid_inference" is loaded
    Then type loopVars should be instantiable

  Scenario: type mutatedVars is instantiable
    Given the module "core/type_system/liquid_inference" is loaded
    Then type mutatedVars should be instantiable

  Scenario: func extractLoopBound is callable
    Given the module "core/type_system/liquid_inference" is loaded
    Then func extractLoopBound should return a valid value

  Scenario: func inferLiquidTypeEnv is callable
    Given the module "core/type_system/liquid_inference" is loaded
    Then func inferLiquidTypeEnv should return a valid value

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
