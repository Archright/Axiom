Feature: Exception Guard — compile-time exception hygiene enforcement
  As the Axiom integrity engine,
  I want compile-time exception hygiene enforcement that prevents untracked exception escapes,
  So that the engine core remains effect-free and gate failures are caught deterministically.

  Background:
    Given the exception guard module is initialized

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
