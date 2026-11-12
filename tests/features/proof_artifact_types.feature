Feature: Proof Artifact Types
  As an Axiom operator
  I want IPC contract types for proof-carrying code
  So that gate daemon and safe-merge communicate with validated types

  Scenario: Valid ProofArtifact passes validation
    Given a ProofArtifact with 40-char commitSha and valid treeSha
    When isValidProofArtifact is called
    Then the result is true

  Scenario: Invalid commitSha fails validation
    Given a ProofArtifact with commitSha shorter than 40 chars
    When isValidProofArtifact is called
    Then the result is false

  Scenario: ProofArtifact JSON roundtrip
    Given a valid ProofArtifact
    When serialized to JSON and deserialized back
    Then all fields match the original
