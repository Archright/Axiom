@generated @critical
Feature: parse_helpers
  # generated | src/core/policy/parse_helpers.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/policy/parse_helpers" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/policy/parse_helpers" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs sortedStrings, quoteTrim, parseStringArray, parseBoolValue, parseNatural, isKnownSection, requiresArray, isValidLayerGlob, addDiagnostic
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func sortedStrings is callable
    Given the module "core/policy/parse_helpers" is loaded
    Then func sortedStrings should return a valid value

  Scenario: func quoteTrim is callable
    Given the module "core/policy/parse_helpers" is loaded
    Then func quoteTrim should return a valid value

  Scenario: func parseStringArray is callable
    Given the module "core/policy/parse_helpers" is loaded
    Then func parseStringArray should return a valid value

  Scenario: func parseBoolValue is callable
    Given the module "core/policy/parse_helpers" is loaded
    Then func parseBoolValue should return a valid value

  Scenario: func parseNatural is callable
    Given the module "core/policy/parse_helpers" is loaded
    Then func parseNatural should return a valid value

  Scenario: func isKnownSection is callable
    Given the module "core/policy/parse_helpers" is loaded
    Then func isKnownSection should return a valid value

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
