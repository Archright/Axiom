@generated @high
Feature: io_module_registry
  # generated | src/gate/nimtry/io_module_registry.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/io_module_registry" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/io_module_registry" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func isIoModule is callable
    Given the module "gate/nimtry/io_module_registry" is loaded
    Then func isIoModule should return a valid value

  Scenario: func hasEffectHint is callable
    Given the module "gate/nimtry/io_module_registry" is loaded
    Then func hasEffectHint should return a valid value

  Scenario: func isIoModuleOrHint is callable
    Given the module "gate/nimtry/io_module_registry" is loaded
    Then func isIoModuleOrHint should return a valid value
