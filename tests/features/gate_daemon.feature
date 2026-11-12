Feature: Gate Daemon (Signing Daemon)
  As an Axiom operator
  I want a daemon that verifies proofs and creates signed commits
  So that only verified commits receive GPG signatures

  Scenario: Daemon listens on Unix socket
    Given a socket path and repository path
    When runDaemon is called
    Then a Unix socket is created and listening

  Scenario: Valid sign request produces signed commit
    Given a SignRequest with valid commitSha
    When the daemon processes the request
    Then a GPG-signed commit is created

  Scenario: Invalid proof produces denied response
    Given a SignRequest with tampered commitSha
    When the daemon processes the request
    Then a SignResponse with status denied is returned

  Scenario: Graceful shutdown on SIGTERM
    Given a running daemon
    When SIGTERM is received
    Then the daemon shuts down cleanly
