@legacy
@executable
Feature: Orchestrator Feature Test
  Auto-generated from orchestrator_feature_test.nim

  Scenario: Orchestrator Feature Test
    Given the Axiom system is initialized
    When Orchestrator Feature Test
    Then the result should be valid

  Scenario: Covers: tests/features/orchestrator.feature
    Given the Axiom system is initialized
    When Covers: tests/features/orchestrator.feature
    Then the result should be valid

  Scenario: Tests: SorterPlan construction, leaf-first ordering, stale/blocked detection.
    Given the Axiom system is initialized
    When Tests: SorterPlan construction, leaf-first ordering, stale/b
    Then the result should be valid

  Scenario: check plan.workItems.len >= 2
    Given the Axiom system is initialized
    When check plan.workItems.len >= 2
    Then the result should be valid

  Scenario: check plan.blockedNodes.len == 0
    Given the Axiom system is initialized
    When check plan.blockedNodes.len == 0
    Then the result should be valid

