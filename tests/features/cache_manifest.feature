Feature: Cache Manifest — tracks gate cache entries and staleness
  As the Axiom gate infrastructure,
  I want a manifest that records cache keys and their validity,
  So that stale cache entries are detected and invalidated.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: fresh cache entry is valid
    Given a cache manifest entry with current hash
    When I check the entry's validity
    Then the entry is valid

  Scenario: stale cache entry is invalid
    Given a cache manifest entry with outdated hash
    When I check the entry's validity
    Then the entry is invalid and marked for refresh
