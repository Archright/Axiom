@generated @high
Feature: pipeline_core_runner
  # generated | src/verification/pipeline_core_runner.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/pipeline_core_runner" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/pipeline_core_runner" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
