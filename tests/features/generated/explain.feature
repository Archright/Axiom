@generated @critical
Feature: explain
  # generated | src/core/topology/explain.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/explain" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/explain" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs findModuleByPath
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func findModuleByPath is callable
    Given the module "core/topology/explain" is loaded
    Then func findModuleByPath should return a valid value
