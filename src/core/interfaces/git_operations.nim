## Module: src/core/interfaces/git_operations.nim
## SSOT for git operations in Axiom.
##
## Two APIs:
##   1. `runGit` / `runGitEx` — thin wrappers over execCmdEx that PRESERVE
##      exact execCmdEx semantics (trailing newline, poStdErrToStdOut default).
##      These are the LEGACY-COMPATIBLE entry point for all git subprocess calls.
##   2. `LiveGitOps`, `DryRunGitOps`, `MockGitOps` — Result-based, IoC-driven
##      git operations for the composition root.
##
## Three implementations:
##   - LiveGitOps[E: IoExecutor] — delegates to an IoExecutor (injected)
##   - DryRunGitOps — logs commands without executing, always returns success
##   - MockGitOps — returns pre-configured results for testing

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/os
import std/osproc
import std/strutils
import std/strtabs
import core/types/results
import core/interfaces/io_executor

# ---------------------------------------------------------------------------
# SSOT: runGit / runGitEx — canonical git subprocess invocation
# ---------------------------------------------------------------------------
# These are the ONE source of truth for shelling out to git.
# They preserve execCmdEx semantics exactly:
#   - trailing newline in output (do NOT strip)
#   - stderr merged into stdout by default (poStdErrToStdOut)
#   - exitCode returned, not raised

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runGitEx*(gitExe: string; cmd: string; workingDir: string = "";
               env: StringTableRef = nil;
               options: set[ProcessOption] = {poStdErrToStdOut, poUsePath}): tuple[output: string, exitCode: int]
    {.raises: [CatchableError].} =
  ## Execute a git command preserving execCmdEx semantics.
  ## `gitExe` is the git binary path (use findRealGit() or "git").
  ## `cmd` is the full command string, e.g. "rev-parse --short HEAD".
  ## Returns `(output, exitCode)` exactly like execCmdEx.
  execCmdEx(gitExe & " " & cmd, workingDir = workingDir, env = env, options = options)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runGit*(cmd: string; workingDir: string = "";
             env: StringTableRef = nil;
             options: set[ProcessOption] = {poStdErrToStdOut, poUsePath}): tuple[output: string, exitCode: int]
    {.raises: [CatchableError].} =
  ## Execute a git command via the default `"git"` binary.
  ## Preserves execCmdEx semantics exactly.
  execCmdEx("git " & cmd, workingDir = workingDir, env = env, options = options)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc findRealGit*(): string {.raises: [CatchableError].} =
  ## Locates the real git binary, avoiding the git_wrapper symlink.
  ## Priority:
  ##   1. /usr/bin/git.real — container bind-mount convention
  ##   2. /usr/bin/git      — standard location (verified not-self)
  ##   3. PATH lookup        — fallback via findExe, excluding self
  ##
  ## This is the SSOT. Modules under gate/ may import and re-export
  ## for backward compatibility.
  let selfPath = getAppFilename()
  if fileExists("/usr/bin/git.real"):
    return "/usr/bin/git.real"
  if fileExists("/usr/bin/git"):
    try:
      let resolvedSelf = expandFilename(selfPath)
      let resolvedGit = expandFilename("/usr/bin/git")
      if resolvedSelf != resolvedGit:
        return "/usr/bin/git"
    except CatchableError:
      return "/usr/bin/git"
  let pathResult = findExe("git")
  if pathResult.len > 0:
    try:
      let resolvedSelf = expandFilename(selfPath)
      let resolvedFound = expandFilename(pathResult)
      if resolvedSelf != resolvedFound:
        return pathResult
    except CatchableError:
      if pathResult != selfPath:
        return pathResult
  return "git"

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  MergeStrategy* = enum
    ## How to integrate a branch.
    msFastForward     ## --ff-only: fast-forward if possible, fail otherwise
    msMergeCommit     ## --no-ff: always create a merge commit
    msRebase          ## rebase onto target branch
    msSquash          ## --squash: stage changes without committing

  MergeResult* = object
    ## Outcome of a merge/rebase operation.
    stdout*: string
    stderr*: string
    exitCode*: int

  GitExitCode* = distinct int
    ## Distinct int for git exit codes — prevents accidental comparison
    ## with generic integers.

  GitError* = object
    ## Typed git failure. Every field is populated when possible.
    exitCode*: GitExitCode
    stderr*: string
    command*: string       ## The git command that failed
    context*: string       ## Human-readable context (e.g. "merge", "rebase")

  GitOperations* = concept g
    ## Compile-time interface for git operations.
    ## Every method returns Result — no exceptions, no implicit failures.
    g.merge(MergeStrategy, string) is Result[MergeResult, GitError]
    g.rebaseOnto(string, string) is Result[MergeResult, GitError]
    g.updateRef(string, string) is Result[void, GitError]
    g.worktreeAdd(string, string) is Result[void, GitError]
    g.worktreeRemove(string) is Result[void, GitError]
    g.isDirty() is Result[bool, GitError]
    g.currentBranch() is Result[string, GitError]
    g.revParse(string) is Result[string, GitError]
    g.status() is Result[string, GitError]
    g.listFiles() is Result[seq[string], GitError]

  LiveGitOps*[E: IoExecutor] = object
    ## Concrete git operations that delegate I/O to an injected executor.
    ## Generic over E: any type satisfying the IoExecutor concept.
    executor*: E
    workDir*: string

  DryRunGitOps* = object
    ## Preview-mode git operations. Records what would be executed.
    ## Every operation returns a sensible success default.
    log*: seq[ProcessCommand]
    workDir*: string

  MockGitOps* = object
    ## Test double for git operations. Returns pre-configured results
    ## and records all commands for assertion.
    commands*: seq[ProcessCommand]
    mergeResult*: Result[MergeResult, GitError]
    rebaseResult*: Result[MergeResult, GitError]
    updateRefResult*: Result[void, GitError]
    worktreeAddResult*: Result[void, GitError]
    worktreeRemoveResult*: Result[void, GitError]
    isDirtyResult*: Result[bool, GitError]
    currentBranchResult*: Result[string, GitError]
    revParseResult*: Result[string, GitError]
    statusResult*: Result[string, GitError]
    listFilesResult*: Result[seq[string], GitError]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func `==`*(a, b: GitExitCode): bool {.inline, raises: [].} =
  int(a) == int(b)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func `$`*(code: GitExitCode): string {.inline, raises: [].} =
  $(int(code))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func gitError*(exitCode: int; stderr, command, context: string):
    GitError {.inline, raises: [].} =
  GitError(
    exitCode: GitExitCode(exitCode),
    stderr: stderr,
    command: command,
    context: context
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func gitProcessCmd(args: seq[string], workDir: string = ""): ProcessCommand
    {.inline, raises: [].} =
  ProcessCommand(program: "git", args: args, workingDir: workDir)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func okMerge(pr: ProcessResult): Result[MergeResult, GitError]
    {.inline, raises: [].} =
  ok(MergeResult(stdout: pr.stdout, stderr: pr.stderr, exitCode: pr.exitCode))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toGitError(pr: ProcessResult, cmdStr: string, context: string):
    GitError {.inline, raises: [].} =
  GitError(exitCode: GitExitCode(pr.exitCode), stderr: pr.stdout,
           command: cmdStr, context: context)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toGitError(execErr: string, cmdStr: string, context: string):
    GitError {.inline, raises: [].} =
  GitError(exitCode: GitExitCode(-1), stderr: execErr,
           command: cmdStr, context: context)

# ---------------------------------------------------------------------------
# LiveGitOps — Real git operations via injected IoExecutor
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func newLiveGitOps*[E: IoExecutor](executor: E,
                                    workDir: string = ""): LiveGitOps[E]
    {.raises: [].} =
  LiveGitOps[E](executor: executor, workDir: workDir)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func execGit[E: IoExecutor](g: LiveGitOps[E], args: seq[string],
                             context: string): Result[ProcessResult, GitError] =
  let cmd = gitProcessCmd(args, g.workDir)
  let cmdStr = "git " & args.join(" ")
  let r =
    try:
      g.executor.execute(cmd)
    except CatchableError as exc:
      return err(toGitError(exc.msg, cmdStr, context))
  if r.isErr:
    return err(toGitError(r.error, cmdStr, context))
  let pr = r.get()
  if pr.exitCode != 0:
    return err(toGitError(pr, cmdStr, context))
  ok(pr)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func execGitVoid[E: IoExecutor](g: LiveGitOps[E], args: seq[string],
                                 context: string): Result[void, GitError] =
  let r = g.execGit(args, context)
  if r.isErr:
    return err(r.error)
  Result[void, GitError](ok: true)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func execGitString[E: IoExecutor](g: LiveGitOps[E], args: seq[string],
                                   context: string): Result[string, GitError] =
  let r = g.execGit(args, context)
  if r.isErr:
    return err(r.error)
  ok(r.get().stdout.strip())

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func execGitBool[E: IoExecutor](g: LiveGitOps[E], args: seq[string],
                                 context: string): Result[bool, GitError] =
  let r = g.execGit(args, context)
  if r.isErr:
    if r.error.exitCode == GitExitCode(1):
      return ok(false)
    return err(r.error)
  ok(true)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func execGitFiles[E: IoExecutor](g: LiveGitOps[E], args: seq[string],
                                  context: string): Result[seq[string], GitError] =
  let r = g.execGit(args, context)
  if r.isErr:
    return err(r.error)
  var files: seq[string] = @[]
  for line in r.get().stdout.splitLines():
    let s = line.strip()
    if s.len > 0:
      files.add(s)
  ok(files)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func merge*[E: IoExecutor](g: LiveGitOps[E], strategy: MergeStrategy,
                            branch: string): Result[MergeResult, GitError] =
  var args: seq[string]
  case strategy
  of msFastForward: args = @["merge", "--ff-only", branch]
  of msMergeCommit: args = @["merge", "--no-ff", branch]
  of msRebase: args = @["rebase", branch]
  of msSquash: args = @["merge", "--squash", branch]
  let r = g.execGit(args, "merge")
  if r.isErr:
    return err(r.error)
  r.get().okMerge()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func rebaseOnto*[E: IoExecutor](g: LiveGitOps[E], upstream: string,
                                 branch: string): Result[MergeResult, GitError] =
  let r = g.execGit(@["rebase", "--onto", upstream, branch], "rebase-onto")
  if r.isErr:
    return err(r.error)
  r.get().okMerge()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func updateRef*[E: IoExecutor](g: LiveGitOps[E], refname: string,
                                newTarget: string): Result[void, GitError] =
  g.execGitVoid(@["update-ref", refname, newTarget], "update-ref")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func worktreeAdd*[E: IoExecutor](g: LiveGitOps[E], path: string,
                                  branch: string): Result[void, GitError] =
  g.execGitVoid(@["worktree", "add", path, branch], "worktree-add")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func worktreeRemove*[E: IoExecutor](g: LiveGitOps[E],
                                     path: string): Result[void, GitError] =
  g.execGitVoid(@["worktree", "remove", path, "--force"], "worktree-remove")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isDirty*[E: IoExecutor](g: LiveGitOps[E]): Result[bool, GitError] =
  g.execGitBool(@["diff", "--quiet"], "is-dirty")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func currentBranch*[E: IoExecutor](g: LiveGitOps[E]):
    Result[string, GitError] =
  g.execGitString(@["branch", "--show-current"], "current-branch")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func revParse*[E: IoExecutor](g: LiveGitOps[E],
                               refname: string): Result[string, GitError] =
  g.execGitString(@["rev-parse", refname], "rev-parse")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func status*[E: IoExecutor](g: LiveGitOps[E]): Result[string, GitError] =
  g.execGitString(@["status", "--porcelain"], "status")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func listFiles*[E: IoExecutor](g: LiveGitOps[E]):
    Result[seq[string], GitError] =
  g.execGitFiles(@["ls-files"], "list-files")

# ---------------------------------------------------------------------------
# DryRunGitOps — Logs commands without executing, always returns success
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func newDryRunGitOps*(workDir: string = ""): DryRunGitOps {.raises: [].} =
  DryRunGitOps(workDir: workDir)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func merge*(g: var DryRunGitOps, strategy: MergeStrategy,
            branch: string): Result[MergeResult, GitError] {.raises: [].} =
  var args: seq[string]
  case strategy
  of msFastForward: args = @["merge", "--ff-only", branch]
  of msMergeCommit: args = @["merge", "--no-ff", branch]
  of msRebase: args = @["rebase", branch]
  of msSquash: args = @["merge", "--squash", branch]
  g.log.add(gitProcessCmd(args, g.workDir))
  ok(MergeResult(stdout: "", exitCode: 0))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func rebaseOnto*(g: var DryRunGitOps, upstream: string,
                 branch: string): Result[MergeResult, GitError]
    {.raises: [].} =
  g.log.add(gitProcessCmd(@["rebase", "--onto", upstream, branch], g.workDir))
  ok(MergeResult(stdout: "", exitCode: 0))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func updateRef*(g: var DryRunGitOps, refname: string,
                newTarget: string): Result[void, GitError] {.raises: [].} =
  let args = @["update-ref", refname, newTarget]
  g.log.add(gitProcessCmd(args, g.workDir))
  Result[void, GitError](ok: true)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func worktreeAdd*(g: var DryRunGitOps, path: string,
                  branch: string): Result[void, GitError] {.raises: [].} =
  let args = @["worktree", "add", path, branch]
  g.log.add(gitProcessCmd(args, g.workDir))
  Result[void, GitError](ok: true)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func worktreeRemove*(g: var DryRunGitOps,
                     path: string): Result[void, GitError] {.raises: [].} =
  let args = @["worktree", "remove", path, "--force"]
  g.log.add(gitProcessCmd(args, g.workDir))
  Result[void, GitError](ok: true)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isDirty*(g: var DryRunGitOps): Result[bool, GitError] {.raises: [].} =
  g.log.add(gitProcessCmd(@["diff", "--quiet"], g.workDir))
  ok(false)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func currentBranch*(g: var DryRunGitOps): Result[string, GitError]
    {.raises: [].} =
  g.log.add(gitProcessCmd(@["branch", "--show-current"], g.workDir))
  ok("main")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func revParse*(g: var DryRunGitOps,
               refname: string): Result[string, GitError] {.raises: [].} =
  g.log.add(gitProcessCmd(@["rev-parse", refname], g.workDir))
  ok("")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func status*(g: var DryRunGitOps): Result[string, GitError] {.raises: [].} =
  g.log.add(gitProcessCmd(@["status", "--porcelain"], g.workDir))
  ok("")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func listFiles*(g: var DryRunGitOps): Result[seq[string], GitError]
    {.raises: [].} =
  g.log.add(gitProcessCmd(@["ls-files"], g.workDir))
  var empty: seq[string]
  ok(empty)

# ---------------------------------------------------------------------------
# MockGitOps — Returns pre-configured results for testing
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func newMockGitOps*(): MockGitOps {.raises: [].} =
  MockGitOps(
    mergeResult: Result[MergeResult, GitError](ok: true, value: MergeResult(stdout: "", exitCode: 0)),
    rebaseResult: Result[MergeResult, GitError](ok: true, value: MergeResult(stdout: "", exitCode: 0)),
    updateRefResult: Result[void, GitError](ok: true),
    worktreeAddResult: Result[void, GitError](ok: true),
    worktreeRemoveResult: Result[void, GitError](ok: true),
    isDirtyResult: Result[bool, GitError](ok: true, value: false),
    currentBranchResult: Result[string, GitError](ok: true, value: "main"),
    revParseResult: Result[string, GitError](ok: true, value: ""),
    statusResult: Result[string, GitError](ok: true, value: ""),
    listFilesResult: Result[seq[string], GitError](ok: true, value: @[])
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func merge*(g: var MockGitOps, strategy: MergeStrategy,
            branch: string): Result[MergeResult, GitError] {.raises: [].} =
  var args: seq[string]
  case strategy
  of msFastForward: args = @["merge", "--ff-only", branch]
  of msMergeCommit: args = @["merge", "--no-ff", branch]
  of msRebase: args = @["rebase", branch]
  of msSquash: args = @["merge", "--squash", branch]
  g.commands.add(gitProcessCmd(args))
  g.mergeResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func rebaseOnto*(g: var MockGitOps, upstream: string,
                 branch: string): Result[MergeResult, GitError]
    {.raises: [].} =
  g.commands.add(gitProcessCmd(@["rebase", "--onto", upstream, branch]))
  g.rebaseResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func updateRef*(g: var MockGitOps, refname: string,
                newTarget: string): Result[void, GitError] {.raises: [].} =
  g.commands.add(gitProcessCmd(@["update-ref", refname, newTarget]))
  g.updateRefResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func worktreeAdd*(g: var MockGitOps, path: string,
                  branch: string): Result[void, GitError] {.raises: [].} =
  g.commands.add(gitProcessCmd(@["worktree", "add", path, branch]))
  g.worktreeAddResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func worktreeRemove*(g: var MockGitOps,
                     path: string): Result[void, GitError] {.raises: [].} =
  g.commands.add(gitProcessCmd(@["worktree", "remove", path, "--force"]))
  g.worktreeRemoveResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isDirty*(g: var MockGitOps): Result[bool, GitError] {.raises: [].} =
  g.commands.add(gitProcessCmd(@["diff", "--quiet"]))
  g.isDirtyResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func currentBranch*(g: var MockGitOps): Result[string, GitError]
    {.raises: [].} =
  g.commands.add(gitProcessCmd(@["branch", "--show-current"]))
  g.currentBranchResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func revParse*(g: var MockGitOps,
               refname: string): Result[string, GitError] {.raises: [].} =
  g.commands.add(gitProcessCmd(@["rev-parse", refname]))
  g.revParseResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func status*(g: var MockGitOps): Result[string, GitError] {.raises: [].} =
  g.commands.add(gitProcessCmd(@["status", "--porcelain"]))
  g.statusResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func listFiles*(g: var MockGitOps): Result[seq[string], GitError]
    {.raises: [].} =
  g.commands.add(gitProcessCmd(@["ls-files"]))
  g.listFilesResult

{.pop.}
