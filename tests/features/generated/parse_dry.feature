@generated @critical
Feature: parse_dry
  # generated | src/core/policy/parsers/parse_dry.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/policy/parsers/parse_dry" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/policy/parsers/parse_dry" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}
