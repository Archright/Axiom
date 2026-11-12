Feature: Omega Strategy Handler — dispatches goals to the omega tactic
  As the Axiom solver persona,
  I want a strategy handler that invokes omega for linear integer arithmetic,
  So that linear arithmetic goals are solved by a decision procedure.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: omega solves a linear integer inequality
    Given a goal "∀ n : Nat, n + 0 = n"
    When I invoke the omega strategy handler
    Then the goal is proved

  Scenario: omega fails on a non-linear integer goal
    Given a goal "∀ n : Nat, n * n ≥ 0"
    When I invoke the omega strategy handler
    Then a tactic failure is returned
