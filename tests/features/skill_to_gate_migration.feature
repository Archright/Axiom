@generated @high
Feature: Skill-to-gate migration infrastructure
  As an Axiom engineer
  I want skill policies that have been systematized as gates to be enforced
  So that project policy remains deterministic and version-controlled

  # pending | src/gate/runners/architecture_config_gate.nim | gate | high
  # pending | src/gate/runners/documentation_first_gate.nim | gate | high
  # pending | src/gate/runners/logging_policy_gate.nim | gate | high
    # pending | src/gate/runners/integrity_workflow_gate.nim | gate | high
  # pending | src/verification/orchestrator/healing_orchestrator.nim | verification | high

  Scenario: Architecture config gate reads JSON rules and reports violations
    Given the module "gate/runners/architecture_config_gate" is loaded
    When the gate scans the repository
    Then architecture rule violations are reported deterministically

  Scenario: Documentation-first gate triggers on system-level changes
    Given the module "gate/runners/documentation_first_gate" is loaded
    When a staged diff contains kernel or bootloader keywords
    Then the gate requires documentation evidence

  Scenario: Logging policy gate enforces structured log conventions
    Given the module "gate/runners/logging_policy_gate" is loaded
    When source or test files contain forbidden log patterns
    Then the gate emits a warning or error


  Scenario: Healing orchestrator dispatches recovery stages
    Given the module "verification/orchestrator/healing_orchestrator" is loaded
    When an inference failure occurs
    Then the orchestrator selects a recovery tactic
