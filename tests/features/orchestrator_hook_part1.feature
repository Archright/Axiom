Feature: Orchestrator Hook Part 1 — gate dispatch with CAS direct execution
  As the Gate Orchestrator,
  I want to resolve gate binaries from CAS by absolute path,
  So that gates execute without symlinks or PATH dependencies.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: CAS hit uses absolute path directly
    Given a gate "test-gate" with a cached binary in CAS
    When I run the gate via orchestrator
    Then the gate executes using the CAS absolute path
    And no symlink is created

  Scenario: CAS miss triggers JIT compile then direct execution
    Given a gate "test-gate" with no cached binary
    When I run the gate via orchestrator
    Then the binary is compiled from source
    And the compiled binary is stored in CAS
    And the gate executes using the CAS absolute path

  Scenario: SessionJournal records gate results at every exit point
    Given a SessionJournal is created for the current orchestrator session
    When pollL2GatesWithTimeout detects a gate completing with exit code 0
    Then the journal records grsSuccess with actual elapsedMs
    When pollL2GatesWithTimeout detects a gate completing with non-zero exit code
    Then the journal records grsFailed with failCategory and failReason
    When pollL2GatesWithTimeout detects a gate timeout
    Then the journal records grsTimeout with fcPermanent category

  @spec-density
  Scenario: GlobalMaxTokens default budget is 12
    Given the orchestrator_hook_part1 module is loaded
    When no AXIOM_GLOBAL_MAX_TOKENS compile-time override is set
    Then GlobalMaxTokens defaults to 12
    And this budget governs maximum concurrent gate token allocation
