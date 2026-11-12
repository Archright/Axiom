Feature: Axiom v1 Productization Readiness Decision
  As the productization gatekeeper
  I need a pure-function verdict over 8 readiness invariants (R1–R8)
  So that "go / conditional-go / no-go" is decided mechanically, never by a human.

  Background:
    Given the readiness policy is loaded from config/readiness_policy.json
    And the invariant criticalities are R1–R6,R8 = critical and R7 = non-critical

  Scenario: All invariants PASS -> GO
    Given every invariant state is PASS
    When the verdict algebra is evaluated
    Then the verdict is "GO"
    And the conditions list is empty

  Scenario: A non-critical invariant FAILs while all critical PASS -> CONDITIONAL GO
    Given R7 state is FAIL
    And all other invariants are PASS
    When the verdict algebra is evaluated
    Then the verdict is "CONDITIONAL GO"
    And the conditions list contains "R7=FAIL"

  Scenario: Any critical FAIL or UNKNOWN -> NO-GO
    Given R2 state is FAIL
    And all other invariants are PASS
    When the verdict algebra is evaluated
    Then the verdict is "NO-GO"
    And the conditions list is empty

  Scenario: Permutation invariance of the verdict
    Given a fixed 8-tuple of invariant states
    When the verdict is computed on 40 random permutations of the tuple
    Then every permutation yields the identical verdict and conditions list

  Scenario: R7 promotion — over-scope verified emitter promotes R1 and R2 to FAIL
    Given R7 verifiedEmitterScope contains a token not in claimedScope
    When the R7 promotion rule fires
    Then R1 becomes FAIL
    And R2 becomes FAIL
    And the verdict is "NO-GO"

  Scenario: Low VKD is a non-critical R7 FAIL, not a NO-GO by itself
    Given R7 measuredCoverage is 0.1, below the 0.5 vkdMinThreshold
    And verifiedEmitterScope is a subset of claimedScope
    When the R7 rule is evaluated
    Then R7 state is FAIL
    And the verdict is "CONDITIONAL GO"

  Scenario: Contradictory evidence for the same (key, scope, subject) resolves to UNKNOWN
    Given two observations with the same key, scope and subject but conflicting bool values
    When the contradiction rule is applied
    Then the owning invariant state is UNKNOWN
    And the verdict is "NO-GO" (fail-closed)

  Scenario: Evidence with different scope is not a contradiction
    Given two observations with the same key and subject but different scope
    When the contradiction rule is applied
    Then the owning invariant state is not UNKNOWN
    And the states are computed normally

  Scenario: Malformed envelope, stale freshness, or missing invariant -> UNKNOWN
    Given an envelope missing invocationId, or with wrong-typed observations, or no sources
    When validateEvidence is applied
    Then the invariant state is UNKNOWN
    And the verdict is "NO-GO"
    Given an envelope whose freshUntil is before evaluationTime
    When validateEvidence is applied
    Then the evidence is invalid and the invariant state is UNKNOWN