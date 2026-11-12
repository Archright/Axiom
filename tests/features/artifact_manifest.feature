Feature: Artifact Manifest — commit-hash-keyed gate result storage (Bazel Action Cache pattern)
  As the Gate Infrastructure,
  I want to store and retrieve gate results keyed by commit hash,
  So that baseline ratchet checks work across runs without redundant recomputation.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: store and lookup round-trip
    Given a commit hash "abc123" and a GateResult for "test-gate" with 2 warnings and 1 error
    When I call storeResult with the commit hash and gate result
    And I call lookupResult for commit "abc123" and gate "test-gate"
    Then the lookup returns the stored result with 2 warnings and 1 error

  Scenario: lookupPreviousResult returns the most recent result
    Given stored results for commit "aaa" and "bbb" for gate "test-gate"
    When I call lookupPreviousResult for gate "test-gate"
    Then the lookup returns the result from the most recent commit

  Scenario: lookup returns None for a missing key
    Given no stored result for commit "missing" and gate "test-gate"
    When I call lookupResult for commit "missing" and gate "test-gate"
    Then the lookup returns None

  Scenario: atomic write via temp+fsync+rename
    When I call storeResult for a new commit hash
    Then the result file is written atomically
    And no partial writes are observable
