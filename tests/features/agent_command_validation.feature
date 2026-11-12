Feature: Agent Command Validation Gate
  As an Axiom operator
  I want the system to block no-op or repeated Bash commands from the agent
  So that the agent uses MCP/Read/Explore tools instead of looping on shell

  Background:
    Given the Axiom gate infrastructure is initialized
    And `bin/gate_admin` is compiled

  Scenario: gate_admin blocks a no-op Bash command
    When I run `bin/gate_admin validate ':'`
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: gate_admin allows a meaningful Bash command
    When I run `bin/gate_admin validate 'bin/gate_hook pre-commit'`
    Then the exit code should be 0

  Scenario: gate_admin validates a command from stdin JSON
    Given stdin contains '{"tool_input":{"command":"bin/gate_hook pre-commit"}}'
    When I run `bin/gate_admin --validate-stdin`
    Then the exit code should be 0

  Scenario: delegation-enforcer detects repeated Bash calls in wire log
    Given a wire log with 3 consecutive no-op Bash commands
    When I run `bin/delegation-enforcer` against that log
    Then the exit code should be 1
    And stderr should contain "LOOP DETECTED"

  Scenario: delegation-enforcer passes on clean wire logs
    Given a wire log with only meaningful Bash commands
    When I run `bin/delegation-enforcer` against that log
    Then the exit code should be 0
    And stdout should contain "PASS"
