Feature: Debug Mode — runtime debug diagnostics
  As the Axiom integrity engine,
  I want runtime debug diagnostics for gate execution and pipeline state,
  So that developers can trace issues during development without affecting production behavior.

  Background:
    Given the debug mode module is initialized

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
