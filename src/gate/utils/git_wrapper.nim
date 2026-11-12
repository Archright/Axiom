import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## git_wrapper — Layer 1+2 command policy enforcement (execution layer)
##
## Intercepts ALL git calls, checks the subcommand against a compile-time
## blocked list derived from `data/command_policy.json`, and either blocks
## or delegates to the real git binary.
##
## Design: AGENTS.md §2 mandates "no direct `git merge`/`git rebase`".
## This wrapper enforces that policy at the execution layer.
##
## Patches incorporated:
##   Patch 5  — commandLineParams() for structured argv
##   Patch 6  — Real git binary discovery (avoids self-referential symlink)
##   Patch 7  — Git alias resolution via `git config --get alias.<name>`
##   Patch 12 — envp whitelist (blocks GIT_SSH_COMMAND, LD_PRELOAD, etc.)
##
## Compile:
##   nim c -d:release src/gate/utils/git_wrapper.nim
##
## Deployment:
##   Place in PATH *before* the real `git`, or symlink as `/usr/local/bin/git`.
##   The real binary should be at `/usr/bin/git.real` or discoverable via PATH.

import core/axiom_pragmas
import core/interfaces/git_operations
import std/[os, osproc, strutils, strformat, json, macros, strtabs]
import ./git_state
import infrastructure/logging_facade

# ---------------------------------------------------------------------------
# Compile-time policy embedding
# ---------------------------------------------------------------------------

macro buildBlockedList(): untyped =
  ## Reads data/command_policy.json at compile time and extracts blocked
  ## subcommands for the "git" tool. Returns a Nim seq literal AST.
  const policyJson = staticRead("../../data/command_policy.json")
  let policy = parseJson(policyJson)
  var blocked: seq[string]
  for p in policy["policies"]:
    if p["tool"].getStr() == "git":
      for sub in p["blockedSubcommands"]:
        blocked.add(sub.getStr())
  result = newLit(blocked)

## Blocked git subcommands — SSOT: data/command_policy.json
## AGENTS.md §2: merge/rebase blocked; use the project sync mechanism.
const BlockedSubcommands* = buildBlockedList()

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  WrapperTag = "[git-wrapper]"

  ## Flags that consume the next argv element as their argument.
  ## When walking argv to find the true subcommand, these are skipped
  ## along with their operand.
  ##
  ## Verified against official git documentation (Context7 / git-htmldocs):
  ##   - Global: -C, -c, --git-dir, --work-tree, --namespace, --super-prefix
  ##   - rebase: --onto, --exec, --strategy, -X, --strategy-option, --empty
  ##   - merge: -m, --message, --strategy, -X, --strategy-option, --cleanup
  ##   - cherry-pick: -m, --mainline, --strategy, -X, --strategy-option, --cleanup, --empty
  ##   - revert: -m, --mainline, --strategy, -X, --strategy-option
  ##   - am: --whitespace, -p, --directory, --exclude, --include, --patch-format
  ##
  ## Excluded (boolean / =-only / optional-arg flags):
  ##   --root, --rebase-merges, --autostash, --keep-empty, --signoff,
  ##   --rerere-autoupdate, --force-if-includes, --gpg-sign (=-only),
  ##   -S (optional arg), --log (optional arg), --empty= (=-only alias)
  # Global: -C, -c, --git-dir, --work-tree, --namespace, --super-prefix
  # Shared strategy: --strategy, --strategy-option, -X
  # rebase: --onto, --exec, --empty
  # merge/cherry-pick/revert: -m, --message, --mainline, --cleanup
  # am: --whitespace, -p, --directory, --exclude, --include, --patch-format
  FlagsWithArgs: array[22, string] = [
    "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix",
    "--strategy", "--strategy-option", "-X",
    "--onto", "--exec", "--empty",
    "-m", "--message", "--mainline", "--cleanup",
    "--whitespace", "-p", "--directory", "--exclude", "--include",
    "--patch-format"
  ]

  ## Environment variables blocked for security (Patch 12).
  ## These could be used to inject arbitrary commands or alter git
  ## behavior in ways that bypass the wrapper's policy enforcement.
  BlockedEnvVars: array[8, string] = [
    "GIT_EXTERNAL_DIFF",
    "GIT_SSH_COMMAND",
    "GIT_PAGER",
    "GIT_EDITOR",
    "PAGER",
    "LD_PRELOAD",
    "LD_LIBRARY_PATH",
    "DYLD_INSERT_LIBRARIES",
  ]

# ---------------------------------------------------------------------------
# Subcommand extraction (Patch 5: clean argv from commandLineParams)
# ---------------------------------------------------------------------------

func getTrueSubcommand(argv: seq[string]): string =
  ## Walks argv to find the first positional argument (the subcommand),
  ## skipping flags and their arguments. Returns "" if no subcommand
  ## is found (e.g., bare `git` invocation).
  var i = 0
  while i < argv.len:
    let arg = argv[i]
    if arg == "--":
      # End-of-options marker; next arg (if any) is the subcommand
      inc i
      if i < argv.len:
        return argv[i]
      return ""
    if arg.startsWith("-"):
      if arg in FlagsWithArgs:
        inc i  # skip the option's argument
    else:
      return arg
    inc i
  return ""

# ---------------------------------------------------------------------------
# Git alias resolution (Patch 7)
# ---------------------------------------------------------------------------

proc resolveGitAlias(subcmd: string, realGit: string): string {.axiomEffect: IOEffect.} =
  ## If `subcmd` is a git alias, resolves it to the underlying command.
  ## On failure, returns the original subcmd unchanged (fail-open for
  ## resolution; the blocked-list check still applies to the alias name).
  if subcmd.len == 0 or subcmd.startsWith("-"):
    return subcmd
  try:
    let (output, exitCode) = git_operations.runGitEx(realGit, "config --get alias." & subcmd)
    if exitCode == 0 and output.strip().len > 0:
      let resolved = output.strip().split({' ', '\t'})
      if resolved.len > 0:
        return resolved[0]
  except CatchableError:
    discard  # alias resolution failure = keep original  # axiom:best-effort(ioboundary catch)
  return subcmd

# ---------------------------------------------------------------------------
# Environment sanitization (Patch 12)
# ---------------------------------------------------------------------------

proc sanitizeEnv(): StringTableRef {.axiomEffect: IOEffect.} =
  ## Builds a clean environment variable table that strips out variables
  ## which could be used to hijack git execution or leak secrets.
  ## All other environment variables are passed through unchanged.
  result = newStringTable(modeCaseSensitive)
  for key, val in envPairs():
    var blocked = false
    for b in BlockedEnvVars:
      if key == b:
        blocked = true
        break
    if not blocked:
      result[key] = val

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

proc main() {.axiomEffect: IOEffect.} =
  ## Layer 1+2 enforcement: state-based policy via GitContext.
  ## All errors lead to quit(2) (Fail-Closed).
  let argv = commandLineParams()

  # --- Locate real git binary ---
  let realGit = git_operations.findRealGit()
  if realGit.len == 0:
    logError("git_wrapper", WrapperTag & " ERROR: real git binary not found")
    logInfo("git_wrapper", WrapperTag & " Searched: /usr/bin/git.real, /usr/bin/git, PATH")
    quit(2)

  # --- Detect Git state (filesystem-based, no execProcess) ---
  let ctx = detectGitContext()

  # --- Extract subcommand from argv ---
  let rawSubcmd = getTrueSubcommand(argv)
  if rawSubcmd.len == 0:
    discard  # bare `git` — let real git handle it

  # --- Resolve aliases ---
  let subcmd = resolveGitAlias(rawSubcmd, realGit)

  # --- State-based policy evaluation ---
  case ctx.state
  of gsContextFree:
    if subcmd in BlockedSubcommands:
      logError("git_wrapper", fmt"{WrapperTag} BLOCKED: 'git {subcmd}' is prohibited by command policy")
      quit(2)
  of gsRebasing, gsRebasingConflict:
    if not isRebaseResolutionCommand(argv):
      logError("git_wrapper", fmt"{WrapperTag} BLOCKED: 'git {subcmd}' during rebase state")
      logInfo("git_wrapper", fmt"{WrapperTag}   Allowed: git rebase --continue|--abort|--skip|--quit")
      quit(2)
  of gsMerging:
    if not isMergeResolutionCommand(argv):
      logError("git_wrapper", fmt"{WrapperTag} BLOCKED: 'git {subcmd}' during merge state")
      logInfo("git_wrapper", fmt"{WrapperTag}   Allowed: git merge --continue|--abort|--quit")
      quit(2)
  of gsCherryPick:
    if not isResolutionCommand(argv, gsCherryPick):
      logError("git_wrapper", fmt"{WrapperTag} BLOCKED: 'git {subcmd}' during cherry-pick state")
      quit(2)
  of gsReverting:
    if not isResolutionCommand(argv, gsReverting):
      logError("git_wrapper", fmt"{WrapperTag} BLOCKED: 'git {subcmd}' during revert state")
      quit(2)
  of gsBisecting:
    # Bisect has no resolution commands — allow all
    discard

  # --- Delegate to real git with sanitized environment ---
  # [WARN] Exception safety: entire delegation wrapped in try...except
  # to prevent exit code loss on signal/interrupt
  try:
    let cleanEnv = sanitizeEnv()
    var p = startProcess(
      realGit,
      args = argv,
      options = {poParentStreams},
      env = cleanEnv
    )
    defer: p.close()
    quit(p.waitForExit())
  except CatchableError as e:
    logError("git_wrapper", fmt"{WrapperTag} FAIL-CLOSED: delegation error: {e.msg}")
    quit(2)

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------

when isMainModule:
  try:
    main()
  except CatchableError as e:
    logError("git_wrapper", fmt"{WrapperTag} FAIL-CLOSED: unhandled error: {e.msg}")
    quit(2)

{.pop.}
