@generated @high
Feature: nimtry_extract_part3_part1
  # generated | src/gate/nimtry/nimtry_extract_part3_part1.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/nimtry_extract_part3_part1" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/nimtry_extract_part3_part1" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func extractImportsV4 is callable
    Given the module "gate/nimtry/nimtry_extract_part3_part1" is loaded
    Then func extractImportsV4 should return a valid value

  Scenario: func extractFunctionsV4 is callable
    Given the module "gate/nimtry/nimtry_extract_part3_part1" is loaded
    Then func extractFunctionsV4 should return a valid value

  Scenario: func extractCallsV4 is callable
    Given the module "gate/nimtry/nimtry_extract_part3_part1" is loaded
    Then func extractCallsV4 should return a valid value

  Scenario: func extractAssignmentsV4 is callable
    Given the module "gate/nimtry/nimtry_extract_part3_part1" is loaded
    Then func extractAssignmentsV4 should return a valid value

  Scenario: func extractTypeDefsV4 is callable
    Given the module "gate/nimtry/nimtry_extract_part3_part1" is loaded
    Then func extractTypeDefsV4 should return a valid value

  Scenario: func extractConstStringsV4 is callable
    Given the module "gate/nimtry/nimtry_extract_part3_part1" is loaded
    Then func extractConstStringsV4 should return a valid value
