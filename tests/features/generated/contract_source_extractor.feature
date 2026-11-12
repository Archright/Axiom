@generated @high
Feature: contract_source_extractor
  # generated | src/verification/contract_source_extractor.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/contract_source_extractor" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/contract_source_extractor" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func extractContractFromSource is callable
    Given the module "verification/contract_source_extractor" is loaded
    Then func extractContractFromSource should return a valid value

  Scenario: func extractContractAndParams is callable
    Given the module "verification/contract_source_extractor" is loaded
    Then func extractContractAndParams should return a valid value
