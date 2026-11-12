@legacy
Feature: Proof-Preserving Fingerprinting
  Comment-only changes must not invalidate certificates. Strips # comments
  and normalizes whitespace before fingerprint hashing.

  Background:
    Given certificate vault exists at "src/verification/certificates/"
    And normalizeHashFingerprint strips # comments and whitespace

  Scenario: Comment-only change preserves fingerprint
    Given source code "proc foo() =\n  # @axiom-hint: lean=\"x >= 0\"\n  discard"
    When normalizeHashFingerprint is called
    Then the result equals normalizeHashFingerprint("proc foo() =\n  discard")

  Scenario: Whitespace-only change preserves fingerprint
    Given source code "proc foo() =\n\n  discard\n"
    When normalizeHashFingerprint is called
    Then the result equals normalizeHashFingerprint("proc foo() =\n  discard")

  Scenario: Logic change produces different fingerprint
    Given source A "proc foo() = 1"
    And source B "proc foo() = 2"
    Then normalizeHashFingerprint(A) != normalizeHashFingerprint(B)

  Scenario: Migration script updates all certificate fingerprints
    Given 995 certificates in vault
    When scripts/refresh_fingerprints.nim is executed
    Then all certificates have comment-stripped fingerprints
    And staleFunctions returns to 0
