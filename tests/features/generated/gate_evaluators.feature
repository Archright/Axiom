@generated @critical
Feature: gate_evaluators
  # generated | src/core/gate/gate_evaluators.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/gate/gate_evaluators" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ProofLinkageCallback
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/gate/gate_evaluators" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type ProofLinkageCallback is instantiable
    Given the module "core/gate/gate_evaluators" is loaded
    Then type ProofLinkageCallback should be instantiable
