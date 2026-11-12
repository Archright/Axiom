@legacy
Feature: Omni-Provenance Guard
  Ensures provenance metadata protects high-quality evidence from
  overwrite across all certificate write paths in the engine.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And provenance guard module exists at "src/core/provenance_guard.nim"

  Scenario: Provenance guard module provides unified protection API
    Given a certificate file without provenance metadata
    When isProvenanceProtected is checked
    Then it returns false for non-leanstral content

  Scenario: enforceProvenanceBeforeWrite blocks overwrite of protected certs
    Given an existing certificate with provenance "leanstral"
    When enforceProvenanceBeforeWrite is called for the same path
    Then it returns false

  Scenario: enforceProvenanceBeforeWrite allows first-time creation
    Given a certificate path that does not exist
    When enforceProvenanceBeforeWrite is called
    Then it returns true

  Scenario: heal_injection respects provenance before overwriting
    Given a provenance-protected certificate exists in the vault
    When saveHint attempts to write a new certificate for the same function
    Then the existing certificate is preserved
    And an overwrite attempt is recorded in the audit log

  Scenario: rebuild_assets preserves provenance-protected orphans
    Given a certificate with provenance "leanstral" exists
    And the corresponding function is removed from the source tree
    When cleanOrphanCertificates runs with destructiveClean=true
    Then the provenance-protected certificate is not deleted

  Scenario: vault_sync skips provenance-protected certificates
    Given a provenance-protected certificate exists in the vault
    When vault-sync backfill runs for the same function
    Then the certificate is skipped
