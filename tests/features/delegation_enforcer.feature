Feature: Delegation Enforcer — wire-log loop detection for agents
  As the Axiom integrity engine,
  I want wire-log loop detection that catches infinite agent delegation cycles,
  So that runaway subagent spawns are terminated before exhausting resources.

  Background:
    Given the delegation enforcer module is initialized

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
