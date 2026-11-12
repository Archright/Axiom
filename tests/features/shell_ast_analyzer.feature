Feature: Shell AST Analyzer
  As an Axiom operator
  I want an AST-based shell command analyzer that allows safe dynamic syntax
  So that commands like `echo $HOME` are not falsely blocked

  Background:
    Given the Axiom gate infrastructure is initialized
    And `tests/gate/test_shell_ast_analyzer` is compiled

  Scenario: allows safe commands with variable expansion
    When I run the shell_ast_analyzer test suite
    Then all tests should pass

  Scenario: blocks eval command
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "eval $X"
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: blocks network tools
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "curl http://example.com"
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: blocks command name obfuscation
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "e'v'al \$X"
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: blocks variable-as-command
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "$CMD arg1"
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: allows safe commands through policy gate
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "echo $HOME"
    Then the exit code should be 0

  Scenario: allows git commands through policy gate
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "git status"
    Then the exit code should be 0

  # ── Zero-Trust Interpreter Validation ────────────────────────────────────

  Scenario: blocks bare python3 invocation
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "python3"
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: blocks python3 -c inline code
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "python3 -c \"print(1)\""
    Then the exit code should be 2
    And stderr should contain "stateful"

  Scenario: blocks python3 -m without -I isolation
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "python3 -m json.tool"
    Then the exit code should be 2
    And stderr should contain "requires"

  Scenario: blocks python3 -Im with non-whitelisted module
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "python3 -Im http.server"
    Then the exit code should be 2
    And stderr should contain "whitelist"

  Scenario: blocks shell interpreter bash
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "bash -c \"echo\""
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: blocks node -e inline code
    Given the command policy gate is compiled
    When the command_policy_gate validates the command "node -e \"console.log(1)\""
    Then the exit code should be 2
    And stderr should contain "stateful"
