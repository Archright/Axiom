Feature: Golden Master Test Framework
  As a gate enforcer
  I want deterministic golden file snapshots for high-churn modules
  So that unintended API changes are caught before commit

  Background:
    Given the project root is the Axiom repository
    And golden files exist in data/golden/

  Scenario: Golden files exist for all Tier 1 modules
    Given hotspot_tiers.json defines Tier 1 modules
    When I check for golden files in data/golden/
    Then every Tier 1 module must have a corresponding .golden.json file

  Scenario: Golden files are deterministic JSON
    Given a golden file for module "wf_state"
    When I parse the golden file as JSON
    Then the JSON keys must be sorted alphabetically
    And no non-deterministic data is present (timestamps, UUIDs, addresses)

  Scenario: Current module output matches golden file
    Given a golden file exists for module "wf_state"
    When I capture the current module snapshot
    And normalize it with normalizeAndSort()
    Then the snapshot must match the golden file exactly

  Scenario: Golden mismatch produces detailed diff
    Given a golden file exists for module "axiom_engine"
    When the current module output differs from the golden file
    Then the test must fail with a line-by-line diff
    And the diff must show expected vs actual values

  Scenario: Missing golden file fails the gate
    Given a Tier 1 module "test_missing_module"
    And no golden file exists for it
    When the golden-master-gate runs
    Then the gate must exit with failure code
    And report the missing golden file path
