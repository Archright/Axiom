@legacy
Feature: Winning Strategy Hard-Gate

  Scenario: certGreen without winningStrategy is rejected at write time
    Given a certificate with status certGreen and empty winningStrategy
    When validateCertGreenWritable is called
    Then it must return false

  Scenario: certGreen with winningStrategy is accepted at write time
    Given a certificate with status certGreen and winningStrategy "orchestration"
    When validateCertGreenWritable is called
    Then it must return true

  Scenario: certVerifiedAxiom without axiom linkage is rejected
    Given a certificate with status certVerifiedAxiom and empty axiom linkage
    When validateCertGreenWritable is called
    Then it must return false

  Scenario: recertify-lean backfills certGreen winningStrategy from provenance
    Given a certificate with empty winningStrategy and provenance "leanstral"
    When updateCertificateLeanHash promotes it after Lean replay
    Then winningStrategy must be "leanstral"

  Scenario: report_cli fallback uses metrics SSOT instead of ad-hoc ratio
    Given a certificate directory with mixed statuses
    When buildProofReportFromCertificates computes fallback ASI
    Then the formula must match metrics.computeCoverage, not verified/total

  Scenario: certificate_manager writeCertificate rejects invalid certGreen
    Given a JsonNode with status certGreen and empty winningStrategy
    When writeCertificate is called
    Then write must return false and the file must not be modified

  Scenario: certificate_manager Lean replay promotion backfills winningStrategy
    Given a certificate with empty winningStrategy and leanHash "abc123"
    When promoteToCertVerifiedAxiom is called with strategy "lean-replay"
    Then status must be certGreen and winningStrategy must be "lean-replay"

  Scenario: mass promotion must not mint unlinked certVerifiedAxiom entries
    Given 1,716 certGreen certificates with valid winningStrategy
    When promote_green_to_verified_axiom runs
    Then every certVerifiedAxiom entry must contain axiomId, axiomVersion, and axiomHash

  Scenario: path normalization eliminates ASI divergence
    Given any certDir path format (relative, absolute, or symlinked)
    When buildAsiReportNode compares it against defaultCertDir
    Then the comparison must be deterministic and environment-independent

  Scenario: all certificate writes flow through certificate_manager
    Given a certificate write operation in any module
    When the write executes
    Then it must call certificate_manager.writeCertificate, never raw writeFile
