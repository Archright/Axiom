Feature: Gate Daemon Client — lightweight client for gate daemon communication
  As the Gate Orchestrator,
  I want a lightweight client that communicates with the gate daemon,
  So that I can check and persist gate results via in-memory cache.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: initDaemonClient creates client with correct socket path
    Given a repoRoot at "/tmp/test-repo"
    When I call initDaemonClient
    Then the client socketPath ends with ".axiom/cache/gate-daemon.sock"

  Scenario: sendRequest returns error when daemon is unreachable
    Given a DaemonClient with a non-existent socket path
    When I call sendRequest with a ping request
    Then the response has ok=false and message "daemon not reachable"

  Scenario: isDaemonRunning returns false when socket does not exist
    Given a repoRoot with no daemon socket
    When I call isDaemonRunning
    Then the result is false
