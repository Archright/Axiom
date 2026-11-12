Feature: Native Decide Strategy — invokes Lean's native decide without preprocessing
  As the Axiom solver persona,
  I want a native decide strategy that calls decide directly,
  So that simple decidable goals are solved with minimal overhead.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: native decide solves a simple arithmetic equality
    Given a goal "1 + 1 = 2"
    When I invoke the native decide strategy
    Then the goal is proved without preprocessing

  Scenario: native decide fails and signals fallback needed
    Given a goal requiring non-trivial reasoning
    When I invoke the native decide strategy
    Then a failure is returned signaling fallback is needed
