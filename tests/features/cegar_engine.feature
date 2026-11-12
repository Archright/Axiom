@legacy
@executable
Feature: CEGAR Engine — Counter-Example Guided Abstraction Refinement
  As an Axiom verification engineer
  I want the CEGAR engine to find loop invariants through fixed-point convergence
  So that loops are verified with mathematically sound invariants

  Background:
    Given the Axiom engine is initialized

  Scenario: Fingerprint is deterministic for identical invariant sets
    Given a set of invariants ["(>= x 0)", "(<= x 100)"]
    When computeInvariantFingerprint is called twice on the same set
    Then both fingerprints must be equal

  Scenario: Fingerprint is order-independent
    Given invariant set A: ["(>= x 0)", "(<= x 100)"]
    And invariant set B: ["(<= x 100)", "(>= x 0)"]
    When computeInvariantFingerprint is called on both sets
    Then the fingerprints must be equal

  Scenario: Different invariant sets produce different fingerprints
    Given invariant set A: ["(>= x 0)"]
    And invariant set B: ["(>= x 10)"]
    When computeInvariantFingerprint is called on both sets
    Then the fingerprints must differ

  Scenario: SMT-LIB2 encoding includes variable declarations
    Given invariants containing variables x and y
    When encodeProvedInvariantsSmtlib2 is called
    Then the output must contain "(declare-const x Int)"
    And the output must contain "(declare-const y Int)"
    And the output must contain "(check-sat)"

  Scenario: SMT-LIB2 encoding of empty invariant set returns empty
    Given an empty invariant set
    When encodeProvedInvariantsSmtlib2 is called
    Then the result must be an empty string

  Scenario: CEGAR loop terminates within iteration budget
    Given a simple loop source code
    And a mock Z3 solver that always returns unsat
    When runCegarAbstraction is invoked with maxIterations=5
    Then the iteration count must be <= 5
    And the verdict must be one of cegarProven, cegarMaxIterations, or cegarBudgetExceeded
