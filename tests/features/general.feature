Feature: General Shape Handler — fallback handler for unclassified goal shapes
  As the Axiom solver persona,
  I want a general shape handler for goals that match no specific pattern,
  So that every goal has at least a default processing path.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: general handler accepts any unrecognized goal shape
    Given a goal with an unrecognized shape "complex_nested_expr"
    When I inspect the goal shape
    Then the shape is classified as "general"

  Scenario: general handler delegates to LLM fallback strategy
    Given a goal classified as "general"
    When I request a strategy for the goal
    Then the strategy is "llm_fallback"
