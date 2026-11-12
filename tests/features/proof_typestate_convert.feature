Feature: Proof Typestate Conversion
  As an Axiom operator
  I want typestate conversions to be deterministic and bidirectional
  So that proof states can be serialized and deserialized safely

  Scenario: String round-trip preserves state
    Given a proof state Verified
    When convertProofStateToString and parseProofState are called
    Then the original state is recovered

  Scenario: Invalid state string returns Unknown
    Given an unrecognized state string "invalid_state"
    When parseProofState is called
    Then the result is Unknown
