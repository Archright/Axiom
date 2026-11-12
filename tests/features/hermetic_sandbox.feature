Feature: Hermetic Sandbox — isolated execution environment for gates
  As the Axiom integrity engine,
  I want a hermetic sandbox that provides isolated execution for gate runners,
  So that gates cannot leak state or affect other concurrent gate runs.

  Background:
    Given the hermetic sandbox module is initialized

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
