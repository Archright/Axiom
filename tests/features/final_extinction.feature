@legacy
Feature: v0.6.2 Final Extinction — Triple Deadlock Resolution
  In order to achieve ASI 1.0000
  As an Axiom operator
  I want the final three-way deadlock to be permanently resolved

  Scenario: field.length namespace confusion is sanitized
    Given a function with field access like field.length
    When boundaries are extracted
    Then the Lean identifier should be field_length not field.length

  Scenario: trailing conjunction with zero is removed
    Given a return condition that generates result = X ∧ 0
    When boundaries are extracted
    Then the Lean proposition should not end with ∧ 0

  Scenario: forall branch binds hypothesis as h_sys
    Given a universal quantifier proof pattern
    When assemblePrimitiveProof generates tactics
    Then the intro tactic should use h_sys

  Scenario: proof_universe.lock Merkle root verifies pre-push deterministically
    Given ax prove has completed with ASI 1.0000
    When proof_universe.lock is written
    Then pre-push gate should verify Merkle root without sampling

  Scenario: proof_universe.lock rejects missing global symbol graph state
    Given ax prove has a current GlobalSymbolGraph in memory
    When proof_universe.lock is written
    Then logs/global_symbol_graph.json must be persisted first
    And the Merkle root must reject a missing or unreadable graph snapshot

  Scenario: Sentinel self-equality is muted for pure modules
    Given a module with {.axiom_pure.} pragma
    When validateSemanticHintVacuity is called
    Then the decision should be accepted without Sentinel warning

  Scenario: topology freeze warns on uncommitted changes
    Given uncommitted changes exist in src/
    When buildGlobalSymbolGraph is called with freezeGraphCache=true
    Then stderr should emit a high-contrast warning

  Scenario: Lean proof includes maxHeartbeats guard
    Given a complex SMT-LIB2 assertion
    When buildLeanProofFromSmtlib2 generates the theorem
    Then the output should contain set_option maxHeartbeats 300000

  Scenario: CONTEXT.md size gate blocks oversized files
    Given CONTEXT.md exceeds 200 lines
    When the pre-commit procedure gate runs
    Then the gate should fail with a size violation message

  Scenario: compiler hints are extinct in full build
    Given the project builds with nim c src/cli/main.nim
    When the compiler finishes
    Then no XCannotRaiseY or XDeclaredButNotUsed hints should remain
