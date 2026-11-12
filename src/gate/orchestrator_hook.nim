import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/gate/gate_memo          # for computeBuildEnvHash
import core/crypto/hash_kernel      # for hashValueToHex
import core/gate/state_ledger       # v27: read ledger from parent process via mmap
import core/gate/state_ledger_types # for LedgerTotalSize
import core/gate/workspace_receipt
import core/parsers/safe_parsers
import core/results
import core/utils/repo_root
import gate/gate_run_context        # Phase 4: GateRunContext for unified cache key SSOT
import gate/gate_utils
import gate/git
import gate/orchestrator_pure  # for classifyFailure
import gate/types
import gate/utils/gate_run_logger
import core/trusted/env_access
import core/gate/gate_context
import std/json
import std/options
import std/os
import std/strutils
import infrastructure/logger

# Domain modules
import gate/orchestrator/hook/context
import gate/orchestrator/hook/memo
import gate/orchestrator/hook/analyzer
import gate/orchestrator/hook/executor

export context
export memo
export analyzer
export executor

# Forwarded type exports for backward compatibility
import gate/orchestrator_types
export orchestrator_types

proc canReadFile*(path: string): bool {.raises: [].} =
  try:
    let f = open(path, fmRead)
    defer: f.close()
    result = true
  except CatchableError:
    result = false

const
  AxiomRootMarker* = ".axiom_root" ## Canonical root marker written by `axiom init`.
                                   ## Guards bootstrap integrity: gate binaries must
                                   ## run from the same root that created the marker.
proc checkDomainLayout*(path: string): bool =
  withGate("domain_layout"):
    if not fileExists(path):
      ctx.fail("Missing domain layout")
    elif not canReadFile(path):
      ctx.fail("Domain layout is not readable")
    else:
      ctx.pass()

proc checkManifestIntegrity*(): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify that every domain in domain_layout.json is covered by at least
  ## one gate's filesPattern. Prevents configuration drift between architecture
  ## declaration and validation schedule.
  let layoutPath = getCurrentDir() / "src" / "core" / "domain_layout.json"
  if not checkDomainLayout(layoutPath):
    logger.warn("[orchestrator_hook] [MANIFEST] WARN: domain_layout.json not found")
    return false

  let layoutJson = parseJson(readFile(layoutPath))
  let primitives = layoutJson{"root_primitives"}
  if primitives == nil or primitives.kind != JArray:
    logger.error("[orchestrator_hook] [MANIFEST] FAIL: root_primitives missing or not an array")
    return false

  let gates = allGates()
  var uncovered: seq[string] = @[]

  for p in primitives.getElems():
    let primitiveName = p.getStr()
    let expectedPath = "src/core/" & primitiveName
    var covered = false
    for g in gates:
      if g.filesPattern.len == 0:
        continue
      for pattern in g.filesPattern.split('|'):
        let pat = pattern.strip()
        if pat.len > 0 and expectedPath.startsWith(pat):
          covered = true
          break
      if covered:
        break
    if not covered:
      uncovered.add(primitiveName)

  if uncovered.len > 0:
    logger.error("[orchestrator_hook] [MANIFEST INTEGRITY] FAIL: " & $uncovered.len & " domain(s) have no gate coverage:")
    for u in uncovered:
      logger.info("[orchestrator_hook]   - " & u)
    return false

  logger.info("[orchestrator_hook] [MANIFEST INTEGRITY] OK: All " & $primitives.getElems().len & " domains covered by gates")
  true

# ---------------------------------------------------------------------------
# Shared executable entry-point helpers
# ---------------------------------------------------------------------------
func resolveStageFromArgs*(invokedAs: string; args: seq[string]): string =
  ## Determine the stage from the binary name or first argument.
  if invokedAs == "pre-commit" or invokedAs == "pre-push" or invokedAs == "post-commit":
    return invokedAs
  if args.len >= 1:
    return args[0]
  return ""
func resolveGateStage*(stage: string): GateStage =
  ## Map a string stage to the GateStage enum.
  if stage == "pre-commit":
    return gsPreCommit
  if stage == "pre-merge-commit":
    return gsPreCommit  # same gate suite as pre-commit
  if stage == "pre-push":
    return gsPrePush
  if stage == "ci":
    return gsPreCommit  # special handling below
  if stage == "post-commit":
    return gsManual  # deferred gates run in manual mode
  return gsManual
proc runSingleGateIfRequested*(gateStage: GateStage; repoRoot: string; maxJobs: int;
                               epoch: int; forCommit: bool = false;
                               updateBaseline: bool = false): Option[bool] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## If AXIOM_SINGLE_GATE_ID is set, run only that gate and return its result.
  ## Returns none(bool) when no single-gate request is present.
  let singleGateId = getAxiomEnv(evSingleGateId)
  if singleGateId.len == 0:
    return none(bool)

  # Write workspace_receipt.json for backward compatibility (ledger or receipt)
  let ledgerPath = getAxiomEnv(evStateLedgerPath)
  if ledgerPath.len > 0 and fileExists(ledgerPath):
    let ledger = openLedger(repoRoot)
    if ledger != nil:
      try:
        let receiptPath = repoRoot / "logs" / "workspace_receipt.json"
        createDir(receiptPath.parentDir())
        writeFile(receiptPath, pretty(%*{
          "baseCommit": "from-ledger",
          "dirtyHash": hashValueToHex(ledger.workspace.dirtyHash),
          "ruleHash": hashValueToHex(ledger.workspace.ruleHash),
          "timestamp": ledger.workspace.timestamp
        }))
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
      closeLedger(ledger)
  else:
    try:
      let receipt = computeReceipt(repoRoot)
      let receiptPath = repoRoot / "logs" / "workspace_receipt.json"
      createDir(receiptPath.parentDir())
      writeFile(receiptPath, pretty(%*{
        "baseCommit": receipt.baseCommit,
        "dirtyHash": receipt.dirtyHash,
        "ruleHash": receipt.ruleHash,
        "timestamp": receipt.timestamp
      }))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  let allGatesDefs = allGates()
  var targetGate: GateConfig
  var found = false
  for g in allGatesDefs:
    if g.id == singleGateId:
      targetGate = g
      found = true
      break
  if not found:
    logger.error("[orchestrator_hook] [GATE] ERROR: Gate " & singleGateId & " not found")
    return some(false)

  # Phase 4: Build GateRunContext — SSOT for cache key computation.
  var vfsHandle = cast[VfsHandle](nil)
  try:
    let vfs = executor.getOrBuildVfs(repoRoot)
    if vfs != nil:
      vfsHandle = buildVfsHandle(vfs)
  except CatchableError:
    vfsHandle = cast[VfsHandle](nil)

  let changedFiles = gitDiffCachedNames()
  let precomputedBuildEnvHash = computeBuildEnvHash(repoRoot)

  var gateCtx = GateRunContext(
    repoRoot: repoRoot,
    stagedFiles: changedFiles,
    vfs: vfsHandle,
    ledger: nil,
    epoch: epoch,
    maxJobs: maxJobs,
    precomputedBuildEnvHash: precomputedBuildEnvHash,
    stage: gateStage
  )
  try:
    gateCtx.ledger = openLedger(repoRoot)
  except CatchableError:
    gateCtx.ledger = nil

  let skip = memo.trySkipGateOptimized(targetGate, gateCtx)
  if skip.isSome:
    if skip.get.result:
      logger.info("[orchestrator_hook] [" & targetGate.id & "] [PASS_CACHED]")
    else:
      logger.error("[orchestrator_hook] [" & targetGate.id & "] [FAIL_CACHED] " & skip.get.reason & " (cached, " & $skip.get.category & ")")
    return some(skip.get.result)

  var dummyTelemetry = initTelemetry(initContext("single-gate", changedFiles.len, epoch))
  let effectiveTimeoutMs = context.loadGateSla(targetGate.id, forCommit = forCommit)
  let res = executor.dispatchGate(targetGate, repoRoot, changedFiles, maxJobs, gateStage,
                                  effectiveTimeoutMs, dummyTelemetry, updateBaseline)
  if res.ok:
    memo.persistGateMemo(targetGate, changedFiles, true, repoRoot, epoch)
  else:
    let (failCat, failReason) = classifyFailure(1, res.stdout & res.stderr)
    memo.persistGateMemo(targetGate, changedFiles, false, repoRoot, epoch, failureCategory=failCat, failureReason=failReason)
  if res.stdout.len > 0:
    logger.info("[orchestrator_hook] " & res.stdout)
  if res.stderr.len > 0:
    logger.info("[orchestrator_hook] " & res.stderr)

  return some(res.ok)
proc verifyAxiomRoot*(repoRoot: string): bool  =
  ## Check `.axiom_root` exists at repoRoot. Binary presence = root identity.
  ## No content parsing. Deterministic.
  return fileExists(repoRoot / ".axiom_root")
proc bootstrapGateEnvironment*(): tuple[repoRoot: string, maxJobs: int] =
  ## Common environment setup for all gate entry points.
  ## Verifies `.axiom_root` integrity before proceeding.

  let home = getHomeDir()
  putEnv("HOME", home)
  putEnv("NIM_CACHE_DIR", joinPath(home, ".cache", "nim"))

  let repoRoot = findRepoRoot()

  # Bootstrap gate self-verification: .axiom_root existence proves root identity.
  if not verifyAxiomRoot(repoRoot):
    logger.warn("[orchestrator_hook] [BOOTSTRAP] WARN: .axiom_root missing at " & $(repoRoot))

  let defaultJobs = GlobalMaxTokens
  let maxJobsRaw = getAxiomEnv(evJobs, $defaultJobs)
  let maxJobsRes = safeParseInt(maxJobsRaw)
  let maxJobs = if maxJobsRes.isOk: maxJobsRes.get() else: defaultJobs
  setCurrentDir(repoRoot)
  discard gate_utils.raiseRlimitNoFile()
  return (repoRoot, maxJobs)

{.pop.}
