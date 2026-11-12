## Unit tests for the git sync command-injection gate.
##
## Validates `syncBranch`'s safety predicate without invoking real git.
## The gate logic is isolated in `isSafeRebaseTarget` so tests exercise the
## injection-prevention contract in isolation — no hermeticExec/src git calls
## are made from this module (verified by the dry-run path / pure predicate).

{.push raises: [CatchableError].}

import std/unittest
import cli/git_cli

suite "isSafeRebaseTarget command-injection guard":
  test "feature/x → safe":
    check isSafeRebaseTarget("feature/x")

  test "empty string → unsafe":
    check not isSafeRebaseTarget("")

  test "-foo → unsafe (option injection)":
    check not isSafeRebaseTarget("-foo")

  test "foo bar → unsafe (whitespace)":
    check not isSafeRebaseTarget("foo bar")

  test "foo..bar → unsafe (path traversal)":
    check not isSafeRebaseTarget("foo..bar")

  test "origin/main → safe (rebase target)":
    check isSafeRebaseTarget("origin/main")

  test "other sanitized branch names → safe":
    check isSafeRebaseTarget("main")
    check isSafeRebaseTarget("release/1.0")

  test "tab in branch → unsafe":
    check not isSafeRebaseTarget("foo\tbar")

  test "leading space → unsafe":
    check not isSafeRebaseTarget(" foo")

suite "syncBranch gate behavior":
  test "dry-run returns 0 without real git execution":
    # dryRun short-circuits before any hermeticExec("git", ...) call
    # (see syncBranch: if dryRun: echo ... ; return 0), so this is safe to run.
    check syncBranch(dryRun = true) == 0
{.pop.}
