Feature: Shadow Trigger — shadow mode trigger detection
  As the Axiom integrity engine,
  I want shadow mode trigger detection that identifies when gates should run in shadow (dry-run) mode,
  So that new gate logic can be validated in production without affecting final verdicts.

  Background:
    Given the shadow trigger module is initialized

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
