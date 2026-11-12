import core/trusted/layer_declaration
axiomLayer "gate"
import infrastructure/logger
{.push raises: [CatchableError].}

## Verification Auditor Gate — L2 Functional
##
## Executes the verification auditor binary to classify modules into
## domain / exempt / infrastructure categories.
##
## Simplified check (current): domain module count must match baseline.
## Future: per-module test-runner mapping under tests/gateway/ or tests/features/.
##
## Usage:
##   nim c -r src/gate/runners/verification_auditor_gate.nim <repoRoot> <mode> <maxJobs> [files...]

import std/[json, os, osproc, strutils, times, monotimes]
import core/results
import core/parsers/safe_parsers
import core/axiom_pragmas
import core/gate/gate_vfs
import infrastructure/logging_facade


# axiomIoBoundary

const
  AuditorBinary = "bin/verification_auditor"
  AuditorSource = "tools/verification_auditor.nim"
  BaselinePath = "data/verification_auditor_baseline.json"
  TopologyLockPath = "topology.lock"

type
  AuditorReport = object
    totalModules: int
    domainCount: int
    exemptCount: int
    infraCount: int
    ok: bool
    rawOutput: string

proc compileAuditor(repoRoot: string): bool {.raises: [OSError, IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compile tools/verification_auditor.nim if the binary is missing.
  let binaryPath = repoRoot / AuditorBinary
  let sourcePath = repoRoot / AuditorSource
  if not fileExists(binaryPath):
    logger.info("[verification-auditor-gate] Compiling " & AuditorBinary & " ...")
    putEnv("AXIOM_GATE_BOND", "1")
    let cmd = "nim c --hints:off -o:" & binaryPath & " " & sourcePath
    let (output, exitCode) = execCmdEx(cmd, workingDir = repoRoot)
    if exitCode != 0:
      logError("verification_auditor_gate", "[verification-auditor-gate] FAILED to compile auditor:")
      logInfo("verification_auditor_gate", output)
      return false
  return true

proc runAuditor(repoRoot: string): AuditorReport {.raises: [OSError, IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run the verification auditor and parse its output.
  let binaryPath = repoRoot / AuditorBinary
  let (output, exitCode) = execCmdEx(binaryPath, workingDir = repoRoot)
  result.rawOutput = output
  result.ok = exitCode == 0

  if not result.ok:
    return

  for line in output.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("Total modules scanned: "):
      try:
        let totalRes = safeParseInt(stripped.split(": ")[1])
        if totalRes.isOk:
          result.totalModules = totalRes.get()
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    elif stripped.startsWith("domain: "):
      try:
        let domainRes = safeParseInt(stripped.split(": ")[1])
        if domainRes.isOk:
          result.domainCount = domainRes.get()
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    elif stripped.startsWith("exempt: "):
      try:
        let exemptRes = safeParseInt(stripped.split(": ")[1])
        if exemptRes.isOk:
          result.exemptCount = exemptRes.get()
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    elif stripped.startsWith("infrastructure: "):
      try:
        let infraRes = safeParseInt(stripped.split(": ")[1])
        if infraRes.isOk:
          result.infraCount = infraRes.get()
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

proc getLockRevision(repoRoot: string): int {.axiomEffect: IOEffect.} =
  ## Read lock_revision from topology.lock.
  let lockPath = repoRoot / TopologyLockPath
  if not fileExists(lockPath):
    logWarn("verification_auditor_gate", "[verification-auditor-gate] WARNING: topology.lock not found, lock_revision=0")
    return 0
  try:
    let content = readFile(lockPath)
    let parsed = parseJson(content)
    result = parsed["lock_revision"].getInt()
  except CatchableError:
    logError("verification_auditor_gate", "[verification-auditor-gate] WARNING: failed to parse topology.lock, lock_revision=0")
    result = 0

proc loadBaseline(repoRoot: string): tuple[domainCount: int, lockRevision: int] {.axiomEffect: IOEffect.} =
  ## Load baseline from external JSON. If missing, auto-calibrate by running the auditor.
  let baselinePath = repoRoot / BaselinePath
  if fileExists(baselinePath):
    try:
      let content = readFile(baselinePath)
      let parsed = parseJson(content)
      result.domainCount = parsed["domain_count"].getInt()
      result.lockRevision = parsed["lock_revision"].getInt()
      return
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  # Auto-calibrate: run auditor, parse domain count, save baseline
  logger.info("[verification-auditor-gate] Baseline not found, auto-calibrating...")
  let report = runAuditor(repoRoot)
  if not report.ok:
    logError("verification_auditor_gate", "[verification-auditor-gate] FAIL — auditor failed during auto-calibration")
    quit(1)

  let lockRev = getLockRevision(repoRoot)
  let now = $now().utc

  var baselineJson = newJObject()
  baselineJson["domain_count"] = newJInt(report.domainCount)
  baselineJson["updated_at"] = newJString(now)
  baselineJson["updated_by"] = newJString("auto-calibrate")
  baselineJson["lock_revision"] = newJInt(lockRev)

  let parentDir = baselinePath.parentDir()
  if not dirExists(parentDir):
    createDir(parentDir)
  writeFile(baselinePath, pretty(baselineJson) & "\n")
  logger.info("[verification-auditor-gate] Baseline auto-calibrated: domain_count=" & $report.domainCount & " lock_revision=" & $lockRev)

  result.domainCount = report.domainCount
  result.lockRevision = lockRev

proc appendGateHistory(gateId: string; verdict: string; durationNs: int64) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Best-effort append of a gate execution record to .axiom/gate_history.jsonl.
  ## Emits a JSONL record compatible with gate_run_logger.flushToDisk's canonical
  ## format (gateId/result/durationNs/ts/...) so both gate_status_metrics.nim and
  ## axiom_status.nim can consume it. Telemetry is incidental — a failure here
  ## MUST NOT affect the gate verdict (fully swallowed).
  try:
    createDir(".axiom")
    var f = open(".axiom" / "gate_history.jsonl", fmAppend)
    defer: close(f)
    let rec = %*{
      "ts": now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
      "stage": "ci",
      "commit": "",
      "branch": "",
      "stagedFiles": 0,
      "epoch": 0,
      "gateId": gateId,
      "result": verdict,
      "durationNs": durationNs,
      "cached": false,
      "tier": 1,
      "dagLayer": 0
    }
    f.writeLine($rec)
    f.flushFile()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch) — never affect gate verdict

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let startMono = getMonoTime()
  let args = commandLineParams()
  if args.len < 3:
    logInfo("verification_auditor_gate", "Usage: verification_auditor_gate <repoRoot> <mode> <maxJobs> [files...]")
    quit(1)

  let repoRoot = args[0]

  # Ensure auditor binary exists
  if not compileAuditor(repoRoot):
    logger.info("[verification-auditor-gate] FAIL — auditor compilation failed")
    quit(1)

  var report = runAuditor(repoRoot)

  # Self-heal: a stale or corrupt persisted bin/verification_auditor (the
  # runner workspace survives across CI runs) exits instantly with no useful
  # output. Rebuild from the current tree and retry once — fail-closed is
  # preserved if the retry also fails.
  if not report.ok:
    logger.info("[verification-auditor-gate] Auditor run failed — rebuilding bin/verification_auditor from current source...")
    try:
      removeFile(repoRoot / AuditorBinary)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    if not compileAuditor(repoRoot):
      logger.info("[verification-auditor-gate] FAIL — auditor compilation failed")
      quit(1)
    report = runAuditor(repoRoot)

  logger.info("=== Verification Auditor Gate Report ===")
  logger.info("Total modules scanned: " & $report.totalModules)
  logger.info("  domain:         " & $report.domainCount)
  logger.info("  exempt:         " & $report.exemptCount)
  logger.info("  infrastructure: " & $report.infraCount)
  logger.info("")

  # Load external baseline and cross-check lock_revision
  let baseline = loadBaseline(repoRoot)
  let currentLockRev = getLockRevision(repoRoot)
  if baseline.lockRevision != currentLockRev:
    logger.info("[WARN] Baseline outdated: baseline revision " & $baseline.lockRevision & ", lock revision " & $currentLockRev & ". Run --update-baseline.")

  # Domain count must match baseline
  let domainMatch = report.domainCount == baseline.domainCount
  let durationNs = (getMonoTime() - startMono).inNanoseconds

  if domainMatch:
    logger.info("Domain module count matches baseline (" & $baseline.domainCount & ").")
    logger.info("[verification-auditor-gate] PASS")
    appendGateHistory("verification-auditor", "pass", durationNs)
    quit(0)
  else:
    logger.info("Domain module count mismatch: expected " & $baseline.domainCount & " got " & $report.domainCount)
    logger.info("[verification-auditor-gate] FAIL")
    appendGateHistory("verification-auditor", "fail", durationNs)
    quit(1)

# ---------------------------------------------------------------------------
# VFS-aware helpers
# ---------------------------------------------------------------------------

proc getLockRevisionVfs(ctx: GateContext; repoRoot: string): int =
  ## Read lock_revision from topology.lock via VFS.
  let lockPath = TopologyLockPath
  if not vfsExists(ctx, lockPath):
    logWarn("verification_auditor_gate", "[verification-auditor-gate] WARNING: topology.lock not found, lock_revision=0")
    return 0
  try:
    let content = vfsRead(ctx, lockPath)
    let parsed = parseJson(content)
    result = parsed["lock_revision"].getInt()
  except CatchableError:
    logError("verification_auditor_gate", "[verification-auditor-gate] WARNING: failed to parse topology.lock, lock_revision=0")
    result = 0

proc compileAuditorVfs(ctx: GateContext; repoRoot: string): bool =
  ## Compile auditor binary via VFS subprocess provider.
  let binaryPath = AuditorBinary
  if not vfsExists(ctx, AuditorSource) and not fileExists(repoRoot / AuditorBinary):
    # Source not in VFS, binary not on disk — can't compile
    return false
  if fileExists(repoRoot / AuditorBinary):
    return true
  # Compilation requires real filesystem (output binary). Use vfsExec for the
  # subprocess but fall back to real filesystem for putEnv + output path.
  putEnv("AXIOM_GATE_BOND", "1")
  let sourcePath = repoRoot / AuditorSource
  let binaryFullPath = repoRoot / AuditorBinary
  let res = vfsExec(ctx, "nim", @["c", "--hints:off", "-o:" & binaryFullPath, sourcePath])
  if res.exitCode != 0:
    logError("verification_auditor_gate", "[verification-auditor-gate] FAILED to compile auditor:")
    logInfo("verification_auditor_gate", res.output)
    return false
  return true

proc runAuditorVfs(ctx: GateContext; repoRoot: string): AuditorReport {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run auditor binary via VFS subprocess provider.
  let binaryFullPath = repoRoot / AuditorBinary
  let res = vfsExec(ctx, binaryFullPath, @[])
  result.rawOutput = res.output
  result.ok = res.exitCode == 0

  if not result.ok:
    return

  for line in res.output.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("Total modules scanned: "):
      try:
        let totalRes = safeParseInt(stripped.split(": ")[1])
        if totalRes.isOk:
          result.totalModules = totalRes.get()
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    elif stripped.startsWith("domain: "):
      try:
        let domainRes = safeParseInt(stripped.split(": ")[1])
        if domainRes.isOk:
          result.domainCount = domainRes.get()
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    elif stripped.startsWith("exempt: "):
      try:
        let exemptRes = safeParseInt(stripped.split(": ")[1])
        if exemptRes.isOk:
          result.exemptCount = exemptRes.get()
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    elif stripped.startsWith("infrastructure: "):
      try:
        let infraRes = safeParseInt(stripped.split(": ")[1])
        if infraRes.isOk:
          result.infraCount = infraRes.get()
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

proc loadBaselineVfs(ctx: GateContext; repoRoot: string): tuple[domainCount: int, lockRevision: int] {.axiomEffect: IOEffect.} =
  ## Load baseline via VFS file read.
  if vfsExists(ctx, BaselinePath):
    try:
      let content = vfsRead(ctx, BaselinePath)
      let parsed = parseJson(content)
      result.domainCount = parsed["domain_count"].getInt()
      result.lockRevision = parsed["lock_revision"].getInt()
      return
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  # Auto-calibrate: run auditor, parse domain count, save baseline
  logger.info("[verification-auditor-gate] Baseline not found, auto-calibrating...")
  let report = runAuditorVfs(ctx, repoRoot)
  if not report.ok:
    logError("verification_auditor_gate", "[verification-auditor-gate] FAIL — auditor failed during auto-calibration")
    quit(1)

  let lockRev = getLockRevisionVfs(ctx, repoRoot)
  let now = $now().utc

  var baselineJson = newJObject()
  baselineJson["domain_count"] = newJInt(report.domainCount)
  baselineJson["updated_at"] = newJString(now)
  baselineJson["updated_by"] = newJString("auto-calibrate")
  baselineJson["lock_revision"] = newJInt(lockRev)

  # writeFile stays on real filesystem (VFS is read-only for writes)
  let baselineFullPath = repoRoot / BaselinePath
  let parentDir = baselineFullPath.parentDir()
  if not dirExists(parentDir):
    createDir(parentDir)
  writeFile(baselineFullPath, pretty(baselineJson) & "\n")
  logger.info("[verification-auditor-gate] Baseline auto-calibrated: domain_count=" & $report.domainCount & " lock_revision=" & $lockRev)

  result.domainCount = report.domainCount
  result.lockRevision = lockRev

proc mainWithVfs(ctx: GateContext) =
  ## VFS entry point. Runs verification auditor via VFS.
  let args = commandLineParams()
  if args.len < 3:
    logInfo("verification_auditor_gate", "Usage: verification_auditor_gate <repoRoot> <mode> <maxJobs> [files...]")
    quit(1)

  let repoRoot = args[0]

  # Ensure auditor binary exists
  if not compileAuditorVfs(ctx, repoRoot):
    logger.info("[verification-auditor-gate] FAIL — auditor compilation failed")
    quit(1)

  let report = runAuditorVfs(ctx, repoRoot)

  logger.info("=== Verification Auditor Gate Report ===")
  logger.info("Total modules scanned: " & $report.totalModules)
  logger.info("  domain:         " & $report.domainCount)
  logger.info("  exempt:         " & $report.exemptCount)
  logger.info("  infrastructure: " & $report.infraCount)
  logger.info("")

  let baseline = loadBaselineVfs(ctx, repoRoot)
  let currentLockRev = getLockRevisionVfs(ctx, repoRoot)
  if baseline.lockRevision != currentLockRev:
    logger.info("[WARN] Baseline outdated: baseline revision " & $baseline.lockRevision & ", lock revision " & $currentLockRev & ". Run --update-baseline.")

  let domainMatch = report.domainCount == baseline.domainCount

  if domainMatch:
    logger.info("Domain module count matches baseline (" & $baseline.domainCount & ").")
    logger.info("[verification-auditor-gate] PASS")
    quit(0)
  else:
    logger.info("Domain module count mismatch: expected " & $baseline.domainCount & " got " & $report.domainCount)
    logger.info("[verification-auditor-gate] FAIL")
    quit(1)

when isMainModule:
  main()

{.pop.}

