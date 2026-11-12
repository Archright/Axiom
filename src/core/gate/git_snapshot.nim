import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

## Git Snapshot Value Object
##
## Captures git state once at orchestrator startup, eliminating redundant
## subprocess calls across gates. Immutable value object — safe to pass
## across function boundaries without mutation concerns.
##
## Subprocess budget: 2 git calls (rev-parse HEAD + diff --cached).
## Eliminates per-gate `git rev-parse HEAD` and `git diff` calls.

import std/[osproc, strutils, sequtils]
import ../trusted/env_access

type
  GitSnapshot* = object
    head*: string           ## Commit SHA from `git rev-parse HEAD`
    treeHash*: string       ## Staged index Merkle root from `git write-tree`
    stagedFiles*: seq[string]  ## Staged file names (git diff --name-only --cached)
    unstagedFiles*: seq[string] ## Unstaged file names (git diff --name-only)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc captureGitOutput(cmd: string): string {.raises: [].} =
  ## Run a git command and return stripped stdout. Returns "" on failure.
  try:
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0: ""
    else: output.strip()
  except CatchableError:
    ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc captureGitOutputInDir(cmd: string; workingDir: string): string {.raises: [].} =
  ## Run a git command in `workingDir` and return stripped stdout. "" on failure.
  try:
    let (output, exitCode) = execCmdEx(cmd, workingDir = workingDir)
    if exitCode != 0: ""
    else: output.strip()
  except CatchableError:
    ""

const emptyTreeOid* = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
  ## The well-known git empty-tree object OID. Fallback for `git write-tree`
  ## when the index is absent or unreadable — the staged axis then binds to the
  ## deterministic empty state instead of an unknowable one.

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc stagedTreeOid*(workingDir: string = ""): string {.raises: [].} =
  ## Staged-index axis: `git write-tree` OID for the current index.
  ## DEBT#471: memo consumers fold this into judgment-input closures so that
  ## staging different content yields a different key even when the worktree
  ## is byte-identical. Falls back to the empty-tree OID on git failure —
  ## deterministic for identical inputs, never nondeterministic.
  let treeOid = if workingDir.len > 0:
    captureGitOutputInDir("git write-tree", workingDir)
  else:
    captureGitOutput("git write-tree")
  if treeOid.len > 0: treeOid else: emptyTreeOid

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc captureGitLines(cmd: string): seq[string] =
  ## Run a git command and return non-empty lines. Returns @[] on failure.
  let raw = captureGitOutput(cmd)
  if raw.len == 0: @[]
  else: raw.splitLines().filterIt(it.len > 0)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc newGitSnapshot*(): GitSnapshot =
  ## Capture all git state in a single construction call.
  ## Internally makes 2 git subprocess calls:
  ##   1. git rev-parse HEAD (commit hash)
  ##   2. git diff --name-only [--cached | baseRef...HEAD] (staged files)
  ## Plus 1 call for unstaged files.
  result.head = captureGitOutput("git rev-parse HEAD")
  result.treeHash = captureGitOutput("git write-tree")

  let baseRef = getAxiomEnv(evCiBaseRef)
  let stagedCmd = if baseRef.len > 0:
    "git diff --name-only " & baseRef & "...HEAD"
  else:
    "git diff --name-only --cached"
  result.stagedFiles = captureGitLines(stagedCmd)
  result.unstagedFiles = captureGitLines("git diff --name-only")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isClean*(snap: GitSnapshot): bool {.raises: [].} =
  ## True if no unstaged changes exist.
  snap.unstagedFiles.len == 0

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func hasStagedChanges*(snap: GitSnapshot): bool {.raises: [].} =
  ## True if there are staged files.
  snap.stagedFiles.len > 0

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func headShort*(snap: GitSnapshot): string {.raises: [].} =
  ## First 8 characters of HEAD commit hash. Empty if no HEAD.
  if snap.head.len >= 8: snap.head[0 ..< 8]
  else: snap.head

{.pop.}
