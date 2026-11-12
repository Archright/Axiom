@gate @registry
Feature: Gate Registry Build-Time Discovery
  The gate registry is constructed at compile time from a declarative manifest
  and a discovered set of runner files, without injecting metadata into runner
  sources.

  Scenario: Registry loads gates from manifest
    Given "src/gate/gate_manifest.json" exists
    When I run "nim c -r tests/gateway/gate_registry_discovery_test.nim"
    Then the exit code should be 0
    And the output should contain "gate count equals manifest entry count"

  Scenario: Manifest schema is valid
    Given "src/gate/gate_manifest.schema.json" exists
    When I run "nim c -r tests/gateway/gate_manifest_schema_test.nim"
    Then the exit code should be 0
    And the output should contain "every gate has required fields"

  Scenario: Runner files and manifest stay consistent
    Given "src/gate/runners/manifest_consistency_gate.nim" exists
    When I run "src/gate/runners/manifest_consistency_gate"
    Then the exit code should be 0
    And the output should contain "PASS"

  Scenario: Registry is deterministic
    Given "src/gate/gate_registry.nim" exists
    When I run "nim c -r tests/gateway/gate_registry_discovery_test.nim"
    Then the exit code should be 0
    And the output should contain "gates are sorted by id ascending"
