Feature: Gate Hook — pre-commit gate orchestrator with dangling symlink safety
  As the Gate Infrastructure,
  I want to orchestrate all pre-commit gates and detect dangling symlinks in bin/,
  So that the gate system runs reliably without stale symlinks.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: all gates pass on clean staged changes
    Given staged files that violate no gate rules
    When I run the gate hook in pre-commit mode
    Then all gates pass

  Scenario: dangling symlinks in bin/ are detected
    Given a dangling symlink exists in bin/
    When I run the gate hook
    Then a warning about the dangling symlink is emitted
    And the symlink is cleaned up
