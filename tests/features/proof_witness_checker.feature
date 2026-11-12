Feature: Proof Witness Checker
  As an Axiom operator
  I want proof witness integrity to be verified at compile time
  So that tampered Lean 4 proofs are detected before execution

  Scenario: Witness file hash matches expected value
    Given a proof_witness.json with known content hash
    When compile-time verification runs
    Then the hash matches and the check passes

  Scenario: Tampered witness file fails verification
    Given a proof_witness.json with modified content
    When compile-time verification runs
    Then the hash mismatch is detected and compilation fails
