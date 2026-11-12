Feature: Leanstral CLI — Lean integration command-line interface
  As the Axiom integrity engine,
  I want a Lean integration CLI that bridges Nim gate output to Lean 4 proof obligations,
  So that formal verification proofs can be generated and validated from gate evidence.

  Background:
    Given the leanstral CLI module is initialized

  @spec-density @guard-ring
  Scenario: Module compiles without errors
    Given the module source is available
    When the module is compiled
    Then it compiles without errors
    And all exported procs have proper effect annotations

  @spec-density @guard-ring
  Scenario: Core functionality works correctly
    Given valid input for the module
    When the core function is invoked
    Then it produces the expected output
    And no unhandled exceptions are raised
