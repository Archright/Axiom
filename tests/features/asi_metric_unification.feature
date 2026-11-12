@legacy
Feature: ASI Metric Unification (AMU)
  As an Axiom integrity engineer
  I want the Architecture Stability Index to be computed from a single canonical formula
  So that no ad-hoc or corrupted ASI values can be committed to proof_universe.lock

  Background:
    Given the Axiom project has source functions count >= 500
    And the certificate vault contains valid .json certificates

  Scenario: ValidatedAsi type prevents raw string injection
    Given metrics.nim defines ValidatedAsi as distinct string
    When any module attempts to pass a raw string literal to computeProofUniverseLock
    Then the Nim compiler rejects it with a type mismatch error

  Scenario: Corrupted denominator triggers panic in full-source scope
    Given hydrateProofStateFromCertificateVault returns totalNodes = 299
    And ax_proof_state.json is missing or stale
    When getUnifiedAsiFixed4 computes AsiUniverse(totalFunctions: 299)
    Then validateUniverse(299, usTotalSource) returns false
    And the engine panics with "[AXIOM PANIC] ASI denominator corrupted"
    And quit(1) is called

  @deprecated
  Scenario: proof_universe.lock ASI matches engine ASI after fix
    Given the codebase has 2414 total source functions
    And 322 certificates are verified (certGreen)
    When ax prove src --no-graph-cache completes successfully
    Then proof_universe.lock contains asiFixed4 = "0.1321"
    And ax report --json engineAsiFixed4 equals "0.1321"
    And the difference between lock ASI and engine ASI is 0.0000

  Scenario: Legacy calculateAsiFixed4 is removed
    Given proof_state_builder.nim no longer exports calculateAsiFixed4
    When any module attempts to import calculateAsiFixed4
    Then the Nim compiler reports "undeclared identifier: calculateAsiFixed4"

  Scenario: Deprecated functions are removed (DEBT#202)
    Given metrics.nim no longer exports computeSplitAsi, computeAsi, computeAxiomaticIntegrity, or computeFormalProofIntegrity
    When any module attempts to call computeSplitAsi
    Then the Nim compiler reports "undeclared identifier: computeSplitAsi"
