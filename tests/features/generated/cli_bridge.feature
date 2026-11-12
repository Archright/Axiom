@generated @high
Feature: cli_bridge
  # generated | src/verification/cli_bridge.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/cli_bridge" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/cli_bridge" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
