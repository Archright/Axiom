Feature: Gate Daemon Types — protocol types and MemoDb for gate daemon
  As the Gate Infrastructure,
  I want typed protocol messages and an in-memory cache database,
  So that the daemon can communicate over Unix sockets and cache gate results.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: encode and decode a request round-trip
    Given a DaemonRequest with method "ping" and requestId "test-1"
    When I encode the request to JSON and decode it back
    Then the decoded request has method "ping" and requestId "test-1"

  Scenario: encode and decode a response round-trip
    Given a DaemonResponse with ok=true and message "pong"
    When I encode the response to JSON and decode it back
    Then the decoded response has ok=true and message "pong"

  Scenario: MemoDb lookup returns empty on miss
    Given an empty MemoDb
    When I lookup gateId "test-gate" with subtreeRoot "abc123"
    Then the result has epoch 0 and result false

  Scenario: MemoDb persist and lookup hit
    Given an empty MemoDb
    When I persist a CacheEntry for gateId "test-gate" with result true
    And I lookup gateId "test-gate"
    Then the result has result true and epoch > 0

  Scenario: MemoDb invalidate removes matching entries
    Given a MemoDb with entries for gateId "test-gate"
    When I invalidate gateId "test-gate"
    Then all entries for "test-gate" are removed
