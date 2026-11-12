@legacy
Feature: Entropy-Weighted ASI
  As an Axiom engineer
  I want complex functions to contribute more to ASI than simple helpers
  So that the score reflects semantic coverage, not just raw count

  Background:
    Given the Axiom engine is initialized

  Scenario: Complex function has higher semantic weight
    When a function with branchCount=5 and nestingDepth=3 is analyzed
    Then its semanticWeight should be greater than a function with branchCount=0

  Scenario: Entropy ASI reflects complexity distribution
    Given a complex function is verified and a simple function is verified
    When entropy ASI is calculated
    Then the entropy ASI should weight the complex function more heavily

  Scenario: JSON report includes all ASI metrics
    When I run "ax report --json"
    Then the JSON summary should contain "weightedAsiFixed4"
    And the JSON summary should contain "entropyAsiFixed4"
    And the JSON summary should contain "substantiveAsiFixed4"
