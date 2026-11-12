Feature: Git Wrapper Command Policy Enforcement
  As an Axiom operator
  I want a deterministic git wrapper that blocks prohibited subcommands
  So that agents cannot bypass command policy via direct git invocation

  Background:
    Given the Axiom gate infrastructure is initialized
    And `src/gate/utils/git_wrapper.nim` is compiled to `build/git_wrapper`

  Scenario: git_wrapper blocks merge subcommand
    When I run `build/git_wrapper merge branch-a`
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: git_wrapper blocks rebase subcommand
    When I run `build/git_wrapper rebase HEAD~3`
    Then the exit code should be 2
    And stderr should contain "BLOCKED"

  Scenario: git_wrapper blocks cherry-pick subcommand
    When I run `build/git_wrapper cherry-pick abc1234`
    Then the exit code should be 2

  Scenario: git_wrapper allows status subcommand
    When I run `build/git_wrapper status`
    Then the exit code should be 0

  Scenario: git_wrapper allows log subcommand
    When I run `build/git_wrapper log -5`
    Then the exit code should be 0

  Scenario: git_wrapper handles flags before subcommand
    When I run `build/git_wrapper -C . log`
    Then the exit code should be 0

  Scenario: git_wrapper blocks revert subcommand
    When I run `build/git_wrapper revert HEAD`
    Then the exit code should be 2
    And stderr should contain "BLOCKED"
