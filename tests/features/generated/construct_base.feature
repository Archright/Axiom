@generated @critical
Feature: construct_base
  # generated | src/core/solver/construct_base.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/solver/construct_base" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/solver/construct_base" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs symInt, intLit, boolLit, ite
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func symInt is callable
    Given the module "core/solver/construct_base" is loaded
    Then func symInt should return a valid value

  Scenario: func intLit is callable
    Given the module "core/solver/construct_base" is loaded
    Then func intLit should return a valid value

  Scenario: func boolLit is callable
    Given the module "core/solver/construct_base" is loaded
    Then func boolLit should return a valid value

  Scenario: func ite is callable
    Given the module "core/solver/construct_base" is loaded
    Then func ite should return a valid value
