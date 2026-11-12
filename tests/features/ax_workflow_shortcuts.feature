@manual
Feature: AX Workflow Shortcut Argument Parsing

  Background:
    Given the Axiom CLI is available

  Scenario: Parse ax scan shortcut args with defaults
    When parseAxTopologyShortcutArgs is called with args @[]
    Then targetDirectory should be "src"
    And limit should be 5
    And diagnosisDepth should be 0
    And emitJson should be false

  Scenario: Parse ax scan shortcut args with custom limit
    When parseAxTopologyShortcutArgs is called with args @["--limit", "10"]
    Then limit should be 10
    And targetDirectory should be "src"

  Scenario: Parse ax prove shortcut args with vault-dir
    When parseAxProofShortcutArgs is called with args @["--vault-dir", "custom/vault"]
    Then vaultDir should be "custom/vault"
    And limit should be 0

  Scenario: shouldUseAxScanShortcut detects scan mode
    When shouldUseAxScanShortcut is called with args @["--limit", "5"]
    Then the result should be true

  Scenario: shouldUseAxProofShortcut detects prove mode
    When shouldUseAxProofShortcut is called with args @["--limit", "5"]
    Then the result should be true
