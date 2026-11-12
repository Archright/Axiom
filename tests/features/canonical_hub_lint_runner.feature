Feature: Canonical Hub Lint Runner — canonical hub import hygiene enforcement
  As the Gate Infrastructure,
  I want to validate canonical hub import patterns,
  So that module boundaries remain clean.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: valid canonical hub imports pass
    Given a staged file with proper canonical hub imports
    When I run the canonical hub lint gate
    Then the gate passes
