Feature: Linear Arithmetic Shape Handler — handles linear arithmetic goals
  As the Axiom solver persona,
  I want a shape handler for goals expressible as linear arithmetic,
  So that the omega or linear arithmetic solver can be invoked directly.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: handler classifies a linear inequality
    Given a goal "3x + 2y ≤ 10"
    When I inspect the goal shape
    Then the shape is classified as "linear_arithmetic"

  Scenario: handler rejects a non-linear goal
    Given a goal "x² + y² = z²"
    When I inspect the goal shape
    Then the shape is not classified as "linear_arithmetic"
