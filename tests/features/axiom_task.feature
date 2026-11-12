Feature: Axiom Task — lightweight task abstraction for async pipeline work
  As the Axiom runtime,
  I want a task type that represents a unit of pipeline work,
  So that tasks can be scheduled, tracked, and completed deterministically.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: task transitions from pending to completed
    Given a task in "pending" state
    When the task is executed successfully
    Then the task state transitions to "completed"

  Scenario: task captures failure state on error
    Given a task in "pending" state
    When the task execution raises an error
    Then the task state transitions to "failed" with an error message
