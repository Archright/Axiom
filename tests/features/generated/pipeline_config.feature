@generated @critical
Feature: pipeline_config
  # generated | src/core/orchestration/pipeline_config.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/orchestration/pipeline_config" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types PipelineConfig, req, translation, priorPromotion, maxIterations, guardNodeId, guardStartTime
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/orchestration/pipeline_config" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type PipelineConfig is instantiable
    Given the module "core/orchestration/pipeline_config" is loaded
    Then type PipelineConfig should be instantiable

  Scenario: type req is instantiable
    Given the module "core/orchestration/pipeline_config" is loaded
    Then type req should be instantiable

  Scenario: type translation is instantiable
    Given the module "core/orchestration/pipeline_config" is loaded
    Then type translation should be instantiable

  Scenario: type priorPromotion is instantiable
    Given the module "core/orchestration/pipeline_config" is loaded
    Then type priorPromotion should be instantiable

  Scenario: type maxIterations is instantiable
    Given the module "core/orchestration/pipeline_config" is loaded
    Then type maxIterations should be instantiable

  Scenario: type guardNodeId is instantiable
    Given the module "core/orchestration/pipeline_config" is loaded
    Then type guardNodeId should be instantiable

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
