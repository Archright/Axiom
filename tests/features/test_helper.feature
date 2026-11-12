Feature: Test Helper — shared utilities for Axiom test infrastructure
  As the Axiom test author,
  I want helper functions that set up common test fixtures,
  So that test boilerplate is reduced and consistent.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: helper creates a temporary workspace with standard layout
    When I call createTestWorkspace
    Then a temporary directory with src/ and tests/ subdirectories exists

  Scenario: helper cleans up the workspace after the test
    Given a created test workspace
    When I call cleanupTestWorkspace
    Then the temporary directory no longer exists
