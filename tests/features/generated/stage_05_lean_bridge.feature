@generated @high
Feature: stage_05_lean_bridge
  # generated | src/verification/analyzer/stage_05_lean_bridge.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/analyzer/stage_05_lean_bridge" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/analyzer/stage_05_lean_bridge" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
