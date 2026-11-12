@legacy
@executable
Feature: Lean 4 Compiler Compatibility for Generated Propositions

  Background:
    Given the Axiom boundary extractor is active
    And the Lean 4 compiler is available

  Scenario: Nim dot-expression fields are filtered from Lean propositions
    Given a function parameter "node" of type "XmlNode"
    When the function contains "if node.kind == xnElement"
    Then the generated Lean proposition must not contain "node.kind"
    And the generated SMT constraint must not contain "node.kind"

  Scenario: Empty call expressions are dropped
    Given a function contains "nodeIdEquals()"
    When convertExpressionToSmtLean processes the call
    Then both SMT and Lean outputs must be empty

  Scenario: Single-conjunct and patterns compile without constructor
    Given an SMT-LIB2 assertion "(assert (and (>= (str.len raw) 0)))"
    When assemblePrimitiveProof generates the proof
    Then the tactic block must not contain "constructor"
    And the tactic block must contain "exact h0"

  @deprecated
  Scenario: Existing formal proof certificates are preserved during heal
    Given a certificate with status "certGreen" and leanArtifactHash "abc123"
    When ax prove --heal runs for the same function
    Then the certificate status must remain "certGreen"
    And the leanArtifactHash must remain "abc123"
