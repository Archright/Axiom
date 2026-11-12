@manual
Feature: ax prove --heal regression surface

  AGENTS.md §3 requires the Self-Healing Loop to remain accessible for regression
  testing. Because the standalone `ax prove --heal` CLI crashes with KeyError, the canonical
  regression path is exposed as `ax prove --heal`, which routes to the same
  shortcut action as `ax prove --heal`.

  Scenario: ax prove --heal dispatches to heal shortcut
    Given the CLI action planner is initialized
    When the user runs "ax prove --heal"
    Then planAxActions returns exactly one action
    And the action kind is cliRunAxHealShortcut
    And the action args contain "--heal"
