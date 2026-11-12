@legacy
Feature: Unstaged Changes Guard
  Lightweight meta gate detecting unstaged modifications in core files.

  Scenario: Unstaged changes in src directory are detected
  Scenario: Unstaged changes in tests directory are detected
  Scenario: Build artifacts are ignored
  Scenario: Log files are ignored
  Scenario: Temporary files are ignored
  Scenario: Unstaged AGENTS.md changes block commit
  Scenario: Staged changes do not trigger failure
