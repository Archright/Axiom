@gate-admin
Feature: Gate Admin State-Aware Validation
  As an Axiom engineer
  I want the gate admin to validate commands against current state
  So that invalid state transitions are rejected deterministically

  Background:
    Given the gate admin state file exists
    And the ring buffer is initialized

  Scenario: Validate a valid bypass command
    Given no gates are currently bypassed
    When I validate a bypass command for "procedure-gate"
    Then validation should pass
    And the command should be allowed to proceed

  Scenario: Reject bypass of an already-bypassed gate
    Given "procedure-gate" is currently bypassed
    When I validate a bypass command for "procedure-gate"
    Then validation should fail with "already bypassed"

  Scenario: Reject resume of a non-bypassed gate
    Given "procedure-gate" is not bypassed
    When I validate a resume command for "procedure-gate"
    Then validation should fail with "not bypassed"

  Scenario: Stagnant cycle detection blocks repeated failures
    Given "procedure-gate" has 2 consecutive failures with the same ctxHash
    When I validate whether the gate should run
    Then the gate should be blocked as stagnant
    And the reason should contain "stagnant cycle"
