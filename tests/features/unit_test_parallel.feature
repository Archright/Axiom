@legacy
Feature: Parallel Unit Test Runner with Incremental Build
  As a developer
  I want unit tests to compile and run in parallel with incremental caching
  So that CI feedback is received within 30 seconds and unchanged tests are not wastefully recompiled

  Background:
    Given the unit test directory is "tests/unit"
    And the build output directory is "build/unit-tests"

  Scenario: Parallel orchestrator completes within timeout
    Given multiple unit test files exist in the unit directory
    When the parallel orchestrator is executed
    Then the total wall time should be less than 30 seconds
    And all tests should pass
    And the JSON report should be generated at "build/unit-tests/unit_test_orchestrator_report.json"
    And the report schema version should be "axiom.unitTestOrchestrator.v1"

  Scenario: Incremental build skips unchanged tests
    Given a test was previously compiled successfully
    And the source file has not changed
    And the incremental cache contains a matching SHA-256 entry
    When the orchestrator runs again
    Then the test should not be recompiled
    And the existing binary should be executed directly
    And the cache should remain valid

  Scenario: Modified source triggers recompilation
    Given a test was previously compiled successfully
    And the source file has been modified
    When the orchestrator runs again
    Then the test should be recompiled
    And the incremental cache should be updated with the new SHA-256
