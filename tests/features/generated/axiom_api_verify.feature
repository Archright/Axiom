@generated @critical
Feature: axiom_api_verify
  # generated | src/core/api/axiom_api_verify.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/api/axiom_api_verify" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/api/axiom_api_verify" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs verifyRaceCondition, verifyUserCodeRace, encodeTransitionSmt
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func verifyRaceCondition is callable
    Given the module "core/api/axiom_api_verify" is loaded
    Then func verifyRaceCondition should return a valid value

  Scenario: func verifyUserCodeRace is callable
    Given the module "core/api/axiom_api_verify" is loaded
    Then func verifyUserCodeRace should return a valid value

  Scenario: func encodeTransitionSmt is callable
    Given the module "core/api/axiom_api_verify" is loaded
    Then func encodeTransitionSmt should return a valid value
