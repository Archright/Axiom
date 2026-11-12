import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## DEBT#420: dir_doc_debt_audit_2026-08-17 grounded 304 doc-link findings in
## docs/ — stale/broken documentation cross-references lack a validation gate.

import core/interfaces/git_operations
import core/axiom_pragmas
const debtMarker420 {.axiomDebt: "DEBT#420".} = true
import core/gate/gate_vfs
import core/utils/file_utils
import infrastructure/logger
import std/options
import std/os
import std/strutils
import std/times
import infrastructure/logging_facade


# axiomIoBoundary

let gitExe = git_operations.findRealGit()
const
  AgmdPath = "AGENTS.md"
  RequiredSections = ["§0.", "§1.", "§2.", "§3."]
  RequiredDocs = [
    "docs/agents/architecture.md",
    "docs/agents/core_rules.md",
    "docs/agents/rules_workflow.md",
  ]
  HistoryDir = "docs/history/"
type
  DocCheckResult = enum
    docOk
    docFail
## Check AGENTS.md has all required sections.
proc checkAgentsMdStructure(): DocCheckResult =
  if not fileExists(AgmdPath):
    logError("doc_completeness_gate", "[doc-gate] FAIL — " & $(AgmdPath) & " not found")
    return docFail
  let content = readFileSafe(AgmdPath)
  for section in RequiredSections:
    if section notin content:
      logError("doc_completeness_gate", "[doc-gate] FAIL — AGENTS.md missing section: " & $(section))
      return docFail
  docOk

## Check that key documentation files exist.
proc checkRequiredDocs(): DocCheckResult =
  var missing: seq[string]
  for path in RequiredDocs:
    if not fileExists(path):
      missing.add(path)
  if missing.len > 0:
    for m in missing:
      logError("doc_completeness_gate", "[doc-gate] FAIL — required documentation missing: " & $(m))
    return docFail
  docOk

## Check that key documentation files exist (VFS-aware).
proc checkRequiredDocsVfs(ctx: GateContext): DocCheckResult =
  var missing: seq[string]
  for path in RequiredDocs:
    if not vfsExists(ctx, path):
      missing.add(path)
  if missing.len > 0:
    for m in missing:
      logError("doc_completeness_gate", "[doc-gate] FAIL — required documentation missing (VFS): " & $(m))
    return docFail
  docOk

## Check no merge commit in progress (local-sync discipline; native MERGE lands via the actuator, never in a dirty worktree).
proc checkRebaseOnly(): DocCheckResult =
  if fileExists(".git/MERGE_HEAD"):
    logError("doc_completeness_gate", "[doc-gate] FAIL — merge commit in progress. Local sync uses 'ax git sync'; PR landing happens through the GitHub native MERGE actuator, never a local merge")
    return docFail
  docOk

## Get staged src/*.nim files.
proc getStagedSrcFiles(): seq[string] =
  let (output, exitCode) = git_operations.runGitEx(gitExe, "diff --cached --name-only --diff-filter=ACMR -- 'src/*.nim'")
  if exitCode != 0:
    return @[]
  for line in output.strip().splitLines():
    if line.strip().len > 0 and line.strip().endsWith(".nim"):
      result.add(line.strip())

## Check evidence freshness — if src/ files changed, recent history should exist.
proc checkEvidenceFreshness(): DocCheckResult =
  let changedFiles = getStagedSrcFiles()
  if changedFiles.len == 0:
    return docOk

  # Check if any history file was modified in the last 24 hours
  let now = getTime()
  let oneDayAgo = now - initDuration(hours = 24)
  var recentHistory = false

  if dirExists(HistoryDir):
    for entry in walkDir(HistoryDir):
      if entry.kind == pcFile and entry.path.endsWith(".md"):
        let modTime = getLastModificationTime(entry.path)
        if modTime > oneDayAgo:
          recentHistory = true
          break

  # Check if evidence registry exists and was recently modified
  var recentEvidence = false

  if not recentHistory and not recentEvidence:
    logWarn("doc_completeness_gate", "[doc-gate] WARN — " & $(changedFiles.len) & " src/ files changed but no recent docs/history/ or docs/evidence/ update found")
    logInfo("doc_completeness_gate", "[doc-gate] Consider recording evidence per AGENTS.md §0.5a")
    # Warning only, not blocking (quit 0)
    return docOk

  docOk

## Entry point.
proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var allOk = true

  if checkAgentsMdStructure() == docFail:
    allOk = false

  if checkRequiredDocs() == docFail:
    allOk = false

  if checkRebaseOnly() == docFail:
    allOk = false

  if checkEvidenceFreshness() == docFail:
    allOk = false

  if allOk:
    logger.info("[doc-gate] PASS")
    quit(0)
  else:
    quit(1)
proc checkAgentsMdStructureVfs(ctx: GateContext): DocCheckResult =
  ## VFS-aware: check AGENTS.md structure via VFS.
  if not vfsExists(ctx, AgmdPath):
    logError("doc_completeness_gate", "[doc-gate] FAIL — " & $(AgmdPath) & " not found")
    return docFail
  let content = vfsReadOpt(ctx, AgmdPath).get("")
  for section in RequiredSections:
    if section notin content:
      logError("doc_completeness_gate", "[doc-gate] FAIL — AGENTS.md missing section: " & $(section))
      return docFail
  docOk
proc checkRebaseOnlyVfs(ctx: GateContext): DocCheckResult =
  ## VFS-aware: check no merge commit in progress via VFS.
  if vfsExists(ctx, ".git/MERGE_HEAD"):
    logError("doc_completeness_gate", "[doc-gate] FAIL — merge commit in progress. Local sync uses 'ax git sync'; PR landing happens through the GitHub native MERGE actuator, never a local merge")
    return docFail
  docOk
proc getStagedSrcFilesVfs(ctx: GateContext): seq[string] =
  ## VFS-aware: get staged src/*.nim files via vfsExec.
  let gitResult = vfsExec(ctx, "git", @["diff", "--cached", "--name-only", "--diff-filter=ACMR", "--", "src/*.nim"])
  if gitResult.exitCode != 0:
    return @[]
  for line in gitResult.output.strip().splitLines():
    if line.strip().len > 0 and line.strip().endsWith(".nim"):
      result.add(line.strip())
proc checkEvidenceFreshnessVfs(ctx: GateContext): DocCheckResult =
  ## VFS-aware: check evidence freshness via VFS.
  ## In VFS mode, checks file existence (not timestamps — VFS reflects current state).
  let changedFiles = getStagedSrcFilesVfs(ctx)
  if changedFiles.len == 0:
    return docOk

  var recentHistory = false
  let historyEntries = vfsListDir(ctx, HistoryDir)
  for path in historyEntries:
    if path.endsWith(".md"):
      recentHistory = true
      break

  var recentEvidence = false

  if not recentHistory and not recentEvidence:
    logWarn("doc_completeness_gate", "[doc-gate] WARN — " & $(changedFiles.len) & " src/ files changed but no recent docs/history/ or docs/evidence/ update found")
    logInfo("doc_completeness_gate", "[doc-gate] Consider recording evidence per AGENTS.md §0.5a")
    return docOk

  docOk
proc mainWithVfs*(ctx: GateContext) =
  ## VFS-aware entry point. Documentation checks via VFS.
  var allOk = true
  if checkAgentsMdStructureVfs(ctx) == docFail:
    allOk = false
  if checkRequiredDocsVfs(ctx) == docFail:
    allOk = false
  if checkRebaseOnlyVfs(ctx) == docFail:
    allOk = false
  if checkEvidenceFreshnessVfs(ctx) == docFail:
    allOk = false
  if allOk:
    logger.info("[doc-gate] PASS")
    quit(0)
  else:
    quit(1)

when isMainModule:
  main()

{.pop.}
