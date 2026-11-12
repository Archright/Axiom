@legacy
Feature: Trivial Discard Breakthrough (Wave D)
  As an Axiom developer
  I want trivial-discard functions to generate tautology-proof certificates
  So that ASI rises by including type-system-level guarantees

  Background:
    Given the boundary_extractor module "src/core/boundary_extractor.nim"
    And the tautology_prover module "src/core/tautology_prover.nim"

  Scenario: Trivial function with type-system constraints gets certificate
    Given a function with only type-derived constraints (str.len >= 0, range bounds)
    When extractBoundaries is called
    Then completeness is bcComplete (not bcTrivialDiscard)
    And hint.strategy is isTautologyProof
    And hint.informationGain is 0.0
    And hint is not none

  Scenario: Non-trivial constraints still get positive information gain
    Given a function with doAssert(x > 5) in its body
    When extractBoundaries is called
    Then completeness is bcComplete
    And hint.informationGain > 0.0
    And hint.strategy is not isTautologyProof

  Scenario: bcIncompleteIO still returns none hint
    Given a function with I/O calls (readFile, execCmd)
    When extractBoundaries is called
    Then completeness is bcIncompleteIO
    And hint is none

  Scenario: Option constraints survive trivial filter
    Given a function with Option[T].isSome constraint
    When isTrivialConstraint is called
    Then the constraint is not marked as trivial
    And the constraint flows into boundary hint
