import core/trusted/layer_declaration
axiomLayer "gate"
{.experimental: "codeReordering".}
## gateway.nim — Monolithic Axiom Gateway (``axiom-gate``)
##
## Single entry-point binary consolidating all hook logic and the
## commit pipeline logic.
##
## Subcommands:
##   axiom-gate commit --message "..." [--skip-ci] [files...]
##   axiom-gate hook pre-commit        [args...]
##   axiom-gate hook prepare-commit-msg [args...]
##   axiom-gate hook commit-msg        [args...]
##   axiom-gate hook pre-push          [args...]
##
## Build:
##   nim c -d:release -o:bin/axiom-gate src/gate/gateway.nim

{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/trusted/env_access
import core/trusted/bypass_verify
import core/gate/gate_memo
import gate/orchestrator_hook as orch
import gate/git
import gate/runners/fail_secure_state
import infrastructure/logging_facade
import infrastructure/cas_index
import gate/gate_contract
import core/parsers/safe_parsers
import core/results
import core/gate/state_ledger
import core/gate/state_ledger_types
import core/gate/hash_types
import core/interfaces/git_operations
import core/utils/repo_root
import gate/self_ref_detect
import gate/bootstrap_verifier
import std/[json, os, osproc, options, parseopt, selectors, sequtils, strformat, strutils, times, monotimes]
import std/posix
import core/gate/gate_cas
import infrastructure/bypass_audit

# ══════════════════════════════════════════════════════════════════════════════
# Constants
# ══════════════════════════════════════════════════════════════════════════════

const
  DefaultHookTimeoutMs* = 30_000     ## 30s for hook subcommands
  DefaultCommitTimeoutMs* = 600_000  ## 10 min for commit pipeline
  GatewayVersion = "1.0.0"
  EnvAxiomGateL2 = "AXIOM_GATE_L2"

proc isL2CommitMode(): bool =
  let value = getEnv(EnvAxiomGateL2).strip().toLowerAscii()
  result = value in ["1", "true", "yes", "on"]

# ══════════════════════════════════════════════════════════════════════════════
# runWithTimeout — subprocess execution with timeout enforcement
# ══════════════════════════════════════════════════════════════════════════════

proc runWithTimeout(args: seq[string], timeoutMs: int): int
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Spawn a subprocess and enforce a wall-clock timeout.
  ## Returns the child exit code, or 1 on timeout.
  if args.len == 0:
    logError("gateway", "[AXIOM GATE] runWithTimeout: no command specified")
    return 1
  let p = startProcess(command = args[0], args = args[1 .. ^1],
                       options = {poParentStreams, poStdErrToStdOut})
  defer: p.close()
  let exitCode = p.waitForExit(timeout = timeoutMs)
  if exitCode == -1:
    p.kill()
    logError("gateway", "[AXIOM GUARD] Process execution timed out (" &
             $(timeoutMs div 1000) & "s). Killed.")
    return 1
  return exitCode

# ══════════════════════════════════════════════════════════════════════════════
# Git helpers (local to gateway)
# ══════════════════════════════════════════════════════════════════════════════

proc findGit(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  git_operations.findRealGit()

proc runGit(args: string): tuple[output: string, exitCode: int]
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  git_operations.runGitEx(git_operations.findRealGit(), args)

proc getStagedFileList(repoRoot: string): seq[string]
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Get list of files staged for commit.
  let (output, exitCode) = execCmdEx(findGit() & " -C " & quoteShell(repoRoot) & " diff --cached --name-only")
  if exitCode != 0:
    return @[]
  result = @[]
  for line in output.splitLines():
    let stripped = line.strip()
    if stripped.len > 0:
      result.add(stripped)

# ══════════════════════════════════════════════════════════════════════════════
# Subcommand: commit
# ══════════════════════════════════════════════════════════════════════════════

proc parseCommitArgs(args: seq[string]): tuple[message: string, files: seq[string], skipCi: bool] =
  ## Parse commit subcommand arguments.
  ## Usage: axiom-gate commit --message "msg" [--skip-ci] [file1 file2 ...]
  result.message = ""
  result.files = @[]
  result.skipCi = false
  var positional: seq[string] = @[]

  for cmdKind, cmdKey, cmdVal in getopt(args):
    case cmdKind
    of cmdArgument:
      positional.add(cmdKey)
    of cmdLongOption, cmdShortOption:
      case cmdKey
      of "message", "m":
        result.message = cmdVal
      of "skip-ci":
        result.skipCi = true
      else:
        discard
    of cmdEnd:
      discard

  if result.message.len == 0 and positional.len > 0:
    result.message = positional[0]
    result.files = positional[1 .. ^1]
  else:
    result.files = positional

proc findRoot(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Walk upward to find .axiom_root marker.
  ## Delegates to the SSOT in repo_root.nim.
  repo_root.findRepoRoot(getCurrentDir())

proc stageFiles(files: seq[string]): bool
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  if files.len == 0:
    return false
  for f in files:
    let (outp, code) = runGit("add " & quoteShell(f))
    if code != 0:
      logError("gateway", "[gateway] Failed to stage " & f & ": " & outp)
      return false
  return true

proc hasStagedChanges(): bool
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let (outp, code) = runGit("diff --cached --name-only")
  if code != 0:
    return false
  return outp.strip().len > 0

proc runToolVerify(toolRel: string, args: seq[string], projectRoot: string): tuple[ok: bool, msg: string]
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Invoke a tools/ verification entry out-of-process (import-encapsulation:
  ## src/ must never import tools/). Returns (success, output).
  let nimExe = getEnv("NIM_EXE")
  let nimBin = if nimExe.len > 0: nimExe else: "nim"
  let cmd = nimBin & " r " & quoteShell(projectRoot / toolRel) & " " &
            args.mapIt(quoteShell(it)).join(" ")
  let (output, code) = execCmdEx(cmd, options = {poStdErrToStdOut})
  result = (code == 0, output.strip())

proc normalizePhase(projectRoot: string)
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Phase 1: 상태 정규화 — verify manifest is up-to-date (read-only).
  let (ok, msg) = runToolVerify("tools/feature_manifest_generator.nim", @["verify"], projectRoot)
  if not ok:
    logWarn("gateway", "[gateway] feature manifest: " & msg)

proc verifyToolchainLock(projectRoot: string): bool
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify toolchain binaries match data/toolchain_lock.json (out-of-process).
  let (ok, msg) = runToolVerify("tools/toolchain_verify.nim", @[], projectRoot)
  if not ok:
    logError("gateway", "[gateway] " & msg)
    return false
  logDebug("gateway", "[gateway] toolchain lock verified OK")
  return true

type
  ProcessResult = object
    output: string
    exitCode: int
    timedOut: bool

proc runProcessStreaming*(executable: string, args: seq[string], workDir: string,
                          timeoutSec: int): ProcessResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let cmdArgs = @["-c", "exec setsid " & quoteShell(executable) & " " & args.map(quoteShell).join(" ")]
  let p = startProcess("/bin/sh", args = cmdArgs,
                       options = {poStdErrToStdOut},
                       workingDir = workDir)

  let startTime = getMonoTime()
  let fd = p.outputHandle()
  let originalFlags = fcntl(fd, F_GETFL, 0)
  discard fcntl(fd, F_SETFL, originalFlags or O_NONBLOCK)
  let selector = newSelector[int]()
  selector.registerHandle(fd, {Event.Read}, 0)
  var buffer = newString(4096)

  block eventLoop:
    while true:
      let elapsedSec = (getMonoTime() - startTime).inSeconds
      if elapsedSec > timeoutSec:
        result.timedOut = true
        discard posix.kill(Pid(-p.processID()), SIGKILL)
        break eventLoop

      let exitCode = p.peekExitCode()
      if exitCode != -1:
        result.exitCode = exitCode

      let remainingMs = int((timeoutSec - elapsedSec) * 1000)
      let events = selector.select(min(remainingMs, 100))

      for event in events:
        if Event.Read in event.events:
          let bytesRead = read(fd, addr buffer[0], buffer.len)
          if bytesRead > 0:
            result.output.add(buffer[0..<bytesRead])
          elif bytesRead == 0:
            break eventLoop
          else:
            let err = errno
            if err == EINTR or err == EAGAIN or err == EWOULDBLOCK:
              continue
            else:
              break eventLoop

  selector.unregister(fd)
  selector.close()
  discard fcntl(fd, F_SETFL, originalFlags)
  p.close()

proc runMakeTest(projectRoot: string): bool
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  logInfo("gateway", "[gateway] Phase 2c: Running make test (perf budget)...")
  let nimExe = getEnv("NIM_EXE", "nim")
  let (output, code) = execCmdEx("make " & quoteShell("NIM=" & nimExe) & " test",
                                  options = {poStdErrToStdOut}, workingDir = projectRoot)
  if code != 0:
    logError("gateway", "[gateway] make test (perf budget) FAILED:\n" & output)
    return false
  logInfo("gateway", "[gateway] make test (perf budget) PASSED")
  return true

proc runSpecDriftCheck(projectRoot: string): bool
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  logInfo("gateway", "[gateway] Phase 2d: Running spec drift check...")
  let (output, code) = execCmdEx(
    getEnv("NIM_EXE", "nim") & " c -r src/gate/runners/spec_binding_gate.nim",
    options = {poStdErrToStdOut}, workingDir = projectRoot)
  if code != 0:
    logError("gateway", "[gateway] Spec drift check FAILED:\n" & output)
    return false
  logInfo("gateway", "[gateway] Spec drift check PASSED")
  return true

proc casLockCheck(projectRoot: string, snapshotSha: string): bool
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let (output, exitCode) = runGit("rev-parse --verify HEAD")
  if exitCode != 0:
    logError("gateway", "[gateway] CAS: Failed to get current HEAD")
    return false
  let currentSha = output.strip()
  if currentSha != snapshotSha:
    logError("gateway", "[gateway] CAS LOCK FAILED: HEAD moved during pipeline execution")
    logError("gateway", "  Snapshot: " & snapshotSha[0 .. min(7, snapshotSha.len - 1)])
    logError("gateway", "  Current:  " & currentSha[0 .. min(7, currentSha.len - 1)])
    logError("gateway", "  Action:   Re-run pipeline with fresh worktree")
    return false
  logDebug("gateway", "[gateway] CAS: HEAD unchanged — safe to commit")
  return true

proc runGateHookWithTimeout(projectRoot: string; forCommit: bool): tuple[output: string, exitCode: int]
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Run self (axiom-gate hook pre-commit) with timeout — in-process via recursive call.
  let timeout = safeParseInt(getAxiomEnv(evGateTimeout, "600")).getOrDefault(600)
  # Re-invoke self as subprocess for isolation (gate_hook expects separate process)
  let gatewayBin = findExe("axiom-gate")
  if gatewayBin.len > 0:
    if forCommit:
      putEnv("AXIOM_GATE_FOR_COMMIT", "1")
    else:
      delEnv("AXIOM_GATE_FOR_COMMIT")
    defer: delEnv("AXIOM_GATE_FOR_COMMIT")
    let exitCode = runWithTimeout(@[gatewayBin, "hook", "pre-commit"], timeout * 1000)
    return ("", exitCode)
  else:
    # Fallback: try legacy gate_hook binary
    let gateHook = projectRoot / "bin" / "gate_hook"
    if fileExists(gateHook):
      if forCommit:
        putEnv("AXIOM_GATE_FOR_COMMIT", "1")
      else:
        delEnv("AXIOM_GATE_FOR_COMMIT")
      defer: delEnv("AXIOM_GATE_FOR_COMMIT")
      let exitCode = runWithTimeout(@[gateHook, "pre-commit"], timeout * 1000)
      return ("", exitCode)
    logError("gateway", "[GATE] gate_hook binary not found at " & gateHook & " — run `make build` (or bin/precompile_gates) first; failing closed per §0.9")
    return ("", 1)

proc logTiming(label: string, start: MonoTime) =
  let elapsed = (getMonoTime() - start).inMilliseconds
  logDebug("gateway", "[TIMING] " & label & ": " & $elapsed & "ms")

proc runCommitCommand(args: seq[string]): int
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Execute the commit pipeline in-process.
  ## This consolidates the full commit flow: normalize → stage → gate →
  ## dual-track → CAS lock → atomic commit.
  let (message, files, skipCi) = parseCommitArgs(args)

  if message.len == 0:
    logError("gateway", "[gateway] Error: commit message required")
    logInfo("gateway", "Usage: axiom-gate commit --message \"msg\" [--skip-ci] [file1 file2 ...]")
    return 1

  let projectRoot = findRoot()

  let pipelineStart = getMonoTime()

  # ── Phase 1: 상태 정규화 (Idempotent Mutation) ──
  let phase1Start = getMonoTime()
  normalizePhase(projectRoot)
  logTiming("Phase 1 (normalize)", phase1Start)

  # ── Phase 2: 스냅샷 고정 (Immutable Snapshot) ──
  let phase2Start = getMonoTime()
  if files.len > 0:
    if not stageFiles(files):
      logError("gateway", "[gateway] Failed to stage files")
      return 1
  discard runGit("add -u")
  let staged = hasStagedChanges()
  logTiming("Phase 2 (stage)", phase2Start)

  # ── Phase 2a: CAS snapshot SHA ──
  let (snapshotHeadOut, snapshotHeadCode) = runGit("rev-parse --verify HEAD")
  let snapshotSha = if snapshotHeadCode == 0: snapshotHeadOut.strip() else: ""

  # ── Phase 2b: Toolchain Hash Verification ──
  let phase2bStart = getMonoTime()
  if not verifyToolchainLock(projectRoot):
    logError("gateway", "[gateway] Toolchain verification failed — commit aborted")
    return 1
  logTiming("Phase 2b (toolchain)", phase2bStart)

  # ── Phase 2c: Perf Budget Check (make test) ──
  let phase2cStart = getMonoTime()
  if not runMakeTest(projectRoot):
    logError("gateway", "[gateway] make test (perf budget) failed — commit aborted")
    return 1
  logTiming("Phase 2c (make test)", phase2cStart)

  # ── Phase 2d: Spec Drift Check ──
  let phase2dStart = getMonoTime()
  if not runSpecDriftCheck(projectRoot):
    logError("gateway", "[gateway] Spec drift check failed — commit aborted")
    return 1
  logTiming("Phase 2d (spec drift)", phase2dStart)

  # ── Phase 2.5: COMMIT_EDITMSG 시드 ──
  let commitMsgPath = projectRoot / ".git" / "COMMIT_EDITMSG"
  try:
    writeFile(commitMsgPath, message)
  except CatchableError as e:
    logWarn("gateway", "[gateway] WARNING: could not seed COMMIT_EDITMSG: " & e.msg)

  # ── Phase 3: 순수 함수 검증 (Verification) ──
  let phase3Start = getMonoTime()
  var contextToken = ""
  var effectiveSkipCi = skipCi

  # Run gate hook pre-commit (spawns self for process isolation)
  let gateHook = projectRoot / "bin" / "gate_hook"
  let axiomGateBin = findExe("axiom-gate")
  if fileExists(gateHook) or axiomGateBin.len > 0:
    let treeHash = execProcess("git write-tree").strip()
    if treeHash.len > 0:
      contextToken = treeHash
      putEnv("AXIOM_GATE_CONTEXT_ID", contextToken)
    let (gateOutput, gateExit) = runGateHookWithTimeout(projectRoot, forCommit = true)
    if gateExit != 0:
      if contextToken.len > 0:
        delEnv("AXIOM_GATE_CONTEXT_ID")
      logError("gateway", "[gateway] Gates failed.\n" & gateOutput)
      return 1

    # Auto-inject [skip ci] if orchestrator detected docs-only changes
    if not effectiveSkipCi:
      let skipCiPath = projectRoot / ".axiom" / "skip_ci"
      if fileExists(skipCiPath):
        try:
          let content = readFile(skipCiPath).strip()
          if content == "true":
            effectiveSkipCi = true
            logInfo("gateway", "[gateway] Auto-injected [skip ci] (docs-only changes detected)")
            removeFile(skipCiPath)
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
  else:
    ## DEBT#286 theater fix — neither gate_hook nor axiom-gate binary available.
    ## Previously this path silently skipped Phase 3 (Dead Gate, Theater Sig#5).
    ## Now fail-closed per §0.9 with persistent audit record.
    logError("gateway", "[GATE] CRITICAL: No gate execution binary available — gate_hook not found at " & gateHook & " and axiom-gate not in PATH. Failing closed per §0.9 (DEBT#286 remediation)")
    logError("gateway", "[GATE] Required: run `make build` or `bin/precompile_gates` to produce bin/gate_hook")
    ## Write persistent audit record for bypass detection
    let auditDir = projectRoot / ".axiom"
    try:
      discard existsOrCreateDir(auditDir)
      let auditPath = auditDir / "bypass_audit.jsonl"
      let timestamp = getTime().toUnix()
      let entry = &"""{{"timestamp":{timestamp},"event":"gate_binary_missing","severity":"critical","detail":"Neither gate_hook nor axiom-gate binary available — Phase 3 gates skipped","debt":"DEBT#286"}}"""
      let f = open(auditPath, fmAppend)
      f.writeLine(entry)
      f.close()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    return 1
  logTiming("Phase 3 (gates)", phase3Start)

  # ── Phase 3.6: CAS Lock Check ──
  let phase36Start = getMonoTime()
  if not casLockCheck(projectRoot, snapshotSha):
    logError("gateway", "[gateway] CAS lock failed — HEAD moved during pipeline")
    return 1
  logTiming("Phase 3.6 (CAS lock)", phase36Start)

  # ── Phase 4: 원자적 커밋 (Atomic Commit) ──
  let phase4Start = getMonoTime()
  var finalMessage = message
  if effectiveSkipCi:
    finalMessage.add("\n\n[skip ci] Docs-only change — CI pipeline skipped")

  var cmd = "commit"
  cmd.add " --no-verify"
  if not staged:
    cmd.add " --allow-empty"
  cmd.add " -m " & quoteShell(finalMessage)

  let (outp, code) = runGit(cmd)
  if contextToken.len > 0:
    delEnv("AXIOM_GATE_CONTEXT_ID")

  if code != 0:
    logError("gateway", "[gateway] Commit failed: " & outp)
    return code
  logTiming("Phase 4 (commit)", phase4Start)

  # Structured JSON output
  logTiming("Total pipeline", pipelineStart)
  var output = newJObject()
  output["exitCode"] = newJInt(0)
  output["stdout"] = newJString(outp)
  output["stderr"] = newJString("")
  output["skipCi"] = newJBool(effectiveSkipCi)
  output["version"] = newJString(GatewayVersion)
  stdout.writeLine(pretty(output))
  return 0

# ══════════════════════════════════════════════════════════════════════════════
# AOT Cache Validation
# ══════════════════════════════════════════════════════════════════════════════

proc countMissingCasBinaries(repoRoot: string; stage: GateStage): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Count gate runners for the given stage (pre-commit/pre-push) that lack
  ## pre-compiled CAS binaries.
  ## Iterates all registered gates, resolves each source path, and checks
  ## whether a CAS binary already exists. Returns 0 when all gates for the
  ## stage are pre-compiled (or have no resolvable source).
  result = 0
  try:
    for gate in allGates():
      if gate.entry.len == 0:
        continue
      # fail-close는 스테이지별 게이트만 — 해당 스테이지에서 precompile 필요 (2026-07 타임아웃 수정)
      if stage notin gate.stages:
        continue
      if gate.executionMode == "interpreted":
        continue  # Interpreted gates are not pre-compiled to CAS binaries.
      let srcPath = orch.resolveGateSourcePath(gate.entry)
      if srcPath.len == 0:
        continue  # No source file — skip (will fail at execution time anyway)
      let casBin = gate_cas.resolveCasBinaryPath(
        gate.id, srcPath, repoRoot)
      if casBin.len == 0:
        inc result
  except CatchableError:
    # On any error, assume all gates are missing (fail-safe: trigger precompile)
    result = high(int)

# ══════════════════════════════════════════════════════════════════════════════
# Subcommand: hook pre-commit
# ══════════════════════════════════════════════════════════════════════════════

proc runHookPreCommit(args: seq[string])
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Execute pre-commit hook logic in-process.
  ## Delegates to orchestrator_hook entry points.

  # DX: skip cgroup/systemd-run wrapping for local hook execution (CI keeps isolation).
  putEnv("AXIOM_LOW_OVERHEAD", "1")

  # --dry-run mode: run gates without committing (for bootstrap self-verification)
  for arg in args:
    if arg == "--dry-run":
      let epoch = gate_memo.advanceCacheEpoch()
      orch.runPreCommit(epoch)
      quit(0)  # If runPreCommit returned, all gates passed (it calls quit(1) on failure)

  let (repoRoot, maxJobs) = orch.bootstrapGateEnvironment()

  # --purge-cache
  for arg in args:
    if arg == "--purge-cache":
      discard gate_memo.advanceCacheEpoch()
      logInfo("gateway", "[CACHE] Cache epoch advanced successfully.")
      quit(0)

  # --rebaseline (DEBT#478: explicit flag threaded as a parameter — no ambient env transport)
  var rebaselineMode = false
  for arg in args:
    if arg == "--rebaseline":
      rebaselineMode = true
      logInfo("gateway", "[GATE] Rebaseline mode enabled.")
      break

  # Emergency bypass — env var + Ed25519 signature (SANCTIONED ONLY)
  if isEmergencyBypass():
    let sigHex = getAxiomEnv(evBypassSignature, "")
    let pubHex = getAxiomEnv(evBypassPubkey, "")
    let reason = getAxiomEnv(evBypassReason, "agent-emergency")
    if sigHex.len == 128 and pubHex.len == 64 and
       verifyBypassSignature(reason, sigHex, pubHex):
      logInfo("gateway", "[AXIOM GUARD] Signed emergency bypass verified. Skipping all gates.")
      let auditPath = repoRoot / ".axiom" / "bypass_audit.jsonl"
      try:
        let entry = "{\"ts\":$1,\"reason\":\"$2\",\"pubkey\":\"$3\",\"window\":$4,\"type\":\"ephemeral\"}" %
          [$getTime().toUnix(), reason, pubHex[0 .. 15], $currentTimeWindow()]
        let f = open(auditPath, fmAppend)
        f.writeLine(entry)
        f.close()
      except CatchableError as e:
        stderr.writeLine("[FATAL] Bypass audit write failed: " & e.msg)
        quit(1)
      quit(0)
    else:
      logError("gateway", "[AXIOM GUARD] BLOCKED: Emergency bypass signature invalid")
      quit(1)

  # Context Token Sanitizer — prevent double execution
  let ctxId = getAxiomEnv(evGateContextId)
  if ctxId.len > 0:
    let parts = ctxId.split("_", maxSplit = 1)
    if parts.len == 2:
      try:
        let currentTree = execProcess("git write-tree").strip()
        if parts[0] == currentTree and currentTree.len > 0:
          let receiptPath = repoRoot / ".axiom" / "gate_receipt.json"
          if fileExists(receiptPath):
            logInfo("gateway", "[GATE] Context token verified — short-circuit (0ms)")
            quit(0)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    logInfo("gateway", "[GATE] Invalid context token — ignoring")
    delEnv("AXIOM_GATE_CONTEXT_ID")

  let gateStage = orch.resolveGateStage("pre-commit")

  let forCommit = getEnv("AXIOM_GATE_FOR_COMMIT") == "1"

  # Epoch-based cache initialization
  gate_memo.migrateFromFlat()
  let cacheEpoch = gate_memo.currentCacheEpoch()

  logInfo("gateway", &"[GATE] Axiom gateway pre-commit — jobs={maxJobs} epoch={cacheEpoch}")

  # Manifest integrity check (always — no AXIOM_STATE_LEDGER_PATH bypass)
  if not orch.checkManifestIntegrity():
    quit(1)

  # Pre-commit specific: contract boundary guard
  let changedFiles = gitDiffCachedNames()
  for f in changedFiles:
    if f.endsWith("gate_contract.nim"):
      let isNewOutput = execProcess(
        "git diff --cached --diff-filter=A --name-only -- " & f).strip()
      if isNewOutput.len == 0:
        let commitMsgPath = repoRoot / ".git" / "COMMIT_EDITMSG"
        if fileExists(commitMsgPath):
          let commitMsg = readFile(commitMsgPath)
          if "[Arch-Review-Verified]" notin commitMsg:
            logInfo("gateway", "[FAIL] [Axiom Guard] gate_contract.nim is a READ-ONLY contract boundary.")
            logInfo("gateway", "   Modifications require [Arch-Review-Verified] in commit message.")
            quit(1)

  # Pre-commit: empty .feature file rejection
  for f in changedFiles:
    if f.endsWith(".feature"):
      if fileExists(f):
        let content = readFile(f)
        if "Scenario:" notin content:
          logInfo("gateway", "[FAIL] [Axiom Guard] Empty .feature file rejected: " & f)
          quit(1)

  # -- AOT-Only Enforcement: Fail-Close policy for CAS binaries --
  # Hook stages (pre-commit, pre-push) must never JIT-compile gate binaries.
  # If ANY gate is missing from CAS, commit is blocked — no auto-recovery.
  let missingGates = countMissingCasBinaries(repoRoot, gsPreCommit)
  if missingGates > 0:
    logError("gateway", "[AOT] " & $missingGates &
      " pre-commit gates missing from CAS. ALL pre-commit gates must be pre-compiled.")
    logError("gateway", "[AOT] Run: bin/precompile_gates")
    logError("gateway", "[AOT] Fail-close policy: commit blocked until all gates compile.")
    quit(1)

  # Φ3-B: CAS cache check
  block casEarlyExit:
    try:
      let transHash = computeSoundCasHash(repoRoot)
      if transHash.len > 0 and isCacheHitForHash(transHash):
        bypass_audit.logBypass("cas_cache_hit", "pre-commit: CAS cache hit — verification skipped")
        logInfo("gateway", "[GATE-CAS] Cache hit — skipping execution")
        quit(0)
      elif transHash.len > 0:
        logInfo("gateway", "[GATE-CAS] Cache miss — running gates")
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  # ── Bootstrap Protocol: Self-Referential Change Detection ──────────
  # When axiom-gate's own source files are being modified, use the
  # Two-Phase Hermetic Bootstrapping protocol instead of running gates
  # with the old binary (which would hit cached failures = Bootstrap Paradox).
  block bootstrapProtocol:
    let stagedFiles = getStagedFileList(repoRoot)
    if self_ref_detect.isSelfReferentialChange(stagedFiles):
      logInfo("gateway", "[BOOTSTRAP] Self-referential change detected — " &
        $self_ref_detect.getSensitiveFiles(stagedFiles).len & " sensitive files")
      let bootResult = bootstrap_verifier.runBootstrapVerification(repoRoot, stagedFiles)
      if bootResult.ok:
        logInfo("gateway", "[BOOTSTRAP] Next-state binary verified and promoted: " &
          bootResult.nextBinaryPath)
        quit(0)  # Bootstrap succeeded — skip normal gate execution
      elif bootResult.deferred:
        logWarn("gateway", "[BOOTSTRAP] Compilation deferred to CI: " & bootResult.reason)
        putEnv("AXIOM_BOOTSTRAP_DEFERRED", "1")
        # Continue to normal gate execution (will use old binary but gates may pass)
      else:
        logError("gateway", "[BOOTSTRAP] Verification failed: " & bootResult.reason)
        quit(1)

  # Single gate mode
  let singleResult = orch.runSingleGateIfRequested(gateStage, repoRoot, maxJobs, cacheEpoch,
                                                   updateBaseline = rebaselineMode)
  if singleResult.isSome:
    quit(if singleResult.get: 0 else: 1)

  # Normal multi-gate execution
  orch.runPreCommit(cacheEpoch, forCommit = forCommit, updateBaseline = rebaselineMode)

# ══════════════════════════════════════════════════════════════════════════════
# Subcommand: hook prepare-commit-msg
# ══════════════════════════════════════════════════════════════════════════════

proc runHookPrepareCommitMsg(args: seq[string])
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Execute prepare-commit-msg hook logic in-process.
  ## Replicates tools/hooks/prepare_commit_msg.nim logic since it lives
  ## in ``when isMainModule`` and cannot be imported directly.

  let commitMsgFile = if args.len >= 1: args[0] else: ""
  let source        = if args.len >= 2: args[1] else: ""
  discard commitMsgFile
  discard source

  # Emergency bypass: requires signed bypass
  if isEmergencyBypass():
    stderr.writeLine("[AXIOM GUARD] Signed emergency bypass acknowledged. Must be documented post-hoc.")
    quit(0)

  let nowEpoch = getTime().toUnix()

  proc execGitLocal(gitArgs: openArray[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    let (output, exitCode) = git_operations.runGit(gitArgs.join(" "))
    if exitCode != 0:
      return ""
    output.strip(leading = false, trailing = true, chars = Whitespace + Newlines)

  proc parseEpochSafe(s: string): Option[int64] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    let trimmed = s.strip()
    if trimmed.len == 0:
      return none(int64)
    let epochRes = safeParseInt(trimmed)
    if epochRes.isOk: result = some(epochRes.get.int64)

  proc isRecentEpoch(candidate: Option[int64]; now: int64; window: int64): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    if candidate.isNone:
      return false
    let age = now - candidate.get
    if age < 0:
      return false
    age <= window

  # ── Content-Addressed Staging Verification (v4) ──────────────────────
  # Replaces time-based 60-second sentinel with content-addressed git write-tree.
  # Pre-commit gates record the staging tree SHA in State Ledger v4.
  # If the staging area hasn't changed, tree SHA matches → commit allowed.
  # No time dependency → no catch-22 deadlock when gates take >60s.
  block stagingVerification:
    let repoRoot = execProcess("git rev-parse --show-toplevel").strip()
    if repoRoot.len == 0:
      stderr.writeLine("[AXIOM GUARD] ERROR: Not inside a git repository.")
      quit(1)

    # Compute current staging tree SHA
    let currentTreeSha = execProcess("git write-tree").strip()
    if currentTreeSha.len == 0:
      stderr.writeLine("[AXIOM GUARD] ERROR: git write-tree failed (no staged changes?).")
      stderr.writeLine("[AXIOM GUARD] Pre-commit gates must run before prepare-commit-msg.")
      quit(1)

    # Open State Ledger v4 to read the recorded staging tree hash
    let ledger = openLedger(repoRoot)
    if ledger == nil:
      stderr.writeLine("[AXIOM GUARD] ERROR: State Ledger not found or invalid.")
      stderr.writeLine("[AXIOM GUARD] Pre-commit gates must run and pass before committing.")
      stderr.writeLine("[AXIOM GUARD] Emergency bypass: AXIOM_EMERGENCY_NO_VERIFY=1 (must be documented post-hoc).")
      stderr.writeLine("")
      stderr.writeLine("[AXIOM GUARD] Per githooks(5): --no-verify suppresses pre-commit and commit-msg,")
      stderr.writeLine("[AXIOM GUARD] but prepare-commit-msg still runs and this guard blocks the commit.")
      quit(1)

    # Read recorded staging tree hash from ledger
    let recordedHashPtr = getStagingTreeHash(ledger)
    let recordedHash = recordedHashPtr[]
    closeLedger(ledger)

    # If stagingTreeHash is void (all zeros), gates didn't record it
    if isVoid(recordedHash):
      stderr.writeLine("[AXIOM GUARD] ERROR: No staging tree hash recorded in ledger.")
      stderr.writeLine("[AXIOM GUARD] Pre-commit gates must record tree state before committing.")
      quit(1)

    # Compare current staging tree against recorded hash
    let currentHash = hashValueFromHex(currentTreeSha)
    if currentHash != recordedHash:
      stderr.writeLine("[AXIOM GUARD] ERROR: Staging area changed since gates passed.")
      stderr.writeLine("[AXIOM GUARD] Current tree:  " & currentTreeSha[0..min(15, currentTreeSha.len-1)] & "...")
      stderr.writeLine("[AXIOM GUARD] Recorded hash: " & hashValueToHex(recordedHash)[0..15] & "...")
      stderr.writeLine("[AXIOM GUARD] Re-run: git commit (triggers fresh gate execution)")
      quit(1)

  # Determine if strict gate is needed based on changed files
  let changedFiles = execGitLocal(["diff", "--cached", "--name-only", "--diff-filter=ACM"])
  var needsStrictGate = false
  for line in changedFiles.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    if trimmed.startsWith("src/") or
       trimmed.startsWith("src/semantic_proofs/") or
       trimmed in ["lakefile.toml", "lean-toolchain", "axiom.nimble", "config.nims"]:
      needsStrictGate = true
      break

  if not needsStrictGate:
    quit(0)

  # Fallback: integrity stamp file
  let integrityStamp = "logs/.integrity_gate_passed_epoch"
  if fileExists(integrityStamp):
    let stampText = try:
      readFile(integrityStamp).strip()
    except CatchableError:
      ""
    if isRecentEpoch(parseEpochSafe(stampText), nowEpoch, 300):
      quit(0)

  stderr.writeLine("[AXIOM GUARD] ERROR: commit quality gate marker missing or stale.")
  stderr.writeLine("[AXIOM GUARD] Run 'prek run --hook-stage pre-commit' and retry.")
  quit(1)

# ══════════════════════════════════════════════════════════════════════════════
# Subcommand: hook commit-msg
# ══════════════════════════════════════════════════════════════════════════════

proc runHookCommitMsg(args: seq[string])
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Execute commit-msg hook logic in-process.
  ## Consolidates: bootstrap → fail-secure check.

  let (repoRoot, _) = orch.bootstrapGateEnvironment()

  # Emergency bypass — env var + Ed25519 signature (SANCTIONED ONLY)
  if isEmergencyBypass():
    let sigHex = getAxiomEnv(evBypassSignature, "")
    let pubHex = getAxiomEnv(evBypassPubkey, "")
    let reason = getAxiomEnv(evBypassReason, "agent-emergency")
    if sigHex.len == 128 and pubHex.len == 64 and
       verifyBypassSignature(reason, sigHex, pubHex):
      logInfo("gateway", "[AXIOM GUARD] Signed emergency bypass verified.")
      let auditPath = repoRoot / ".axiom" / "bypass_audit.jsonl"
      try:
        let entry = "{\"ts\":$1,\"reason\":\"$2\",\"pubkey\":\"$3\",\"window\":$4,\"type\":\"ephemeral\"}" %
          [$getTime().toUnix(), reason, pubHex[0 .. 15], $currentTimeWindow()]
        let f = open(auditPath, fmAppend)
        f.writeLine(entry)
        f.close()
      except CatchableError as e:
        stderr.writeLine("[FATAL] Bypass audit write failed: " & e.msg)
        quit(1)
      quit(0)
    else:
      logError("gateway", "[AXIOM GUARD] BLOCKED: Emergency bypass signature invalid")
      quit(1)

  # Fail-Secure reconciliation: verify audit log integrity
  let auditPath = repoRoot / ".axiom" / "bypass_audit.jsonl"
  let commitMsgPath = if args.len > 1: args[^1] else: ""
  let failState = computeState(auditPath, commitMsgPath)
  if not canBypass(failState):
    logError("gateway", &"[GATE] Fail-Secure state: {stateDescription(failState)}")
    logError("gateway", "[GATE] Audit log integrity check failed. Blocking commit.")
    quit(1)
  logInfo("gateway", &"[GATE] Fail-Secure state: {stateDescription(failState)} — OK")

# ══════════════════════════════════════════════════════════════════════════════
# Subcommand: hook pre-push
# ══════════════════════════════════════════════════════════════════════════════

proc runHookPrePush(args: seq[string])
  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Execute pre-push hook logic in-process.
  ## Parses stdin for push refs, then delegates to orchestrator_hook.

  let (repoRoot, maxJobs) = orch.bootstrapGateEnvironment()

  # --purge-cache
  for arg in args:
    if arg == "--purge-cache":
      discard gate_memo.advanceCacheEpoch()
      logInfo("gateway", "[CACHE] Cache epoch advanced successfully.")
      quit(0)

  # Emergency bypass — env var + Ed25519 signature (SANCTIONED ONLY)
  if isEmergencyBypass():
    let sigHex = getAxiomEnv(evBypassSignature, "")
    let pubHex = getAxiomEnv(evBypassPubkey, "")
    let reason = getAxiomEnv(evBypassReason, "agent-emergency")
    if sigHex.len == 128 and pubHex.len == 64 and
       verifyBypassSignature(reason, sigHex, pubHex):
      logInfo("gateway", "[AXIOM GUARD] Signed emergency bypass verified.")
      let auditPath = repoRoot / ".axiom" / "bypass_audit.jsonl"
      try:
        let entry = "{\"ts\":$1,\"reason\":\"$2\",\"pubkey\":\"$3\",\"window\":$4,\"type\":\"ephemeral\"}" %
          [$getTime().toUnix(), reason, pubHex[0 .. 15], $currentTimeWindow()]
        let f = open(auditPath, fmAppend)
        f.writeLine(entry)
        f.close()
      except CatchableError as e:
        stderr.writeLine("[FATAL] Bypass audit write failed: " & e.msg)
        quit(1)
      quit(0)
    else:
      logError("gateway", "[AXIOM GUARD] BLOCKED: Emergency bypass signature invalid")
      quit(1)

  let gateStage = orch.resolveGateStage("pre-push")

  # Epoch-based cache initialization
  gate_memo.migrateFromFlat()
  let cacheEpoch = gate_memo.currentCacheEpoch()

  logInfo("gateway", &"[GATE] Axiom gateway pre-push — jobs={maxJobs} epoch={cacheEpoch}")

  # Manifest integrity check (always — no AXIOM_STATE_LEDGER_PATH bypass)
  if not orch.checkManifestIntegrity():
    quit(1)

  # -- AOT-Only Enforcement: Fail-Close policy for CAS binaries (pre-push) --
  # Pre-push heavy gates (e.g. integrity-workflow) must never JIT-compile.
  # If ANY pre-push gate is missing from CAS, push is blocked — no auto-recovery.
  let missingPushGates = countMissingCasBinaries(repoRoot, gsPrePush)
  if missingPushGates > 0:
    logError("gateway", "[AOT] " & $missingPushGates &
      " pre-push gates missing from CAS. ALL pre-push gates must be pre-compiled.")
    logError("gateway", "[AOT] Run: bin/precompile_gates")
    logError("gateway", "[AOT] Fail-close policy: push blocked until all gates compile.")
    quit(1)

  # Ingestion Boundary: parse pre-push stdin
  let stdinData = stdin.readAll()
  var pushRefs: seq[PushRef]
  for line in stdinData.splitLines():
    if line.len == 0: continue
    let parts = line.splitWhitespace()
    if parts.len >= 4:
      let localSha = parts[1]
      let remoteSha = parts[3]
      if localSha.len == 40 and remoteSha.len == 40:
        pushRefs.add(PushRef(localRef: parts[0], localSha: localSha,
                             remoteRef: parts[2], remoteSha: remoteSha))

  # Φ3-B: CAS cache check
  block casEarlyExit:
    try:
      let transHash = computeSoundCasHash(repoRoot)
      if transHash.len > 0 and isCacheHitForHash(transHash):
        bypass_audit.logBypass("cas_cache_hit", "pre-push: CAS cache hit — verification skipped")
        logInfo("gateway", "[GATE-CAS] Cache hit — skipping execution")
        quit(0)
      elif transHash.len > 0:
        logInfo("gateway", "[GATE-CAS] Cache miss — running gates")
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  # Single gate mode
  let singleResult = orch.runSingleGateIfRequested(gateStage, repoRoot, maxJobs, cacheEpoch)
  if singleResult.isSome:
    quit(if singleResult.get: 0 else: 1)

  # Normal multi-gate execution — set push refs before dispatching
  orch.setPushRefs(pushRefs)
  orch.runPrePush(cacheEpoch)

# ══════════════════════════════════════════════════════════════════════════════
# Usage & Main Entry Point
# ══════════════════════════════════════════════════════════════════════════════

proc showUsage() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  stdout.writeLine("axiom-gate v" & GatewayVersion)
  stdout.writeLine("")
  stdout.writeLine("Monolithic Axiom Gateway — consolidates all hook + commit logic.")
  stdout.writeLine("")
  stdout.writeLine("Usage:")
  stdout.writeLine("  axiom-gate commit --message \"...\" [--skip-ci] [files...]")
  stdout.writeLine("  axiom-gate hook pre-commit [args...]")
  stdout.writeLine("  axiom-gate hook prepare-commit-msg [args...]")
  stdout.writeLine("  axiom-gate hook commit-msg [args...]")
  stdout.writeLine("  axiom-gate hook pre-push [args...]")
  stdout.writeLine("")
  stdout.writeLine("Options:")
  stdout.writeLine("  --message, -m  Commit message (for commit subcommand)")
  stdout.writeLine("  --skip-ci      Skip CI pipeline (for commit subcommand)")
  stdout.writeLine("  --purge-cache  Advance cache epoch and exit")
  stdout.writeLine("  --rebaseline   Rebaseline mode for all gates")
  stdout.writeLine("  --help, -h     Show this help message")
  stdout.writeLine("  --version, -v  Show version")

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let args = commandLineParams()

  if args.len == 0:
    showUsage()
    quit(0)

  # --help / --version (top-level)
  if args[0] == "--help" or args[0] == "-h":
    showUsage()
    quit(0)
  if args[0] == "--version" or args[0] == "-v":
    stdout.writeLine("axiom-gate " & GatewayVersion)
    quit(0)

  case args[0]
  of "commit":
    if isL2CommitMode():
      logInfo("gateway", "[AXIOM-GATE-L2] L2 commit pipeline enabled via AXIOM_GATE_L2=1")
    quit(runCommitCommand(args[1 .. ^1]))
  of "hook":
    if args.len < 2:
      logError("gateway", "Usage: axiom-gate hook <pre-commit|prepare-commit-msg|commit-msg|pre-push> [args...]")
      quit(1)
    case args[1]
    of "pre-commit":
      runHookPreCommit(args[2 .. ^1])
    of "prepare-commit-msg":
      runHookPrepareCommitMsg(args[2 .. ^1])
    of "commit-msg":
      runHookCommitMsg(args[2 .. ^1])
    of "pre-push":
      runHookPrePush(args[2 .. ^1])
    else:
      logError("gateway", "Unknown hook: " & args[1])
      logError("gateway", "Supported hooks: pre-commit, prepare-commit-msg, commit-msg, pre-push")
      quit(1)
  else:
    logError("gateway", "Unknown subcommand: " & args[0])
    showUsage()
    quit(1)

when isMainModule:
  main()

{.pop.}
