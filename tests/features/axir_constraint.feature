@legacy
Feature: Axiom-IR Constraint Inference Gateway Test
  Auto-generated from axir_constraint_test.nim

  Scenario: Axiom-IR Constraint Inference Gateway Test
    Given the Axiom system is initialized
    When Axiom-IR Constraint Inference Gateway Test
    Then the result should be valid

  Scenario: check declared(extractBoundaries)
    Given the Axiom system is initialized
    When check declared(extractBoundaries)
    Then the result should be valid

  Scenario: check declared(moduleAliasTable)
    Given the Axiom system is initialized
    When check declared(moduleAliasTable)
    Then the result should be valid

