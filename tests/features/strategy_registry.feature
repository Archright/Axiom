Feature: Strategy Registry — central registry mapping strategies to handlers
  As the Axiom solver persona,
  I want a registry that maps strategy names to their handler modules,
  So that strategy dispatch is centralized and extensible.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: registered strategy is resolved by name
    Given a strategy "omega" registered with the omega handler
    When I resolve the strategy name "omega"
    Then the resolved handler is the omega handler

  Scenario: resolving an unregistered strategy returns an error
    Given no strategy registered as "unknown_strategy"
    When I resolve the strategy name "unknown_strategy"
    Then a strategy-not-found error is returned
