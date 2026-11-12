Feature: State Hash — deterministic state fingerprinting
  As the Axiom integrity engine,
  I want deterministic state fingerprinting that produces stable hashes from pipeline state,
  So that gate outputs can be compared across runs for drift detection.

  Background:
    Given the state hash module is initialized

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
