Feature: GC Roots — mark-and-sweep garbage collection for cache stores
  As the Hermetic Build Engine,
  I want mark-and-sweep GC rooted at .axiom/gcroots/,
  So that unused cache store entries are reclaimed deterministically.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: registerRoot creates a root marker file in gcroots directory
    Given the gcroots directory ".axiom/gcroots" exists
    When I call registerRoot for store path "stores/abc123"
    Then a file named "abc123.root" exists in ".axiom/gcroots"
    And the file content contains the store path

  Scenario: collectRoots lists all registered root entries
    Given registered roots for "store-alpha", "store-beta", and "store-gamma"
    When I call collectRoots
    Then the result contains exactly 3 entries
    And each entry matches a registered store path

  Scenario: sweep removes unreferenced store entries
    Given registered roots for "store-keep" only
    And unregistered store directories "store-orphan-1" and "store-orphan-2"
    When I call sweep
    Then "store-keep" is preserved
    And "store-orphan-1" is removed
    And "store-orphan-2" is removed
