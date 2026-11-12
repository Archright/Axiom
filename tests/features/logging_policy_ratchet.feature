Feature: Logging Policy Gate — Exception-Based Ratchet
  As a developer
  I want the logging-policy-gate to support exception manifests and delta-only checking
  So that pre-existing false positives don't block unrelated commits

  Background:
    Given the logging-policy-gate is configured
    And the baseline exists with known counts

  Scenario: Delta mode passes with no new violations in staged files
    Given I am in delta mode
    And the staged files contain no new logging policy violations
    When the gate runs
    Then the gate should PASS
    And the output should mention "Delta mode"

  Scenario: Exception manifest filters approved false positives
    Given the exception manifest has an entry for "state_hash.nim" with rule "sensitive-data-leak"
    And the entry has not expired
    When the gate runs
    Then the exception should reduce the effective error count
    And the output should mention "covered by exception manifest"

  Scenario: Expired exceptions are not counted
    Given the exception manifest has an entry with expires date "2020-01-01"
    When the gate runs
    Then the expired entry should be ignored
    And the effective error count should not be reduced

  Scenario: New violations in changed files still fail the gate
    Given I am in delta mode
    And a staged file introduces a new "sensitive-data-leak" violation
    When the gate runs
    Then the gate should FAIL

  Scenario: Baseline ratchet holds when effective errors ≤ baseline
    Given the current error count is 82
    And the baseline allows 79 errors
    And 5 errors are covered by the exception manifest
    When the gate runs
    Then the effective error count should be 77
    And the gate should PASS
