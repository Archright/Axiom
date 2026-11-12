Feature: Grind Strategy Handler — dispatches goals to the grind tactic
  As the Axiom solver persona,
  I want a strategy handler that invokes the grind tactic,
  So that goals requiring congruence closure are solved automatically.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: grind handler solves a congruence-based goal
    Given a goal solvable by congruence closure
    When I invoke the grind strategy handler
    Then the goal is proved

  Scenario: grind handler reports failure for unsupported goals
    Given a goal outside grind's capability
    When I invoke the grind strategy handler
    Then a tactic failure is returned
