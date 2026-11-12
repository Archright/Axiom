Feature: Tree SHA Verification Receipt System
  As a developer using Axiom-core
  I want automatic verification receipts for pre-commit gate passes
  So that pushes are authorized without manual git config

  Background:
    Given a clean git repository with Axiom-core initialized
    And the verification receipt cache directory exists at ".axiom/cache/verification_receipts"

  @basic
  Scenario: Pre-commit gates generate Tree SHA receipt on full pass
    Given staged changes that will pass all pre-commit gates
    When the pre-commit hook runs and all gates pass
    Then a verification receipt is created at ".axiom/cache/verification_receipts/<tree_sha>"
    And the receipt file content is "<epoch>|<unix_timestamp>"
    And the receipt is recorded in the orchestrator hook

  @basic
  Scenario: Tree SHA receipt is deterministic for identical index state
    Given two identical git index states
    When pre-commit gates run on both index states
    Then both receipts reference the same tree SHA
    And the second write is a no-op due to content-addressing

  @basic
  Scenario: sync_protocol_gate accepts push with valid receipt
    Given a valid verification receipt exists for the current tree SHA
    And the receipt is less than 7 days old
    When the sync_protocol_gate checks the push
    Then the push is authorized without manual git config
    And the receipt remains in the cache

  @basic
  Scenario: sync_protocol_gate accepts branch deletion via EMPTY token
    Given a branch deletion is requested
    When the sync_protocol_gate processes the deletion
    Then the push is authorized using the EMPTY token
    And no verification receipt is required for deletion

  @basic
  Scenario: sync_protocol_gate trusts upstream commits
    Given a commit from an upstream remote
    When the sync_protocol_gate checks the push
    Then the push is authorized as an upstream commit
    And no verification receipt check is performed

  @basic
  Scenario: sync_protocol_gate rejects unverified non-upstream commits
    Given a local commit that is not from upstream
    And no valid verification receipt exists for the commit
    When the sync_protocol_gate checks the push
    Then the push is rejected
    And an error indicates the commit is unverified

  @basic
  Scenario: pre-merge-commit hook generates receipt for merge commits
    Given a merge commit is being created
    And all pre-commit gates pass for the merged tree
    When the pre-merge-commit hook runs
    Then a verification receipt is created for the merge commit tree SHA
    And the receipt content contains the current epoch and timestamp

  @basic
  Scenario: post-rewrite hook generates receipts for rebased commits
    Given commits have been rewritten by a rebase
    When the post-rewrite hook runs
    Then verification receipts are generated for each rewritten commit
    And each receipt references the new tree SHA after rebase

  @basic
  Scenario: Verification receipts expire after 7 days
    Given a verification receipt that was created 8 days ago
    When gcVerificationReceipts runs
    Then the expired receipt is removed from the cache
    And the sync_protocol_gate will reject pushes that relied on the expired receipt
