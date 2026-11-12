Feature: Git Ops — git operations abstraction layer
  As the Axiom integrity engine,
  I want a git operations abstraction layer that wraps git plumbing and porcelain commands,
  So that gate runners perform git actions through a safe, auditable interface.

  Background:
    Given the git ops module is initialized

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
