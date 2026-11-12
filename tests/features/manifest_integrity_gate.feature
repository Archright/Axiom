Feature: Manifest Integrity Gate
  As the Gate System,
  I want to validate bootstrap_manifest.json against the JSON Schema,
  So that PBT algebraic properties are verified as correct and complete.

  Background:
    Given the manifest integrity gate is installed

  Scenario: Valid manifest passes validation
    Given a bootstrap_manifest.json with 23 modules and 150 functions
    When the manifest-integrity gate runs
    Then the gate should PASS

  Scenario: Missing required fields fails validation
    Given a bootstrap_manifest.json with missing "properties" field
    When the manifest-integrity gate runs
    Then the gate should FAIL with a schema validation error
