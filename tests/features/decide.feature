Feature: Decide Strategy Handler — dispatches goals to the decide tactic
  As the Axiom solver persona,
  I want a strategy handler that invokes Lean's decide tactic,
  So that decidable propositions are discharged automatically.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: decide handler solves a decidable proposition
    Given a decidable goal "2 + 2 = 4"
    When I invoke the decide strategy handler
    Then the goal is proved

  Scenario: decide handler fails on an undecidable proposition
    Given an undecidable goal involving general recursion
    When I invoke the decide strategy handler
    Then a tactic failure is returned
