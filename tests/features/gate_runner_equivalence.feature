@legacy
@executable
Feature: Gate Runner Equivalence
  Auto-generated from gate_runner_equivalence_test.nim

  Scenario: doAssert gates.len == 20
    Given the Axiom system is initialized
    When doAssert gates.len == 20
    Then the result should be valid

  Scenario: "gate-self-check", "sentinel", "unstaged-guard", "cli-build",
    Given the Axiom system is initialized
    When "gate-self-check", "sentinel", "unstaged-guard", "cli-build"
    Then the result should be valid

  Scenario: "procedure-gate", "nim-check", "drnim", "gateway-test", "integrity-test",
    Given the Axiom system is initialized
    When "procedure-gate", "nim-check", "drnim", "gateway-test", "int
    Then the result should be valid

  Scenario: doAssert found, "Missing gate: " & expected
    Given the Axiom system is initialized
    When doAssert found, "Missing gate: " & expected
    Then the result should be valid

  Scenario: doAssert hasSrc or hasBin,
    Given the Axiom system is initialized
    When doAssert hasSrc or hasBin,
    Then the result should be valid

