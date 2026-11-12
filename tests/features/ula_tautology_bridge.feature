@legacy
Feature: ULA Tautology Bridge Connection
  As an Axiom developer
  I want the ULA pipeline to correctly route isTautologyProof to tautology_prover
  So that trivial-discard functions generate compilable Lean proofs and certGreen certificates

  Background:
    Given the universal_assembler module "src/translator/universal_assembler.nim"

  Scenario: buildLeanProofBody routes isTautologyProof to tautology_prover
    Given a SemanticHint with strategy isTautologyProof
    When buildLeanProofBody is called with the hint
    Then the proof body is "  simpa using h_sys\n"

  Scenario: sanitizeLeanSource strips Nim type annotations
    Given a Lean source line containing "let x : int = 42"
    When sanitizeLeanSource is called
    Then "let x : int =" is transformed to "let x :="
    And ": int" is removed from the output

  Scenario: Leanstral timeout is 30 seconds for large functions
    Given the constants module
    When leanstralTimeoutMs is read
    Then the value is 30000
