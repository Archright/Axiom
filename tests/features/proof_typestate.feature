Feature: Proof Typestate FSM
  As an Axiom operator
  I want proof states to be enforced via typestate pattern
  So that invalid state transitions are caught at compile time

  Scenario: Initial proof starts in Unattempted state
    Given a new proof entry with no prior attempts
    When the proof state is queried
    Then the state is Unattempted

  Scenario: Valid transition from Unattempted to InProgress
    Given a proof in Unattempted state
    When markInProgress is called
    Then the state transitions to InProgress

  Scenario: Counter-example blocks further verification
    Given a proof in InProgress state
    When markCounterEx is called
    Then the state transitions to CounterEx
    And further markVerified calls are rejected
