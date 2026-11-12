@executable
Feature: State-Aware Proof Universe Lock Gate
  As an Axiom engineer
  I want the pre-push proof gate to make bounded, checkpointed progress
  So that git push is not blocked by a full proof-universe timeout

  Background:
    Given the Axiom repository root is initialized
    And the proof-universe lock gate binary is built

  Scenario: Stale lock triggers chunked proof regeneration
    Given "proof_universe.lock" is older than the newest certificate
    When "proof-universe-lock-gate" runs
    Then it executes at most one 110-second chunk
    And it updates "proof_universe.lock" with checkpoint metadata
    And the gate exits with status PASS

  Scenario: Chunk timeout with no progress is non-blocking
    Given "proof_universe.lock" is older than the newest certificate
    And an "ax prove" chunk times out without new certificates
    When "proof-universe-lock-gate" processes the chunk
    Then the gate exits with status PASS and a warning
    And the checkpoint in "proof_universe.lock" is not advanced

  Scenario: Transitive dependency change invalidates cached certificate
    Given a verified certificate exists for a function
    And one of its transitive dependencies changed since the certificate was written
    When certificate hydration runs
    Then the certificate is not hydrated
    And the function is scheduled for re-verification
