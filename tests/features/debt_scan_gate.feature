Feature: Debt Scan Gate — architecture debt scanning and blocking
  As the Gate Infrastructure,
  I want to scan staged changes for architecture debt violations,
  So that debt does not increase beyond the established baseline.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: no new debt violations pass
    Given staged files that introduce no new debt violations
    When I run the debt scan gate
    Then the gate passes
