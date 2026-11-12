@executable
@manual
Feature: ax command surface is limited to prove/heal/report
  The ax CLI binary exposes only the three core workflow commands.
  All other subcommands are rejected as unknown.

  Scenario: ax prove is accepted
    When ax prove is invoked with valid arguments
    Then the command executes without "unknown ax subcommand"


  Scenario: ax report is accepted
    When ax report is invoked with valid arguments
    Then the command executes without "unknown ax subcommand"

Feature: ax prove flag surface uses macro-generated mutually exclusive parser
  The ax prove command accepts only flags defined by the AxProveFlags type.
  Mutually exclusive enum variants cannot be combined.

  Scenario: ax prove accepts new-style flags
    When ax prove is invoked with "--limit 10 --full --json src"
    Then the command parses successfully
    And executionMode is evFull
    And limit is 10
    And json is true

  Scenario: ax prove rejects mutually exclusive flags
    When ax prove is invoked with "--full --retry-failed"
    Then stderr contains "mutually exclusive flag already set"
    And exit code is not 0

  Scenario: ax prove auto-generates negation flags for bool=true defaults
    When ax prove is invoked with "--no-graph-cache"
    Then the command parses successfully
    And graphCache is false
