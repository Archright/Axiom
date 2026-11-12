Feature: LLM Fallback Strategy — uses LLM to generate proof hints
  As the Axiom solver persona,
  I want an LLM fallback strategy when native tactics fail,
  So that no goal is left unaddressed without attempting LLM assistance.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: LLM fallback generates a proof hint for an unsolved goal
    Given a goal that all native strategies failed on
    When I invoke the LLM fallback strategy
    Then a proof hint is generated and returned

  Scenario: LLM fallback returns empty when the LLM is unavailable
    Given a goal and no LLM endpoint configured
    When I invoke the LLM fallback strategy
    Then an empty hint is returned with an unavailable-LLM warning
