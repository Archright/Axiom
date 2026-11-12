Feature: Gate CAS GC — garbage collection for content-addressable storage
  As the Gate Infrastructure,
  I want to evict old CAS entries while preserving the newest N,
  So that disk usage is bounded without losing recent builds.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory with CAS entries exists

  Scenario: preserve newest 3 entries per gate
    Given 5 CAS entries for gate "test-gate" with varying ages
    When I run CAS GC with maxEntries=3
    Then the 3 newest entries are preserved
    And the 2 oldest entries are deleted

  Scenario: entries younger than MinCasEntryAgeSec are never deleted
    Given a CAS entry created 30 minutes ago
    When I run CAS GC
    Then the entry is preserved regardless of maxEntries

  Scenario: log deleted files
    Given a CAS entry eligible for deletion
    When I run CAS GC
    Then a deletion log message is emitted before removal
