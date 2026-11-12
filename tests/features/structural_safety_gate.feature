Feature: Structural Safety Gate — compile-time structural invariant checks
  As the Axiom integrity engine,
  I want compile-time structural invariant checks that enforce module boundaries and dependency rules,
  So that architectural violations are caught during compilation rather than at runtime.

  Background:
    Given the structural safety gate module is initialized

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
