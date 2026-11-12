Feature: Axiom Proof Generator
  As an Axiom operator
  I want axiom-prove to generate proof artifacts inside a sandbox
  So that untrusted code execution is isolated from the signing daemon

  Scenario: Generate proof for valid commit
    Given a repository with a valid commit SHA
    When generateProof is called
    Then a ProofArtifact with valid proofHash is returned

  Scenario: Invalid commit SHA is rejected
    Given a commit SHA with invalid characters
    When generateProof is called
    Then a CatchableError is raised

  Scenario: Missing .smt2 files produce trivial proof
    Given a repository with no .smt2 files
    When generateProof is called
    Then a ProofArtifact with empty Z3 proof is returned
