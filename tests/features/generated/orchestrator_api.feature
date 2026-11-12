@generated @critical
Feature: orchestrator_api
  # generated | src/core/orchestrator/orchestrator_api.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/orchestrator/orchestrator_api" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/orchestrator/orchestrator_api" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs initParallelTaskQueue, addPlanReproofNodes
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func initParallelTaskQueue is callable
    Given the module "core/orchestrator/orchestrator_api" is loaded
    Then func initParallelTaskQueue should return a valid value

  Scenario: func addPlanReproofNodes is callable
    Given the module "core/orchestrator/orchestrator_api" is loaded
    Then func addPlanReproofNodes should return a valid value
