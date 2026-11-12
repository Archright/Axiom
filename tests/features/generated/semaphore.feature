@generated @high
Feature: semaphore
  # generated | src/gate/semaphore.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/semaphore" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/semaphore" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func initJobSemaphore is callable
    Given the module "gate/semaphore" is loaded
    Then func initJobSemaphore should return a valid value

  Scenario: func acquire is callable
    Given the module "gate/semaphore" is loaded
    Then func acquire should return a valid value

  Scenario: func release is callable
    Given the module "gate/semaphore" is loaded
    Then func release should return a valid value
