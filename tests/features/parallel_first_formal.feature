@legacy
Feature: Parallel-First Formal Sketching
  Complex nodes get Formal Sketching even after intrinsic certification succeeds,
  providing higher-assurance proofs through deterministic skeleton + Leanstral tactics.

  Background:
    Given heal.nim has isComplexNode heuristic
    And tryLeanstralSelfCorrection supports Formal Sketching mode

  Scenario: Complex node triggers parallel Formal Sketching
    Given a node with function name containing "verify"
    When BoundaryExtractor produces intrinsic hint
    And saveHint succeeds with certIntrinsic
    Then isComplexNode returns true
    And tryLeanstralSelfCorrection is invoked with the BoundaryExtractor candidate
    And [Parallel-First] appears in the log

  Scenario: Simple node does not trigger Formal Sketching
    Given a node with function name "add" and 1 parameter
    When BoundaryExtractor produces intrinsic hint
    And saveHint succeeds with certIntrinsic
    Then isComplexNode returns false
    And executeHealNode returns immediately

  Scenario: Complex patterns are detected by name
    Given function name contains "ffi" or "callback" or "verify"
    When isComplexNode is called
    Then it returns true

  Scenario: Three or more parameters triggers complexity
    Given function signature has 3+ comma-separated parameters
    When isComplexNode is called
    Then it returns true
