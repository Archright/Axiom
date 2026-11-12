@legacy
Feature: Integrity Guard Injection (Wave 4)
  As a verification engineer
  I want verified Axiom-IR contracts to be physically injected into source code
  So that "no proof, no execution" is enforced at the source level

  Background:
    Given the NimFrontend and Weaver are loaded
    And a verified AxiomIrNode for function "add"

  # ---------------------------------------------------------------------------
  # Weaver Core
  # ---------------------------------------------------------------------------

  Scenario: Weaver injects pre-condition doAssert at function entry
    Given Nim source:
      """
      proc add(x, y: int): int =
        return x + y
      """
    And the IR has pre-condition "x >= 0" with scope invPre
    When I weave guards into the source
    Then the result contains "doAssert x >= 0"
    And the result contains "# AxiomGuard:" marker
    And the result contains "# EndAxiomGuard"

  Scenario: Weaver injects effect pragma before proc header
    Given Nim source:
      """
      proc add(x, y: int): int =
        return x + y
      """
    And the IR has effect constraint effNoSideEffect with severity 1
    When I weave guards into the source
    Then the result contains "{.noSideEffect.}"
    And the result contains "# AxiomGuard:" before the proc declaration

  Scenario: Weaver is idempotent — strips old guards before re-injecting
    Given Nim source already contains an AxiomGuard marker for old predicate "x > 0"
    And the IR now has pre-condition "x >= 0" with scope invPre
    When I weave guards into the source
    Then the result contains "doAssert x >= 0"
    And the result does NOT contain "doAssert x > 0"
    And the source contains exactly one "# AxiomGuard:" marker block

  Scenario: Weaver preserves indentation
    Given Nim source:
      """
      proc add(x, y: int): int =
        return x + y
      """
    And the IR has pre-condition "x >= 0" with scope invPre
    When I weave guards into the source
    Then the injected "doAssert" line has the same indentation as the first body line

  # ---------------------------------------------------------------------------
  # PseudocodeFrontend Guard Injection
  # ---------------------------------------------------------------------------

  Scenario: PseudocodeFrontend generates check statements
    Given pseudocode source:
      """
      function add(x, y)
        return x + y
      """
    And the IR has pre-condition "x >= 0" with scope invPre
    When I inject guards via PseudocodeFrontend with the source code
    Then the result contains "check x >= 0"

  # ---------------------------------------------------------------------------
  # Integrity Guard Orchestrator
  # ---------------------------------------------------------------------------

  Scenario: IntegrityGuard only injects after proof success
    Given a verified AxiomIrNode for function "safeAdd"
    And Nim source at path "tests/fixtures/safe_add.nim"
    When I call applyGuardToSource with the verified IR
    Then the file is written with AxiomGuard markers
    And a backup file "tests/fixtures/safe_add.nim.bak" exists

  Scenario: IntegrityGuard does not modify source on failure
    Given an invalid module path ""
    When I call applyGuardToSource
    Then the result is false
    And no file is written

  Scenario: IntegrityGuard reports guarded status
    Given Nim source at path "tests/fixtures/safe_add.nim" containing AxiomGuard markers
    When I call isSourceGuarded on the path
    Then the result is true

  # ---------------------------------------------------------------------------
  # Heal Integration
  # ---------------------------------------------------------------------------

  Scenario: Heal injects guards on Leanstral proof success
    Given a failing node with Nim source context
    When Leanstral synthesis succeeds and compiler verifies the proof
    Then the heal log contains "[Wave 4] Integrity guards injected into source"

  Scenario: Heal skips injection on proof failure
    Given a failing node with Nim source context
    When Leanstral synthesis fails compiler verification
    Then the heal log does NOT contain "[Wave 4] Integrity guards injected"
    And the original Nim source is NOT modified
