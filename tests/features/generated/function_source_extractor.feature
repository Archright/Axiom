@generated @critical
Feature: function_source_extractor
  # generated | src/core/proof/function_source_extractor.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/proof/function_source_extractor" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/proof/function_source_extractor" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs sourceSlice, findNamedDeclaration, extractFunctionSource
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func sourceSlice is callable
    Given the module "core/proof/function_source_extractor" is loaded
    Then func sourceSlice should return a valid value

  Scenario: func findNamedDeclaration is callable
    Given the module "core/proof/function_source_extractor" is loaded
    Then func findNamedDeclaration should return a valid value

  Scenario: func extractFunctionSource is callable
    Given the module "core/proof/function_source_extractor" is loaded
    Then func extractFunctionSource should return a valid value
