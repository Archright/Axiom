@generated @critical
Feature: the_judge_eval
  # generated | src/core/judge/the_judge_eval.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/judge/the_judge_eval" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types Z3QueryResult, isUnsat, proofTrace, counterExample
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/judge/the_judge_eval" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs executeProof*[T: ProverInterface], runZ3Query*[T: ProverInterface], runLeanReplay*[T: ProverInterface], verifySmtLeanConsistency
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type Z3QueryResult is instantiable
    Given the module "core/judge/the_judge_eval" is loaded
    Then type Z3QueryResult should be instantiable

  Scenario: type isUnsat is instantiable
    Given the module "core/judge/the_judge_eval" is loaded
    Then type isUnsat should be instantiable

  Scenario: type proofTrace is instantiable
    Given the module "core/judge/the_judge_eval" is loaded
    Then type proofTrace should be instantiable

  Scenario: type counterExample is instantiable
    Given the module "core/judge/the_judge_eval" is loaded
    Then type counterExample should be instantiable

  Scenario: func executeProof*[T: ProverInterface] is callable
    Given the module "core/judge/the_judge_eval" is loaded
    Then func executeProof*[T: ProverInterface] should return a valid value

  Scenario: func runZ3Query*[T: ProverInterface] is callable
    Given the module "core/judge/the_judge_eval" is loaded
    Then func runZ3Query*[T: ProverInterface] should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
