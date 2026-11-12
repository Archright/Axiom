@generated @critical
Feature: vault_factory
  # generated | src/core/vault/vault_factory.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/vault/vault_factory" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types Vault, backend, storagePath
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/vault/vault_factory" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs sessionLookupJson, traceLookupJson, saveSession, saveProof, getProof, findTraceByRef, listSessions
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type Vault is instantiable
    Given the module "core/vault/vault_factory" is loaded
    Then type Vault should be instantiable

  Scenario: type backend is instantiable
    Given the module "core/vault/vault_factory" is loaded
    Then type backend should be instantiable

  Scenario: type storagePath is instantiable
    Given the module "core/vault/vault_factory" is loaded
    Then type storagePath should be instantiable

  Scenario: func sessionLookupJson is callable
    Given the module "core/vault/vault_factory" is loaded
    Then func sessionLookupJson should return a valid value

  Scenario: func traceLookupJson is callable
    Given the module "core/vault/vault_factory" is loaded
    Then func traceLookupJson should return a valid value

  Scenario: func saveSession is callable
    Given the module "core/vault/vault_factory" is loaded
    Then func saveSession should return a valid value

  # +4 more scenarios (types+funcs) omitted to stay under 50 lines
