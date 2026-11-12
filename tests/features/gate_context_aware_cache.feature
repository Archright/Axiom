Feature: Context-Aware Gate Cache Key
  As the Gate Memoization Engine,
  I want cache keys that include external state dependencies (git config, env vars),
  So that gates depending on external state are properly invalidated when that state changes.

  Background:
    Given the gate memoization infrastructure is initialized
    And orchestrator_hook_part1.nim provides captureContext and computeEnvHash

  Scenario: captureContext reads git config dependencies
    Given a gate with envDependencies [{kind: "gitConfig", key: "axiom.sync-authorized"}]
    And git config "axiom.sync-authorized" is set to "true"
    When I call captureContext with the gate's envDependencies
    Then the snapshot contains key "axiom.sync-authorized" with value "true"

  Scenario: captureContext reads environment variable dependencies
    Given a gate with envDependencies [{kind: "envVar", key: "AXIOM_JOBS"}]
    And environment variable "AXIOM_JOBS" is set to "4"
    When I call captureContext with the gate's envDependencies
    Then the snapshot contains key "AXIOM_JOBS" with value "4"

  Scenario: computeEnvHash is deterministic for identical snapshots
    Given a snapshot with values {"axiom.sync-authorized": "true"}
    When I call computeEnvHash twice with the same dependencies and snapshot
    Then both calls return the same hash

  Scenario: computeEnvHash produces different hashes for different snapshots
    Given snapshot A with values {"axiom.sync-authorized": "true"}
    And snapshot B with values {"axiom.sync-authorized": "false"}
    When I call computeEnvHash with the same dependencies for both snapshots
    Then the hashes are different

  Scenario: computeEnvHash records missing values as sentinel
    Given a gate with envDependencies [{kind: "gitConfig", key: "nonexistent.key"}]
    And git config "nonexistent.key" is not set
    When I call computeEnvHash with the dependency and snapshot
    Then the hash uses "__AXIOM_MISSING__" for the missing value

  Scenario: computeEnvHash returns empty string for no dependencies
    Given a gate with empty envDependencies
    When I call computeEnvHash with empty dependencies and empty snapshot
    Then the result is an empty string

  Scenario: computeGateCacheKey includes envHash in composite lock hash
    Given a gate with envDependencies [{kind: "gitConfig", key: "axiom.sync-authorized"}]
    And git config "axiom.sync-authorized" is set to "true"
    When I call computeGateCacheKey
    Then the returned cache key includes the envHash contribution

  Scenario: computeGateCacheKey changes when external state changes
    Given a gate with envDependencies [{kind: "gitConfig", key: "axiom.sync-authorized"}]
    And git config "axiom.sync-authorized" is set to "true"
    And I compute cache key A
    When git config "axiom.sync-authorized" is changed to "false"
    And I compute cache key B
    Then cache key A and cache key B are different

  Scenario: sync-protocol-gate uses envDependencies for authorization
    Given the sync-protocol-gate is registered with envDependencies
    When the sync-protocol-gate runs after a successful sync
    Then the cache key reflects the "axiom.sync-authorized" git config value
    And the gate passes because authorization is set
