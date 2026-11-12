Feature: Gate Types — Core Domain Types for the Gate Layer
  As the gate infrastructure,
  the gate_types module must define the type hierarchy that forms
  the contract between L0 orchestrator and all gate runners,
  ensuring deterministic behavior via value types.

  Background:
    Given the gate_types module is imported by gate runners

  # ── GateStage enum ───────────────────────────────────────────────

  Scenario: GateStage covers all execution stages
    Given the GateStage enum
    Then it contains gsPreCommit, gsPrePush, gsManual, and gsCI

  # ── GateLayer enum ───────────────────────────────────────────────

  Scenario: GateLayer distinguishes Meta and Functional layers
    Given the GateLayer enum
    Then glMeta represents L1 infrastructure verification
    And glFunctional represents L2 functional gates

  # ── GateWeight enum ──────────────────────────────────────────────

  Scenario: GateWeight classifies resource cost
    Given the GateWeight enum
    Then gates can be classified as light, medium, or heavy

  # ── GateConfig completeness ──────────────────────────────────────

  Scenario: GateConfig contains all required fields
    Given a GateConfig for a gate runner
    Then it has an entry point (binary path)
    And it has a stage (pre-commit, pre-push, manual, or CI)
    And it has a layer (Meta or Functional)
    And it has a weight for concurrency scheduling

  # ── GateResult structure ─────────────────────────────────────────

  Scenario: GateResult captures execution outcome
    Given a gate has finished executing
    When a GateResult is constructed
    Then it contains the exit code
    And it contains the execution duration
    And it contains the gate ID

  # ── Value type guarantee ─────────────────────────────────────────

  Scenario: All gate types are value types
    Given any GateStage, GateLayer, or GateWeight value
    When assigned to a new variable
    Then the original and copy are independent (no shared heap)
