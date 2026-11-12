Feature: Safe Resolve Rebase — Automated Conflict Resolution
  As an Axiom operator
  I want merge conflicts to be resolved automatically via AST merger
  So that .nim file conflicts are handled deterministically without manual intervention

  Scenario: Script requires clean worktree
    Given the working directory has uncommitted changes
    When safe-resolve-rebase is executed
    Then the script exits with code 3
    And the output contains "dirty worktree"

  Scenario: Script detects rebase-in-progress via .git/rebase-merge
    Given a rebase is in progress with conflict markers
    When the script checks for rebase context
    Then the while loop condition ".git/rebase-merge" is true
    And the loop body processes conflicted files

  Scenario: Nim conflicts resolved via AST merger with :2/:3 index stages
    Given a rebase conflict on a .nim file with stage 2 and stage 3 entries
    When the AST merger is invoked with ancestor, clean ours, and clean theirs
    Then the merger writes the result in-place to the ours temp file
    And the result is copied to the working tree file
    And git add is called on the resolved file

  Scenario: Empty commit detected and skipped
    Given a rebase conflict was resolved but the commit became empty
    When git rebase continues but fails with no remaining U-stage files
    Then the script skips the empty commit
    And the loop continues to the next commit

  Scenario: HALT preserves conflict state for manual resolution
    Given JSON or non-Nim files have unresolvable conflicts
    When the AST merger cannot resolve all Nim files
    Then the script exits with code 2
    And the rebase context remains active in .git/rebase-merge
    And the RUN_STATUS is set to HALT preventing trap rollback

  Scenario: Multi-commit rebase processes each conflicting commit
    Given core branch has 3 commits each causing conflicts
    When safe-resolve-rebase processes the rebase loop
    Then each commit's ancestor is computed from stopped-sha
    And the loop iterates once per conflicting commit
    And REMAINING is recomputed each iteration
