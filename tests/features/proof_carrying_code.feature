Feature: Proof-Carrying Code Pipeline

  The proof-carrying code pipeline verifies the integrity of AI-generated
  software logic through a chain: artifact construction, SMT-LIB2 DFA parsing,
  Z3 proof validation, Lean kernel soundness checking, and Merkle binding.
  Every component is pure — no I/O, no process execution, no side effects.

  # ─── Verification Pipeline ────────────────────────────────────────

  Scenario: Valid proof artifact passes verification
    Given a ProofArtifact with valid tree SHA and toolchain hash
    And a Z3 proof in valid SMT-LIB2 format
    And a proofHash matching the artifact fields
    When verifyProof is called with matching expectedTreeSha
    Then result is vrValid

  Scenario: Tampered proof artifact fails Merkle binding
    Given a ProofArtifact with valid proof
    When verifyProof is called with different expectedTreeSha
    Then result is vrInvalidMerkle

  Scenario: Oversized proof artifact rejected
    Given a ProofArtifact with z3Proof larger than MaxZ3ProofSize
    When verifyProof is called
    Then result is vrInputTooLarge

  Scenario: Malformed SMT-LIB2 proof rejected
    Given a ProofArtifact with invalid SMT-LIB2 syntax
    When verifyProof is called
    Then result is vrMalformedInput

  Scenario: Toolchain hash mismatch rejects proof
    Given a ProofArtifact with toolchain hash different from local build
    When verifyProof is called
    Then result is vrInvalidToolchain

  # ─── DFA Parser ───────────────────────────────────────────────────

  Scenario: DFA parser rejects regex patterns
    Given an SMT-LIB2 input with regex-like syntax
    When parseSmtLib2 is called
    Then result is Failure

  Scenario: DFA parser accepts valid SMT-LIB2
    Given an SMT-LIB2 input with balanced parentheses and valid tokens
    When parseSmtLib2 is called
    Then result is Success with tokens

  # ─── IPC Protocol ─────────────────────────────────────────────────

  Scenario: IPC message validation
    Given a valid IPC sign request with commitSha
    When parseIpcMessage is called
    Then result contains a valid IpcMessage

  Scenario: IPC rejects oversized messages
    Given an IPC message exceeding MaxIpcMessageSize
    When parseIpcMessage is called
    Then result is Failure

  Scenario: IPC rejects invalid socket path
    Given a socket path containing ".."
    When isValidUnixSocketPath is called
    Then result is false

  Scenario: IPC accepts valid socket path
    Given a well-formed Unix socket path
    When isValidUnixSocketPath is called
    Then result is true

  # ─── Z3 Proof Validation ─────────────────────────────────────────

  Scenario: Z3 proof roundtrip
    Given a Z3 proof with 3 steps in topological order
    When parseZ3Proof and validateZ3Proof are called
    Then proof is valid and stepCount is 3

  Scenario: Z3 proof rejects self-referencing step
    Given a Z3 proof where step 0 references itself as premise
    When validateZ3Proof is called
    Then validation fails
