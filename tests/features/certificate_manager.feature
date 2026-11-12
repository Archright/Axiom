@legacy
Feature: Certificate Manager — Hard-Gate and Mutation Integrity
  Verifies that certificate status mutations follow the hard-gate
  contract: certGreen requires winningStrategy, certVerifiedAxiom
  requires axiom identity, and all status transitions are deterministic.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And certificate_manager module exists at "src/verification/certificate_manager.nim"

  Scenario: certGreen without winningStrategy is rejected
    Given a JsonNode with status "certGreen" and empty winningStrategy
    When validateCertGreenWritable is called
    Then the result is false

  Scenario: certGreen with winningStrategy is accepted
    Given a JsonNode with status "certGreen" and non-empty winningStrategy
    When validateCertGreenWritable is called
    Then the result is true

  Scenario: non-JObject node passes validation
    Given a JsonNode of kind JString
    When validateCertGreenWritable is called
    Then the result is true

  Scenario: certRed certificate passes validation
    Given a FunctionCertificate with status certRed
    When validateCertGreenWritable is called on the FunctionCertificate
    Then the result is true

  Scenario: markCertificateInvalid sets certRed status
    Given a FunctionCertificate with status certPending
    When markCertificateInvalid is called with reason "test-failure"
    Then the certificate status is certRed
    And the certificate reason is "test-failure"

  Scenario: markCertificatePendingByDependency sets pending status
    Given a FunctionCertificate with status certGreen
    When markCertificatePendingByDependency is called with "dep-module"
    Then the certificate status is certPending
    And the certificate reason contains "dep-module"

  Scenario: createInvalidCertificate produces certRed with normalized path
    Given a certificate path string
    When createInvalidCertificate is called
    Then the returned certificate has status certRed
    And the reason is "certificate-invalid"
