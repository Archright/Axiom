Feature: Equality Shape Handler — handles equality-based proof obligations
  As the Axiom solver persona,
  I want a shape handler for equality goals,
  So that propositions of the form a = b are dispatched to the right strategy.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: handler identifies an equality goal
    Given a goal "a = b" over integers
    When I inspect the goal shape
    Then the shape is classified as "equality"

  Scenario: handler rejects a non-equality goal
    Given a goal "a < b" over integers
    When I inspect the goal shape
    Then the shape is not classified as "equality"
