@generated @critical
Feature: bmc_artifacts
  # generated | src/core/bmc/bmc_artifacts.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/bmc/bmc_artifacts" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types config, transitions, safetyProperty, varMap, scopeCtx
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/bmc/bmc_artifacts" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs isEmpty
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type config is instantiable
    Given the module "core/bmc/bmc_artifacts" is loaded
    Then type config should be instantiable

  Scenario: type transitions is instantiable
    Given the module "core/bmc/bmc_artifacts" is loaded
    Then type transitions should be instantiable

  Scenario: type safetyProperty is instantiable
    Given the module "core/bmc/bmc_artifacts" is loaded
    Then type safetyProperty should be instantiable

  Scenario: type varMap is instantiable
    Given the module "core/bmc/bmc_artifacts" is loaded
    Then type varMap should be instantiable

  Scenario: type scopeCtx is instantiable
    Given the module "core/bmc/bmc_artifacts" is loaded
    Then type scopeCtx should be instantiable

  Scenario: func isEmpty is callable
    Given the module "core/bmc/bmc_artifacts" is loaded
    Then func isEmpty should return a valid value
