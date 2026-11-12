Feature: Deterministic Environment
  As the hermetic build engine
  I need a frozen, reproducible build environment with controlled timestamps and paths
  So that builds are hermetic and produce bit-identical outputs across runs

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: freezeTimestamp produces a fixed SOURCE_DATE_EPOCH
    Given a DeterministicEnv is created with a frozen timestamp
    When I query the SOURCE_DATE_EPOCH value
    Then the epoch matches the timestamp that was frozen
    And the value remains constant across repeated queries

  Scenario: buildDeterministicEnv sets PATH, CC, and LD_LIBRARY_PATH
    Given a DeterministicEnv is built with default configuration
    When I inspect the environment variables
    Then PATH is set and contains only allowed toolchain directories
    And CC is set to the configured C compiler
    And LD_LIBRARY_PATH is set and contains only allowed library paths

  Scenario: envVars returns a sorted list of environment variables
    Given a DeterministicEnv is built with default configuration
    When I call envVars on the environment
    Then the returned list is sorted alphabetically by key
    And the list contains no duplicate keys
