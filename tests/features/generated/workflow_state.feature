@generated @critical
Feature: workflow_state
  # generated | src/core/types/workflow_state.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/workflow_state" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ProofReplayTactic, name, step, verified
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/workflow_state" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs proofReplayTacticNames, `%`, `%`, toJson
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type ProofReplayTactic is instantiable
    Given the module "core/types/workflow_state" is loaded
    Then type ProofReplayTactic should be instantiable

  Scenario: type name is instantiable
    Given the module "core/types/workflow_state" is loaded
    Then type name should be instantiable

  Scenario: type step is instantiable
    Given the module "core/types/workflow_state" is loaded
    Then type step should be instantiable

  Scenario: type verified is instantiable
    Given the module "core/types/workflow_state" is loaded
    Then type verified should be instantiable

  Scenario: func proofReplayTacticNames is callable
    Given the module "core/types/workflow_state" is loaded
    Then func proofReplayTacticNames should return a valid value

  Scenario: func `%` is callable
    Given the module "core/types/workflow_state" is loaded
    Then func `%` should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
