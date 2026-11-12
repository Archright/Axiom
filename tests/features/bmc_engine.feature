@legacy
@executable
Feature: BMC Race Condition Engine
  As an Axiom verification engineer
  I want the BMC engine to correctly detect race conditions in two-thread interleavings
  So that verified programs are provably free of data races

  Background:
    Given the Axiom engine is initialized
    And the BMC step bound is 10

  Scenario: Subtract rule with underflow protection
    Given a TransitionRule with op=transitionSub and delta=5
    When applyRule is called with readVal=3
    Then the result must be 3 (clamped, not negative)

  Scenario: Subtract rule normal case
    Given a TransitionRule with op=transitionSub and delta=3
    When applyRule is called with readVal=10
    Then the result must be 7

  Scenario: Add rule
    Given a TransitionRule with op=transitionAdd and delta=4
    When applyRule is called with readVal=6
    Then the result must be 10

  Scenario: Sequential execution order T1-first
    Given initialX=10, firstThread=ownerT1, delta=3
    When runSequentialWithDelta is called
    Then the result must be 4 (10-3-3)

  Scenario: Sequential execution order T2-first produces same result for commutative subtract
    Given initialX=10, firstThread=ownerT2, delta=3
    When runSequentialWithDelta is called
    Then the result must be 4 (10-3-3)

  Scenario: ownerNone returns initial value unchanged
    Given initialX=42, firstThread=ownerNone, rule=any
    When runSequentialByRule is called
    Then the result must be 42

  Scenario: Race condition detected for non-commutative operations
    Given an initial state where thread ordering changes the outcome
    When verifyRaceCondition is called
    Then raceDetected must be true
    And the witness trace must be non-empty

  Scenario: No race condition for commutative operations
    Given initialX=10, delta=3 with subtract rule
    When verifyRaceCondition is called
    Then raceDetected must be false
    And sequentialUniqueCount must be 1

  Scenario: verifyRaceConditionWithDelta delegates correctly
    Given stateValue=10, inputDelta=3
    When verifyRaceConditionWithDelta is called
    Then the result must match verifyRaceCondition with makeSubtractRule(3)
