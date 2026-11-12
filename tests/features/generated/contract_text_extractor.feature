@generated @critical
Feature: contract_text_extractor
  # generated | src/core/contract/contract_text_extractor.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/contract/contract_text_extractor" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/contract/contract_text_extractor" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs extractIndexTarget, extractIndexExpr, isStringContext, extractContractFromNimBodyText
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func extractIndexTarget is callable
    Given the module "core/contract/contract_text_extractor" is loaded
    Then func extractIndexTarget should return a valid value

  Scenario: func extractIndexExpr is callable
    Given the module "core/contract/contract_text_extractor" is loaded
    Then func extractIndexExpr should return a valid value

  Scenario: func isStringContext is callable
    Given the module "core/contract/contract_text_extractor" is loaded
    Then func isStringContext should return a valid value

  Scenario: func extractContractFromNimBodyText is callable
    Given the module "core/contract/contract_text_extractor" is loaded
    Then func extractContractFromNimBodyText should return a valid value
