@legacy
Feature: Ledger Inlining — Audit Trail SSOT

  Background:
    Given the Axiom engine is initialized
    And the certificate vault contains valid certificates

  Scenario: ax prove populates reasoningTrail in certificates
    When I run "ax prove"
    Then the command completes successfully
    And at least one certificate in the vault contains a non-empty "reasoningTrail" array
    And each reasoningTrail entry contains "phase" and "verdict" fields

  Scenario: ax prove populates transitionLog in certificates
    When I run "ax prove"
    Then the command completes successfully
    And certificates modified by the run contain a non-empty "transitionLog" array

  @deprecated
  Scenario: ax prove with --force populates provenanceLog
    When I run "ax prove --force"
    Then the command completes successfully
    And at least one certificate contains a "provenanceLog" entry with "action" = "blocked"

  Scenario: flushGlobalAuditBufferToCertificates uses 1-pass I/O
    When I run "ax prove"
    Then the command completes successfully
    And the total certificate read/write operations during flush do not exceed the number of unique nodeIds across all audit buffers
