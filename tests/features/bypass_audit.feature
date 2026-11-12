Feature: Bypass Audit Logging
  As the Gate System,
  I want to log all emergency bypass events,
  So that bypass frequency is tracked and reliability score can be computed.

  Background:
    Given the bypass audit infrastructure is initialized

  Scenario: Bypass event is logged to audit trail
    Given a gate "test-gate" triggers an emergency bypass with reason "timeout"
    When logBypass is called
    Then a JSON line is appended to data/bypass_audit.jsonl
    And the entry contains the gate id and reason

  Scenario: Reliability score computed from bypass count
    Given 4 bypass events have been logged
    When computeReliabilityScore is called
    Then the reliability score should be 80
