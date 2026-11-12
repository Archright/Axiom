import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import core/axiom_pragmas
import infrastructure/hermetic_sandbox
import std/strutils
import infrastructure/logging_facade
proc atomicCommit*(dryRun: bool): int =
  ## Stage all changes and create an atomic signed commit.
  if dryRun:
    echo "ax git atomic: dry-run — would stage + commit + sign"
    return 0

  # Stage all
  let (stageOut, stageCode) = hermeticExec("git", @["add", "-A"])
  if stageCode != 0:
    logError("git_cli", "ax git atomic: git add failed")
    if stageOut.len > 0: logInfo("git_cli", stageOut)
    return 1

  # Check if there are staged changes
  let (_, diffCode) = hermeticExec("git", @["diff", "--cached", "--quiet"])
  if diffCode == 0:
    echo "ax git atomic: nothing to commit"
    return 0

  # Commit with sign
  let (commitOut, commitCode) = hermeticExec("git", @["commit", "-s", "-m", "atomic: staged commit"])
  if commitCode != 0:
    logError("git_cli", "ax git atomic: commit failed")
    if commitOut.len > 0: logInfo("git_cli", commitOut)
    return 1

  echo "ax git atomic: committed successfully"
  return 0

proc isSafeRebaseTarget*(branch: string): bool {.axiomDecision.} =
  ## Command-injection guard for the git sync rebase target.
  ## A branch is safe only if it is a non-empty, single-token name that does
  ## not begin with a dash (option injection), contain whitespace, or contain
  ## path-traversal (`..`). This is the gate that keeps the rebase target on
  ## the whitelisted branch-sync path and never on raw user-supplied input.
  if branch.len == 0 or branch.startsWith("-") or branch.contains(" ") or
     branch.contains(".."):
    return false
  for c in branch:
    if c in Whitespace:
      return false
  return true

proc syncBranch*(dryRun: bool): int {.axiomDecision.} =
  ## Authorized rebase path — bypasses raw git rebase block (command_policy.json)
  ## by design. Keep in sync with AGENTS.md §2.8.
  ## This wrapper is the ONLY approved rebase path; raw `git rebase` stays BLOCKED
  ## (command_policy_gate exit 2) for all other callers.
  ## Deterministic branch maintenance sync: fetch + rebase onto origin/main —
  ## the documented cross-branch flow (rules §2.8 "cross-branch maintenance
  ## sync"; Makefile check-repository-surface: "ax git sync로 계약 이후 main에
  ## 재단골 후 push"). Target is a compile-time constant, never derived from
  ## input. Main landing remains the GitHub native MERGE actuator.
  if dryRun:
    echo "ax git sync: dry-run — would fetch + rebase onto origin/main"
    return 0

  # Get current branch
  let (branchOut, branchCode) = hermeticExec("git", @["rev-parse", "--abbrev-ref", "HEAD"])
  if branchCode != 0:
    logInfo("git_cli", "ax git sync: cannot determine branch")
    return 1
  let branch = branchOut.strip()

  # Sanity guard: operate only from a safe, single-token branch name
  # (the rebase target itself is the constant below — no injection surface).
  if not isSafeRebaseTarget(branch):
    logError("git_cli", "ax git sync: unsafe branch name: " & branch)
    return 1

  # Fetch
  let (fetchOut, fetchCode) = hermeticExec("git", @["fetch", "origin"])
  if fetchCode != 0:
    logError("git_cli", "ax git sync: fetch failed")
    if fetchOut.len > 0: logInfo("git_cli", fetchOut)
    return 1

  # Rebase onto origin/main (whitelisted path — compile-time constant target).
  let (rebaseOut, rebaseCode) = hermeticExec("git", @["rebase", "origin/main"])
  if rebaseCode != 0:
    logError("git_cli", "ax git sync: rebase failed")
    if rebaseOut.len > 0: logInfo("git_cli", rebaseOut)
    return 1

  echo "ax git sync: synced with origin/main"
  return 0
proc runGitCli*(args: seq[string]): int =
  ## Entry point for `ax git` subcommand.
  try:
    var dryRun = false
    var subcommand = ""
    for a in args:
      if a == "--dry-run":
        dryRun = true
      elif a == "atomic" or a == "sync":
        subcommand = a

    case subcommand
    of "atomic":
      return atomicCommit(dryRun)
    of "sync":
      return syncBranch(dryRun)
    else:
      logInfo("git_cli", "ax git: unknown subcommand '" & subcommand & "'")
      logInfo("git_cli", "usage: ax git <atomic|sync> [--dry-run]")
      return 1
  except CatchableError:
    logError("git_cli", "ax git: error: " & getCurrentExceptionMsg())
    return 1
{.pop.}
