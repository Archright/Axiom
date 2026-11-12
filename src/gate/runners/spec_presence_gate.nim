import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## spec_presence_gate.nim — BDD Contract Gate (Tier 0)
##
## Pre-commit gate that enforces the "Intent → Spec → Test → Code" workflow
## by verifying that every staged .nim file in src/ has a corresponding
## feature specification or unit/gateway test.
##
## Checks:
##   1. For each staged .nim file in src/, check if spec evidence exists in
##      any of these locations:
##      - tests/features/<name>.feature
##      - tests/unit/<name>_test.nim
##      - tests/gateway/<name>_test.nim
##   2. Matching rule: module name → spec/test name
##      (e.g., src/core/intrinsic_filter.nim →
##        tests/features/intrinsic_filter.feature,
##        tests/unit/intrinsic_filter_test.nim, or
##        tests/gateway/intrinsic_filter_test.nim)
##   3. Allows exceptions for pure refactoring commits (if commit message
##      indicates "refactor" with no functional change intent)
##
## All output to stderr; stdout reserved for pipeline data.
## Exit code 0 = pass, 1 = fail.

import std/[os, osproc, strutils, sets, json]
import core/utils/file_utils
import core/utils/formal_text_diff
import core/gate/gate_vfs
import core/axiom_pragmas
import infrastructure/logging_facade


# axiomIoBoundary

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  SrcPrefix = "src/"
  FeaturesDir = "tests/features/"
  UnitDir = "tests/unit/"
  GatewayDir = "tests/gateway/"
  # GeneratedDir removed in Phase 0 purge (DEBT_REGISTRY §Purge protocol)
  FeatureExt = ".feature"
  NimExt = ".nim"
  TestExt = "_test.nim"
  BaselineFile = "data/spec_presence_baseline.json"

# ---------------------------------------------------------------------------
# Baseline (grandfathered modules without feature specs)
# ---------------------------------------------------------------------------

proc loadBaseline(): HashSet[string] {.axiomEffect: IOEffect.} =
  ## Load grandfathered module names from data/spec_presence_baseline.json.
  ## These are modules that exist in the codebase but don't yet have
  ## corresponding .feature files. The baseline is ratcheted — new modules
  ## must have spec evidence.
  result = initHashSet[string]()
  if not fileExists(BaselineFile):
    return
  try:
    let content = readFile(BaselineFile)
    let json = parseJson(content)
    if json.hasKey("allowed_modules"):
      for item in json["allowed_modules"]:
        result.incl(item.getStr())
  except CatchableError as e:
    logWarn("spec_presence_gate", "[spec-presence-gate] WARN — could not load baseline: " & e.msg)

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

proc execGit(args: openArray[string]): string =
  let cmd = "git " & args.join(" ")
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    return ""
  output.strip(leading = false, trailing = true, chars = Whitespace + Newlines)

proc getStagedNimFilesInSrc(): seq[string] =
  ## Get all staged .nim files under src/ directory.
  let raw = execGit(["diff", "--cached", "--name-only", "--diff-filter=ACM"])
  for line in raw.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(SrcPrefix) and trimmed.endsWith(NimExt):
      result.add(trimmed)

proc getCommitMessage(): string =
  ## Try to read the commit message to detect refactoring intent.
  for path in [".git/COMMIT_EDITMSG", ".git/COMMIT_MSG"]:
    if fileExists(path):
      try:
        let content = readFileSafe(path)
        for line in content.splitLines():
          let trimmed = line.strip()
          if trimmed.len > 0 and trimmed[0] != '#':
            return trimmed
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  result = ""

# ---------------------------------------------------------------------------
# Matching logic
# ---------------------------------------------------------------------------

func modulePathToFeaturePath(modulePath: string): string =
  ## Convert a src/ module path to its expected feature path.
  ## e.g., src/core/intrinsic_filter.nim → tests/features/intrinsic_filter.feature
  ## e.g., src/gate/runners/intent_gate.nim → tests/features/intent_gate.feature
  let filename = modulePath.splitFile().name
  result = FeaturesDir & filename & FeatureExt

proc getExistingFeatures(files: seq[string] = @[]): HashSet[string] =
  ## Get all existing feature filenames (without extension) for fast lookup.
  result = initHashSet[string]()
  if not dirExists(FeaturesDir):
    return
  try:
    if files.len == 0:
      for path in walkDirRec(FeaturesDir):
        if path.endsWith(FeatureExt):
          let name = path.splitFile().name
          result.incl(name)
    else:
      for f in files:
        if f.endsWith(FeatureExt):
          let name = f.splitFile().name
          result.incl(name)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc hasSpecEvidence(modulePath: string, existingFeatures: HashSet[string]): bool =
  ## Check whether the given module path has spec evidence in any of the
  ## accepted locations:
  ##   - tests/features/<filename>.feature  (fast path via existingFeatures)
  ##   - tests/unit/<filename>_test.nim
  ##   - tests/gateway/<filename>_test.nim
  let filename = modulePath.splitFile().name

  # Fast path — check existing .feature files
  if filename in existingFeatures:
    return true

  # Check unit test file
  if fileExists(UnitDir & filename & TestExt):
    return true

  # Check gateway test file
  if fileExists(GatewayDir & filename & TestExt):
    return true

  false

# ---------------------------------------------------------------------------
# Refactoring detection
# ---------------------------------------------------------------------------

func isRefactorCommit(message: string): bool =
  ## Detect if the commit message indicates a pure refactoring.
  ## A refactor commit starts with "refactor" in Conventional Commits format.
  let msg = message.strip()
  if msg.len == 0:
    return false
  # Check for "refactor" type prefix
  if msg.startsWith("refactor"):
    return true
  false

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let args = commandLineParams()
  var files: seq[string] = @[]
  for arg in args:
    if not arg.startsWith("--"):
      files.add(arg)

  let stagedFiles = getStagedNimFilesInSrc()
  if stagedFiles.len == 0:
    quit(0)

  # Filter: skip non-logic changes (pragma-only, comment-only, whitespace)
  var logicFiles: seq[string] = @[]
  for modulePath in stagedFiles:
    let diff = execGit(["diff", "--cached", modulePath])
    let kind = classifyChange(diff)
    if kind == ckLogic:
      logicFiles.add(modulePath)
    else:
      logInfo("spec_presence_gate", "[spec-presence-gate] SKIP — " & modulePath & " (" & $kind & ")")

  if logicFiles.len == 0:
    quit(0)

  let existingFeatures = getExistingFeatures(files)

  # Load grandfathered modules baseline
  let baseline = loadBaseline()

  # Check if this is a refactoring commit (allows exceptions for new files)
  let commitMsg = getCommitMessage()
  let isRefactor = isRefactorCommit(commitMsg)

  var missingFeatures: seq[string] = @[]
  var foundCount = 0
  var baselineSkipped = 0

  for modulePath in logicFiles:
    if hasSpecEvidence(modulePath, existingFeatures):
      foundCount.inc
    else:
      # Check baseline — grandfathered modules skip the check
      let moduleName = modulePath.splitFile().name
      if moduleName in baseline:
        baselineSkipped.inc
        continue
      # For refactor commits, only flag if the module already existed
      if isRefactor:
        # In a pure refactor, existing modules should already have specs.
        # Check if the file was newly added vs. just modified.
        let raw = execGit(["diff", "--cached", "--name-status", "--diff-filter=A", modulePath])
        if raw.len > 0:
          # Newly added file in a refactor commit — allow without spec
          continue
      missingFeatures.add(modulePath)

  if baselineSkipped > 0:
    logInfo("spec_presence_gate", "[spec-presence-gate] INFO — " & $baselineSkipped &
                     " module(s) grandfathered via baseline")

  if missingFeatures.len == 0:
    quit(0)

  logError("spec_presence_gate", "[spec-presence-gate] FAIL — " & $missingFeatures.len & " module(s) missing feature specification:")
  for m in missingFeatures:
    let expected = modulePathToFeaturePath(m)
    logInfo("spec_presence_gate", "  " & m & "  →  " & expected & " (not found)")
  logInfo("spec_presence_gate", "")
  logInfo("spec_presence_gate", "[spec-presence-gate] Create .feature files in " & FeaturesDir)
  logInfo("spec_presence_gate", "[spec-presence-gate] Or add to " & BaselineFile & " if grandfathered")
  logInfo("spec_presence_gate", "[spec-presence-gate] See: tests/features/ for existing examples")
  quit(1)

# ---------------------------------------------------------------------------
# VFS-aware helpers
# ---------------------------------------------------------------------------

func execGitVfs(ctx: GateContext; args: openArray[string]): string =
  ## Execute git via VFS subprocess provider.
  let res = vfsExec(ctx, "git", @args)
  if res.exitCode != 0:
    return ""
  res.output.strip(leading = false, trailing = true, chars = Whitespace + Newlines)

proc getStagedNimFilesInSrcVfs(ctx: GateContext): seq[string] =
  ## Get all staged .nim files under src/ directory via VFS.
  let raw = execGitVfs(ctx, ["diff", "--cached", "--name-only", "--diff-filter=ACM"])
  for line in raw.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(SrcPrefix) and trimmed.endsWith(NimExt):
      result.add(trimmed)

func getExistingFeaturesVfs(ctx: GateContext; files: seq[string] = @[]): HashSet[string] =
  ## Get all existing feature filenames via VFS directory listing.
  result = initHashSet[string]()
  let entries = vfsListDir(ctx, FeaturesDir)
  if entries.len == 0:
    return
  if files.len == 0:
    for entry in entries:
      # vfsListDir returns full paths or names; check for .feature suffix
      if entry.endsWith(FeatureExt):
        let name = entry.splitFile().name
        result.incl(name)
  else:
    for f in files:
      if f.endsWith(FeatureExt):
        let name = f.splitFile().name
        result.incl(name)

func hasSpecEvidenceVfs(ctx: GateContext; modulePath: string; existingFeatures: HashSet[string]): bool =
  ## Check spec evidence via VFS.
  let filename = modulePath.splitFile().name
  if filename in existingFeatures:
    return true
  if vfsExists(ctx, UnitDir & filename & TestExt):
    return true
  if vfsExists(ctx, GatewayDir & filename & TestExt):
    return true
  false

proc mainWithVfs(ctx: GateContext) =
  ## VFS entry point. Enforces Intent → Spec → Test → Code via VFS.
  let args = commandLineParams()
  var files: seq[string] = @[]
  for arg in args:
    if not arg.startsWith("--"):
      files.add(arg)

  let stagedFiles = getStagedNimFilesInSrcVfs(ctx)
  if stagedFiles.len == 0:
    quit(0)

  # Filter: skip non-logic changes (pragma-only, comment-only, whitespace)
  var logicFiles: seq[string] = @[]
  for modulePath in stagedFiles:
    let diff = execGitVfs(ctx, ["diff", "--cached", modulePath])
    let kind = classifyChange(diff)
    if kind == ckLogic:
      logicFiles.add(modulePath)
    else:
      logInfo("spec_presence_gate", "[spec-presence-gate] SKIP — " & modulePath & " (" & $kind & ")")

  if logicFiles.len == 0:
    quit(0)

  let existingFeatures = getExistingFeaturesVfs(ctx, files)

  # Load grandfathered modules baseline
  let baseline = loadBaseline()

  # Check if this is a refactoring commit
  var commitMsg = ""
  for path in [".git/COMMIT_EDITMSG", ".git/COMMIT_MSG"]:
    if vfsExists(ctx, path):
      try:
        let content = vfsRead(ctx, path)
        for line in content.splitLines():
          let trimmed = line.strip()
          if trimmed.len > 0 and trimmed[0] != '#':
            commitMsg = trimmed
            break
      except KeyError:
        discard
      if commitMsg.len > 0:
        break
  let isRefactor = isRefactorCommit(commitMsg)

  var missingFeatures: seq[string] = @[]
  var foundCount = 0
  var baselineSkipped = 0

  for modulePath in logicFiles:
    if hasSpecEvidenceVfs(ctx, modulePath, existingFeatures):
      foundCount.inc
    else:
      # Check baseline — grandfathered modules skip the check
      let moduleName = modulePath.splitFile().name
      if moduleName in baseline:
        baselineSkipped.inc
        continue
      if isRefactor:
        let raw = execGitVfs(ctx, ["diff", "--cached", "--name-status", "--diff-filter=A", modulePath])
        if raw.len > 0:
          continue
      missingFeatures.add(modulePath)

  if baselineSkipped > 0:
    logInfo("spec_presence_gate", "[spec-presence-gate] INFO — " & $baselineSkipped &
                     " module(s) grandfathered via baseline")

  if missingFeatures.len == 0:
    quit(0)

  logError("spec_presence_gate", "[spec-presence-gate] FAIL — " & $missingFeatures.len & " module(s) missing feature specification:")
  for m in missingFeatures:
    let expected = modulePathToFeaturePath(m)
    logInfo("spec_presence_gate", "  " & m & "  →  " & expected & " (not found)")
  logInfo("spec_presence_gate", "")
  logInfo("spec_presence_gate", "[spec-presence-gate] Create .feature files in " & FeaturesDir)
  logInfo("spec_presence_gate", "[spec-presence-gate] Or add to " & BaselineFile & " if grandfathered")
  logInfo("spec_presence_gate", "[spec-presence-gate] See: tests/features/ for existing examples")
  quit(1)

when isMainModule:
  main()

{.pop.}
