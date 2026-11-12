@generated @high
Feature: arithmetic_type_directed_pipeline
  # generated | src/verification/proof/arithmetic_type_directed_pipeline.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/proof/arithmetic_type_directed_pipeline" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ArithmeticProofResult, verified, smtlib2, leanSource, z3Output, leanResult, reason
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/proof/arithmetic_type_directed_pipeline" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type ArithmeticProofResult is instantiable
    Given the module "verification/proof/arithmetic_type_directed_pipeline" is loaded
    Then type ArithmeticProofResult should be instantiable

  Scenario: type verified is instantiable
    Given the module "verification/proof/arithmetic_type_directed_pipeline" is loaded
    Then type verified should be instantiable

  Scenario: type smtlib2 is instantiable
    Given the module "verification/proof/arithmetic_type_directed_pipeline" is loaded
    Then type smtlib2 should be instantiable

  Scenario: type leanSource is instantiable
    Given the module "verification/proof/arithmetic_type_directed_pipeline" is loaded
    Then type leanSource should be instantiable

  Scenario: type z3Output is instantiable
    Given the module "verification/proof/arithmetic_type_directed_pipeline" is loaded
    Then type z3Output should be instantiable

  Scenario: type leanResult is instantiable
    Given the module "verification/proof/arithmetic_type_directed_pipeline" is loaded
    Then type leanResult should be instantiable

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
