{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "domain"
import core/types/results
import core/trusted/effect_bridge
# Directly bring in the `checkDiscardResult:` macro. The product build also
# injects this module globally via config/effects.nims (switch("import", ...)),
# but hermetic gate/tool builds run with `--skipParentCfg --skipProjCfg` and do
# NOT load effects.nims; a direct import keeps the wrap resolvable there too.
# Same layer ("domain") → intra-core, exempt from import-encapsulation gate.
import core/lint/discard_result_linter
import std/osproc
import std/strutils
import std/strtabs

# ---------------------------------------------------------------------------
# Command Data Types
# ---------------------------------------------------------------------------

type
  ProcessCommand* = object
    ## Declarative process invocation. No I/O — pure data.
    program*: string
    args*: seq[string]
    workingDir*: string
    env*: seq[(string, string)]

  ProcessResult* = object
    ## Process outcome. Carries stdout/stderr/exitCode from execution.
    stdout*: string
    stderr*: string
    exitCode*: int

  GitCommand* = distinct ProcessCommand
    ## Type-safe wrapper for git commands. Prevents accidental use of
    ## non-git programs where git commands are expected.
# ---------------------------------------------------------------------------
# IoExecutor Concept — Compile-time interface contract
# ---------------------------------------------------------------------------

  IoExecutor* = concept e
    ## Compile-time interface for process execution.
    ## SystemExecutor satisfies this for real I/O.
    ## MockExecutor satisfies this for testing.
    e.execute(ProcessCommand) is Result[ProcessResult, string]
    e.executeGit(GitCommand) is Result[ProcessResult, string]

# ---------------------------------------------------------------------------
# IOCapability — Sealed I/O Permission Token
# ---------------------------------------------------------------------------

  ioCapabilityData = object
    capabilityId: int32  # NOT exported — prevents external construction

  IOCapability* = distinct ioCapabilityData
    ## Sealed I/O permission token. Cannot be forged outside this module
    ## because the internal field is not exported (Nim module visibility).
    ## Only `createIOCapability()` can construct one, and it requires
    ## `{.axiomEffect: IOEffect.}` (I/O context).
    ##
    ## This provides a compile-time guarantee that any function accepting
    ## IOCapability was called from an I/O context.
var nextCapabilityId {.threadvar.}: int32

# ---------------------------------------------------------------------------
# SystemExecutor — Actual I/O execution (boundary)
# ---------------------------------------------------------------------------
type
  SystemExecutor* = object
    ## Real process executor. Satisfies IoExecutor.
    ## All I/O is performed here; core logic never touches this type directly.

# ---------------------------------------------------------------------------
# MockExecutor — Test double with pre-configured results
# ---------------------------------------------------------------------------
type
  MockExecutor* = object
    ## Test double that records commands and returns pre-configured results.
    ## Satisfies IoExecutor for testing without real I/O.
    results*: seq[Result[ProcessResult, string]]
    gitResults*: seq[Result[ProcessResult, string]]
    recordedCommands*: seq[ProcessCommand]
    recordedGitCommands*: seq[GitCommand]

checkDiscardResult:
  proc createIOCapability*(): IOCapability =
    ## Create an I/O capability token. Only callable from I/O contexts.
    inc nextCapabilityId
    result = IOCapability(ioCapabilityData(capabilityId: nextCapabilityId))
  func isValid*(cap: IOCapability): bool {.inline, raises: [].} =
    ## Check if a capability is valid (non-zero ID).
    ioCapabilityData(cap).capabilityId != 0
  func `$`*(cap: IOCapability): string {.raises: [].} =
    ## String representation (does not reveal internal ID).
    if cap.isValid(): "IOCapability(valid)"
    else: "IOCapability(invalid)"

  # ---------------------------------------------------------------------------
  # GitCommand helpers
  # ---------------------------------------------------------------------------
  func `==`*(a, b: GitCommand): bool {.inline, raises: [].} =
    ## Equality for GitCommand distinct type.
    let pa = cast[ptr ProcessCommand](unsafeAddr a)
    let pb = cast[ptr ProcessCommand](unsafeAddr b)
    pa.program == pb.program and pa.args == pb.args and
      pa.workingDir == pb.workingDir
  func `$`*(gc: GitCommand): string {.inline, raises: [].} =
    ## String representation of a GitCommand as "program arg1 arg2 ...".
    let pc = ProcessCommand(gc)
    if pc.args.len > 0:
      pc.program & " " & pc.args.join(" ")
    else:
      pc.program
  func toGitCommand*(cmd: ProcessCommand): GitCommand {.inline, raises: [].} =
    ## Wrap a ProcessCommand as a GitCommand.
    GitCommand(cmd)
  func toProcessCommand*(cmd: GitCommand): ProcessCommand {.inline, raises: [].} =
    ## Unwrap a GitCommand to ProcessCommand.
    ProcessCommand(cmd)
  func gitCmd*(program: string = "git", args: seq[string] = @[],
               workingDir: string = "",
               env: seq[(string, string)] = @[]): GitCommand {.inline, raises: [].} =
    ## Construct a GitCommand with defaults for the git program.
    GitCommand(ProcessCommand(program: program, args: args,
                              workingDir: workingDir, env: env))

  # ---------------------------------------------------------------------------
  # SystemExecutor — Actual I/O execution (boundary)
  # ---------------------------------------------------------------------------
  func newSystemExecutor*(): SystemExecutor {.raises: [].} =
    ## Construct a SystemExecutor (no configuration needed).
    SystemExecutor()
  proc execute*(e: SystemExecutor, cmd: ProcessCommand): Result[ProcessResult, string]
      {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    ## Execute a process command via execCmdEx.
    let opts = {poStdErrToStdOut, poEvalCommand}
    var envTable = newStringTable(modeCaseSensitive)
    for (k, v) in cmd.env:
      envTable[k] = v
    let env = if cmd.env.len > 0: envTable else: nil
    try:
      let (output, exitCode) = execCmdEx(cmd.program & " " & cmd.args.join(" "),
        workingDir = cmd.workingDir, env = env, options = opts)
      ok(ProcessResult(stdout: output, exitCode: exitCode))
    except CatchableError as exc:
      err("execute failed: " & exc.msg)
  proc executeGit*(e: SystemExecutor, cmd: GitCommand): Result[ProcessResult, string]
      {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    ## Execute a git command via ProcessCommand dispatch.
    e.execute(ProcessCommand(cmd))

  # ---------------------------------------------------------------------------
  # MockExecutor — Test double with pre-configured results
  # ---------------------------------------------------------------------------
  func newMockExecutor*(): MockExecutor {.raises: [].} =
    ## Construct an empty MockExecutor.
    MockExecutor()
  func pushResult*(e: var MockExecutor, r: Result[ProcessResult, string])
      {.raises: [].} =
    ## Enqueue a pre-configured result for the next execute() call.
    e.results.add(r)
  func pushGitResult*(e: var MockExecutor, r: Result[ProcessResult, string])
      {.raises: [].} =
    ## Enqueue a pre-configured result for the next executeGit() call.
    e.gitResults.add(r)
  func execute*(e: var MockExecutor, cmd: ProcessCommand): Result[ProcessResult, string] {.raises: [].} =
    ## Execute a process command by popping from the results queue.
    ## Records the command and returns the next queued result, or a default success.
    e.recordedCommands.add(cmd)
    if e.results.len > 0:
      let r = e.results[0]
      e.results.delete(0)
      return r
    else:
      return ok(ProcessResult(stdout: "", exitCode: 0))
  func executeGit*(e: var MockExecutor, cmd: GitCommand): Result[ProcessResult, string] {.raises: [].} =
    ## Execute a git command by popping from the git results queue.
    ## Records the command and returns the next queued result, or a default success.
    e.recordedGitCommands.add(cmd)
    if e.gitResults.len > 0:
      let r = e.gitResults[0]
      e.gitResults.delete(0)
      return r
    else:
      return ok(ProcessResult(stdout: "", exitCode: 0))
