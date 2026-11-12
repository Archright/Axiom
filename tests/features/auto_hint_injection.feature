@legacy
Feature: Automatic Axiom Hint Injection
  As an Axiom verification pipeline
  I want the self-healing loop to inject proven invariant hints back into source code
  So that subsequent verification runs benefit from cached premises

  Background:
    Given the Axiom source tree is available

  Scenario: Heal loop injects depth hint into diagnostics engine
    When the self-healing loop processes `emptyTimeoutDiagnosis`
    And the SMT solver proves `depth >= 0`
    Then an `@axiom-hint: lean="depth >= 0"` comment should exist above `emptyTimeoutDiagnosis`

  Scenario: Heal loop injects depth hint into symbolic engine constructors
    When the self-healing loop processes `sTrue` and `sFalse`
    And the SMT solver proves `depth >= 0` for both
    Then an `@axiom-hint: lean="depth >= 0"` comment should exist above each constructor

  Scenario: Injected hints do not break compilation
    Given injected `@axiom-hint` comments exist in source files
    When `nim c src/cli/main.nim` is executed
    Then compilation should succeed with zero errors
