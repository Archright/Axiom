Feature: Metrics — compile-time and runtime metric collection
  As the Axiom integrity engine,
  I want lightweight metric counters for gate passes, failures, and durations,
  So that pipeline performance can be observed without affecting determinism.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: incrementing a counter records the value
    Given a metric counter "gate_passes" at zero
    When I increment "gate_passes" by 3
    Then the value of "gate_passes" is 3

  Scenario: metrics are reset on initialization
    Given a metric counter "gate_failures" previously set to 5
    When I reinitialize the metrics store
    Then the value of "gate_failures" is 0
