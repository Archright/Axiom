@legacy
Feature: external_cli_smoke gate

  Scenario: Smoke test completes within timeout without deadlock
    Given the external CLI smoke gate binary exists
    When the gate is executed
    Then it must complete within 300 seconds
    And it must not deadlock on pipe buffer fill

  Scenario: AOT binary enables sub-second execution
    Given the AOT compiled smoke_test binary exists
    And the AOT compiled external_cli_smoke binary exists
    When the external-cli-smoke-hard gate is executed
    Then it must complete within 2 seconds
