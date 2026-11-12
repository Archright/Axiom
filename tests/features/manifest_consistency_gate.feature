Feature: Manifest Consistency Gate — Gate Registry Integrity
  As the Axiom gate hook architecture
  I want to validate that gate_manifest.json stays in sync with runner files
  So that every gate runner has a manifest entry and every manifest entry has a runner

  Background:
    Given the Manifest Consistency Gate module is available
    And the manifest file exists at src/gate/gate_manifest.json

  Scenario: Manifest JSON is valid and parseable
    Given the manifest file at src/gate/gate_manifest.json
    When the manifest is parsed
    Then parsing succeeds without errors
    And the manifest contains a top-level "gates" array

  Scenario: Schema JSON is valid and parseable
    Given the schema file at src/gate/gate_manifest.schema.json
    When the schema is parsed
    Then parsing succeeds without errors

  Scenario: Each gate entry has all required fields
    Given a gate entry with id, name, layer, entry, stages, and weight
    When validateGateEntry is called on the entry
    Then no missing field errors are reported

  Scenario: Gate entry with invalid layer is rejected
    Given a gate entry with layer set to "invalid_layer"
    When validateGateEntry is called on the entry
    Then an error is reported for invalid layer

  Scenario: Gate entry with invalid weight is rejected
    Given a gate entry with weight set to "invalid_weight"
    When validateGateEntry is called on the entry
    Then an error is reported for invalid weight

  Scenario: Gate entry with invalid stage is rejected
    Given a gate entry with stages array containing "invalid_stage"
    When validateGateEntry is called on the entry
    Then an error is reported for invalid stage

  Scenario: Duplicate gate ids are detected
    Given a manifest with two gates sharing the same id
    When manifest consistency is checked
    Then a duplicate id error is reported

  Scenario: Unsorted gate ids are detected
    Given a manifest where gates are not sorted by id ascending
    When manifest consistency is checked
    Then a sort order error is reported

  Scenario: Missing runner file for src/gate/runners/ entry is detected
    Given a manifest entry pointing to src/gate/runners/nonexistent_gate
    When manifest consistency is checked
    Then a missing runner file error is reported

  Scenario: Gate runner without manifest entry is detected
    Given a .nim file in src/gate/runners/ with gate signals
    And no manifest entry covers the runner file
    When manifest consistency is checked
    Then a missing manifest entry error is reported

  Scenario: Utility modules are excluded from manifest requirement
    Given a .nim file in src/gate/runners/ listed as a utility module
    When manifest consistency is checked
    Then no missing manifest entry error is reported for the utility module

  Scenario: All manifest ids are unique across the full gate list
    Given the full manifest at src/gate/gate_manifest.json
    When all gate ids are collected
    Then every id appears exactly once
