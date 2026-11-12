Feature: ActionKey — Bazel-style deterministic action identity
  As the Hermetic Build Engine,
  I want a distinct string type for action identity computed from inputs,
  So that identical actions share cache entries and different actions never collide.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: computeActionKey is deterministic for the same inputs
    Given action inputs with command "nim c -d:release src/main.nim"
    And input files ["src/main.nim", "lib/utils.nim"]
    When I call computeActionKey twice with identical inputs
    Then both calls return the same ActionKey value

  Scenario: different inputs produce different keys
    Given action inputs set A with command "nim c src/a.nim"
    And action inputs set B with command "nim c src/b.nim"
    When I call computeActionKey for each input set
    Then the two ActionKey values are not equal

  Scenario: shortKey truncates correctly for display
    Given an ActionKey with value "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    When I call shortKey
    Then the result is "a1b2c3d4"
    And the result length is 8 characters
