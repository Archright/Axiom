@legacy
@executable
Feature: Judge Persona — Lean 4 Kernel Verification & Diagnostic Parsing
  As an Axiom verification engineer
  I want the Judge persona to parse Lean diagnostics into mathematical discontinuities
  So that the proof pipeline can classify verification failures accurately

  Background:
    Given the Axiom engine is initialized

  Scenario: Empty diagnostic produces no discontinuities
    Given an empty diagnostic string
    When parseDiagnosticToDiscontinuities is called
    Then the result must be an empty sequence

  Scenario: Lean error line is parsed with correct location
    Given a diagnostic line "src/foo.lean:42:10: error: type mismatch"
    When parseDiagnosticToDiscontinuities is called
    Then the result must contain one discontinuity
    And the filePath must be "src/foo.lean"
    And the lineNumber must be 42
    And the discontinuityKind must be dkMissingInvariant

  Scenario: Non-linear arithmetic keyword classification
    Given a diagnostic containing "non-linear arithmetic detected"
    When parseDiagnosticToDiscontinuities is called
    Then the discontinuityKind must be dkNonLinearArithmetic

  Scenario: Recursion keyword classification
    Given a diagnostic containing "unbounded recursion in function"
    When parseDiagnosticToDiscontinuities is called
    Then the discontinuityKind must be dkUnboundedRecursion

  Scenario: Side effect keyword classification
    Given a diagnostic containing "side effect detected in pure context"
    When parseDiagnosticToDiscontinuities is called
    Then the discontinuityKind must be dkExternalSideEffect

  Scenario: Alias keyword classification
    Given a diagnostic containing "pointer aliasing violation"
    When parseDiagnosticToDiscontinuities is called
    Then the discontinuityKind must be dkPointerAliasing

  Scenario: Race condition keyword classification
    Given a diagnostic containing "race condition between threads"
    When parseDiagnosticToDiscontinuities is called
    Then the discontinuityKind must be dkConcurrencyRace
