@generated @critical
Feature: axiom_api_types
  # generated | src/core/api/axiom_api_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/api/axiom_api_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types BmcVerificationResponse, raceDetected, raceFinalState, bothWritePathExists, sequentialResultA, sequentialResultB, sequentialUniqueCount, stepBound
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/api/axiom_api_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type BmcVerificationResponse is instantiable
    Given the module "core/api/axiom_api_types" is loaded
    Then type BmcVerificationResponse should be instantiable

  Scenario: type raceDetected is instantiable
    Given the module "core/api/axiom_api_types" is loaded
    Then type raceDetected should be instantiable

  Scenario: type raceFinalState is instantiable
    Given the module "core/api/axiom_api_types" is loaded
    Then type raceFinalState should be instantiable

  Scenario: type bothWritePathExists is instantiable
    Given the module "core/api/axiom_api_types" is loaded
    Then type bothWritePathExists should be instantiable

  Scenario: type sequentialResultA is instantiable
    Given the module "core/api/axiom_api_types" is loaded
    Then type sequentialResultA should be instantiable

  Scenario: type sequentialResultB is instantiable
    Given the module "core/api/axiom_api_types" is loaded
    Then type sequentialResultB should be instantiable

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
