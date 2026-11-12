@generated @critical
Feature: suggest
  # generated | src/core/topology/suggest.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/suggest" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types SuggestionSeverity
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/suggest" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs severityFromString, severityToString, actionToString, inAllowedPath, locationDriftSeverity, locationDriftSuggestion, runDeclarationAudit, suggestFromPolicyViolation, runTopologyAuditWithSuggestions, formatSuggestionHuman, formatResultJson
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type SuggestionSeverity is instantiable
    Given the module "core/topology/suggest" is loaded
    Then type SuggestionSeverity should be instantiable

  Scenario: func severityFromString is callable
    Given the module "core/topology/suggest" is loaded
    Then func severityFromString should return a valid value

  Scenario: func severityToString is callable
    Given the module "core/topology/suggest" is loaded
    Then func severityToString should return a valid value

  Scenario: func actionToString is callable
    Given the module "core/topology/suggest" is loaded
    Then func actionToString should return a valid value

  Scenario: func inAllowedPath is callable
    Given the module "core/topology/suggest" is loaded
    Then func inAllowedPath should return a valid value

  Scenario: func locationDriftSeverity is callable
    Given the module "core/topology/suggest" is loaded
    Then func locationDriftSeverity should return a valid value

  # +6 more scenarios (types+funcs) omitted to stay under 50 lines
