@generated @high
Feature: cegar_bmc_bridge
  # generated | src/verification/cegar_bmc_bridge.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/cegar_bmc_bridge" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/cegar_bmc_bridge" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
