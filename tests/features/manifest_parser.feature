Feature: Manifest Parser — SSOT for gate manifest JSON parsing
  As the Gate Infrastructure,
  I want a single parser module for gate manifest JSON files,
  So that parsing logic is DRY across compile-time and runtime consumers.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: parse valid gate JSON with all required fields
    Given a JSON object with id, name, layer, entry, stages, passFilenames, weight
    When I call parseGateConfig
    Then the result is a valid GateConfig
    And all fields match the input values

  Scenario: reject gate JSON missing required field
    Given a JSON object missing the "weight" field
    When I call parseGateConfig
    Then a compile-time doAssert or runtime ValueError is raised

  Scenario: validate manifest with unique gate IDs
    Given a sequence of GateConfig objects with unique IDs
    When I call validateGateManifest
    Then no error is raised

  Scenario: reject manifest with duplicate gate IDs
    Given a sequence of GateConfig objects with duplicate IDs
    When I call validateGateManifest
    Then a compile-time doAssert or runtime ValueError is raised
