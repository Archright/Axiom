@legacy
Feature: Wave 11 Type Class Synthesis and ASI Fixes
  Critical fixes addressing ASI regression (0.4908 → 0.4188) and Leanstral
  synthInstanceFailed errors.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And certificate vault exists at "src/verification/certificates/"

  Scenario: certIntrinsic is recognized by keyToStatus
    Given certificate JSON contains "status": "certIntrinsic"
    When the certificate is hydrated by the analyzer
    Then keyToStatus("certIntrinsic") returns certIntrinsic
    And the function is counted toward verifiedFunctions in ASI

  Scenario: certIntrinsic is NOT misclassified as certRed
    Given certificate JSON contains "status": "certIntrinsic"
    When the certificate is hydrated by the analyzer
    Then the status is NOT certRed
    And redFunctions does not increase

  Scenario: Nim type class instances exist in axiom prelude
    Given axiom_prelude.nim is loaded
    Then prelude contains "instance : DecidableEq NimInt"
    And prelude contains "instance : Inhabited NimChar"
    And prelude contains "instance : BEq NimString"
    And prelude contains "instance : Repr NimBool"
    And prelude contains "abbrev Table"
    And prelude contains "DecidableEq (Table K V)"

  Scenario: Type class guidance is included in tactic prompt
    Given buildLeanstralTacticPrompt is called
    Then the prompt contains "failed to synthesize instance"
    And the prompt contains "define the missing instance locally"

  Scenario: Int-typed SMT variables use hypothesis proof not Nat.zero_le
    Given SMT-LIB2 contains "(declare-const x Int)" and "(assert (>= x 0))"
    When buildLeanProofFromSmtlib2 generates the Lean 4 source
    Then the theorem includes hypothesis "(h0 : x ≥ 0)"
    And the proof body is "exact h0"
    And the proof compiles without "Nat.zero_le" type mismatch

  Scenario: certRed certificate with leanArtifactHash is promoted on recertify
    Given certificate JSON has status "certRed" and non-empty "leanArtifactHash"
    When updateCertificateLeanHash is called with a valid hash
    Then the certificate status becomes "certVerifiedAxiom"
    And the reason is "verified-axiom:lean-replay"
