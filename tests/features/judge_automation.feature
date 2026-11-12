Feature: Judge Automation — automated judgment pipeline
  As the Axiom integrity engine,
  I want an automated judgment pipeline that chains evidence collection through to verdict output,
  So that gate evaluations run end-to-end without manual intervention.

  Background:
    Given the judge automation module is initialized

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
