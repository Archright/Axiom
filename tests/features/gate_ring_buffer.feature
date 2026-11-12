@gate-admin
Feature: Gate Ring Buffer for Stagnant Cycle Detection
  As an Axiom engineer
  I want a POSIX file-locked ring buffer to track gate execution history
  So that stagnant cycles are detected across concurrent processes

  Background:
    Given the ring buffer file exists at .axiom/ring_buffer.json

  Scenario: Record a new transaction
    When I start a new transaction with ctxHash "abc123"
    Then the transaction should be recorded with a unique executionId
    And the transaction state should be "active"

  Scenario: Complete a transaction with success
    Given an active transaction exists
    When I record outcome with exitCode 0
    Then the transaction state should be "success"
    And the consecutive failure count should be 0

  Scenario: Complete a transaction with failure
    Given an active transaction exists
    When I record outcome with exitCode 1
    Then the transaction state should be "failure"
    And the consecutive failure count should increment

  Scenario: Detect stagnant cycle after repeated failures
    Given 2 consecutive failures with the same ctxHash "abc123"
    When I check for stagnant cycles with ctxHash "abc123"
    Then the stagnant check should return true

  Scenario: Reset consecutive count on success after failure
    Given 1 failure followed by 1 success with the same ctxHash
    When I check for stagnant cycles
    Then the stagnant check should return false
    And the consecutive failure count should be 0

  Scenario: Different ctxHash resets the cycle counter
    Given 2 failures with ctxHash "abc123"
    When I record a failure with ctxHash "def456"
    Then the consecutive count for "abc123" should not affect "def456"

  Scenario: File locking prevents concurrent corruption
    Given multiple processes attempt simultaneous writes
    Then POSIX file locks should serialize access
    And no data corruption should occur
