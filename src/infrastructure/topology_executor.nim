import core/trusted/layer_declaration
axiomLayer "infrastructure"
import infrastructure/logger
## Topology Executor — Infrastructure layer for filesystem/process orchestration.
## Bridges pure topology domain functions (core/topology/apply) with the real
## filesystem. All I/O primitives are concentrated here.

import std/[os, osproc, strutils, times, random, tables]

import core/contracts/topology_contract
import core/trusted/stdlib_shield
import core/axiom_pragmas
import core/macros/best_effort
import core/interfaces/git_operations

export topology_contract

axiomIoBoundary()

let gitExe* = git_operations.findRealGit()

# ---------------------------------------------------------------------------
# Low-level I/O helpers
# ---------------------------------------------------------------------------

proc readFileContent*(path: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read file content, return empty string on error.
  try:
    result = safeReadFile(path)
  except TopologyIOError:
    result = ""

proc writeFileContent*(path, content: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""file write failure is non-fatal at ioboundary""").} =
  ## Write content to file, ignoring errors.
  try:
    writeFile(path, content)
  except CatchableError:
    discard

proc ensureDirExists*(dirPath: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Create directory (and parents) if missing.
  if not safeDirExists(dirPath):
    createDir(dirPath)

proc moveFileSafe*(src, dst: string): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Move file, creating parent dirs as needed. Returns success.
  try:
    let parent = parentDir(dst)
    if parent.len > 0:
      ensureDirExists(parent)
    safeMoveFile(src, dst)
    result = true
  except FileMoveError:
    result = false
  except TopologyIOError:
    result = false

proc copyFileSafe*(src, dst: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""file copy failure is non-fatal at ioboundary""").} =
  ## Copy file, creating parent dirs as needed.
  try:
    let parent = parentDir(dst)
    if parent.len > 0:
      ensureDirExists(parent)
    copyFile(src, dst)
  except CatchableError:
    discard

proc removeDirSafe*(path: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""directory removal failure is non-fatal cleanup""").} =
  try:
    if safeDirExists(path):
      removeDir(path)
  except CatchableError as e:
    try:
      stderr.writeLine("[WARN] topology_executor: Failed to remove directory " & path & ": " & e.msg)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# Policy checks
# ---------------------------------------------------------------------------

proc isGitClean*(): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let (output, exitCode) = git_operations.runGitEx(gitExe, "status --porcelain")
  if exitCode != 0:
    return false
  result = output.strip.len == 0

proc promptApproval*(message: string): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  logger.info $message & " [y/N]"
  let answer = readLine(stdin)
  result = answer.toLowerAscii in ["y", "yes"]

# ---------------------------------------------------------------------------
# Staging area I/O
# ---------------------------------------------------------------------------

proc makeStagingId*(): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  randomize()
  let now = getTime().format("yyyyMMdd-HHmmss-fff")
  let pid = getCurrentProcessId()
  let rnd = rand(999999)
  result = now & "-" & $pid & "-" & $rnd

proc createStagingAreaIO*(base: string = ".axiom/staging"): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = base / makeStagingId()
  ensureDirExists(result / "original")

proc stageFileIO*(stagingRoot, relPath: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  copyFileSafe(relPath, stagingRoot / "original" / relPath)

proc stageLockFileIO*(stagingRoot, lockPath: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if fileExists(lockPath):
    copyFileSafe(lockPath, stagingRoot / "original" / "topology.lock")

proc recordManifestIO*(stagingRoot: string; plan: Plan) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let jsonStr = stagingManifestJson(stagingRoot, plan)
  writeFileContent(stagingRoot / "manifest.json", jsonStr)

proc rollbackIO*(stagingRoot: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let originalRoot = stagingRoot / "original"
  if not safeDirExists(originalRoot):
    return
  for path in safeWalkDirRec(originalRoot):
    let rel = path.relativePath(originalRoot)
    copyFileSafe(path, rel)

proc rollbackLockFileIO*(stagingRoot, lockPath: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let backup = stagingRoot / "original" / "topology.lock"
  if fileExists(backup):
    copyFileSafe(backup, lockPath)

# ---------------------------------------------------------------------------
# Plan data loading
# ---------------------------------------------------------------------------

proc scanSourceFiles*(root: string = "src"): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan all .nim files under root, return relative paths.
  result = @[]
  let base = root.parentDir
  for path in safeWalkDirRec(root):
    if path.endsWith(".nim"):
      result.add(path.relativePath(base))

proc readSourceContents*(files: seq[string]): Table[string, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = initTable[string, string]()
  for f in files:
    result[f] = readFileContent(f)

# ---------------------------------------------------------------------------
# Execution engine
# ---------------------------------------------------------------------------

proc executeTopologyPlan*(execPlan: TopologyExecutionPlan;
                          axPath: string;
                          lockPath: string): TopologyExecutionResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute a topology execution plan. All I/O happens here.
  result = TopologyExecutionResult(kind: terkSuccess)
  let policy = execPlan.policy

  # Print plan preview.
  for op in execPlan.operations:
    case op.kind
    of tokMoveFile:
      logger.info("→ move " & $op.srcPath & " -> " & op.dstPath)
    of tokWriteFile:
      logger.info("→ rewrite " & $op.writePath)
    of tokExec:
      logger.info("→ exec " & $op.command.join(" "))
    of tokCreateDir:
      logger.info("→ mkdir " & $op.dirPath)
    of tokStageFile:
      logger.info("→ stage " & $op.stageSrc)
    of tokRecordManifest:
      logger.info("→ record manifest")
    of tokUpdateLock:
      logger.info("→ update lock")

  if execPlan.operations.len == 0:
    result.kind = terkDryRun
    return

  if policy.dryRun:
    result.kind = terkDryRun
    return

  if policy.requireCleanGit and not isGitClean():
    result.kind = terkCancelled
    result.error = some("Working tree is not clean. Commit or stash changes, or use --force.")
    return

  if policy.requireApproval and not promptApproval("Apply the above plan?"):
    result.kind = terkCancelled
    result.error = some("Cancelled by user.")
    return

  var stagingRoot = ""
  var lockStaged = false

  try:
    # Create staging area.
    stagingRoot = createStagingAreaIO()

    # First pass: stage files and record manifest.
    for op in execPlan.operations:
      case op.kind
      of tokStageFile:
        stageFileIO(stagingRoot, op.stageSrc)
        result.executed.add(op)
      of tokRecordManifest:
        recordManifestIO(stagingRoot, op.manifestPlan)
        result.executed.add(op)
      of tokUpdateLock:
        if lockPath.len > 0:
          stageLockFileIO(stagingRoot, lockPath)
          lockStaged = true
        result.executed.add(op)
      else:
        discard

    # Second pass: execute mutating operations.
    for op in execPlan.operations:
      case op.kind
      of tokCreateDir:
        ensureDirExists(op.dirPath)
        result.executed.add(op)
      of tokMoveFile:
        if not moveFileSafe(op.srcPath, op.dstPath):
          raise newException(CatchableError, "move failed: " & op.srcPath & " -> " & op.dstPath)
        result.executed.add(op)
      of tokWriteFile:
        writeFileContent(op.writePath, op.content)
        result.executed.add(op)
      of tokExec:
        let cmd = op.command.join(" ")
        let (output, exitCode) = execCmdEx(cmd)
        if exitCode != 0:
          raise newException(CatchableError, "command failed: " & cmd & "\n" & output)
        result.executed.add(op)
      of tokUpdateLock:
        if lockPath.len > 0:
          let lockJson = readFileContent(lockPath)
          let lockRes = parseTopologyLockJson(lockJson)
          if not lockRes.ok:
            raise newException(CatchableError,
              "topology executor: " & lockRes.err)
          let nowStr = getTime().format("yyyy-MM-dd'T'HH:mm:sszzz")
          let updated = updateLockModel(lockRes.value, op.lockMoves, nowStr)
          writeFileContent(lockPath, renderLockJson(updated))
        result.executed.add(op)
      else:
        discard

    # Cleanup staging area on success.
    removeDirSafe(stagingRoot)
    result.kind = terkSuccess

  except CatchableError as e:
    result.error = some(e.msg)
    if policy.allowRollback and stagingRoot.len > 0:
      logger.info("\nApply failed (" & e.msg & "). Rolling back from " & stagingRoot & " ...")
      rollbackIO(stagingRoot)
      if lockStaged:
        rollbackLockFileIO(stagingRoot, lockPath)
      removeDirSafe(stagingRoot)
      logger.info("Rollback complete.")
      result.kind = terkValidationFailed
    else:
      result.kind = terkRollbackFailed

# ---------------------------------------------------------------------------
# High-level apply entry point
# ---------------------------------------------------------------------------

proc executeTopologyApply*(plan: Plan;
                           dryRun, autoApprove, force: bool;
 axPath: string = "./bin/ax";
                           lockPath: string = ""): TopologyExecutionResult {.raises: [CatchableError].} =
  ## Load file contents, build execution plan, and execute.
  let policy = buildTopologyExecutionPolicy(dryRun, autoApprove, force)

  # Pre-load contents for files that may need import rewrites.
  var filesToRead: seq[string] = @[]
  for r in plan.rewrites:
    if r.file notin filesToRead:
      filesToRead.add(r.file)
  for m in plan.moves:
    if m.fromPath notin filesToRead:
      filesToRead.add(m.fromPath)

  let fileContents = readSourceContents(filesToRead)
  let execPlan = buildTopologyExecutionPlan(plan, fileContents, policy, axPath, lockPath)
  result = executeTopologyPlan(execPlan, axPath, lockPath)
