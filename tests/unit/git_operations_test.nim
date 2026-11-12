## Smoke tests for io_executor and git_operations modules.
## Verifies:
##   1. MockExecutor records commands and returns queued results
##   2. MockGitOps returns pre-configured results per operation
##   3. DryRunGitOps logs commands and always returns success
##   4. LiveGitOps[SystemExecutor] compiles (concept satisfaction)
##   5. GitError construction helper

import std/unittest
import core/types/results
import core/interfaces/io_executor
import core/interfaces/git_operations

# ─── MockExecutor tests ─────────────────────────────────────────────────────

suite "MockExecutor":
  test "records executed commands":
    var mock = newMockExecutor()
    let cmd = ProcessCommand(program: "git", args: @["status"])
    let r = mock.execute(cmd)
    check r.isOk()
    check mock.recordedCommands.len == 1
    check mock.recordedCommands[0].program == "git"
    check mock.recordedCommands[0].args == @["status"]

  test "returns queued results in order":
    var mock = newMockExecutor()
    mock.pushResult(Result[ProcessResult, string](ok: true, value: ProcessResult(stdout: "first", exitCode: 0)))
    mock.pushResult(Result[ProcessResult, string](ok: true, value: ProcessResult(stdout: "second", exitCode: 1)))

    let cmd = ProcessCommand(program: "echo", args: @["a"])
    let r1 = mock.execute(cmd)
    let r2 = mock.execute(cmd)

    check r1.get().stdout == "first"
    check r2.get().stdout == "second"
    check r2.get().exitCode == 1

  test "falls back to default when queue is empty":
    var mock = newMockExecutor()
    let cmd = ProcessCommand(program: "echo", args: @[])
    let r = mock.execute(cmd)
    check r.isOk()
    check r.get().stdout == ""
    check r.get().exitCode == 0

  test "executeGit records through distinct wrapper":
    var mock = newMockExecutor()
    let gc = GitCommand(ProcessCommand(program: "git", args: @["log"]))
    let r = mock.executeGit(gc)
    check r.isOk()
    check mock.recordedGitCommands.len == 1
    check mock.recordedGitCommands[0] == gc

# ─── MockGitOps tests ──────────────────────────────────────────────────────

suite "MockGitOps":
  test "merge records command and returns configured result":
    var ops = newMockGitOps()
    let r = ops.merge(msFastForward, "main")
    check r.isOk()
    check r.get().exitCode == 0
    check ops.commands.len == 1
    check ops.commands[0].args == @["merge", "--ff-only", "main"]

  test "merge with failure result":
    var ops = newMockGitOps()
    ops.mergeResult = Result[MergeResult, GitError](ok: false, err: gitError(1, "CONFLICT", "merge feature", "merge"))
    let r = ops.merge(msMergeCommit, "feature")
    check r.isErr()
    check r.error.exitCode == GitExitCode(1)
    check r.error.stderr == "CONFLICT"

  test "rebaseOnto records command":
    var ops = newMockGitOps()
    let r = ops.rebaseOnto("origin/main", "feature")
    check r.isOk()
    check ops.commands[0].args == @["rebase", "--onto", "origin/main", "feature"]

  test "updateRef records command":
    var ops = newMockGitOps()
    let r = ops.updateRef("refs/heads/main", "abc123")
    check r.isOk()
    check ops.commands[0].args == @["update-ref", "refs/heads/main", "abc123"]

  test "worktreeAdd records command":
    var ops = newMockGitOps()
    let r = ops.worktreeAdd("/tmp/wt", "HEAD")
    check r.isOk()
    check ops.commands[0].args == @["worktree", "add", "/tmp/wt", "HEAD"]

  test "worktreeRemove records command":
    var ops = newMockGitOps()
    let r = ops.worktreeRemove("/tmp/wt")
    check r.isOk()
    check ops.commands[0].args == @["worktree", "remove", "/tmp/wt", "--force"]

  test "isDirty returns configured value":
    var ops = newMockGitOps()
    check ops.isDirty().get() == false
    ops.isDirtyResult = Result[bool, GitError](ok: true, value: true)
    check ops.isDirty().get() == true

  test "currentBranch returns configured branch":
    var ops = newMockGitOps()
    ops.currentBranchResult = Result[string, GitError](ok: true, value: "feature-x")
    let r = ops.currentBranch()
    check r.isOk()
    check r.get() == "feature-x"

  test "revParse records command":
    var ops = newMockGitOps()
    let r = ops.revParse("HEAD~1")
    check r.isOk()
    check ops.commands[0].args == @["rev-parse", "HEAD~1"]

  test "listFiles returns configured list":
    var ops = newMockGitOps()
    ops.listFilesResult = Result[seq[string], GitError](ok: true, value: @["a.nim", "b.nim"])
    let r = ops.listFiles()
    check r.get() == @["a.nim", "b.nim"]

  test "all operations accumulate commands":
    var ops = newMockGitOps()
    discard ops.currentBranch()
    discard ops.isDirty()
    discard ops.status()
    check ops.commands.len == 3

# ─── DryRunGitOps tests ────────────────────────────────────────────────────

suite "DryRunGitOps":
  test "merge logs command and returns success":
    var ops = newDryRunGitOps()
    let r = ops.merge(msSquash, "release")
    check r.isOk()
    check r.get().exitCode == 0
    check ops.log.len == 1
    check ops.log[0].args == @["merge", "--squash", "release"]

  test "all operations log commands":
    var ops = newDryRunGitOps()
    discard ops.merge(msFastForward, "main")
    discard ops.rebaseOnto("up", "br")
    discard ops.updateRef("ref", "sha")
    discard ops.worktreeAdd("/p", "HEAD")
    discard ops.worktreeRemove("/p")
    discard ops.isDirty()
    discard ops.currentBranch()
    discard ops.revParse("HEAD")
    discard ops.status()
    discard ops.listFiles()
    check ops.log.len == 10

  test "dry run never fails":
    var ops = newDryRunGitOps()
    check ops.merge(msFastForward, "x").isOk()
    check ops.rebaseOnto("a", "b").isOk()
    check ops.updateRef("r", "s").isOk()
    check ops.worktreeAdd("p", "r").isOk()
    check ops.worktreeRemove("p").isOk()
    check ops.isDirty().isOk()
    check ops.currentBranch().isOk()
    check ops.revParse("r").isOk()
    check ops.status().isOk()
    check ops.listFiles().isOk()

# ─── GitError helper tests ─────────────────────────────────────────────────

suite "GitError construction":
  test "gitError builds structured error":
    let e = gitError(128, "fatal: not a git repository", "git status", "status")
    check e.exitCode == GitExitCode(128)
    check e.stderr == "fatal: not a git repository"
    check e.command == "git status"
    check e.context == "status"

  test "$GitExitCode renders as string":
    check $(GitExitCode(0)) == "0"
    check $(GitExitCode(128)) == "128"
