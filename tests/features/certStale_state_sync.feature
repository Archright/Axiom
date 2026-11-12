@legacy
Feature: certStale State Sync Protection
  As an Axiom integrity operator
  I want `certStale` certificates to survive proof-state normalization
  So that fingerprint-mismatch nodes are not silently downgraded to `unattempted`

  Background:
    Given the certificate vault contains a certificate with status `certStale`
    And the proof state JSON contains an entry for the same function

  Scenario: certStale survives dependency-mismatch normalization
    Given the function has a stale dependency that triggers `semanticEntryDependencyMismatchReason`
    When `normalizeSemanticProofStateDependencies` runs
    Then the proof-state entry status must remain `certStale`
    And the certificate vault status must remain `certStale`

  Scenario: certStale is not overwritten by unattempted downgrade
    Given the proof-state entry currently has status `certStale`
    When the merge logic attempts to set status to `unattempted`
    Then the status priority hierarchy must block the downgrade
    And the final status must still be `certStale`

  Scenario: Dependency invalidation does not downgrade certStale
    Given a `certStale` certificate depends on another function
    When that dependency is invalidated by `invalidateDependents`
    Then the `certStale` certificate must retain its status
    And must not be marked `certPending` by dependency invalidation

  Scenario: autoRepairFingerprintMismatches promotes certStale to certGreen
    Given a certificate has status `certStale` and `fingerprint` != `currentFingerprint`
    When `autoRepairFingerprintMismatches` runs
    Then the certificate `fingerprint` must equal `currentFingerprint`
    And the certificate status must be `certGreen`
    And the certificate reason must be `auto-repaired`

  Scenario: Incremental hydration forces re-verification of certStale certificates
    Given a certificate has status `certStale` and source mtime matches index
    When `verifyCertificates` performs incremental hydration
    Then the certificate must be hydrated regardless of mtime match
    And if fingerprint now matches, status must become `certGreen`

  Scenario: hydrateCertificate persists currentFingerprint to certificate file
    Given a certificate has fingerprint mismatch during hydration
    When `hydrateCertificate` detects the mismatch
    Then the certificate file must contain `currentFingerprint` field
    And the certificate file status must be `certStale`
