@generated @critical
Feature: tautology_checker
  # generated | src/core/judge/tautology_checker.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/judge/tautology_checker" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/judge/tautology_checker" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs isTautologyConstraint
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func isTautologyConstraint is callable
    Given the module "core/judge/tautology_checker" is loaded
    Then func isTautologyConstraint should return a valid value
