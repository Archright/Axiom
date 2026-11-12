@legacy
@executable
Feature: Proof Vacuity Gate — Anti-Vacuity Enforcement
  As an Axiom verification engineer
  I want the vacuity gate to reject trivially-true or vacuous proofs
  So that the integrity engine only certifies meaningful correctness properties

  Background:
    Given the Axiom engine is initialized

  Scenario: Trivial Lean source is detected as vacuous
    Given a Lean source "theorem foo : True := by trivial"
    When leanVacuityReason is evaluated
    Then the reason must contain "trivially True"

  Scenario: Empty Lean source is detected as vacuous
    Given an empty Lean source
    When leanVacuityReason is evaluated
    Then the reason must contain "empty"

  Scenario: Self-equality tautology is detected
    Given a Lean source "theorem foo (n : Nat) : n = n := by rfl"
    When leanVacuityReason is evaluated
    Then the reason must contain "self-equality"

  Scenario: Assert true SMT constraint is detected as vacuous
    Given an SMT constraint "(assert true)"
    When smtVacuityReason is evaluated
    Then the reason must contain "vacuous"

  Scenario: Meaningful Lean proof is accepted
    Given a Lean source "theorem foo (x y : Nat) (h : x > y) : x >= y := by omega"
    And source context with variables x and y
    When validateVacuityParts is evaluated
    Then accepted must be true

  Scenario: Proof with insufficient entropy is rejected
    Given a Lean source with only one semantic term and low information gain
    When validateVacuityParts is evaluated
    Then accepted must be false
    And the reason must contain "entropy"

  Scenario: Semantic identifier extraction finds meaningful tokens
    Given source code "proc calculateTotal(price: int, qty: int): int"
    When extractSemanticIdentifiers is called
    Then the result must contain "calculatetotal"
    And the result must contain "price"
    And the result must contain "qty"

  Scenario: Reserved symbols are excluded from identifier extraction
    Given source code "assert and or not true"
    When extractSemanticIdentifiers is called
    Then the result must be empty

  Scenario: vacuityEvidenceLine formats correctly
    Given a VacuityGateDecision with entropyPassed=true, bindingPassed=true, counterExamplePassed=false
    When vacuityEvidenceLine is called
    Then the output must contain "Entropy: Pass"
    And the output must contain "Binding: Valid"
    And the output must contain "Counter-Ex: Missing"
