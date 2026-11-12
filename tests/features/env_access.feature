Feature: Env Access — centralized environment variable access via EnvVar enum
  As the Axiom integrity engine,
  I want centralized environment variable access through a typed EnvVar enum,
  So that all env lookups are discoverable, auditable, and free from raw string typos.

  Background:
    Given the env access module is initialized

  @spec-density @guard-ring
  Scenario: Module compiles without errors
    Given the module source is available
    When the module is compiled
    Then it compiles without errors
    And all exported procs have proper effect annotations

  @spec-density @guard-ring
  Scenario: All procs have axiomEffect annotations
    Given the env_access module source
    When effect annotations are inspected
    Then all procs should have {.axiomEffect: IoEffect.}
    And setAxiomEnv should propagate OSError
