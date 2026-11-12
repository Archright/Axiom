@generated @critical
Feature: construct_arithmetic
  # generated | src/core/solver/construct_arithmetic.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/solver/construct_arithmetic" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/solver/construct_arithmetic" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs add, sub, mul
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func add is callable
    Given the module "core/solver/construct_arithmetic" is loaded
    Then func add should return a valid value

  Scenario: func sub is callable
    Given the module "core/solver/construct_arithmetic" is loaded
    Then func sub should return a valid value

  Scenario: func mul is callable
    Given the module "core/solver/construct_arithmetic" is loaded
    Then func mul should return a valid value
