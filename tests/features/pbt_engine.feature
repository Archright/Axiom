Feature: PBT Engine — property-based testing engine
  As the Axiom integrity engine,
  I want a property-based testing engine that generates and evaluates randomised test cases,
  So that edge-case regressions are discovered through automated input exploration.

  Background:
    Given the PBT engine module is initialized

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
