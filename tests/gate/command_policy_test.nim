{.push raises: [CatchableError].}

## Command Policy Enforcement Test — Integration tests for L0 command policy
## gate and L1+L2 git wrapper. Validates observable behavior (exit codes +
## stderr content) against compiled binaries.

import std/[os, osproc, strutils, unittest]

const
  projectRoot = currentSourcePath().parentDir().parentDir().parentDir()
  gateBin = projectRoot / "build" / "command_policy_gate"
  wrapperBin = projectRoot / "build" / "git_wrapper"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc runGate(testCmd: string): (string, int) =
  ## Run command_policy_gate with --test-command= flag.
  let fullCmd = gateBin & " --test-command=" & quoteShell(testCmd)
  result = execCmdEx(fullCmd)

proc runWrapper(args: string): (string, int) =
  ## Run git_wrapper with direct arguments.
  let fullCmd = wrapperBin & " " & args
  result = execCmdEx(fullCmd)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

{.push warning[BareExcept]:off.}
suite "command policy enforcement":
  # -- command_policy_gate: prohibited git subcommands (exit 2 + BLOCKED) --

  test "git merge → exit 2, BLOCKED":
    let (output, exitCode) = runGate("git merge main")
    check exitCode == 2
    check "BLOCKED" in output

  test "git rebase → exit 2, BLOCKED":
    let (output, exitCode) = runGate("git rebase HEAD~3")
    check exitCode == 2
    check "BLOCKED" in output

  test "git rebase-interactive → exit 2, BLOCKED":
    let (output, exitCode) = runGate("git rebase-interactive HEAD~3")
    check exitCode == 2
    check "BLOCKED" in output

  test "git cherry-pick → exit 2, BLOCKED":
    let (output, exitCode) = runGate("git cherry-pick abc123")
    check exitCode == 2
    check "BLOCKED" in output

  test "git revert → exit 2, BLOCKED":
    let (output, exitCode) = runGate("git revert HEAD")
    check exitCode == 2
    check "BLOCKED" in output

  test "git am → exit 2, BLOCKED":
    let (output, exitCode) = runGate("git am /tmp/mbox")
    check exitCode == 2
    check "BLOCKED" in output

  # -- command_policy_gate: allowed git subcommands (exit 0) --

  test "git status → exit 0, allowed":
    let (output, exitCode) = runGate("git status")
    check exitCode == 0
    check "BLOCKED" notin output

  test "git log → exit 0, allowed":
    let (output, exitCode) = runGate("git log --oneline -5")
    check exitCode == 0
    check "BLOCKED" notin output

  test "git diff → exit 0, allowed":
    let (output, exitCode) = runGate("git diff HEAD~1")
    check exitCode == 0
    check "BLOCKED" notin output

  # -- command_policy_gate: wrapper-skip / env prefix detection --

  test "env GIT_PAGER=cat git merge → exit 2, BLOCKED (env wrapper skip)":
    let (output, exitCode) = runGate("env GIT_PAGER=cat git merge main")
    check exitCode == 2
    check "BLOCKED" in output

  # -- command_policy_gate: flag before subcommand --

  test "git -C /tmp merge → exit 2, BLOCKED (flag before subcommand)":
    let (output, exitCode) = runGate("git -C /tmp merge main")
    check exitCode == 2
    check "BLOCKED" in output

  # -- command_policy_gate: dynamic syntax (Patch 9 → AST-based) --

  test "git $(whoami) status → exit 2, dynamic syntax in unknown cmd":
    let (output, exitCode) = runGate("git $(whoami) status")
    check exitCode == 2
    check "BLOCKED" in output

  test "git `id` status → exit 2, dynamic syntax (backtick)":
    let (output, exitCode) = runGate("git `id` status")
    check exitCode == 2
    check "BLOCKED" in output

  # -- command_policy_gate: shell chaining (Patch 8) --

  test "git status && git merge → exit 2, BLOCKED (control op)":
    let (output, exitCode) = runGate("git status && git merge main")
    check exitCode == 2
    check "BLOCKED" in output

  # -- git_wrapper: direct binary invocation --

  test "git_wrapper merge → exit 2, BLOCKED":
    let (output, exitCode) = runWrapper("merge main")
    check exitCode == 2
    check "BLOCKED" in output

  test "git_wrapper status → exit 0, delegates to real git":
    let (output, exitCode) = runWrapper("status")
    check exitCode == 0
    check "BLOCKED" notin output

  test "git_wrapper -C . log → exit 0 (flag before subcommand)":
    let (output, exitCode) = runWrapper("-C . log --oneline -3")
    check exitCode == 0
    check "BLOCKED" notin output
{.pop.}
{.pop.}
