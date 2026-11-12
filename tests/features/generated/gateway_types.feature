@generated @critical
Feature: gateway_types
  # generated | src/core/gateway/gateway_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/gateway/gateway_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types NumericInvariantProc, RelationalInvariantProc, ConstraintDefinition, minValue, maxValue, invariant, InputConstraintDefinition, stateConstraint, inputConstraint, relationalInvariant, makeInputConstraintDefinition, stateConstraint, inputConstraint, relationalInvariant
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/gateway/gateway_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs requireLen, gatekeepNumericInput
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type NumericInvariantProc is instantiable
    Given the module "core/gateway/gateway_types" is loaded
    Then type NumericInvariantProc should be instantiable

  Scenario: type RelationalInvariantProc is instantiable
    Given the module "core/gateway/gateway_types" is loaded
    Then type RelationalInvariantProc should be instantiable

  Scenario: type ConstraintDefinition is instantiable
    Given the module "core/gateway/gateway_types" is loaded
    Then type ConstraintDefinition should be instantiable

  Scenario: type minValue is instantiable
    Given the module "core/gateway/gateway_types" is loaded
    Then type minValue should be instantiable

  Scenario: type maxValue is instantiable
    Given the module "core/gateway/gateway_types" is loaded
    Then type maxValue should be instantiable

  Scenario: type invariant is instantiable
    Given the module "core/gateway/gateway_types" is loaded
    Then type invariant should be instantiable

  # +10 more scenarios (types+funcs) omitted to stay under 50 lines
