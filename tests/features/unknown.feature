Feature: Unknown Shape Handler — handles goals with indeterminate shape
  As the Axiom solver persona,
  I want a handler for goals whose shape cannot be determined,
  So that indeterminate goals are flagged for manual review or LLM fallback.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: handler marks an opaque goal as unknown
    Given a goal with an opaque or unsupported expression
    When I inspect the goal shape
    Then the shape is classified as "unknown"

  Scenario: unknown goals receive no automatic strategy
    Given a goal classified as "unknown"
    When I request a strategy for the goal
    Then no automatic strategy is assigned
