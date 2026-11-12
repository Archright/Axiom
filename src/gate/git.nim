import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Git Integration Helpers
##
## Provides git operations used by gate runners:
## - ``gitDiffCachedNames`` — staged file list for incremental gates
## - Diff parsing for change detection
##
## All git subprocess calls delegate to git_operations.nim (SSOT).

import std/os
import std/osproc
import std/strutils
import std/sequtils
import core/interfaces/git_operations
import core/axiom_pragmas
import core/trusted/env_access

let gitExe = git_operations.findRealGit()

# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
proc gitDiffCachedNames*(): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let baseRef = getAxiomEnv(evCiBaseRef)
  let cmd = if baseRef.len > 0:
    "diff --name-only " & baseRef & "...HEAD"
  else:
    "diff --name-only --cached"
  let (output, exitCode) = git_operations.runGitEx(gitExe, cmd)
  if exitCode != 0:
    return @[]
  result = output.splitLines().filterIt(it.len > 0)

# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
proc gitDiffCachedPatch*(paths: openArray[string] = ["src", "src/semantic_proofs", "lakefile.toml", "lean-toolchain", "axiom.nimble", "config.nims"]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let (output, _) = git_operations.runGitEx(gitExe, "diff --cached --unified=0 -- " & paths.join(" "))
  output

# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
proc gitUnstagedNames*(): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let (output, exitCode) = git_operations.runGitEx(gitExe, "diff --name-only")
  if exitCode != 0:
    return @[]
  result = output.splitLines().filterIt(it.len > 0)

# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
proc hasUnstagedChanges*(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  gitUnstagedNames().len > 0

# @axiom-hint: lean="path.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len path) 0) external_io_isolated))"
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
proc gitStage*(path: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  discard git_operations.runGitEx(gitExe, "add " & quoteShell(path))
{.pop.}
