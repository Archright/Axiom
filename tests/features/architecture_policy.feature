@legacy

@executable
Feature: Architecture policy parser tests.
  Auto-generated from architecture_policy_test.nim

  Scenario: Architecture policy parser tests.
    Given the Axiom system is initialized
    When Architecture policy parser tests.
    Then the result should be valid

  Scenario: check parsed.ok
    Given the Axiom system is initialized
    When check parsed.ok
    Then the result should be valid

  Scenario: check parsed.diagnostics.len == 0
    Given the Axiom system is initialized
    When check parsed.diagnostics.len == 0
    Then the result should be valid

  Scenario: check parsed.policy.version == "axiom.architecture-policy.v1"
    Given the Axiom system is initialized
    When check parsed.policy.version == "axiom.architecture-policy.v1
    Then the result should be valid

  Scenario: check parsed.policy.layers["Domain"] == @["src/core/**"]
    Given the Axiom system is initialized
    When check parsed.policy.layers["Domain"] == @["src/core/**"]
    Then the result should be valid

