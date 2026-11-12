@generated @critical
Feature: sync_utils_process
  # generated | src/core/sync/sync_utils_process.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/sync/sync_utils_process" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/sync/sync_utils_process" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs killManagedProcess
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func killManagedProcess is callable
    Given the module "core/sync/sync_utils_process" is loaded
    Then func killManagedProcess should return a valid value
