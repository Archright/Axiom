Feature: Proof Verifier (Lean Kernel Only)
  As an Axiom operator
  I want proof artifacts verified by the Lean kernel only
  So that the TCB is minimal and trustworthy

  Scenario: Valid proof passes all 8 verification steps
    Given a ProofArtifact with matching treeSha and toolchainHash
    When verifyProof is called with the same expectedTreeSha
    Then the result is vrSuccess

  Scenario: Tampered treeSha fails Merkle binding
    Given a ProofArtifact with valid proof
    When verifyProof is called with a different expectedTreeSha
    Then the result is vrInvalidMerkle

  Scenario: Oversized proof is rejected
    Given a ProofArtifact with z3Proof larger than MaxZ3ProofSize
    When verifyProof is called
    Then the result is vrInputTooLarge

  Scenario: Mismatched toolchain hash is rejected
    Given a ProofArtifact with wrong toolchainHash
    When verifyProof is called
    Then the result is vrInvalidToolchain
