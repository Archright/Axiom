## Regression test for pre-push ref deletion handling
## Verifies that git's exact pre-push stdin deletion format (40-zero local OID)
## is correctly skipped by the hook, allowing branch deletions to proceed.
##
## Red→green proof:
##   With the 40-zero fix  → test passes (exit 0, [PASS] in output)
##   With the buggy 38-zero → test fails (hook treats deletion as normal push,
##     runs `git worktree add --detach <snap> 000...0` which fails)

import std/[unittest, os, osproc, streams, strutils, times]

const
  RepoRoot = currentSourcePath().parentDir().parentDir().parentDir()
  PrePushHook = RepoRoot / ".githooks" / "pre-push"

suite "pre_push_ref_deletion":

  test "deletion with 40-zero local OID passes pre-push checks":
    # Git's exact pre-push stdin line format for a ref deletion:
    # <local-ref> SP <local-sha> SP <remote-ref> SP <remote-sha>
    # For deletion: local-sha is 40 zeros (the correct git protocol sentinel)
    let deletionLine = "(delete) 0000000000000000000000000000000000000000 refs/heads/deletion-probe cdf31e3f6e0baea987a84b100c2fa0dfbb07bf088\n"

    var p = startProcess(
      "bash",
      args = @[".githooks/pre-push"],
      workingDir = RepoRoot,
      options = {poUsePath}
    )

    p.inputStream.write(deletionLine)
    p.inputStream.flush()
    p.inputStream.close()

    let output = p.outputStream.readAll()
    let exitCode = p.waitForExit(30000)

    check exitCode == 0
    check "[PASS] Pre-push checks passed" in output

    p.close()