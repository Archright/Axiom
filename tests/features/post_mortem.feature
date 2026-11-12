Feature: Post Mortem — preserve failed sandbox state for diagnosis
  As the Hermetic Build Engine,
  I want failed sandbox snapshots preserved in a post-mortem directory,
  So that engineers can inspect the exact state of a failed build.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: preserveFailed copies sandbox to post_mortem directory
    Given a failed sandbox at "sandbox/run-007"
    When I call preserveFailed for "sandbox/run-007"
    Then a snapshot exists under ".axiom/post_mortem/"
    And the snapshot contains all sandbox files

  Scenario: listFailed shows recent failures sorted by timestamp
    Given post-mortem entries from 3 different failed runs
    When I call listFailed
    Then the result contains exactly 3 entries
    And entries are ordered newest first

  Scenario: cleanPostMortem removes entries older than 7 days
    Given a post-mortem entry from 10 days ago
    And a post-mortem entry from 2 days ago
    When I call cleanPostMortem
    Then the 10-day-old entry is removed
    And the 2-day-old entry is preserved
