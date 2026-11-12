@legacy
Feature: Mirror Shield — certificate generation for all verification paths

  Background:
    Given the Axiom CLI is compiled and available
    And the verification certificate vault is initialized

  Scenario: BoundaryExtractor verified node writes certificate to vault
    Given a function with string parameter verified by BoundaryExtractor
    When the heal pipeline completes with verifiedKey status
    Then a certificate JSON must exist in src/verification/certificates/
    And the certificate modulePath must match the source file location

  Scenario: Leanstral synthesis verified node writes certificate to vault
    Given a function verified by Leanstral synthesis
    When the heal pipeline completes with verifiedKey status
    Then a certificate JSON must exist in src/verification/certificates/
    And the certificate status must be certGreen

  @deprecated
  Scenario: ASI calculation reflects all certificates in vault
    Given multiple verified functions across different modules
    When ax report --calculate-asi is executed
    Then the coverage must equal verifiedCertificates / totalSourceFunctions
    And blockingFailure must be false when certificates are present
