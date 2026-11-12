@generated @critical
Feature: lock_update
  # generated | src/core/topology/lock_update.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/lock_update" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/lock_update" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs renderLockJson
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func renderLockJson is callable
    Given the module "core/topology/lock_update" is loaded
    Then func renderLockJson should return a valid value
