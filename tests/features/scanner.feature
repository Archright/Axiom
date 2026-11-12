Feature: Scanner — source code scanning utilities
  As the Axiom integrity engine,
  I want source code scanning utilities that parse and tokenise Nim files,
  So that static analysis gates can extract structural information for verification.

  Background:
    Given the scanner module is initialized

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
