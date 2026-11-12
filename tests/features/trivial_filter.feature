Feature: Trivial Filter — boundary filter for trivially safe code patterns
  As the Axiom boundary subsystem,
  I want a filter that accepts trivially safe code without full analysis,
  So that obvious non-issues skip expensive gate processing.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: trivially safe code is filtered out
    Given a code fragment with no side effects or branching
    When I apply the trivial filter
    Then the fragment is marked as trivially safe

  Scenario: non-trivial code passes through the filter
    Given a code fragment with mutable state access
    When I apply the trivial filter
    Then the fragment is not marked as trivially safe
