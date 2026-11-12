Feature: Stateless Sync Protocol Gate
  As a developer
  I want the sync protocol gate to be stateless
  So that it works from any worktree without HEAD dependency

  Scenario: Empty push passes
    Given AXIOM_PUSH_COMMITS is "EMPTY"
    When the gate runs
    Then it exits with code 0

  Scenario: Missing env var fails
    Given AXIOM_PUSH_COMMITS is not set
    When the gate runs
    Then it exits with code 1

  Scenario: Unauthorized commit fails
    Given AXIOM_PUSH_COMMITS contains a commit without sync metadata
    When the gate runs
    Then it exits with code 1
