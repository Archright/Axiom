@generated @high
Feature: pipeline_state_types
  # generated | src/verification/pipeline_state_types.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/pipeline_state_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types DetectiveContext, detectiveInput, kInductionPayload, ScribedState, req, translation, healedSource, seededInvariant, leanstralLeanSource, theoremSource, tacticTrace, verified, VerificationVerdict
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/pipeline_state_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type DetectiveContext is instantiable
    Given the module "verification/pipeline_state_types" is loaded
    Then type DetectiveContext should be instantiable

  Scenario: type detectiveInput is instantiable
    Given the module "verification/pipeline_state_types" is loaded
    Then type detectiveInput should be instantiable

  Scenario: type kInductionPayload is instantiable
    Given the module "verification/pipeline_state_types" is loaded
    Then type kInductionPayload should be instantiable

  Scenario: type ScribedState is instantiable
    Given the module "verification/pipeline_state_types" is loaded
    Then type ScribedState should be instantiable

  Scenario: type req is instantiable
    Given the module "verification/pipeline_state_types" is loaded
    Then type req should be instantiable

  Scenario: type translation is instantiable
    Given the module "verification/pipeline_state_types" is loaded
    Then type translation should be instantiable

  # +8 more scenarios (types+funcs) omitted to stay under 50 lines
