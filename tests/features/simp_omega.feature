Feature: Simp+Omega Strategy — combined simp preprocessing with omega dispatch
  As the Axiom solver persona,
  I want a combined strategy that simplifies then applies omega,
  So that goals needing simplification before linear arithmetic are solved.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: simp+omega solves a goal requiring both steps
    Given a goal "n + 0 + m = m + n"
    When I invoke the simp_omega strategy handler
    Then simp reduces the goal and omega closes it

  Scenario: simp+omega reports failure when omega cannot close
    Given a goal that simp reduces but omega cannot prove
    When I invoke the simp_omega strategy handler
    Then a tactic failure is returned after simp succeeds
