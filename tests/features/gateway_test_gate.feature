Feature: gateway_test_gate — Gateway Test Execution Gate
  As a contributor committing changes to the Axiom project,
  the gateway_test_gate must execute BDD gateway tests and
  verify that all feature test suites pass before allowing
  the commit to proceed.

  Background:
    Given the gateway_test_gate binary is compiled
    And the working directory is the Axiom project root

  # ── Mode parsing ─────────────────────────────────────────────────

  Scenario: Accepts incremental mode
    When the gateway_test_gate runs with mode "incremental"
    Then it should parse the mode as grmIncremental

  Scenario: Accepts pre-commit mode alias
    When the gateway_test_gate runs with mode "pre-commit"
    Then it should parse the mode as grmIncremental

  Scenario: Accepts exhaustive mode
    When the gateway_test_gate runs with mode "exhaustive"
    Then it should parse the mode as grmExhaustive

  Scenario: Accepts pre-push mode alias
    When the gateway_test_gate runs with mode "pre-push"
    Then it should parse the mode as grmExhaustive

  Scenario: Rejects invalid mode
    When the gateway_test_gate runs with mode "invalid-mode"
    Then it should exit with code 1
    And stderr should contain "invalid mode"

  # ── Test execution ───────────────────────────────────────────────

  Scenario: All gateway tests pass
    Given all gateway test files compile successfully
    When the gateway_test_gate runs with mode "exhaustive"
    Then it should exit with code 0
    And stdout should contain "PASS"

  Scenario: Gateway test failure blocks commit
    Given a gateway test file has a failing assertion
    When the gateway_test_gate runs with mode "exhaustive"
    Then it should exit with code 1
    And stdout should contain "FAIL"
