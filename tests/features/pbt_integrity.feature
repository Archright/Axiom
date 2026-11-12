Feature: PBT Integrity Verification
  As a developer using Axiom
  I want property-based tests to verify core invariants
  So that AI-generated logic maintains mathematical integrity

  @basic
  Scenario: Generated DAGs are always acyclic
    Given a PBT engine with seed-based deterministic generation
    When 200 DAGs are generated with up to 20 nodes
    Then every generated DAG must have hasCycle == false
    And the adjacency table must be consistent with edges

  @basic
  Scenario: TopologyLock JSON roundtrip preserves all fields
    Given a TopologyLock generator producing valid lock structures
    When a lock is serialized via renderLockJson and parsed back
    Then schema, lock_revision, modules, shards, and transitional_modules must match

  @basic
  Scenario: Gate idempotency holds for valid inputs
    Given a gate config mutation generator
    When mutations are applied to a base config
    Then the result must remain structurally valid

  @basic
  Scenario: Shrink convergence finds minimal counter-example within timeout
    Given a property that always fails for values >= 50
    When checkProperty runs with maxShrinkSteps=50
    Then the counter-example must be found
    And the shrink must complete within the timeout

  @basic
  Scenario: BitStream withSnapshot restores cursor on exception
    Given a BitStream with cursor at position 10
    When a generator throws mid-consumption inside withSnapshot
    Then the cursor must be restored to position 10

  @stress
  Scenario: TopologyLock roundtrip under 1000-iteration stress
    Given a TopologyLock generator
    When 1000 locks are roundtripped through renderLockJson + parseTopologyLockJson
    Then all 1000 must preserve schema, revision, and module counts
