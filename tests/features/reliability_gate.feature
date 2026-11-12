@executable
Feature: Reliability Score Hard Gate

  As an Axiom gate operator
  I want emergency bypass to be blocked when reliability degrades
  So that the system self-heals by forcing engineers to fix underlying issues

  Background:
    Given the reliability gate is installed

  Scenario: Emergency bypass blocked when reliability score below threshold
    Given the reliability score is 75
    When AXIOM_EMERGENCY_NO_VERIFY is set to 1
    Then the gate should FAIL with "Emergency bypass BLOCKED"

  Scenario: Emergency bypass allowed when reliability score above threshold
    Given the reliability score is 85
    When AXIOM_EMERGENCY_NO_VERIFY is set to 1
    Then the gate should log the bypass and return PASS

  Scenario: Normal gate run without emergency bypass
    Given the reliability score is 75
    When no emergency bypass is set
    Then the gate should PASS with a warning

  Scenario: Score exactly at threshold allows bypass
    Given the reliability score is 80
    When AXIOM_EMERGENCY_NO_VERIFY is set to 1
    Then the gate should log the bypass and return PASS

  Scenario: Score one below threshold blocks bypass
    Given the reliability score is 79
    When AXIOM_EMERGENCY_NO_VERIFY is set to 1
    Then the gate should FAIL with "Emergency bypass BLOCKED"
