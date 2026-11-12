@legacy
Feature: Semantic-First Topology
  As an Axiom engineer
  I want trivial nodes to be excluded from the verification queue
  So that proof resources are spent on meaningful semantic boundaries

  Background:
    Given the Axiom engine is initialized

  Scenario: Helper function with only length >= 0 is discarded
    When a function "proc helper(s: string): int = s.len" is analyzed
    Then its boundary completeness should be "bcTrivialDiscard"

  Scenario: Complex function with branches is not discarded
    When a function "proc complex(x: int): int = if x > 0: x else: 0" is analyzed
    Then its boundary completeness should not be "bcTrivialDiscard"
