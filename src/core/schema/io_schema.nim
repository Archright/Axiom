import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/json
import std/tables
import std/times
import core/types/results
type
  ProcessExitCode* = distinct int
    ## Exit code from a subprocess. Distinct from raw int to prevent
    ## accidental arithmetic on exit codes.

  DurationMs* = distinct int64
    ## Duration in milliseconds. Prevents mixing with raw int64.

  FilePath* = distinct string
    ## Filesystem path. Prevents accidental string concatenation.

  CommandString* = distinct string
    ## A shell command string. Prevents mixing with file paths or args.
type
  ProcessOptions* = object
    ## Configuration for process execution behavior.
    captureOutput*: bool
      ## Whether to capture stdout/stderr.
    allowNonZeroExit*: bool
      ## If true, non-zero exit codes are not treated as errors.
    input*: string
      ## Stdin content to pipe into the process.
    workingDir*: FilePath
      ## Working directory for the process.
    extraEnv*: Table[string, string]
      ## Additional environment variables.
    excludedEnvKeys*: seq[string]
      ## Environment keys to exclude from the child process.
type
  ProcessCommand* = object
    ## A complete description of a process to execute.
    cmd*: CommandString
      ## The command binary or shell command.
    args*: seq[string]
      ## Command-line arguments.
    options*: ProcessOptions
      ## Execution options.
    description*: string
      ## Human-readable description for logging.
    retries*: int
      ## Number of retry attempts on failure. 0 = no retries.
    binaryOk*: bool
      ## If true, cmd refers to a binary on PATH (not a shell command).
    isHelp*: bool
      ## If true, this is a help/usage invocation (output is informational).
type
  ProcessResult* = object
    ## Result of a process execution.
    exitCode*: ProcessExitCode
      ## Process exit code.
    stdout*: string
      ## Captured stdout content.
    stderr*: string
      ## Captured stderr content.
    command*: string
      ## The command that was executed (for logging/audit).
    durationMs*: DurationMs
      ## Wall-clock time in milliseconds.
    timedOut*: bool
      ## Whether the process was killed due to timeout.
    captured*: bool
      ## Whether output was captured (matches ProcessOptions.captureOutput).
    duration*: Duration
      ## Nim Duration object for precise time arithmetic.
type
  GitCommand* = enum
    ## Exhaustive enumeration of all git operations the system may invoke.
    ## SSOT for git command routing — new operations MUST be added here first.
    gcMerge = "merge"
    gcSquash = "squash"
    gcRebase = "rebase"
    gcBranch = "branch"
    gcDeleteBranch = "delete-branch"
    gcCherryPick = "cherry-pick"
    gcReset = "reset"
    gcCreateWorktree = "create-worktree"
    gcRemoveWorktree = "remove-worktree"
    gcStatus = "status"
    gcCommit = "commit"
    gcStage = "stage"
    gcUnstage = "unstage"
    gcStash = "stash"
    gcStashPop = "stash-pop"
    gcResolveStart = "resolve-start"
    gcResolveAccept = "resolve-accept"
    gcResolveAbort = "resolve-abort"
    gcIgnore = "ignore"
    gcSetRef = "set-ref"
    gcPush = "push"
    gcBranchReady = "branch-ready"
    gcBranchCleanup = "branch-cleanup"
    gcGetCurrentRef = "get-current-ref"
    gcIsAncestor = "is-ancestor"
type
  IoExecutor* = concept T
    ## Typeclass for anything that can execute process commands.
    ## Implementations provide the actual I/O (OS process, sandbox, mock).
    execute(T, ProcessCommand) is Result[ProcessResult, string]
type
  GitOpsResult* = Result[string, string]
    ## Result of a git operation: Ok on success with output, Err on failure.

  GitOperations* = concept T
    ## Typeclass for git operation providers.
    ## Abstracts git CLI behind a typed interface.
    merge(T, string) is GitOpsResult
    squash(T, string, string) is GitOpsResult
    rebaseOnto(T, string, string) is GitOpsResult
    deleteBranch(T, string) is GitOpsResult
    deleteWorktree(T, string) is GitOpsResult
type
  SandboxSpec* = object
    ## Resource constraints for sandboxed execution.
    tags*: seq[string]
      ## Semantic tags for routing (e.g., "lean", "z3", "git").
    resourceClass*: string
      ## Resource tier (e.g., "small", "medium", "large").
    baselineBytes*: int
      ## Baseline memory allocation in bytes.
    perOpBytes*: seq[int]
      ## Per-operation memory increments in bytes.
    perOpSeconds*: seq[int]
      ## Per-operation time limits in seconds.
    networking*: bool
      ## Whether network access is permitted.
    baselineSeconds*: int
      ## Baseline time limit in seconds.
    perOpBytesBurst*: int
      ## Burst memory allowance in bytes.
    perOpSecondsBurst*: int
      ## Burst time allowance in seconds.
func toJson*(opts: ProcessOptions): JsonNode {.raises: [].} =
  ## Serialize ProcessOptions to JsonNode.
  result = newJObject()
  result["captureOutput"] = newJBool(opts.captureOutput)
  result["allowNonZeroExit"] = newJBool(opts.allowNonZeroExit)
  result["input"] = newJString(opts.input)
  result["workingDir"] = newJString(opts.workingDir.string)
  let envNode = newJObject()
  for k, v in opts.extraEnv:
    envNode[k] = newJString(v)
  result["extraEnv"] = envNode
  let exclNode = newJArray()
  for k in opts.excludedEnvKeys:
    exclNode.add(newJString(k))
  result["excludedEnvKeys"] = exclNode
func fromJsonProcessOptions*(node: JsonNode): ProcessOptions {.raises: [].} =
  ## Deserialize ProcessOptions from JsonNode.
  result = ProcessOptions()
  block:
    let n = node{"captureOutput"}
    if n != nil: result.captureOutput = n.getBool()
  block:
    let n = node{"allowNonZeroExit"}
    if n != nil: result.allowNonZeroExit = n.getBool()
  block:
    let n = node{"input"}
    if n != nil: result.input = n.getStr()
  block:
    let n = node{"workingDir"}
    if n != nil: result.workingDir = FilePath(n.getStr())
  block:
    let n = node{"extraEnv"}
    if n != nil:
      for k, v in n.pairs:
        result.extraEnv[k] = v.getStr()
  block:
    let n = node{"excludedEnvKeys"}
    if n != nil:
      for item in n:
        result.excludedEnvKeys.add(item.getStr())
func fromJsonProcessCommand*(node: JsonNode): ProcessCommand {.raises: [].} =
  ## Deserialize ProcessCommand from JsonNode.
  result = ProcessCommand()
  block:
    let n = node{"cmd"}
    if n != nil: result.cmd = CommandString(n.getStr())
  block:
    let n = node{"args"}
    if n != nil:
      for item in n:
        result.args.add(item.getStr())
  block:
    let n = node{"options"}
    if n != nil: result.options = fromJsonProcessOptions(n)
  block:
    let n = node{"description"}
    if n != nil: result.description = n.getStr()
  block:
    let n = node{"retries"}
    if n != nil: result.retries = n.getInt()
  block:
    let n = node{"binaryOk"}
    if n != nil: result.binaryOk = n.getBool()
  block:
    let n = node{"isHelp"}
    if n != nil: result.isHelp = n.getBool()
func fromJsonProcessResult*(node: JsonNode): ProcessResult {.raises: [].} =
  ## Deserialize ProcessResult from JsonNode.
  result = ProcessResult()
  block:
    let n = node{"exitCode"}
    if n != nil: result.exitCode = ProcessExitCode(n.getInt())
  block:
    let n = node{"stdout"}
    if n != nil: result.stdout = n.getStr()
  block:
    let n = node{"stderr"}
    if n != nil: result.stderr = n.getStr()
  block:
    let n = node{"command"}
    if n != nil: result.command = n.getStr()
  block:
    let n = node{"durationMs"}
    if n != nil: result.durationMs = DurationMs(n.getInt())
  block:
    let n = node{"timedOut"}
    if n != nil: result.timedOut = n.getBool()
  block:
    let n = node{"captured"}
    if n != nil: result.captured = n.getBool()
func fromJsonSandboxSpec*(node: JsonNode): SandboxSpec {.raises: [].} =
  ## Deserialize SandboxSpec from JsonNode.
  result = SandboxSpec()
  block:
    let n = node{"tags"}
    if n != nil:
      for item in n:
        result.tags.add(item.getStr())
  block:
    let n = node{"resourceClass"}
    if n != nil: result.resourceClass = n.getStr()
  block:
    let n = node{"baselineBytes"}
    if n != nil: result.baselineBytes = n.getInt()
  block:
    let n = node{"perOpBytes"}
    if n != nil:
      for item in n:
        result.perOpBytes.add(item.getInt())
  block:
    let n = node{"perOpSeconds"}
    if n != nil:
      for item in n:
        result.perOpSeconds.add(item.getInt())
  block:
    let n = node{"networking"}
    if n != nil: result.networking = n.getBool()
  block:
    let n = node{"baselineSeconds"}
    if n != nil: result.baselineSeconds = n.getInt()
  block:
    let n = node{"perOpBytesBurst"}
    if n != nil: result.perOpBytesBurst = n.getInt()
  block:
    let n = node{"perOpSecondsBurst"}
    if n != nil: result.perOpSecondsBurst = n.getInt()
func validateProcessOptions*(opts: ProcessOptions): bool {.raises: [].} =
  ## Compile-time or runtime validation of ProcessOptions.
  ## Returns false if the options are inconsistent.
  result = true
  # A non-empty input requires captureOutput to be meaningful
  if opts.input.len > 0 and not opts.captureOutput:
    result = false
  # An excluded key must not appear in extraEnv
  for key in opts.excludedEnvKeys:
    if key in opts.extraEnv:
      result = false
func validateSandboxSpec*(spec: SandboxSpec): bool {.raises: [].} =
  ## Validate sandbox spec invariants.
  result = true
  if spec.tags.len == 0:
    result = false
  if spec.resourceClass.len == 0:
    result = false
  if spec.baselineBytes < 0:
    result = false
  if spec.baselineSeconds < 0:
    result = false
  if spec.perOpBytes.len != spec.perOpSeconds.len:
    result = false
func validateProcessCommand*(cmd: ProcessCommand): bool {.raises: [].} =
  ## Validate process command invariants.
  result = true
  if string(cmd.cmd).len == 0:
    result = false
  if cmd.retries < 0:
    result = false
func `$`*(e: ProcessExitCode): string {.raises: [].} =
  ## String representation of exit code.
  $(int(e))
proc `$`*(e: ProcessExitCode): string {.raises: [].} =
  ## String representation of exit code.
  $(int(e))
func gitCommandName*(gc: GitCommand): string {.raises: [].} =
  ## Return the string representation of a GitCommand.
  ## Equivalent to $gc but explicit for API consumers.
  case gc
  of gcMerge: "merge"
  of gcSquash: "squash"
  of gcRebase: "rebase"
  of gcBranch: "branch"
  of gcDeleteBranch: "delete-branch"
  of gcCherryPick: "cherry-pick"
  of gcReset: "reset"
  of gcCreateWorktree: "create-worktree"
  of gcRemoveWorktree: "remove-worktree"
  of gcStatus: "status"
  of gcCommit: "commit"
  of gcStage: "stage"
  of gcUnstage: "unstage"
  of gcStash: "stash"
  of gcStashPop: "stash-pop"
  of gcResolveStart: "resolve-start"
  of gcResolveAccept: "resolve-accept"
  of gcResolveAbort: "resolve-abort"
  of gcIgnore: "ignore"
  of gcSetRef: "set-ref"
  of gcPush: "push"
  of gcBranchReady: "branch-ready"
  of gcBranchCleanup: "branch-cleanup"
  of gcGetCurrentRef: "get-current-ref"
  of gcIsAncestor: "is-ancestor"

{.pop.}

