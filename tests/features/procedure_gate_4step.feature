@legacy
@executable
Feature: procedure_gate 4-step deterministic enforcement

  Scenario: src/ change requires separate Spec and Test evidence
    Given a src/ file is modified
    When procedure-gate evaluates the commit
    Then tests/features/*.feature must be present for Spec
    And tests/gateway/* or tests/unit/* must be present for Test
    And the same file must NOT satisfy both Spec and Test

  Scenario: tests/gateway/*_test.nim is NOT Spec evidence
    Given a tests/gateway/*_test.nim file is modified
    When procedure-gate checks hasSpecification
    Then it must return false
    And hasTest must return true
