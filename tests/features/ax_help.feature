@legacy
@executable
Feature: ax help command

  The `ax help` command is the canonical surface for discovering all `ax` and `axiom`
  subcommands. Every command's metadata (name, usage, description) is defined in a
  single SSOT registry so that help output, error messages, and parser hints never drift.

  Scenario: ax help prints detailed usage for all commands
    Given the user runs "ax help"
    Then the CLI prints the usage header
    And every ax subcommand (prove, heal, report, help) is listed with description
    And every axiom subcommand is listed with description
    And the exit code is 0

  Scenario: unknown ax subcommand prints full help
    Given the user runs "ax unknown"
    Then the CLI prints an unknown subcommand error
    And the CLI prints the full usage lines
    And the exit code is 1
