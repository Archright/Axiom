@legacy
@executable
Feature: Axiom Pure Promotion
  Auto-generated from axiom_pure_promotion_test.nim

  Scenario: check sourceHasAxiomPurePragma(source)
    Given the Axiom system is initialized
    When check sourceHasAxiomPurePragma(source)
    Then the result should be valid

  Scenario: check not sourceHasAxiomPurePragma(source)
    Given the Axiom system is initialized
    When check not sourceHasAxiomPurePragma(source)
    Then the result should be valid

