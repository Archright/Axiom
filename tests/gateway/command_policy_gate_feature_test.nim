{.push raises: [CatchableError].}

## Command Policy Gate Feature Test.
## See tests/features/command_policy_gate.feature for the specification.
##
## Validates the standalone CLI command policy validator (Layer 0).
## Tests observable behavior: exit codes and stderr content against
## compiled binary at build/command_policy_gate.

import std/[os, osproc, strutils, unittest]

const
  projectRoot = currentSourcePath().parentDir().parentDir().parentDir()
  gateBin = projectRoot / "build" / "command_policy_gate"

proc runGate(testCmd: string): (string, int) =
  let fullCmd = gateBin & " --test-command=" & quoteShell(testCmd)
  result = execCmdEx(fullCmd)

{.push warning[BareExcept]:off.}
suite "command policy gate — CLI validator":
  # -- blocked subcommands --

  test "git merge is blocked":
    let (output, exitCode) = runGate("git merge main")
    check exitCode == 2
    check "BLOCKED" in output

  test "git rebase is blocked":
    let (output, exitCode) = runGate("git rebase HEAD~3")
    check exitCode == 2
    check "BLOCKED" in output

  test "git cherry-pick is blocked":
    let (output, exitCode) = runGate("git cherry-pick abc123")
    check exitCode == 2
    check "BLOCKED" in output

  test "git revert is blocked":
    let (output, exitCode) = runGate("git revert HEAD")
    check exitCode == 2
    check "BLOCKED" in output

  # -- allowed subcommands --

  test "git status is allowed":
    let (output, exitCode) = runGate("git status")
    check exitCode == 0
    check "BLOCKED" notin output

  test "git push is allowed":
    let (output, exitCode) = runGate("git push origin main")
    check exitCode == 0
    check "BLOCKED" notin output

  # -- shell injection defense --

  test "shell control operator chaining is blocked":
    let (output, exitCode) = runGate("git status && git merge main")
    check exitCode == 2
    check "BLOCKED" in output

  test "dynamic syntax $(...) is blocked":
    let (output, exitCode) = runGate("git $(whoami) status")
    check exitCode == 2
    check "dynamic syntax" in output

  # -- flag-before-subcommand --

  test "git -C /tmp merge is blocked (flag before subcommand)":
    let (output, exitCode) = runGate("git -C /tmp merge main")
    check exitCode == 2
    check "BLOCKED" in output
{.pop.}
{.pop.}
