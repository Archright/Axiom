@legacy
@executable
Feature: Detective Persona — CEGAR Tracking SMT Generation
  As an Axiom verification engineer
  I want the Detective persona to generate tracking SMT-LIB2 for unsat core extraction
  So that counterexample analysis can identify specific conflicting variables

  Background:
    Given the Axiom engine is initialized

  Scenario: Empty candidates produce empty SMT
    Given an empty candidate list
    When buildTrackingSmtlib2 is called
    Then the result must be an empty string

  Scenario: Single candidate produces tracking literal
    Given a single SymSExpr candidate
    When buildTrackingSmtlib2 is called
    Then the result must contain "produce-unsat-cores"
    And the result must contain "track_0"
    And the result must contain "check-sat-assuming"

  Scenario: Multiple candidates produce multiple tracking literals
    Given three SymSExpr candidates
    When buildTrackingSmtlib2 is called
    Then the result must contain "track_0"
    And the result must contain "track_1"
    And the result must contain "track_2"

  Scenario: Variable deduplication in SMT declarations
    Given candidates sharing the same variable name
    When buildTrackingSmtlib2 is called
    Then each variable must be declared exactly once

  Scenario: SMT format is syntactically valid
    Given a non-empty candidate list
    When buildTrackingSmtlib2 is called
    Then the result must start with "(set-option"
    And the result must end with "(get-unsat-core)"
