Feature: Verification Orchestration
  As the Axiom integrity engine
  I want orchestrated verification workflows
  So that self-healing, proof refinement, and full cycles run correctly

  Scenario: All orchestration procs have effect annotations
    Given the verification_orchestration module
    When effect annotations are inspected
    Then all procs should have {.axiomEffect: IoEffect.}

  Scenario: Self-healing workflow executes
    Given a verification failure
    When runSelfHealing is invoked
    Then it should attempt recovery with proper error handling

  Scenario: Full verification cycle completes
    Given a source code change
    When runFullVerificationCycle is invoked
    Then it should run all verification steps in sequence
