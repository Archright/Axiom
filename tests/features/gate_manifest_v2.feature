Feature: GateManifest v2 with InputSpec/OutputSpec
  As the Hermetic Build Engine
  I want a manifest schema that captures declared inputs and outputs per gate
  So that the orchestrator can validate completeness and detect output collisions

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: validateManifest catches missing outputs
    Given a GateManifest v2 with a gate declaring expected outputs
    And the actual gate result omits one of the declared outputs
    When validateManifest is called
    Then the validation fails with a missing output error
    And the error references the omitted output name

  Scenario: findOutputCollisions detects overlapping outputs
    Given a GateManifest v2 with two gates that each declare outputs
    And both gates declare an output targeting the same path
    When findOutputCollisions is called
    Then a collision is reported for the overlapping output path
    And the collision entry lists both gate identifiers

  Scenario: GateManifest round-trips through JSON
    Given a fully populated GateManifest v2 with inputs and outputs
    When the manifest is serialized to JSON
    And the JSON is deserialized back to a GateManifest v2
    Then the deserialized manifest is equal to the original
    And all InputSpec and OutputSpec fields are preserved
