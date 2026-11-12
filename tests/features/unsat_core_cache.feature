Feature: Unsat Core Cache
  As an Axiom operator running batch UAP verification
  I want an LRU cache for unsat core fingerprints
  So that repeated solver queries for identical cores are skipped

  Background:
    Given the unsat core cache is initialized with capacity 4096

  @core
  Scenario: Cache miss on empty cache
    Given an empty unsat core cache
    When a lookup is performed for hash "abc123"
    Then the lookup must return a miss

  @core
  Scenario: Cache hit after store
    Given an unsat core cache
    When a result is stored for hash "abc123"
    And a lookup is performed for hash "abc123"
    Then the lookup must return a hit

  @core
  Scenario: LRU eviction on capacity overflow
    Given a cache at full capacity
    When a new entry is stored
    Then the least recently used entry must be evicted
    And the new entry must be stored

  @metrics
  Scenario: Hit rate tracking
    Given a cache with 3 misses and 7 hits
    When the hit rate is queried
    Then the hit rate must be 0.7

  @safety
  Scenario: Value-type only safety
    Given the UnsatCoreCache type
    Then it must not contain any ref object fields
    And it must be safe for malebolgia spawn value args
