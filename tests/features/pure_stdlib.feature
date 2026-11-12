Feature: Pure Stdlib — effect-free wrappers around Nim stdlib functions
  As the Axiom core engine,
  I want pure wrappers for common stdlib operations,
  So that core logic remains free of side effects per §0.6.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: pure split divides a string by delimiter
    Given the input string "a,b,c" and delimiter ","
    When I call pureSplit on the input
    Then the result is ["a", "b", "c"]

  Scenario: pure split returns the whole string for missing delimiter
    Given the input string "abc" and delimiter ","
    When I call pureSplit on the input
    Then the result is ["abc"]
