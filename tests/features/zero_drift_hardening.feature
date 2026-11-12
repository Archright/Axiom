@legacy
Feature: Zero Drift — Structural ASI Hardening
  Four-stage hardening to eliminate ASI degradation modes caused by
  fingerprint divergence, destructive rebuilds, stale caches, and
  unprotected evidence overwrite.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And certificate directory exists at "src/verification/certificates/"

  Scenario: AxiomIdentity provides unified fingerprint computation
    Given a function body "proc add(a, b: int): int = a + b"
    When computeAxiomFingerprint is called with the body
    Then the result is deterministic across repeated calls
    And normalizePayloadForFingerprint strips comments and normalizes whitespace
    And hashNormalizedPayload returns a non-empty string

  Scenario: Self-healing hydrateCertificate updates stale graph fingerprint
    Given a certificate with a stale globalGraphFingerprint
    And the function fingerprint matches the current source
    When hydrateCertificate is called with the current graph hash
    Then the certificate status remains verified
    And the globalGraphFingerprint is updated to the current graph hash
    And an audit event "certificate_graph_fingerprint_healed" is recorded

  Scenario: rebuild_assets is idempotent by default
    Given existing certificates in the certificate directory
    When writeCertificates is called with destructiveClean = false
    Then existing certificates are not modified
    And only missing certificates are generated

  Scenario: rebuild_assets with destructive clean removes orphans
    Given existing certificates and a reduced function list
    When writeCertificates is called with destructiveClean = true
    Then certificates for functions not in the list are removed

  Scenario: Status-aware ASI cache invalidates on status change
    Given a valid ASI cache with statusChecksum
    When any certificate status changes from green to red
    Then isAsiCacheValid returns false
    And buildAsiCache computes a new statusChecksum

  Scenario: Provenance guard protects leanstral evidence from overwrite
    Given a certificate with provenance "leanstral"
    When isProvenanceProtected is checked
    Then it returns true
    And detectProvenanceFromContent identifies "h_sys" content as "leanstral"

  Scenario: No raw DEBUG dumps in production code
    Given the source tree is scanned
    When searching for `stderr.writeLine("[DEBUG]` patterns
    Then zero matches are found in src/verification/healing_orchestrator.nim
    And all debug-like logging routes through cli/log.nim structured procs
