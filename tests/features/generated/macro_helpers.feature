@generated @critical
Feature: macro_helpers
  # generated | src/core/policy/macro_helpers.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/policy/macro_helpers" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/policy/macro_helpers" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs getActualObjectImpl, extractFields
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func getActualObjectImpl is callable
    Given the module "core/policy/macro_helpers" is loaded
    Then func getActualObjectImpl should return a valid value

  Scenario: func extractFields is callable
    Given the module "core/policy/macro_helpers" is loaded
    Then func extractFields should return a valid value
