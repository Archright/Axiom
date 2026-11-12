Feature: Kimi Pre-Tool-Use Hook
  As the Axiom Language Ban enforcement layer,
  I want to block direct interpreter invocations (python3, bash, sh, zsh) in Axiom-core,
  So that no interpreted script source code is persisted in the repository.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: block direct python3 invocation
    Given a tool call with command "python3 -c 'print(1)'"
    When the pre-tool-use hook processes the call
    Then the hook returns exit code 2

  Scenario: allow python3 pipe to jq
    Given a tool call with command "python3 -c 'import json' | jq ."
    When the pre-tool-use hook processes the call
    Then the hook allows the call

  Scenario: allow non-interpreter commands
    Given a tool call with command "nim c src/main.nim"
    When the pre-tool-use hook processes the call
    Then the hook allows the call

  Scenario: stdin JSON parsing
    Given a JSON payload on stdin with action "Bash" and command "python3 -c test"
    When the hook reads stdin
    Then the hook parses the JSON correctly
    And returns the appropriate exit code
