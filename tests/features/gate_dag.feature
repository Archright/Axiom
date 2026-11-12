Feature: Gate DAG — Dependency-Aware Scheduling for L2 Functional Gates
  As the gate orchestrator,
  the Gate DAG must compute topological layers from gate_manifest.json
  dependency declarations, so that gates execute in correct order with
  parallel execution within each layer.

  Background:
    Given the gate manifest is loaded from "src/gate/gate_manifest.json"
    And each gate may declare an "after" field listing prerequisite gate IDs

  # ── DAG construction ─────────────────────────────────────────────

  Scenario: DAG is built from manifest after-field declarations
    Given a manifest with gates A, B, C where B declares after=["A"]
    When buildGateDag is called
    Then gate B has in-degree 1
    And gate A has in-degree 0
    And gate C has in-degree 0

  # ── Topological layering ─────────────────────────────────────────

  Scenario: Gates with no dependencies are in layer 0
    Given a manifest with gates A, B having no after-field
    When computeLayers is called
    Then layer 0 contains both A and B

  Scenario: Dependent gates are placed in subsequent layers
    Given a manifest where gate C depends on gate A
    When computeLayers is called
    Then gate A is in layer 0
    And gate C is in layer 1 or higher

  Scenario: Transitive dependencies produce correct layer ordering
    Given a manifest where C depends on B and B depends on A
    When computeLayers is called
    Then gate A is in layer 0
    And gate B is in layer 1
    And gate C is in layer 2

  # ── Failure propagation ──────────────────────────────────────────

  Scenario: Failure in layer N skips dependents in layer N+1
    Given a manifest where gate C depends on gate A
    And gate A fails during execution
    When failure propagation is applied
    Then gate C is marked as skipped
    And gate C does not execute

  # ── Cycle detection ──────────────────────────────────────────────

  Scenario: Cycle in dependencies is detected
    Given a manifest where A depends on B and B depends on A
    When buildGateDag is called
    Then a cycle detection error is raised
