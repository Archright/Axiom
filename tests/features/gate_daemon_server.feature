Feature: Gate Daemon Server — Unix socket server with in-memory MemoDb
  As the Gate Infrastructure,
  I want a persistent daemon process that serves cache queries over Unix sockets,
  So that the orchestrator avoids disk I/O for gate_memo reads.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: warm start loads existing gate history
    Given a gate_history.jsonl file with 3 entries
    When the daemon starts with warmStart
    Then the MemoDb contains 3 entries

  Scenario: handleRequest returns pong for ping
    Given an initialized MemoDb
    When I send a request with method "ping"
    Then the response has ok=true and message "pong"

  Scenario: handleRequest caches gate result
    Given an initialized MemoDb
    When I send a persist_result request for gateId "test-gate"
    And I send a check_cache request for gateId "test-gate"
    Then the response has cached=true

  Scenario: handleRequest rejects missing gateId
    Given an initialized MemoDb
    When I send a check_cache request with empty gateId
    Then the response has ok=false and message "missing gateId"
