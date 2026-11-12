Feature: Rfl Strategy Handler — dispatches goals to the rfl tactic
  As the Axiom solver persona,
  I want a strategy handler that invokes rfl for definitional equality,
  So that goals trivially true by definition are discharged instantly.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: rfl solves a definitional equality
    Given a goal "id x = x" where id is the identity function
    When I invoke the rfl strategy handler
    Then the goal is proved

  Scenario: rfl fails on a non-definitional equality
    Given a goal "x + 0 = x" requiring the Nat.add_zero lemma
    When I invoke the rfl strategy handler
    Then a tactic failure is returned
