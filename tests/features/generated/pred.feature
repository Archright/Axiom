@generated @critical
Feature: pred
  # generated | src/core/parsers/pred.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/parsers/pred" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/parsers/pred" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs collectAssertConditions, collectIfConditions, hasAssertCondition, hasIfCondition, hasIdentifierNamed, hasCallTo, hasAssignmentTo, hasTypeWithFields, hasPragmaNamed, hasInfixOperator
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func collectAssertConditions is callable
    Given the module "core/parsers/pred" is loaded
    Then func collectAssertConditions should return a valid value

  Scenario: func collectIfConditions is callable
    Given the module "core/parsers/pred" is loaded
    Then func collectIfConditions should return a valid value

  Scenario: func hasAssertCondition is callable
    Given the module "core/parsers/pred" is loaded
    Then func hasAssertCondition should return a valid value

  Scenario: func hasIfCondition is callable
    Given the module "core/parsers/pred" is loaded
    Then func hasIfCondition should return a valid value

  Scenario: func hasIdentifierNamed is callable
    Given the module "core/parsers/pred" is loaded
    Then func hasIdentifierNamed should return a valid value

  Scenario: func hasCallTo is callable
    Given the module "core/parsers/pred" is loaded
    Then func hasCallTo should return a valid value

  # +4 more scenarios (types+funcs) omitted to stay under 50 lines
