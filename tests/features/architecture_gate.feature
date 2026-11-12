@legacy
Feature: Architecture Integrity Gate
  Pre-commit detection of DRY, SSOT, SoC, SOLID, Circular, and Completeness violations.

  Scenario: Duplicate axiomPrelude is flagged
  Scenario: ASI calculation outside metrics.nim is flagged
  Scenario: Circular dependency is detected
  Scenario: Complex function without @axiom-hint is flagged
  Scenario: SOLID SRP threshold is 15 functions
  Scenario: Completeness comma threshold is 5
  Scenario: String constant duplicate ignores same-file matches
  Scenario: Circular dependency is detected with path resolution

  Scenario: wf_planning delegates SMT assertion building to smt_hints
  Scenario: Lean default variable declaration is shared constant
  Scenario: Healing hint strings use SSOT constants from lean_diagnostic
  Scenario: Bridge operators prevent invalidField on NimSeq
  Scenario: Two-Pass pipeline processes intrinsic nodes first

  # Zero Tolerance 4D Upgrade (2026-05-24)
  Scenario: Debt baseline file does not exist
    Given the repository is clean
    Then "src/gate/architecture_debt_baseline.toml" should not exist

  Scenario: All hardcoded exceptions are in policy lock
    Given "src/gate/architecture_policy.lock" exists
    Then it should contain "[forbidden_call_policies]"
    And it should contain "[forbidden_pragmas]"
    And it should contain "[external_packages]"
    And it should contain "[layer_limits]"
    And it should contain "boilerplate_node_count_threshold"

  Scenario: Layer-specific limits are explicit
    Given "src/gate/architecture_policy.lock" exists
    Then it should contain "core = { maxImports = 30, maxExportedFunctions = 30 }"
    And it should contain "gate = { maxImports = 30, maxExportedFunctions = 20 }"
    And it should contain "verification = { maxImports = 30, maxExportedFunctions = 20 }"

  Scenario: Architecture gate passes with zero violations
    When I run "bin/architecture_gate"
    Then the exit code should be 0
    And the output should contain "PASSED"
    And the output should contain "no violations"

  Scenario: Nimtry passes with zero violations
    When I run "bin/nimtry"
    Then the exit code should be 0
    And the output should contain "PASSED"
    And the output should contain "no violations"
