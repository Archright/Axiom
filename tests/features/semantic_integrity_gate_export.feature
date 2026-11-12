@manual
@gate
Feature: Semantic integrity gate symbol export
  runSemanticIntegrityGate must be reachable from stage_05_lean_bridge
  through the gate_rule_adapter so that binary-freshness-gate rebuilds
  of bin/main compile without undefined-symbol errors.

  Scenario: runSemanticIntegrityGate is exported via gate_rule_adapter
    Given stage_05_lean_bridge imports gate_rule_adapter
    When binary-freshness-gate rebuilds bin/main
    Then the compilation succeeds with no undefined-symbol errors
    And runSemanticIntegrityGate is reachable through gate_rule_adapter

  Scenario: Wrapper in gate_evaluators delegates to runSemanticIntegrityGate
    Given gate_evaluators.nim wraps runSemanticIntegrityGate
    When gate_rule_adapter re-exports the wrapper
    Then the symbol is visible to verification layer modules
