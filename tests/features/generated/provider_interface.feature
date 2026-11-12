@generated @critical
Feature: provider_interface
  # generated | src/core/trusted/provider_interface.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/trusted/provider_interface" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ProviderSolverStatus, ProviderResult, status, output, error, SolverProvider
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/trusted/provider_interface" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs toProviderStatus, toSolverStatus, providerStatusString, `==`, initZ3Provider, initLean4Provider, executeProof*[T: SolverProvider]
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type ProviderSolverStatus is instantiable
    Given the module "core/trusted/provider_interface" is loaded
    Then type ProviderSolverStatus should be instantiable

  Scenario: type ProviderResult is instantiable
    Given the module "core/trusted/provider_interface" is loaded
    Then type ProviderResult should be instantiable

  Scenario: type status is instantiable
    Given the module "core/trusted/provider_interface" is loaded
    Then type status should be instantiable

  Scenario: type output is instantiable
    Given the module "core/trusted/provider_interface" is loaded
    Then type output should be instantiable

  Scenario: type error is instantiable
    Given the module "core/trusted/provider_interface" is loaded
    Then type error should be instantiable

  Scenario: type SolverProvider is instantiable
    Given the module "core/trusted/provider_interface" is loaded
    Then type SolverProvider should be instantiable

  # +7 more scenarios (types+funcs) omitted to stay under 50 lines
