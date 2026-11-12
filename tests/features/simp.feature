Feature: Simp Strategy Handler — dispatches goals to the simp tactic
  As the Axiom solver persona,
  I want a strategy handler that invokes simp for simplification-based proofs,
  So that goals solvable by rewriting with known lemmas are automated.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: simp solves a goal using the default simp set
    Given a goal "0 + n = n"
    When I invoke the simp strategy handler
    Then the goal is proved by simplification

  Scenario: simp fails when required lemmas are not in the simp set
    Given a goal requiring a custom lemma not in the default simp set
    When I invoke the simp strategy handler
    Then a tactic failure is returned
