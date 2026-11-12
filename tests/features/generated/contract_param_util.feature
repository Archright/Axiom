@generated @critical
Feature: contract_param_util
  # generated | src/core/contract/contract_param_util.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/contract/contract_param_util" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/contract/contract_param_util" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs detectParams, detectParamNames, generateTypeDrivenContracts, inferTypeFromSmtUsage
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func detectParams is callable
    Given the module "core/contract/contract_param_util" is loaded
    Then func detectParams should return a valid value

  Scenario: func detectParamNames is callable
    Given the module "core/contract/contract_param_util" is loaded
    Then func detectParamNames should return a valid value

  Scenario: func generateTypeDrivenContracts is callable
    Given the module "core/contract/contract_param_util" is loaded
    Then func generateTypeDrivenContracts should return a valid value

  Scenario: func inferTypeFromSmtUsage is callable
    Given the module "core/contract/contract_param_util" is loaded
    Then func inferTypeFromSmtUsage should return a valid value
