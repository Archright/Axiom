Feature: Axiom DSL — domain-specific language for writing Axiom tests
  As the Axiom test author,
  I want a concise DSL for defining gate test scenarios,
  So that test files are readable and follow a consistent structure.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: DSL compiles a valid test block
    Given an Axiom DSL block with a valid Given/When/Then structure
    When I compile the DSL block
    Then the compilation succeeds without errors

  Scenario: DSL rejects a block with missing Then clause
    Given an Axiom DSL block with only Given and When clauses
    When I compile the DSL block
    Then a compile error is raised about the missing Then clause
