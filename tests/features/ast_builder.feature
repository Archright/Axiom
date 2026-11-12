Feature: AST Builder — Nim AST construction for code analysis
  As the Axiom integrity engine,
  I want programmatic Nim AST construction utilities,
  So that code analysis gates can inspect and transform source representations.

  Background:
    Given the AST builder module is initialized

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
