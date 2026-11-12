@generated @critical
Feature: pipeline_types
  # generated | src/core/orchestration/pipeline_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/orchestration/pipeline_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types PersonaDispatchFn, LoopAccumulators, globalRegistry, goalDeltas, visitedStates, stagnation, iteration, kInductionPayload, detected, legislated, scribed, judged
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/orchestration/pipeline_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs newPipelineContext, applySwatResult, applyDetectiveOpenResult, applyLegislatorResult, applyScribeResult, applyJudgeResult, applyPostProcessResult, extractDispatchResult
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type PersonaDispatchFn is instantiable
    Given the module "core/orchestration/pipeline_types" is loaded
    Then type PersonaDispatchFn should be instantiable

  Scenario: type LoopAccumulators is instantiable
    Given the module "core/orchestration/pipeline_types" is loaded
    Then type LoopAccumulators should be instantiable

  Scenario: type globalRegistry is instantiable
    Given the module "core/orchestration/pipeline_types" is loaded
    Then type globalRegistry should be instantiable

  Scenario: type goalDeltas is instantiable
    Given the module "core/orchestration/pipeline_types" is loaded
    Then type goalDeltas should be instantiable

  Scenario: type visitedStates is instantiable
    Given the module "core/orchestration/pipeline_types" is loaded
    Then type visitedStates should be instantiable

  Scenario: type stagnation is instantiable
    Given the module "core/orchestration/pipeline_types" is loaded
    Then type stagnation should be instantiable

  # +14 more scenarios (types+funcs) omitted to stay under 50 lines
