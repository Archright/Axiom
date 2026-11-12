Feature: Action Cache — disk-backed cache keyed by ActionKey
  As the Hermetic Build Engine,
  I want a disk-backed action cache stored at .axiom/cache/actions/,
  So that build artifacts survive restarts and are shared across runs.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: store and lookup round-trip
    Given an ActionKey "abc123" and output artifact at "out/main"
    When I call store with key "abc123" and artifact "out/main"
    And I call lookup for key "abc123"
    Then the lookup returns a cache hit
    And the artifact path matches "out/main"

  Scenario: lookup returns None for a missing key
    Given no cache entry for key "missing-key"
    When I call lookup for key "missing-key"
    Then the lookup returns None

  Scenario: invalidate removes a cache entry
    Given a cached entry for key "invalidate-me"
    When I call invalidate for key "invalidate-me"
    And I call lookup for key "invalidate-me"
    Then the lookup returns None

  Scenario: verifyOutputs checks that all output files exist on disk
    Given a cached entry with outputs ["out/a.nim", "out/b.nim"]
    When I call verifyOutputs for the cache entry
    Then verification succeeds and returns true
    Given the file "out/a.nim" is deleted
    When I call verifyOutputs for the cache entry
    Then verification fails and returns false
  # Guard Ring integration: exception hygiene + env_access centralized

  Scenario: axiom cache --status shows cache hit rate
    Given the gate memo cache has entries from previous runs
    When I run "axiom cache --status"
    Then the output contains "Cache Hit Rate"
    And the output contains "Total Entries"

  Scenario: axiom cache --clear --force purges all cache
    Given the gate memo cache has entries
    When I run "axiom cache --clear --force"
    Then the cache directory is empty
    And the exit code is 0

  Scenario: shadow worker runs heavy gates in background
    Given a gate with weight "heavy" is queued for pre-commit
    When the shadow worker starts
    Then the shadow lock file is created
    And the heavy gate runs without blocking the pre-commit path

  Scenario: DAG artifact subscription invalidates dependent gates
    Given gate "producer-gate" produces artifact "data/output.json"
    And gate "consumer-gate" subscribes to artifact "data/output.json"
    When "producer-gate" completes successfully
    Then "consumer-gate" is invalidated and re-queued
    And the artifact tracker logs the invalidation
