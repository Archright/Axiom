Feature: Z3 Proof to Lean ADT Converter
  As an Axiom operator
  I want Z3 proofs converted to Lean ADT for independent verification
  So that Z3 soundness bugs do not compromise the TCB

  Scenario: Valid Z3 proof converts to Lean ADT
    Given a Z3 proof with steps in topological order
    When parseZ3Proof is called
    Then a valid Z3ProofObject with correct step count is returned

  Scenario: Self-referencing proof step is rejected
    Given a Z3 proof where a step references itself as premise
    When validateZ3Proof is called
    Then validation fails

  Scenario: Cyclic proof DAG is rejected
    Given a Z3 proof with circular dependency between steps
    When validateZ3Proof is called
    Then validation fails

  Scenario: Unreachable proof steps are rejected
    Given a Z3 proof with steps not reachable from the root
    When validateZ3Proof is called
    Then validation fails
