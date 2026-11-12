Feature: Python Shell Exemptions Policy
  As the Axiom Language Ban enforcement layer,
  I want a curated list of allowed Python invocations for one-off tooling,
  So that legitimate CI/debug usage is permitted without enabling script persistence.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: exempt python3 invocations are allowed
    Given a Python invocation using json.tool module
    When the exemption policy is consulted
    Then the invocation is marked as exempt

  Scenario: non-exempt python3 invocations are blocked
    Given a Python invocation running a .py file
    When the exemption policy is consulted
    Then the invocation is not marked as exempt

  Scenario: exemption list is monotonic
    When the exemption policy is loaded
    Then the list cannot be reduced below the baseline count
