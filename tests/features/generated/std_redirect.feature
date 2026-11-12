@generated @critical
Feature: std_redirect
  # generated | src/core/json/std_redirect.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/json/std_redirect" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/json/std_redirect" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs parseJson
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func parseJson is callable
    Given the module "core/json/std_redirect" is loaded
    Then func parseJson should return a valid value
