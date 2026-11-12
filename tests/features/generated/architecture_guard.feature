@generated @high
Feature: architecture_guard
  # generated | src/gate/runners/architecture_guard.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/runners/architecture_guard" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/runners/architecture_guard" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
