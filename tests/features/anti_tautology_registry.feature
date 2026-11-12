@legacy
Feature: Anti-Tautology Registry
  As an Axiom engineer
  I want trivial axioms to contribute zero weight to ASI
  So that the score reflects only runtime-meaningful integrity

  Background:
    Given the Axiom engine is initialized

  Scenario: Trivial length axiom has zero ASI weight
    When the axiom "nim.string.len.isNat" is evaluated
    Then its ASI weight should be 0.0

  Scenario: Runtime-meaningful axiom has full ASI weight
    When the axiom "nim.os.readFileOpt.externalIO" is evaluated
    Then its ASI weight should be 1.0

  Scenario: Weighted ASI excludes trivial axioms
    Given all certificates are verified via trivial axioms
    When weighted ASI is calculated
    Then the weighted ASI should be 0.0000
