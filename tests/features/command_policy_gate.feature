Feature: Command Policy Gate CLI Validator
  As an Axiom operator
  I want a standalone CLI tool that validates commands against policy
  So that command policy can be checked independently of the orchestrator

  Background:
    Given the Axiom gate infrastructure is initialized
    And `src/gate/utils/command_policy_gate.nim` is compiled to `build/command_policy_gate`

  Scenario: blocks git merge command
    When the command_policy_gate validates the command "git merge branch-a"
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: blocks git rebase command
    When the command_policy_gate validates the command "git rebase HEAD~3"
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: allows git status command
    When the command_policy_gate validates the command "git status"
    Then the exit code should be 0

  Scenario: blocks command with shell control operator
    When the command_policy_gate validates the command "git status && git merge main"
    Then the exit code should be 2

  Scenario: blocks dynamic syntax injection
    When the command_policy_gate validates the command "git log $(rm -rf /)"
    Then the exit code should be 2

  Scenario: allows git push command
    When the command_policy_gate validates the command "git push origin main"
    Then the exit code should be 0

  Scenario: stdin JSON input works
    Given stdin contains '{"tool_input":{"command":"git status"}}'
    When I run `build/command_policy_gate`
    Then the exit code should be 0

  # ── Zero-Trust Interpreter Validation in Pipeline ────────────────────────

  Scenario: blocks python -c inline code in pipeline
    When the command_policy_gate validates the command "python -c \"import os\""
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: blocks bare interpreter in pipeline
    When the command_policy_gate validates the command "python3"
    Then the exit code should be 2
    And stderr should contain "BLOCKED"
