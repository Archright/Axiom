@generated @high
Feature: layer1_bmc
  # generated | src/verification/layer1_bmc.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/layer1_bmc" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/layer1_bmc" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func runLayer1Bmc is callable
    Given the module "verification/layer1_bmc" is loaded
    Then func runLayer1Bmc should return a valid value
