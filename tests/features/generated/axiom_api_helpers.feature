@generated @critical
Feature: axiom_api_helpers
  # generated | src/core/api/axiom_api_helpers.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/api/axiom_api_helpers" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/api/axiom_api_helpers" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs describeError, stateDeltaWithinBalance, toSymbolicFailure, parseSemanticEnumLabels, parseSemanticEqualityPayloadJson, semanticEnumDatatypeDecl, semanticRuleString, buildSemanticEqualityPayloadSmt, encodeSemanticEqualityPayload
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func describeError is callable
    Given the module "core/api/axiom_api_helpers" is loaded
    Then func describeError should return a valid value

  Scenario: func stateDeltaWithinBalance is callable
    Given the module "core/api/axiom_api_helpers" is loaded
    Then func stateDeltaWithinBalance should return a valid value

  Scenario: func toSymbolicFailure is callable
    Given the module "core/api/axiom_api_helpers" is loaded
    Then func toSymbolicFailure should return a valid value

  Scenario: func parseSemanticEnumLabels is callable
    Given the module "core/api/axiom_api_helpers" is loaded
    Then func parseSemanticEnumLabels should return a valid value

  Scenario: func parseSemanticEqualityPayloadJson is callable
    Given the module "core/api/axiom_api_helpers" is loaded
    Then func parseSemanticEqualityPayloadJson should return a valid value

  Scenario: func semanticEnumDatatypeDecl is callable
    Given the module "core/api/axiom_api_helpers" is loaded
    Then func semanticEnumDatatypeDecl should return a valid value

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
