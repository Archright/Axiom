Feature: Golden Version — golden master version management
  As the Axiom integrity engine,
  I want golden master version management for baselining expected test outputs,
  So that regressions are detected when actual outputs diverge from approved golden masters.

  Background:
    Given the golden version module is initialized

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
