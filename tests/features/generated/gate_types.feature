@generated @high
Feature: gate_types
  # generated | src/gate/gate_types.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/gate_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types GateStage
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/gate_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type GateStage is instantiable
    Given the module "gate/gate_types" is loaded
    Then type GateStage should be instantiable

  Scenario: func `$` is callable
    Given the module "gate/gate_types" is loaded
    Then func `$` should return a valid value

  Scenario: func gateErr is callable
    Given the module "gate/gate_types" is loaded
    Then func gateErr should return a valid value

  Scenario: func gateOk is callable
    Given the module "gate/gate_types" is loaded
    Then func gateOk should return a valid value

  Scenario: func gateFail is callable
    Given the module "gate/gate_types" is loaded
    Then func gateFail should return a valid value
