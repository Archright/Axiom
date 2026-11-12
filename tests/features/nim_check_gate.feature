Feature: nim_check_gate — Nim Compilation Check Gate
  As a contributor committing changes to the Axiom project,
  the nim_check_gate must verify that all Nim source files
  compile without errors before allowing the commit to proceed.

  Background:
    Given the nim_check_gate binary is compiled
    And the working directory is the Axiom project root

  # ── Mode parsing ─────────────────────────────────────────────────

  Scenario: Accepts incremental mode
    When the nim_check_gate runs with mode "incremental"
    Then it should parse the mode as grmIncremental

  Scenario: Accepts pre-commit mode alias
    When the nim_check_gate runs with mode "pre-commit"
    Then it should parse the mode as grmIncremental

  Scenario: Accepts exhaustive mode
    When the nim_check_gate runs with mode "exhaustive"
    Then it should parse the mode as grmExhaustive

  Scenario: Accepts pre-push mode alias
    When the nim_check_gate runs with mode "pre-push"
    Then it should parse the mode as grmExhaustive

  Scenario: Rejects invalid mode
    When the nim_check_gate runs with mode "invalid-mode"
    Then it should exit with code 1
    And stderr should contain "invalid mode"

  # ── Aggregator strategy ──────────────────────────────────────────

  Scenario: Aggregator imports compile cleanly
    Given all src/ modules have valid imports
    When the nim_check_gate runs with mode "exhaustive"
    Then it should exit with code 0
    And stdout should contain "PASS"

  Scenario: Forwarding stubs excluded from aggregator
    Given a src/ module contains "Forwarding stub" in its first 10 lines
    When the nim_check_gate runs with mode "exhaustive"
    Then the forwarding stub module should be checked per-file
    And excluded from the aggregator import list

  Scenario: isMainModule files checked per-file
    Given a src/ module contains "when isMainModule"
    When the nim_check_gate runs with mode "exhaustive"
    Then the isMainModule file should be checked per-file
    And excluded from the aggregator import list
