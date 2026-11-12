@generated @critical
Feature: type_registry
  # generated | src/core/boundary/type_registry.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/boundary/type_registry" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types TypeRegistry
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/boundary/type_registry" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs get, setFieldCount, canonicalizeTypeName, heuristicFieldWeight, lookupTypeFields, isComplexType, buildTypeRegistry
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type TypeRegistry is instantiable
    Given the module "core/boundary/type_registry" is loaded
    Then type TypeRegistry should be instantiable

  Scenario: func get is callable
    Given the module "core/boundary/type_registry" is loaded
    Then func get should return a valid value

  Scenario: func setFieldCount is callable
    Given the module "core/boundary/type_registry" is loaded
    Then func setFieldCount should return a valid value

  Scenario: func canonicalizeTypeName is callable
    Given the module "core/boundary/type_registry" is loaded
    Then func canonicalizeTypeName should return a valid value

  Scenario: func heuristicFieldWeight is callable
    Given the module "core/boundary/type_registry" is loaded
    Then func heuristicFieldWeight should return a valid value

  Scenario: func lookupTypeFields is callable
    Given the module "core/boundary/type_registry" is loaded
    Then func lookupTypeFields should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
