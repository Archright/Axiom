@generated @critical
Feature: cegar_bmc_types
  # generated | src/core/orchestrator/cegar_bmc_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/orchestrator/cegar_bmc_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types CegarBmcResult, cegarVerdict, bmcVerdict, concreteWitness, propertyKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/orchestrator/cegar_bmc_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type CegarBmcResult is instantiable
    Given the module "core/orchestrator/cegar_bmc_types" is loaded
    Then type CegarBmcResult should be instantiable

  Scenario: type cegarVerdict is instantiable
    Given the module "core/orchestrator/cegar_bmc_types" is loaded
    Then type cegarVerdict should be instantiable

  Scenario: type bmcVerdict is instantiable
    Given the module "core/orchestrator/cegar_bmc_types" is loaded
    Then type bmcVerdict should be instantiable

  Scenario: type concreteWitness is instantiable
    Given the module "core/orchestrator/cegar_bmc_types" is loaded
    Then type concreteWitness should be instantiable

  Scenario: type propertyKind is instantiable
    Given the module "core/orchestrator/cegar_bmc_types" is loaded
    Then type propertyKind should be instantiable
