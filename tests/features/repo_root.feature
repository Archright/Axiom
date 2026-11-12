Feature: Repo Root — deterministic repository root resolution
  As the Axiom integrity engine,
  I want deterministic repository root resolution anchored by the .axiom_root marker file,
  So that all path calculations are stable regardless of the working directory at invocation time.

  Background:
    Given the repo root module is initialized

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
