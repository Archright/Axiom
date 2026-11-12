Feature: Pending Feature Guard — blocks compilation when features lack gate coverage
  As the Axiom gate layer,
  I want a guard that fails when a feature has no corresponding gate test,
  So that every shipped feature is verified by at least one gate.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: guard passes when all features have gate coverage
    Given all registered features have at least one gate test
    When I run the pending feature guard
    Then the guard passes

  Scenario: guard fails when a feature lacks gate coverage
    Given a feature "untested_feature" with zero gate tests
    When I run the pending feature guard
    Then the guard fails listing "untested_feature"
