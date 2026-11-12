@generated @critical
Feature: contract_ast_extractor
  # generated | src/core/contract/contract_ast_extractor.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/contract/contract_ast_extractor" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/contract/contract_ast_extractor" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs extractContractFromNimBody, scanAstForCertifiedExemption
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func extractContractFromNimBody is callable
    Given the module "core/contract/contract_ast_extractor" is loaded
    Then func extractContractFromNimBody should return a valid value

  Scenario: func scanAstForCertifiedExemption is callable
    Given the module "core/contract/contract_ast_extractor" is loaded
    Then func scanAstForCertifiedExemption should return a valid value
