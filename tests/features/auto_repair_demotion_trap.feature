@legacy
Feature: Auto-repair must not create certRed demotion traps

  Background:
    Given the certificate vault contains a stale certificate

  Scenario: Fingerprint auto-repair avoids global-graph-stale demotion
    Given the certificate has an outdated globalGraphFingerprint
    When autoRepairFingerprintMismatches executes
    Then the certificate status becomes certPending
    And the globalGraphFingerprint is cleared

  Scenario: Proof-state sync isolates verified pending certificates without kernel evidence
    Given a certPending certificate exists in the vault
    And the proof-state marks it as verified without Lean negative-test evidence
    When syncCertificatesWithProofState executes
    Then the certificate status becomes certPseudoVerified
    And the reason becomes "proof-state-sync-missing-kernel-negative-test"
