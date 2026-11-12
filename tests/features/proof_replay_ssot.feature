@legacy
Feature: Proof Replay SSOT — Centralized Proof-Replay Data Structure
  Eliminates scattered proof-replay fields across LeanSpecInference by
  enforcing single source of truth via src/core/workflow_state.nim.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And workflow_state module exists at "src/core/workflow_state.nim"

  Scenario: LeanSpecInference contains proofReplay field
    Given pipeline_core_types.nim imports workflow_state
    When LeanSpecInference is defined
    Then it has a single "proofReplay" field of type ProofReplayResult
    And it does not have top-level proofReplayTactics, proofReplayVerified,
        leanKernelVerified, strictSpecWarnings, or soundnessNote fields

  Scenario: JSON serialization exposes proofReplay under consistent keys
    Given a UniversalPipelineResult is produced
    When jsonFromUniversalPipelineResult is called
    Then "inferredSpec" contains "proofReplay" with tactics, method, verified,
         leanKernelVerified, minimalProofPath, soundnessNote, strictSpecWarnings
    And "proofReplay" top-level key contains the same data for backward compat

  Scenario: ax report reads proof-replay data through ProofReplayResult
    Given a certificate with proof replay data exists
    When "ax report" generates output
    Then proof replay tactics are read from ProofReplayResult.tactics
    And leanKernelVerified is read from ProofReplayResult.leanKernelVerified
    And strictSpecWarnings are read from ProofReplayResult.strictSpecWarnings

  Scenario: ASI is deterministic based on verdict
    Given a pipeline run produces a verification verdict
    When computeAsiFixed4 is called with finalScan and verdict
    Then verdict "verified" or "proven_by_induction" returns "1.0000"
    And other verdicts fall back to scan-based calculation

  Scenario: Ghost Update PoC matches test specification
    Given a ghost_update vulnerability hit exists
    When buildGhostUpdateNimPoc is called
    Then the snippet contains "proc reproduceGhostUpdate*()"
    And the snippet contains "doAssert committed.version >= newest.version"
    And the snippet defines "newest", "stale", and "committed" RecordState values

  Scenario: Guard detection recognizes notin and in operators
    Given a source snippet with "x notin seq" or "x in seq" guards
    When runNegativeInvariantSearch scans the source
    Then hasNullGuard and hasAmountGuard return true for "in" and "notin" patterns

  Scenario: Lean fallback hint synthesis detects Unicode >=
    Given Lean compiler output contains "≥" or ">=" symbols
    When synthesizeLeanFallbackHints processes the output
    Then the generated hints include balance >= 0 or amount <= balance assertions

  Scenario: Unified fingerprint uses SHA-256 via refinement_base
    Given computeUnifiedProofFingerprints is called
    When the unified fingerprint is serialized
    Then it matches refinement_base.computeSourceFingerprint output
    And it differs from vault_manager.computeSourceFingerprint hash output
