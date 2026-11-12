@generated @critical
Feature: type_mapping
  # generated | src/core/types/type_mapping.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/type_mapping" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/type_mapping" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs nimTypeToLeanType, nimTypeToLeanTypeWithRefinement, inferBoolOrPropFromUsage
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func nimTypeToLeanType is callable
    Given the module "core/types/type_mapping" is loaded
    Then func nimTypeToLeanType should return a valid value

  Scenario: func nimTypeToLeanTypeWithRefinement is callable
    Given the module "core/types/type_mapping" is loaded
    Then func nimTypeToLeanTypeWithRefinement should return a valid value

  Scenario: func inferBoolOrPropFromUsage is callable
    Given the module "core/types/type_mapping" is loaded
    Then func inferBoolOrPropFromUsage should return a valid value
