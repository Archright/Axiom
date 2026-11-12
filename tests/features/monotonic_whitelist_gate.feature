Feature: Monotonic Whitelist Gate
  As the Gate System,
  I want to ensure the impure_procedures_whitelist never grows,
  So that impure procedure count is monotonically decreasing over time.

  Background:
    Given the monotonic whitelist gate is installed

  Scenario: Whitelist count stable — gate passes
    Given the whitelist count matches the baseline count
    When the monotonic-whitelist-gate runs
    Then the gate should PASS

  Scenario: Whitelist count increased — gate fails
    Given the whitelist count exceeds the baseline count
    When the monotonic-whitelist-gate runs
    Then the gate should FAIL with "whitelist grew"

  Scenario: Whitelist count decreased below ceiling — gate fails
    Given the whitelist count is below the ratchet ceiling
    When the monotonic-whitelist-gate runs
    Then the gate should FAIL with "dropped below ratchet ceiling"
