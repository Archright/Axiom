@legacy
@core @sovereignty
Feature: proof_universe.lock caller sovereignty
  The Merkle lock can only be committed by the ax prove core pipeline.
  Unauthorized callers trigger a constitutional violation hard-fail.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And proof_universe_lock module exists at "src/core/proof_universe_lock.nim"

  Scenario: Authorized caller commits the lock successfully
    Given ax prove core executes with caller = AuthorizedLockCaller
    When commitUniverseIntegrityAndLock is invoked
    Then proof_universe.lock is written with a valid merkleRoot
    And the process exits normally

  Scenario: Unauthorized caller is rejected with constitutional violation
    Given an unauthorized module attempts to commit the lock
    When commitUniverseIntegrityAndLock is invoked with caller = "malicious_module"
    Then the process terminates with [CONSTITUTIONAL VIOLATION]
    And proof_universe.lock remains unchanged

  @deprecated
  Scenario: Heal pipeline no longer bakes the lock
    Given ax prove --heal completes successfully
    When the autonomous heal loop finishes a batch
    Then proof_universe.lock timestamp is identical to before heal

  Scenario: Seed graph fallback produces valid Merkle hash
    Given logs/global_symbol_graph.json is missing
    And src/core/assets/seed_symbol_graph.json exists and is valid
    When verifyProofUniverseLock is invoked
    Then the seed is copied to logs/global_symbol_graph.json
    And Merkle verification passes with the seeded graph hash

  Scenario: Merkle root is independent of process-local hash seeds
    Given proof certificates and global_symbol_graph.json are unchanged
    When ax prove writes proof_universe.lock
    And the pre-push hook verifies proof_universe.lock in a separate process
    Then proof_universe.lock merkleRoot is a stable SHA digest
    And Merkle verification passes without rewriting proof_universe.lock
