@generated @critical
Feature: vault_manager_spec
  # generated | src/core/vault/vault_manager_spec.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/vault/vault_manager_spec" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types AxiomInvalidError
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/vault/vault_manager_spec" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs axiomInvalidErrorMessage, vaultLoadErrorMessage, invalidLoadError, storageLoadError, computeSourceFingerprint, ownedAxiomSpec, sanitizeVaultToken, axiomSpecFileName, axiomSpecToJsonNode, parseAxiomSpec, loadAxiomSpec
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type AxiomInvalidError is instantiable
    Given the module "core/vault/vault_manager_spec" is loaded
    Then type AxiomInvalidError should be instantiable

  Scenario: func axiomInvalidErrorMessage is callable
    Given the module "core/vault/vault_manager_spec" is loaded
    Then func axiomInvalidErrorMessage should return a valid value

  Scenario: func vaultLoadErrorMessage is callable
    Given the module "core/vault/vault_manager_spec" is loaded
    Then func vaultLoadErrorMessage should return a valid value

  Scenario: func invalidLoadError is callable
    Given the module "core/vault/vault_manager_spec" is loaded
    Then func invalidLoadError should return a valid value

  Scenario: func storageLoadError is callable
    Given the module "core/vault/vault_manager_spec" is loaded
    Then func storageLoadError should return a valid value

  Scenario: func computeSourceFingerprint is callable
    Given the module "core/vault/vault_manager_spec" is loaded
    Then func computeSourceFingerprint should return a valid value

  # +6 more scenarios (types+funcs) omitted to stay under 50 lines
