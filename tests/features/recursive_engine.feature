@legacy
Feature: Recursive Core & Induction Engine
  As an Axiom prover
  I want structural induction and pattern matching strategies to generate hints
  So that recursive and complex control flow functions can be verified automatically

  Scenario: structuralInduction detects seq parameter and for loop
    Given a Nim function with a seq[int] parameter and a for loop
    When the isStructuralInduction strategy is applied
    Then the generated hint contains a forall proposition over sequence elements
    And the SMT constraint contains a seq.len assertion

  Scenario: structuralInduction detects recursive function
    Given a Nim function that calls itself recursively
    When the isStructuralInduction strategy is applied
    Then the generated hint contains depth and impact non-negativity assertions

  Scenario: patternMatching detects case statement
    Given a Nim function containing a case statement
    When the isPatternMatching strategy is applied
    Then the generated hint references case branch exhaustiveness

  Scenario: patternMatching detects if branches
    Given a Nim function containing if-else branches
    When the isPatternMatching strategy is applied
    Then the generated hint references branch exhaustiveness
