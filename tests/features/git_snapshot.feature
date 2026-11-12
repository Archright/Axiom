Feature: Git Snapshot — git state capture for deterministic gates
  As the Axiom integrity engine,
  I want deterministic git state snapshots that capture commit hash, branch, and dirty status,
  So that gate runs are reproducible and verifiable across environments.

  Background:
    Given the git snapshot module is initialized

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
