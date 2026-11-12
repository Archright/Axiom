Feature: Verification Pipeline Context — shared state for pipeline stages
  As the Axiom verification pipeline,
  I want a shared context object carrying state across pipeline stages,
  So that each stage can access common configuration and results.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: context carries configuration to downstream stages
    Given a pipeline context with gate config "strict"
    When I pass the context to a downstream stage
    Then the stage reads config as "strict"

  Scenario: context accumulates results from upstream stages
    Given a pipeline context with a result from stage "scout"
    When I read the accumulated results from the context
    Then the result from "scout" is present
