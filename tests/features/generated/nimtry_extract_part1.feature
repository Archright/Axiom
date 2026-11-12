@generated @high
Feature: nimtry_extract_part1
  # generated | src/gate/nimtry/nimtry_extract_part1.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/nimtry_extract_part1" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/nimtry_extract_part1" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func isExportMarker is callable
    Given the module "gate/nimtry/nimtry_extract_part1" is loaded
    Then func isExportMarker should return a valid value

  Scenario: func extractName is callable
    Given the module "gate/nimtry/nimtry_extract_part1" is loaded
    Then func extractName should return a valid value

  Scenario: func calleeName is callable
    Given the module "gate/nimtry/nimtry_extract_part1" is loaded
    Then func calleeName should return a valid value

  Scenario: func qualifiedCalleeRec is callable
    Given the module "gate/nimtry/nimtry_extract_part1" is loaded
    Then func qualifiedCalleeRec should return a valid value

  Scenario: func recNodeCount is callable
    Given the module "gate/nimtry/nimtry_extract_part1" is loaded
    Then func recNodeCount should return a valid value

  Scenario: func fingerprintNode is callable
    Given the module "gate/nimtry/nimtry_extract_part1" is loaded
    Then func fingerprintNode should return a valid value

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
