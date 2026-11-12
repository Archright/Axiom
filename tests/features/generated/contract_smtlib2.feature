@generated @critical
Feature: contract_smtlib2
  # generated | src/core/contract/contract_smtlib2.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/contract/contract_smtlib2" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/contract/contract_smtlib2" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs contractToSmtlib2
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func contractToSmtlib2 is callable
    Given the module "core/contract/contract_smtlib2" is loaded
    Then func contractToSmtlib2 should return a valid value
