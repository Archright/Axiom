Feature: Orchestrator Token — typed token for orchestrator pipeline coordination
  As the Axiom orchestrator,
  I want a token type that uniquely identifies an orchestrator session,
  So that pipeline stages can correlate work to a specific run.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: token is generated with a unique value
    When I create two orchestrator tokens
    Then the two tokens have distinct string representations

  Scenario: token serialization round-trips correctly
    Given an orchestrator token "tok-abc123"
    When I serialize and deserialize the token
    Then the deserialized token equals the original
