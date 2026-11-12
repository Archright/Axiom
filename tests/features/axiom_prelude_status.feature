@legacy
@executable
Feature: Axiom Prelude Status Gateway Test
  Auto-generated from axiom_prelude_status_test.nim

  Scenario: Axiom Prelude Status Gateway Test
    Given the Axiom system is initialized
    When Axiom Prelude Status Gateway Test
    Then the result should be valid

  Scenario: check keyToStatus("certVerifiedAxiom") == certVerifiedAxiom
    Given the Axiom system is initialized
    When check keyToStatus("certVerifiedAxiom") == certVerifiedAxiom
    Then the result should be valid

  Scenario: check keyToStatus("intrinsic") == certVerifiedAxiom
    Given the Axiom system is initialized
    When check keyToStatus("intrinsic") == certVerifiedAxiom
    Then the result should be valid

  Scenario: check keyToStatus("certIntrinsic") == certVerifiedAxiom
    Given the Axiom system is initialized
    When check keyToStatus("certIntrinsic") == certVerifiedAxiom
    Then the result should be valid

  Scenario: check keyToStatus("certGreen") == certGreen
    Given the Axiom system is initialized
    When check keyToStatus("certGreen") == certGreen
    Then the result should be valid

