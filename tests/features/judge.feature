Feature: Judge — verification result judgment persona
  As the Axiom integrity engine,
  I want a Judge persona that evaluates verification evidence and produces a final verdict,
  So that gate outcomes are determined by a single authoritative decision point.

  Background:
    Given the judge module is initialized

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
