Feature: Aesop Strategy Handler — dispatches goals to the Aesop tactic
  As the Axiom solver persona,
  I want a strategy handler that invokes Aesop for automated proof search,
  So that goals amenable to heuristic search are solved efficiently.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: Aesop handler is selected for a rule-heavy goal
    Given a goal solvable by Aesop's rule set
    When I request a strategy for the goal
    Then the strategy is "aesop" and the tactic is invoked

  Scenario: Aesop handler gracefully falls back on timeout
    Given a goal that exceeds Aesop's timeout
    When I invoke the Aesop strategy handler
    Then a timeout result is returned without crashing
