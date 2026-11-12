Feature: Git Config — git configuration management
  As the Axiom integrity engine,
  I want git configuration management that reads and validates repository settings,
  So that gate runs operate with the correct git identity, pager, and hook configuration.

  Background:
    Given the git config module is initialized

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
