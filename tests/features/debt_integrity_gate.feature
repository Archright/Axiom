Feature: Debt Integrity Gate — consolidated debt registry enforcer
  As the Debt Registry,
  I want a single gate that validates the integrity of the consolidated debt ledger,
  So that the four previously-separate debt gates can be enforced without redundant passes.

  Background:
    Given the debt registry is loaded from data/debt_registry.json
    And the debt integrity gate is registered in the manifest

  Scenario: registry schema is well-formed
    Given a debt registry file with valid JSON schema
    When debt_integrity_gate validates the schema
    Then validation succeeds and the gate passes

  Scenario: dangling debt references are rejected
    Given a debt entry that references a non-existent module
    When debt_integrity_gate scans the registry
    Then the gate fails with a dangling-reference violation

  Scenario: debt reduction ratchet is enforced
    Given the current debt total is below the previous baseline
    When debt_integrity_gate compares against the baseline
    Then the gate passes
    And the baseline is updated to the lower total
