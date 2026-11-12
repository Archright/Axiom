import core/trusted/layer_declaration


axiomLayer "gate"
{.push raises: [CatchableError].}

import core/interfaces/git_operations
import core/axiom_pragmas
import std/os
import std/strutils
import infrastructure/logging_facade
# axiomIoBoundary

let gitExe = git_operations.findRealGit()
proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if existsEnv("AXIOM_BOOTSTRAP_VERIFY"):
    # Bootstrap sandbox is not a git repo (no .git copied) — unstaged-state
    # check is meaningless there; the real repo runs this gate post-commit.
    logInfo("unstaged_guard", "[unstaged-guard] SKIP (bootstrap sandbox)")
    quit(0)
  let (statusOutput, statusCode) = git_operations.runGitEx(gitExe, "status --porcelain")
  if statusCode != 0:
    quit(statusCode)

  var hasUnstaged = false
  for line in statusOutput.splitLines:
    if line.len < 4:
      continue
    let worktree = line[1]
    if worktree == ' ':
      continue
    var pathRaw = line[3..^1].strip()
    if pathRaw.startsWith("logs/") or pathRaw.endsWith(".tmp") or
       pathRaw.startsWith("nimcache/") or pathRaw.startsWith("build/") or
       pathRaw.startsWith("hooks/"):
      continue
    if pathRaw.startsWith("src/") or pathRaw.startsWith("src/semantic_proofs/") or
       pathRaw.startsWith("tests/") or pathRaw == "lakefile.toml" or
       pathRaw == "lean-toolchain" or pathRaw == "axiom.nimble" or
       pathRaw == "config.nims" or pathRaw == "AGENTS.md":
      logError("unstaged_guard", "Error: Unstaged changes detected in core files: " & pathRaw)
      logInfo("unstaged_guard", "Please 'git add' or 'git stash' your changes before committing.")
      hasUnstaged = true

  if hasUnstaged:
    quit(1)

  logInfo("unstaged_guard", "[unstaged-guard] PASS: no unstaged core files")
  quit(0)

when isMainModule:
  main()

{.pop.}
