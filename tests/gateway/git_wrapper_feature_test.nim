{.push raises: [CatchableError].}

## Git Wrapper Feature Test.
## See tests/features/git_wrapper.feature for the specification.
##
## Validates the execution-layer git wrapper (Layer 1+2).
## Tests observable behavior: exit codes and stderr content against
## compiled binary at build/git_wrapper.

import std/[os, osproc, strutils, unittest]

const
  projectRoot = currentSourcePath().parentDir().parentDir().parentDir()
  wrapperBin = projectRoot / "build" / "git_wrapper"

proc runWrapper(args: string): (string, int) =
  let fullCmd = wrapperBin & " " & args
  result = execCmdEx(fullCmd)

{.push warning[BareExcept]:off.}
suite "git wrapper — execution layer":
  # -- blocked subcommands --

  test "git_wrapper merge is blocked":
    let (output, exitCode) = runWrapper("merge main")
    check exitCode == 2
    check "BLOCKED" in output

  test "git_wrapper rebase is blocked":
    let (output, exitCode) = runWrapper("rebase HEAD~3")
    check exitCode == 2
    check "BLOCKED" in output

  test "git_wrapper cherry-pick is blocked":
    let (output, exitCode) = runWrapper("cherry-pick abc123")
    check exitCode == 2
    check "BLOCKED" in output

  test "git_wrapper revert is blocked":
    let (output, exitCode) = runWrapper("revert HEAD")
    check exitCode == 2
    check "BLOCKED" in output

  # -- allowed subcommands --

  test "git_wrapper status delegates to real git":
    let (output, exitCode) = runWrapper("status")
    check exitCode == 0
    check "BLOCKED" notin output

  test "git_wrapper log delegates to real git":
    let (output, exitCode) = runWrapper("log --oneline -5")
    check exitCode == 0
    check "BLOCKED" notin output

  # -- flag-before-subcommand --

  test "git_wrapper -C . log works (flag before subcommand)":
    let (output, exitCode) = runWrapper("-C . log --oneline -3")
    check exitCode == 0
    check "BLOCKED" notin output
{.pop.}
{.pop.}
