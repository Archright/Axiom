@generated @critical
Feature: boundary_extraction_main
  # generated | src/core/boundary/boundary_extraction_main.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/boundary/boundary_extraction_main" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/boundary/boundary_extraction_main" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs sanitizeLeanIdentifier, extractPathConditions, computeInformationGain, sequenceElementBinderName, logRefactorHint
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func sanitizeLeanIdentifier is callable
    Given the module "core/boundary/boundary_extraction_main" is loaded
    Then func sanitizeLeanIdentifier should return a valid value

  Scenario: func extractPathConditions is callable
    Given the module "core/boundary/boundary_extraction_main" is loaded
    Then func extractPathConditions should return a valid value

  Scenario: func computeInformationGain is callable
    Given the module "core/boundary/boundary_extraction_main" is loaded
    Then func computeInformationGain should return a valid value

  Scenario: func sequenceElementBinderName is callable
    Given the module "core/boundary/boundary_extraction_main" is loaded
    Then func sequenceElementBinderName should return a valid value

  Scenario: func logRefactorHint is callable
    Given the module "core/boundary/boundary_extraction_main" is loaded
    Then func logRefactorHint should return a valid value
