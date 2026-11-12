@legacy
@executable
Feature: Gateway Policy
  Auto-generated from gateway_policy_test.nim

  Scenario: check cert.status == certRed
    Given the Axiom system is initialized
    When check cert.status == certRed
    Then the result should be valid

  Scenario: check cert.reason == "proof-failed"
    Given the Axiom system is initialized
    When check cert.reason == "proof-failed"
    Then the result should be valid

  Scenario: check cert.status == certPending
    Given the Axiom system is initialized
    When check cert.status == certPending
    Then the result should be valid

  Scenario: check cert.reason == "pending-by-dependency:withdraw"
    Given the Axiom system is initialized
    When check cert.reason == "pending-by-dependency:withdraw"
    Then the result should be valid

  Scenario: check cert.reason == "certificate-invalid"
    Given the Axiom system is initialized
    When check cert.reason == "certificate-invalid"
    Then the result should be valid

