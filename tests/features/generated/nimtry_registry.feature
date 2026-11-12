@generated @high
Feature: nimtry_registry
  # generated | src/gate/nimtry/nimtry_registry.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/nimtry_registry" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types CheckerProc
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/nimtry_registry" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type CheckerProc is instantiable
    Given the module "gate/nimtry/nimtry_registry" is loaded
    Then type CheckerProc should be instantiable
