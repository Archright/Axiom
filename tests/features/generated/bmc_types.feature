@generated @critical
Feature: bmc_types
  # generated | src/core/bmc/bmc_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/bmc/bmc_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types InvariantKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/bmc/bmc_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs makeMinValueInvariant, makeMaxValueInvariant, makeSubtractRule, makeAddRule
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type InvariantKind is instantiable
    Given the module "core/bmc/bmc_types" is loaded
    Then type InvariantKind should be instantiable

  Scenario: func makeMinValueInvariant is callable
    Given the module "core/bmc/bmc_types" is loaded
    Then func makeMinValueInvariant should return a valid value

  Scenario: func makeMaxValueInvariant is callable
    Given the module "core/bmc/bmc_types" is loaded
    Then func makeMaxValueInvariant should return a valid value

  Scenario: func makeSubtractRule is callable
    Given the module "core/bmc/bmc_types" is loaded
    Then func makeSubtractRule should return a valid value

  Scenario: func makeAddRule is callable
    Given the module "core/bmc/bmc_types" is loaded
    Then func makeAddRule should return a valid value
