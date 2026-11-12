Feature: Gate Contract — Type Definitions for the Gate Layer
  As the gate infrastructure,
  the gate_contract module must define the type hierarchy that forms
  the single source of truth for gate types,
  decoupled from utility functions.

  Background:
    Given the gate_contract module is the READ-ONLY API boundary

  # ── Type exports ─────────────────────────────────────────────────

  Scenario: gate_contract exports all gate types
    Given the gate_contract module
    Then it exports GateStage, GateLayer, GateWeight, GateRunMode, GateSeverity
    And it exports GateResult, GateError, GateConfig, GateRunner
    And it exports GateErrorCode, DependencyKind, EnvDependency, EnvContextSnapshot, EnvError
    And it exports GateOutcome as Result[GateResult, GateError]

  # ── Re-exports from core ─────────────────────────────────────────

  Scenario: gate_contract re-exports core types
    Given the gate_contract module
    Then it re-exports FailureCategory, FailCacheTtlSec, cacheTtl from core/gate_types
    And it re-exports GateHermeticity, ghHermetic, ghTransient from core/gate_types

  # ── Value type guarantee ─────────────────────────────────────────

  Scenario: All contract types are value types
    Given any type exported by gate_contract
    When assigned to a new variable
    Then the original and copy are independent (no shared heap)

  # ── Forwarding compatibility ─────────────────────────────────────

  Scenario: gate_types.nim re-exports gate_contract
    Given consumers importing gate/gate_types
    Then all symbols from gate_contract are available
    And no behavioral change from the refactoring
