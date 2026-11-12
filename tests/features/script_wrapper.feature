Feature: Script Wrapper — safe invocation wrapper for external scripts
  As the Axiom runtime,
  I want a wrapper that invokes scripts with timeout and env isolation,
  So that external scripts cannot exceed their allocated resources.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: wrapper executes a script within timeout
    Given a script "echo_test" that completes in 1 second
    When I invoke the script wrapper with a 10-second timeout
    Then the script completes successfully

  Scenario: wrapper terminates a script that exceeds timeout
    Given a script "sleep_forever" that runs indefinitely
    When I invoke the script wrapper with a 2-second timeout
    Then the script is terminated and a timeout error is returned
