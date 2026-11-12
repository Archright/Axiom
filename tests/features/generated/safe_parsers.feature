@generated @critical
Feature: safe_parsers
  # generated | src/core/parsers/safe_parsers.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/parsers/safe_parsers" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/parsers/safe_parsers" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs safeParseInt, safeParseFloat, safeParseBool, safeParseNatural
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func safeParseInt is callable
    Given the module "core/parsers/safe_parsers" is loaded
    Then func safeParseInt should return a valid value

  Scenario: func safeParseFloat is callable
    Given the module "core/parsers/safe_parsers" is loaded
    Then func safeParseFloat should return a valid value

  Scenario: func safeParseBool is callable
    Given the module "core/parsers/safe_parsers" is loaded
    Then func safeParseBool should return a valid value

  Scenario: func safeParseNatural is callable
    Given the module "core/parsers/safe_parsers" is loaded
    Then func safeParseNatural should return a valid value
