@legacy
Feature: Heal-on-Prove Convergence — Eliminate Heal-on-Push Side-Effect

  As an Axiom architect
  I want ax prove to absorb the final incremental heal before baking the Merkle lock
  So that push never leaves stale lock residue and the pre-push hook remains side-effect free

  Background:
    Given the Axiom engine is initialized
    And proof_universe.lock exists and is tracked by Git

  Scenario: pre-push hook performs zero writes
    Given proof assets differ from the stored Merkle lock
    When the pre-push hook executes
    Then it must reject the push without modifying proof_universe.lock
    And it must report "Run 'ax prove' to regenerate proof_universe.lock"

  Scenario: ax prove converges with inline heal before lock freeze
    Given ax prove reaches the final convergence phase
    When the inline incremental heal executes before Merkle lock baking
    Then the lock must be generated against the post-heal disk state
    And subsequent pre-push verification must pass without modification

  @deprecated
  Scenario: Heal-on-Push is permanently removed
    Given the pre-push hook source is inspected
    Then no invocation of "ax prove --heal" must exist
    And the hook must quit immediately after gate verification

  Scenario: Post-heal proof-state converges to certificate SSOT
    Given ax prove executes inline heal on at least one node
    When the post-heal final convergence phase executes
    Then logs/ax_proof_state.json must reflect the converged disk certificate state
    And certificateConvergence metadata must report checkedCertificates equal to matchedCertificates
    And no mismatch between proof-state status and certificate status must remain
