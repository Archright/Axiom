Feature: DFA-based SMT-LIB2 Parser
  As an Axiom operator
  I want a DFA-based parser for SMT-LIB2 proofs
  So that proof parsing is deterministic and regex-free

  Scenario: Valid SMT-LIB2 input parses successfully
    Given an SMT-LIB2 string with balanced parentheses
    When parseSmtLib2 is called
    Then the result is Success with valid tokens

  Scenario: Unbalanced parentheses fail parsing
    Given an SMT-LIB2 string with unmatched opening paren
    When parseSmtLib2 is called
    Then the result is Failure

  Scenario: Input exceeding MaxZ3ProofSize is rejected
    Given an SMT-LIB2 input larger than 10MB
    When parseSmtLib2 is called
    Then the result is Failure with size error

  Scenario: Regex-like patterns are rejected
    Given an SMT-LIB2 input containing regex syntax
    When parseSmtLib2 is called
    Then the result is Failure
