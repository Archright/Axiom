import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Workspace Receipt — Deterministic workspace state capture for cross-session SSOT.
##
## Captures the current workspace state as a deterministic receipt containing:
## - baseCommit: current HEAD SHA
## - dirtyHash: hash of diff stat + porcelain status
## - ruleHash: hash of config.nims + architecture_debt.json
## - timestamp: Unix epoch seconds

import std/[strutils, os, times]
import core/crypto/hash_kernel
import core/trusted/axiom_pragmas
import core/interfaces/git_operations

axiomIoBoundary()

type WorkspaceReceipt* = object
  baseCommit*: string
  dirtyHash*: string
  ruleHash*: string
  timestamp*: int64

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc execGit(args: seq[string], repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute a git command at runtime and return stripped stdout.
  ## Delegates to the SSOT in git_operations.nim, preserving empty-string-on-error behavior.
  try:
    let (output, exitCode) = git_operations.runGit(args.join(" "), workingDir = repoRoot)
    if exitCode != 0:
      return ""
    result = output.strip
  except CatchableError:
    result = ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeReceipt*(repoRoot: string): WorkspaceReceipt {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Capture current workspace state as a deterministic receipt.
  result.baseCommit = execGit(@["rev-parse", "HEAD"], repoRoot)
  let diffStat = execGit(@["diff", "--stat"], repoRoot)
  let statusPorcelain = execGit(@["status", "--porcelain"], repoRoot)
  result.dirtyHash = hash_kernel.sha256Hex(diffStat & statusPorcelain)

  # ruleHash with fileExists guard
  var ruleContent = ""
  let configPath = repoRoot / "config.nims"
  let debtPath = repoRoot / "data/architecture_debt.json"
  if fileExists(configPath):
    try:
      ruleContent &= readFile(configPath)
    except IOError:
      discard
  if fileExists(debtPath):
    try:
      ruleContent &= readFile(debtPath)
    except IOError:
      discard
  result.ruleHash = hash_kernel.sha256Hex(ruleContent)
  result.timestamp = int64(epochTime())

{.pop.}
