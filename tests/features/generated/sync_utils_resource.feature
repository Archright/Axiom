@generated @critical
Feature: sync_utils_resource
  # generated | src/core/sync/sync_utils_resource.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/sync/sync_utils_resource" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/sync/sync_utils_resource" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs deinitResourceSemaphore, readCpuLoadRatio, acquireResourceSemaphore, releaseResourceSemaphore, releaseTicket
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func deinitResourceSemaphore is callable
    Given the module "core/sync/sync_utils_resource" is loaded
    Then func deinitResourceSemaphore should return a valid value

  Scenario: func readCpuLoadRatio is callable
    Given the module "core/sync/sync_utils_resource" is loaded
    Then func readCpuLoadRatio should return a valid value

  Scenario: func acquireResourceSemaphore is callable
    Given the module "core/sync/sync_utils_resource" is loaded
    Then func acquireResourceSemaphore should return a valid value

  Scenario: func releaseResourceSemaphore is callable
    Given the module "core/sync/sync_utils_resource" is loaded
    Then func releaseResourceSemaphore should return a valid value

  Scenario: func releaseTicket is callable
    Given the module "core/sync/sync_utils_resource" is loaded
    Then func releaseTicket should return a valid value
