@gate-admin
Feature: Gate Admin CLI
  As an Axiom operator
  I want a CLI to manage gate state (bypass, resume, history, status)
  So that I can control gate execution without modifying source code

  Background:
    Given the gate admin state file exists at .axiom/gate_admin_state.json
    And the ring buffer is initialized at .axiom/ring_buffer.json

  Scenario: Disable a specific gate by ID
    When I run "gate_admin disable procedure-gate"
    Then the exit code should be 0
    And the state file should mark "procedure-gate" as disabled

  Scenario: Enable a disabled gate
    Given "procedure-gate" is currently disabled
    When I run "gate_admin enable procedure-gate"
    Then the exit code should be 0
    And the state file should not mark "procedure-gate" as disabled

  Scenario: Show gate status
    When I run "gate_admin status procedure-gate"
    Then the exit code should be 0
    And the output should contain gate state information

  Scenario: Reject unknown subcommand
    When I run "gate_admin unknown-command"
    Then the exit code should be non-zero
