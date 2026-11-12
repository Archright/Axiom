@legacy
Feature: 4-Layer Verification Pipeline E2E
  The complete verification pipeline exercises BMC (L1),
  CEGAR abstraction refinement (L2), LLM-based auto-formalization (L3),
  and Lean 4 kernel verification (L4) in a single end-to-end pass.

  Rule: CEGAR engine converges on simple loop invariant
    Scenario: Loop with monotonic counter reaches fixed-point
      Given a ControlFlowGraph with a simple increment loop
      When the CEGAR engine runs with maxIterations=20
      Then the engine reaches fixed-point within 20 iterations
      And the proved invariants are non-empty
      And the verdict is cegarProven

  Rule: CEGAR fingerprint is deterministic
    Given the same set of proved invariants
    When computeInvariantFingerprint is called twice
    Then the fingerprints are identical

  Rule: Leanstral fails honestly when no backend configured
    Given no LLM backend is configured (no API URL or key)
    When callLeanstral is invoked
    Then the result contains "FATAL: No LLM backend available"
    And success is false
    And theoremSource is empty

  Rule: LLM backend auto-detection works
    Given AXIOM_LLM_API_URL and AXIOM_LLM_API_KEY are set
    When resolveDefaultBackend is called
    Then a backend is returned (not none)

  Rule: Tactic catalog validates verified primitives
    Given a tactic "intros" from the verified catalog
    When isVerifiedTactic is called
    Then it returns true
    Given a tactic "nonexistent_tactic"
    When isVerifiedTactic is called
    Then it returns false
