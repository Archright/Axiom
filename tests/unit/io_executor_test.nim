## Smoke tests for io_executor.nim and git_operations.nim
## Verifies concept satisfaction, data type construction, and mock behavior.

import std/unittest
import std/strutils
import core/types/results
import core/interfaces/io_executor
import core/interfaces/git_operations

# ---------------------------------------------------------------------------
# Concept satisfaction (compile-time check)
# ---------------------------------------------------------------------------

proc assertIoExecutor[E: IoExecutor](e: var E) =
  ## If this compiles, E satisfies IoExecutor at compile time.
  discard

proc assertGitOperations[E: GitOperations](g: var E) =
  ## If this compiles, E satisfies GitOperations at compile time.
  discard

suite "IoExecutor concept satisfaction":
  test "SystemExecutor satisfies IoExecutor":
    var exec = newSystemExecutor()
    assertIoExecutor(exec)

  test "MockExecutor satisfies IoExecutor":
    var exec = newMockExecutor()
    assertIoExecutor(exec)

suite "GitOperations concept satisfaction":
  test "DryRunGitOps satisfies GitOperations":
    var ops = newDryRunGitOps()
    assertGitOperations(ops)

  test "MockGitOps satisfies GitOperations":
    var ops = newMockGitOps()
    assertGitOperations(ops)

# ---------------------------------------------------------------------------
# ProcessCommand data types
# ---------------------------------------------------------------------------

suite "ProcessCommand construction":
  test "default fields are empty":
    let cmd = ProcessCommand()
    check cmd.program == ""
    check cmd.args.len == 0
    check cmd.workingDir == ""
    check cmd.env.len == 0

  test "populated fields":
    let cmd = ProcessCommand(
      program: "git",
      args: @["status", "--porcelain"],
      workingDir: "/tmp/repo",
      env: @[("GIT_DIR", "/tmp/repo/.git")]
    )
    check cmd.program == "git"
    check cmd.args.len == 2
    check cmd.args[0] == "status"
    check cmd.workingDir == "/tmp/repo"

# ---------------------------------------------------------------------------
# GitCommand helpers
# ---------------------------------------------------------------------------

suite "GitCommand helpers":
  test "gitCmd creates default git command":
    let gc = gitCmd(args = @["status"])
    let pc = ProcessCommand(gc)
    check pc.program == "git"
    check pc.args == @["status"]

  test "gitCmd with custom program":
    let gc = gitCmd(program = "mygit", args = @["push"])
    let pc = ProcessCommand(gc)
    check pc.program == "mygit"

  test "toGitCommand round-trips":
    let original = ProcessCommand(program: "git", args: @["log"])
    let gc = original.toGitCommand()
    let back = gc.toProcessCommand()
    check back.program == original.program
    check back.args == original.args

  test "$ shows program and args":
    let gc = gitCmd(args = @["diff", "--cached"])
    check $gc == "git diff --cached"

# ---------------------------------------------------------------------------
# MockExecutor behavior
# ---------------------------------------------------------------------------

suite "MockExecutor":
  test "default result when queue is empty":
    var exec = newMockExecutor()
    let cmd = ProcessCommand(program: "echo", args: @["hello"])
    let r = exec.execute(cmd)
    check r.isOk()
    check r.get().stdout == ""
    check r.get().exitCode == 0

  test "records commands":
    var exec = newMockExecutor()
    let cmd = ProcessCommand(program: "ls", args: @["-la"])
    discard exec.execute(cmd)
    check exec.recordedCommands.len == 1
    check exec.recordedCommands[0].program == "ls"

  test "returns pre-configured results in order":
    var exec = newMockExecutor()
    exec.pushResult(Result[ProcessResult, string](ok: true, value: ProcessResult(stdout: "first", exitCode: 0)))
    exec.pushResult(Result[ProcessResult, string](ok: true, value: ProcessResult(stdout: "second", exitCode: 1)))
    let cmd = ProcessCommand(program: "test")
    let r1 = exec.execute(cmd)
    let r2 = exec.execute(cmd)
    check r1.get().stdout == "first"
    check r2.get().stdout == "second"
    check r2.get().exitCode == 1

  test "pre-configured error results":
    var exec = newMockExecutor()
    exec.pushResult(Result[ProcessResult, string](ok: false, err: "connection refused"))
    let r = exec.execute(ProcessCommand(program: "fail"))
    check r.isErr()
    check r.error == "connection refused"

  test "records git commands separately":
    var exec = newMockExecutor()
    let gc = gitCmd(args = @["status"])
    discard exec.executeGit(gc)
    check exec.recordedGitCommands.len == 1

  test "git results queue independent of command results":
    var exec = newMockExecutor()
    exec.pushResult(Result[ProcessResult, string](ok: true, value: ProcessResult(stdout: "cmd", exitCode: 0)))
    exec.pushGitResult(Result[ProcessResult, string](ok: true, value: ProcessResult(stdout: "git", exitCode: 0)))
    let r1 = exec.execute(ProcessCommand(program: "test"))
    let r2 = exec.executeGit(gitCmd())
    check r1.get().stdout == "cmd"
    check r2.get().stdout == "git"

# ---------------------------------------------------------------------------
# SystemExecutor (live I/O smoke test)
# ---------------------------------------------------------------------------

suite "SystemExecutor":
  test "executes echo successfully":
    var exec = newSystemExecutor()
    let cmd = ProcessCommand(program: "echo", args: @["smoke-test-42"])
    let r = exec.execute(cmd)
    check r.isOk()
    let pr = r.get()
    check pr.exitCode == 0
    check "smoke-test-42" in pr.stdout

  test "executes false and captures non-zero exit code":
    var exec = newSystemExecutor()
    let cmd = ProcessCommand(program: "false")
    let r = exec.execute(cmd)
    check r.isOk()  # execCmdEx itself succeeds
    check r.get().exitCode != 0

  test "wraps nonexistent command with non-zero exit code":
    var exec = newSystemExecutor()
    let cmd = ProcessCommand(program: "definitely-not-a-real-binary-12345")
    let r = exec.execute(cmd)
    check r.isOk()  # execCmdEx wraps the failure in Result
    check r.get().exitCode != 0

  test "SystemExecutor satisfies IoExecutor concept":
    var exec = newSystemExecutor()
    assertIoExecutor(exec)

# ---------------------------------------------------------------------------
# MockGitOps
# ---------------------------------------------------------------------------

suite "MockGitOps":
  test "default constructor returns success for all operations":
    var ops = newMockGitOps()
    check ops.currentBranch().isOk()
    check ops.currentBranch().get() == "main"
    check ops.isDirty().isOk()
    check ops.isDirty().get() == false

  test "records all commands":
    var ops = newMockGitOps()
    discard ops.merge(msFastForward, "feature")
    discard ops.updateRef("refs/heads/x", "abc123")
    discard ops.listFiles()
    check ops.commands.len == 3

  test "custom error results":
    var ops = newMockGitOps()
    let err = GitError(
      exitCode: GitExitCode(128),
      stderr: "fatal: not a git repository",
      command: "git status",
      context: "status"
    )
    ops.statusResult = Result[string, GitError](ok: false, err: err)
    let r = ops.status()
    check r.isErr()
    check r.error.exitCode == GitExitCode(128)
    check "not a git repository" in r.error.stderr

# ---------------------------------------------------------------------------
# DryRunGitOps
# ---------------------------------------------------------------------------

suite "DryRunGitOps":
  test "records commands without executing":
    var ops = newDryRunGitOps("/tmp/test")
    discard ops.merge(msMergeCommit, "develop")
    discard ops.updateRef("refs/heads/x", "abc")
    check ops.log.len == 2
    # First logged command should be git merge --no-ff develop
    let cmd = ops.log[0]
    check cmd.program == "git"
    check "--no-ff" in cmd.args
    check "develop" in cmd.args

  test "all operations return success":
    var ops = newDryRunGitOps()
    check ops.merge(msFastForward, "x").isOk()
    check ops.rebaseOnto("main", "feat").isOk()
    check ops.updateRef("r", "c").isOk()
    check ops.worktreeAdd("/wt", "main").isOk()
    check ops.worktreeRemove("/wt").isOk()
    check ops.isDirty().isOk()
    check ops.currentBranch().isOk()
    check ops.revParse("HEAD").isOk()
    check ops.status().isOk()
    check ops.listFiles().isOk()
    check ops.log.len == 10

# ---------------------------------------------------------------------------
# GitOperations integration (concept usage in generic code)
# ---------------------------------------------------------------------------

suite "GitOperations generic usage":
  test "generic function works with any GitOperations":
    proc countCommands[G: GitOperations](g: var G): int =
      discard g.merge(msFastForward, "x")
      discard g.listFiles()
      2  # expected command count for MockGitOps

    var mock = newMockGitOps()
    check countCommands(mock) == 2
    check mock.commands.len == 2
