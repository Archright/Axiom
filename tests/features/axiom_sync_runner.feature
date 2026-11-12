Feature: Axiom Sync Runner
  As a developer
  I want a git plumbing-based merge pipeline
  So that sync operations are worktree-independent and deterministic

  Scenario: Resolve refs succeeds with valid branches
    Given base and secondary branches exist with common ancestor
    When resolve is called
    Then a MergeTransaction is returned with valid OIDs

  Scenario: Merge-tree produces clean result for non-overlapping changes
    Given base and secondary branches with no file conflicts
    When resolve is called
    Then the transaction stage is tsMaterialized

  Scenario: Commit-and-publish writes sync metadata
    Given a materialized MergeTransaction with valid tree OID
    When commitAndPublish is called
    Then a merge commit OID is returned
    And sync metadata is written to .axiom/sync_state/

  Scenario: ReSign renews TTL on existing metadata
    Given a commit with existing sync metadata
    When reSign is called
    Then the metadata timestamp is updated
    And the signature is re-computed
