Feature: Core Invariant Gate — core engine invariant validation
  As the Gate Infrastructure,
  I want to verify core engine invariants hold,
  So that structural integrity is maintained across changes.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: all core invariants satisfied
    Given staged files that preserve core invariants
    When I run the core invariant gate
    Then the gate passes
