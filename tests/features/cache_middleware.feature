Feature: CEGAR Pipeline Cache Middleware
  As an Axiom operator running batch verification
  I want a content-addressed cache between the pipeline and the solver
  So that identical (source, invariant) pairs skip redundant CEGAR invocations

  Background:
    Given the cache middleware module is available
    And the unsat core cache is initialized

  @core
  Scenario: Cache hit returns cached verification result
    Given a verification module path "src/core/example.nim"
    And an invariant hash "inv_abc123"
    When the cache middleware stores the result as verified
    And the cache middleware looks up the same module and invariant
    Then the lookup must return a cache hit
    And the cached result must be verified

  @core
  Scenario: Cache miss on different invariant
    Given a verification module path "src/core/example.nim"
    And an invariant hash "inv_abc123"
    When the cache middleware stores the result as verified
    And the cache middleware looks up with invariant hash "inv_def456"
    Then the lookup must return a cache miss

  @core
  Scenario: Cache miss on different module
    Given a verification module path "src/core/example.nim"
    And an invariant hash "inv_abc123"
    When the cache middleware stores the result as verified
    And the cache middleware looks up module "src/core/other.nim" with same invariant
    Then the lookup must return a cache miss

  @core
  Scenario: Cache stores non-verified results too
    Given a verification module path "src/core/example.nim"
    And an invariant hash "inv_abc123"
    When the cache middleware stores the result as NOT verified
    And the cache middleware looks up the same module and invariant
    Then the lookup must return a cache hit
    And the cached result must be NOT verified

  @metrics
  Scenario: Hit rate tracking is accurate
    Given an empty cache middleware
    When 3 lookups miss and 2 lookups hit
    Then the hit rate must be 0.4

  @eviction
  Scenario: Cache eviction on capacity overflow
    Given a cache middleware at near capacity
    When storing a new entry beyond the limit
    Then the oldest entry must be evicted
    And the new entry must be stored

  @integration
  Scenario: Combined lookup and store cycle
    Given a verification module path "src/core/example.nim"
    And an invariant hash "inv_abc123"
    When checkOrStore is called for the first time
    Then the lookup must return a cache miss
    When checkOrStore is called again with same parameters
    Then the lookup must return a cache hit
