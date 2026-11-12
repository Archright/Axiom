Feature: Task Schema
  Centralized task domain types for the Control Engine with schema-as-Code
  types, compile-time validation, and JSON serialization.

  Background:
    Given the task schema module is available

  Scenario: TaskId construction and equality
    Given a TaskId created from string "task-001"
    Then the TaskId should equal "task-001"
    And the TaskId should not be empty

  Scenario: TaskId empty check
    Given a TaskId created from string ""
    Then the TaskId should be empty

  Scenario: TaskId ordering
    Given TaskIds "alpha" and "beta"
    Then "alpha" should be less than "beta"

  Scenario: TaskSpec default construction
    When I create a TaskSpec with id "t1" and title "Test Task"
    Then the TaskSpec state should be tsPending
    And the TaskSpec deps should be empty
    And the TaskSpec resourceClass should be rcDefault
    And the TaskSpec costWeight should be 1.0

  Scenario: TaskSpec JSON round-trip
    Given a valid TaskSpec with id "t1" and title "Test"
    When I serialize the TaskSpec to JSON
    And I deserialize the JSON back to a TaskSpec
    Then the round-tripped TaskSpec should match the original

  Scenario: TaskSpec validation passes for valid spec
    Given a valid TaskSpec with id "t1" and title "Test"
    When I validate the TaskSpec
    Then the validation should produce no errors

  Scenario: TaskSpec validation fails for empty id
    Given a TaskSpec with empty id and title "Test"
    When I validate the TaskSpec
    Then the validation should report "TaskSpec.id must not be empty"

  Scenario: TaskSpec validation fails for empty title
    Given a TaskSpec with id "t1" and empty title
    When I validate the TaskSpec
    Then the validation should report "TaskSpec.title must not be empty"

  Scenario: TaskSpec validation fails for self-dependency
    Given a TaskSpec with id "t1" and title "Test"
    And the TaskSpec depends on itself
    When I validate the TaskSpec
    Then the validation should report self-dependency error

  Scenario: DagConfig default values
    When I create a default DagConfig
    Then the maxConcurrency should be 4
    And the globalTimeoutMinutes should be 30

  Scenario: ShadowTolerance default values
    When I create a default ShadowTolerance
    Then the maxDiffPercent should be 5.0
    And autoPromote should be false
    And retryBudget should be 3
    And promotionThreshold should be 0.95

  Scenario: TaskState serialization round-trip
    Given a TaskState tsRunning
    When I serialize the TaskState to JSON
    Then the JSON string should be "running"

  Scenario: TaskState deserialization from invalid string
    When I deserialize "invalid_state" to TaskState
    Then the result should be an error

  Scenario: ResourceClass serialization round-trip
    Given a ResourceClass rcPrivileged
    When I serialize the ResourceClass to JSON
    Then the JSON string should be "privileged"
