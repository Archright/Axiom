@legacy
Feature: refresh_cli_binaries keeps PATH-resolved binaries synchronized

  The `refresh_cli_binaries` script is the canonical build entry point for CLI
  binaries. After compilation, it must ensure that `~/.local/bin/ax` (and siblings)
  reflect the latest source so that `ax help` and all other commands never drift.

  Scenario: refresh_cli_binaries builds and installs to ~/.local/bin
    Given the source tree has changed
    When the developer runs refresh_cli_binaries
    Then bin/main is rebuilt
    And bin/ax is a link to bin/main
    And ~/.local/bin/ax matches bin/ax
    And ax help shows the current SSOT command registry

  Scenario: gate bond runs once and child processes skip redundant checks
    Given all_gateway_runner exists
    When refresh_cli_binaries compiles multiple targets
    Then all_gateway_runner executes exactly once

  Scenario: shared nimcache with sequential compilation avoids race conditions
    Given multiple targets share a nimcache directory
    When refresh_cli_binaries builds stale targets
    Then targets compile sequentially (jobs=1 default)
    And no linker undefined reference errors occur
