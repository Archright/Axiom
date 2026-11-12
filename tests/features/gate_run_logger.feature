Feature: Gate Run Logger — gate execution audit logging
  As the Axiom integrity engine,
  I want gate execution audit logging that records every gate invocation, input, output, and verdict,
  So that all gate activity is traceable for post-hoc analysis and compliance audits.

  Background:
    Given the gate run logger module is initialized

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
