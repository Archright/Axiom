import std/unittest
import std/tables
import std/times
import core/schema/io_schema

# ── Result Type Tests ───────────────────────────────────────────────────────

suite "Result type contracts":
  test "ok constructs Ok variant":
    let r: Result[int, string] = ok[int, string](42)
    check r.kind == rkOk
    check r.val == 42
    check r.isOk
    check not r.isErr

  test "err constructs Err variant":
    let r: Result[int, string] = err[int, string]("fail")
    check r.kind == rkErr
    check r.err == "fail"
    check not r.isOk
    check r.isErr

  test "get unwraps Ok value":
    let r: Result[string, string] = ok[string, string]("hello")
    check r.get() == "hello"

# ── Distinct Type Tests ────────────────────────────────────────────────────

suite "Distinct type safety":
  test "ProcessExitCode wraps int":
    let code = ProcessExitCode(0)
    check int(code) == 0

  test "DurationMs wraps int64":
    let d = DurationMs(1500)
    check int64(d) == 1500

  test "FilePath wraps string":
    let p = FilePath("/tmp/test")
    check string(p) == "/tmp/test"

  test "CommandString wraps string":
    let c = CommandString("git status")
    check string(c) == "git status"

  test "ProcessExitCode $ returns string":
    let code = ProcessExitCode(127)
    check $code == "127"

  test "FilePath $ returns string":
    let p = FilePath("/a/b")
    check $p == "/a/b"

  test "CommandString $ returns string":
    let c = CommandString("ls -la")
    check $c == "ls -la"

# ── ProcessOptions Tests ────────────────────────────────────────────────────

suite "ProcessOptions contracts":
  test "default options are valid":
    var opts = ProcessOptions()
    opts.captureOutput = true
    check validateProcessOptions(opts)

  test "input without captureOutput is invalid":
    var opts = ProcessOptions()
    opts.input = "data"
    opts.captureOutput = false
    check not validateProcessOptions(opts)

  test "excludedEnvKeys must not overlap extraEnv":
    var opts = ProcessOptions()
    opts.captureOutput = true
    opts.extraEnv["PATH"] = "/usr/bin"
    opts.excludedEnvKeys = @["PATH"]
    check not validateProcessOptions(opts)

  test "valid excludedEnvKeys pass":
    var opts = ProcessOptions()
    opts.captureOutput = true
    opts.extraEnv["HOME"] = "/home/user"
    opts.excludedEnvKeys = @["PATH"]
    check validateProcessOptions(opts)

  test "JSON round-trip ProcessOptions":
    var opts = ProcessOptions()
    opts.captureOutput = true
    opts.allowNonZeroExit = false
    opts.input = "stdin-data"
    opts.workingDir = FilePath("/tmp")
    opts.extraEnv["KEY"] = "val"
    opts.excludedEnvKeys = @["DEL"]
    let node = toJson(opts)
    let restored = fromJsonProcessOptions(node)
    check restored.captureOutput == true
    check restored.allowNonZeroExit == false
    check restored.input == "stdin-data"
    check string(restored.workingDir) == "/tmp"
    check restored.extraEnv["KEY"] == "val"
    check restored.excludedEnvKeys == @["DEL"]

# ── ProcessCommand Tests ────────────────────────────────────────────────────

suite "ProcessCommand contracts":
  test "valid command passes validation":
    var opts = ProcessOptions(captureOutput: true)
    let cmd = ProcessCommand(
      cmd: CommandString("git"),
      args: @["status"],
      options: opts,
      description: "check status",
      retries: 0,
      binaryOk: true,
      isHelp: false
    )
    check validateProcessCommand(cmd)

  test "empty cmd fails validation":
    let cmd = ProcessCommand(cmd: CommandString(""))
    check not validateProcessCommand(cmd)

  test "negative retries fails validation":
    let cmd = ProcessCommand(cmd: CommandString("ls"), retries: -1)
    check not validateProcessCommand(cmd)

  test "JSON round-trip ProcessCommand":
    var opts = ProcessOptions(captureOutput: true)
    let cmd = ProcessCommand(
      cmd: CommandString("nim"),
      args: @["c", "-d:release", "main.nim"],
      options: opts,
      description: "compile",
      retries: 2,
      binaryOk: true,
      isHelp: false
    )
    let node = toJson(cmd)
    let restored = fromJsonProcessCommand(node)
    check string(restored.cmd) == "nim"
    check restored.args == @["c", "-d:release", "main.nim"]
    check restored.description == "compile"
    check restored.retries == 2
    check restored.binaryOk == true
    check restored.isHelp == false

# ── ProcessResult Tests ─────────────────────────────────────────────────────

suite "ProcessResult contracts":
  test "constructs with all fields":
    let pr = ProcessResult(
      exitCode: ProcessExitCode(0),
      stdout: "ok",
      stderr: "",
      command: "echo ok",
      durationMs: DurationMs(42),
      timedOut: false,
      captured: true,
      duration: initDuration(milliseconds = 42)
    )
    check int(pr.exitCode) == 0
    check pr.stdout == "ok"
    check pr.stderr == ""
    check int64(pr.durationMs) == 42
    check not pr.timedOut

  test "JSON round-trip ProcessResult":
    let pr = ProcessResult(
      exitCode: ProcessExitCode(1),
      stdout: "out",
      stderr: "err",
      command: "test-cmd",
      durationMs: DurationMs(999),
      timedOut: true,
      captured: true
    )
    let node = toJson(pr)
    let restored = fromJsonProcessResult(node)
    check int(restored.exitCode) == 1
    check restored.stdout == "out"
    check restored.stderr == "err"
    check restored.command == "test-cmd"
    check int64(restored.durationMs) == 999
    check restored.timedOut == true
    check restored.captured == true

# ── GitCommand Tests ────────────────────────────────────────────────────────

suite "GitCommand enum contracts":
  test "enum has 25 values":
    check ord(high(GitCommand)) - ord(low(GitCommand)) + 1 == 25

  test "gitCommandName returns correct names":
    check gitCommandName(gcMerge) == "merge"
    check gitCommandName(gcSquash) == "squash"
    check gitCommandName(gcRebase) == "rebase"
    check gitCommandName(gcBranch) == "branch"
    check gitCommandName(gcDeleteBranch) == "delete-branch"
    check gitCommandName(gcCherryPick) == "cherry-pick"
    check gitCommandName(gcReset) == "reset"
    check gitCommandName(gcCreateWorktree) == "create-worktree"
    check gitCommandName(gcRemoveWorktree) == "remove-worktree"
    check gitCommandName(gcStatus) == "status"
    check gitCommandName(gcCommit) == "commit"
    check gitCommandName(gcStage) == "stage"
    check gitCommandName(gcUnstage) == "unstage"
    check gitCommandName(gcStash) == "stash"
    check gitCommandName(gcStashPop) == "stash-pop"
    check gitCommandName(gcResolveStart) == "resolve-start"
    check gitCommandName(gcResolveAccept) == "resolve-accept"
    check gitCommandName(gcResolveAbort) == "resolve-abort"
    check gitCommandName(gcIgnore) == "ignore"
    check gitCommandName(gcSetRef) == "set-ref"
    check gitCommandName(gcPush) == "push"
    check gitCommandName(gcBranchReady) == "branch-ready"
    check gitCommandName(gcBranchCleanup) == "branch-cleanup"
    check gitCommandName(gcGetCurrentRef) == "get-current-ref"
    check gitCommandName(gcIsAncestor) == "is-ancestor"

  test "GitCommand $ matches gitCommandName":
    check $gcMerge == "merge"
    check $gcPush == "push"
    check $gcIsAncestor == "is-ancestor"

# ── SandboxSpec Tests ───────────────────────────────────────────────────────

suite "SandboxSpec contracts":
  test "valid spec passes validation":
    let spec = SandboxSpec(
      tags: @["lean", "z3"],
      resourceClass: "medium",
      baselineBytes: 1024,
      perOpBytes: @[256, 512],
      perOpSeconds: @[10, 20],
      networking: false,
      baselineSeconds: 30,
      perOpBytesBurst: 128,
      perOpSecondsBurst: 5
    )
    check validateSandboxSpec(spec)

  test "empty tags fails validation":
    let spec = SandboxSpec(
      tags: @[],
      resourceClass: "small",
      baselineBytes: 0,
      perOpBytes: @[],
      perOpSeconds: @[]
    )
    check not validateSandboxSpec(spec)

  test "empty resourceClass fails validation":
    let spec = SandboxSpec(
      tags: @["test"],
      resourceClass: "",
      baselineBytes: 0,
      perOpBytes: @[],
      perOpSeconds: @[]
    )
    check not validateSandboxSpec(spec)

  test "mismatched perOpBytes/perOpSeconds fails":
    let spec = SandboxSpec(
      tags: @["test"],
      resourceClass: "small",
      baselineBytes: 0,
      perOpBytes: @[100, 200],
      perOpSeconds: @[10]
    )
    check not validateSandboxSpec(spec)

  test "negative baselineBytes fails":
    let spec = SandboxSpec(
      tags: @["test"],
      resourceClass: "small",
      baselineBytes: -1,
      perOpBytes: @[],
      perOpSeconds: @[]
    )
    check not validateSandboxSpec(spec)

  test "negative baselineSeconds fails":
    let spec = SandboxSpec(
      tags: @["test"],
      resourceClass: "small",
      baselineBytes: 0,
      baselineSeconds: -1,
      perOpBytes: @[],
      perOpSeconds: @[]
    )
    check not validateSandboxSpec(spec)

  test "JSON round-trip SandboxSpec":
    let spec = SandboxSpec(
      tags: @["lean", "z3"],
      resourceClass: "large",
      baselineBytes: 4096,
      perOpBytes: @[128, 256, 512],
      perOpSeconds: @[5, 10, 15],
      networking: true,
      baselineSeconds: 60,
      perOpBytesBurst: 1024,
      perOpSecondsBurst: 10
    )
    let node = toJson(spec)
    let restored = fromJsonSandboxSpec(node)
    check restored.tags == @["lean", "z3"]
    check restored.resourceClass == "large"
    check restored.baselineBytes == 4096
    check restored.perOpBytes == @[128, 256, 512]
    check restored.perOpSeconds == @[5, 10, 15]
    check restored.networking == true
    check restored.baselineSeconds == 60
    check restored.perOpBytesBurst == 1024
    check restored.perOpSecondsBurst == 10
