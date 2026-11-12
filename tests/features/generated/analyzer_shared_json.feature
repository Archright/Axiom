@generated @high
Feature: analyzer_shared_json
  # generated | src/verification/analyzer/analyzer_shared_json.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/analyzer/analyzer_shared_json" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/analyzer/analyzer_shared_json" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func mergeStringEvidence is callable
    Given the module "verification/analyzer/analyzer_shared_json" is loaded
    Then func mergeStringEvidence should return a valid value

  Scenario: func keyToStatus is callable
    Given the module "verification/analyzer/analyzer_shared_json" is loaded
    Then func keyToStatus should return a valid value

  Scenario: func toStringList is callable
    Given the module "verification/analyzer/analyzer_shared_json" is loaded
    Then func toStringList should return a valid value

  Scenario: func firstStringField is callable
    Given the module "verification/analyzer/analyzer_shared_json" is loaded
    Then func firstStringField should return a valid value

  Scenario: func firstBoolField is callable
    Given the module "verification/analyzer/analyzer_shared_json" is loaded
    Then func firstBoolField should return a valid value

  Scenario: func firstArrayField is callable
    Given the module "verification/analyzer/analyzer_shared_json" is loaded
    Then func firstArrayField should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
