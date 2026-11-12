Feature: sync_protocol_gate — Sync Protocol Enforcement
  As a contributor pushing to the upstream repository,
  the sync_protocol_gate must verify authorization, integrity,
  and safety before allowing the push to proceed.

  Background:
    Given the sync_protocol_gate binary is compiled
    And the working directory is a valid git repository

  # ── Sync authorization via git config ────────────────────────────

  Scenario: Authorized via git config flag
    Given git config "axiom.sync-authorized" is set to "true"
    And the working tree is clean
    And the current branch is not detached
    When the sync_protocol_gate runs
    Then it should exit with code 0
    And stderr should contain "[PASS]"

  Scenario: Rejected when git config flag is missing
    Given git config "axiom.sync-authorized" is unset
    And no verification receipt exists for the current HEAD tree
    And the commit is not in upstream history
    When the sync_protocol_gate runs
    Then it should exit with code 1
    And stderr should contain "Neither verification receipt"

  Scenario: Rejected when git config flag is set to false
    Given git config "axiom.sync-authorized" is set to "false"
    And no verification receipt exists for the current HEAD tree
    And the commit is not in upstream history
    When the sync_protocol_gate runs
    Then it should exit with code 1

  # ── Tree SHA verification receipt acceptance ─────────────────────

  Scenario: Accepted via verification receipt
    Given git config "axiom.sync-authorized" is unset
    And a verification receipt exists at ".axiom/cache/verification_receipts/<tree_sha>"
    And the working tree is clean
    When the sync_protocol_gate runs
    Then it should exit with code 0

  Scenario: Accepted via batch AXIOM_PUSH_COMMITS with valid receipts
    Given git config "axiom.sync-authorized" is unset
    And the environment variable AXIOM_PUSH_COMMITS is set to "<commit_sha>"
    And a verification receipt exists for the commit's tree SHA
    When the sync_protocol_gate runs
    Then it should exit with code 0

  Scenario: Rejected when batch AXIOM_PUSH_COMMITS has no receipts
    Given git config "axiom.sync-authorized" is unset
    And the environment variable AXIOM_PUSH_COMMITS is set to "<commit_sha>"
    And no verification receipt exists for the commit's tree SHA
    And the commit is not in upstream history
    When the sync_protocol_gate runs
    Then it should exit with code 1

  # ── EMPTY token for branch deletion ─────────────────────────────

  Scenario: Accepted when AXIOM_PUSH_COMMITS is EMPTY
    Given git config "axiom.sync-authorized" is unset
    And the environment variable AXIOM_PUSH_COMMITS is set to "EMPTY"
    And the working tree is clean
    When the sync_protocol_gate runs
    Then it should exit with code 0

  # ── Upstream trust ──────────────────────────────────────────────

  Scenario: Accepted when commit is already in origin/core
    Given git config "axiom.sync-authorized" is unset
    And no verification receipt exists for the current HEAD tree
    And the current commit is an ancestor of origin/core
    And the working tree is clean
    When the sync_protocol_gate runs
    Then it should exit with code 0

  # ── Rejection of unverified non-upstream commits ────────────────

  Scenario: Rejected when commit has no receipt and is not upstream
    Given git config "axiom.sync-authorized" is unset
    And no verification receipt exists for the current HEAD tree
    And the current commit is not an ancestor of origin/core
    When the sync_protocol_gate runs
    Then it should exit with code 1
    And stderr should contain "Neither verification receipt"

  # ── Force-push detection ────────────────────────────────────────

  Scenario: Rejected when push would be non-fast-forward
    Given git config "axiom.sync-authorized" is set to "true"
    And the local HEAD has diverged from the upstream tracking branch
    When the sync_protocol_gate runs
    Then it should exit with code 1
    And stderr should contain "Non-fast-forward push detected"

  Scenario: Accepted for fast-forward push
    Given git config "axiom.sync-authorized" is set to "true"
    And the local HEAD is ahead of the upstream tracking branch
    And the working tree is clean
    When the sync_protocol_gate runs
    Then it should exit with code 0

  # ── Detached HEAD rejection ─────────────────────────────────────

  Scenario: Rejected on detached HEAD
    Given git config "axiom.sync-authorized" is set to "true"
    And the repository is in detached HEAD state
    When the sync_protocol_gate runs
    Then it should exit with code 1
    And stderr should contain "Detached HEAD detected"

  # ── Uncommitted changes rejection ───────────────────────────────

  Scenario: Rejected when working tree is dirty
    Given git config "axiom.sync-authorized" is set to "true"
    And there are uncommitted changes in the working tree
    When the sync_protocol_gate runs
    Then it should exit with code 1
    And stderr should contain "Uncommitted changes detected"

  Scenario: Rejected on partially staged changes
    Given git config "axiom.sync-authorized" is set to "true"
    And some files are staged and some are unstaged
    When the sync_protocol_gate runs
    Then it should exit with code 1
    And stderr should contain "Uncommitted changes detected"


