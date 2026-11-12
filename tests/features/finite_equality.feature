Feature: Finite Equality Shape Handler — handles equality over finite types
  As the Axiom solver persona,
  I want a shape handler for equality goals over finite types,
  So that exhaustive enumeration can be used when the domain is small.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: handler classifies equality over a finite type
    Given a goal "x = y" over Bool
    When I inspect the goal shape
    Then the shape is classified as "finite_equality"

  Scenario: handler rejects equality over an infinite type
    Given a goal "x = y" over Nat
    When I inspect the goal shape
    Then the shape is not classified as "finite_equality"
