@generated @critical
Feature: verification_interface
  # generated | src/core/boundary/verification_interface.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/boundary/verification_interface" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types LeanstralResult, success, proof, theoremSource, tacticTrace, premises, diagnostics, rawOutput, timedOut, confidence, error
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/boundary/verification_interface" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type LeanstralResult is instantiable
    Given the module "core/boundary/verification_interface" is loaded
    Then type LeanstralResult should be instantiable

  Scenario: type success is instantiable
    Given the module "core/boundary/verification_interface" is loaded
    Then type success should be instantiable

  Scenario: type proof is instantiable
    Given the module "core/boundary/verification_interface" is loaded
    Then type proof should be instantiable

  Scenario: type theoremSource is instantiable
    Given the module "core/boundary/verification_interface" is loaded
    Then type theoremSource should be instantiable

  Scenario: type tacticTrace is instantiable
    Given the module "core/boundary/verification_interface" is loaded
    Then type tacticTrace should be instantiable

  Scenario: type premises is instantiable
    Given the module "core/boundary/verification_interface" is loaded
    Then type premises should be instantiable

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
