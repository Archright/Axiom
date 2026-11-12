@generated @high
Feature: nimtry_extract_part3_part2
  # generated | src/gate/nimtry/nimtry_extract_part3_part2.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/nimtry_extract_part3_part2" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/nimtry_extract_part3_part2" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func extractWhenBlocksV4 is callable
    Given the module "gate/nimtry/nimtry_extract_part3_part2" is loaded
    Then func extractWhenBlocksV4 should return a valid value

  Scenario: func countCaseBranches is callable
    Given the module "gate/nimtry/nimtry_extract_part3_part2" is loaded
    Then func countCaseBranches should return a valid value
