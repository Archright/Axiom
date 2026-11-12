## executor.nim — Gate execution, parallel dispatch for orchestrator hook.
## (domain: executor)

import core/trusted/layer_declaration
axiomLayer "gate"
{.experimental: "codeReordering".}

import core/axiom_pragmas
import core/types/results  # for isErr
import gate/orchestrator_types
import gate/orchestrator/hook/context
import gate/orchestrator/hook/memo
import gate/orchestrator/hook/analyzer
import gate/orchestrator_pure  # for classifyFailure
import core/trusted/env_access
import core/parsers/safe_parsers
import gate/gate_contract  # for GateConfig, PushRef
import gate/gate_utils
import gate/utils/gate_run_logger  # for TelemetryBuffer, logGate
import gate/utils/inprocess_dispatch  # for dispatchGateInProcess, tryDispatchInProcess
import gate/utils/gate_safety_macro  # for InProcessGateContext
import gate/utils/real_git  # for findRealGit
import core/gate/gate_cas  # for resolveCasBinaryPath
import infrastructure/logging_facade  # for logInfo, logError, logWarn
import core/gate/merkle_vfs  # for MerkleVfs
import gate/daemon/salsa_memo  # for SalsaMemoDb
import gate/daemon/gate_daemon_client  # for isDaemonRunning, startDaemon
import gate/daemon/symbol_cas
import gate/config_loader  # axiom:gate-config — Phase 3-C runtime config
import gate/types
import std/cpuinfo
import core/crypto/hash_kernel  # for sha256Hex
import core/gate/git_snapshot
import core/gate/hash_types
import core/gate/state_ledger
import core/gate/gate_memo  # for garbageCollectOldEpochs, computeBuildEnvHash
import core/gate/file_hash_cache
import core/gate/vfs_hasher  # for hashFiles, discoverFiles, diffAgainstCache, buildVfsFromCache
import gate/attestation
import gate/gate_dag
import core/topology/import_graph  # for buildImportGraph
import infrastructure/cas_index  # for CasEntry, persistCas
import core/trusted/bypass_verify  # for isEmergencyBypass
import malebolgia  # for createMaster
import infrastructure/vfs_intern
import std/os
import std/osproc
import std/strformat
import std/strutils
import std/tables
import std/times
import std/monotimes
import std/options
import std/posix
import std/sets
import std/streams  # for Stream readLine
import std/sequtils
import std/algorithm  # for sort
import std/json

# ---------------------------------------------------------------------------
# Command execution helpers
# ---------------------------------------------------------------------------
proc execCmdExWithBond*(cmd: string): tuple[output: string, exitCode: int] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let prev = getAxiomEnv(evGateBond)
  putEnv("AXIOM_GATE_BOND", "1")
  var p = startProcess("/bin/sh", args = @["-c", cmd], options = {poStdErrToStdOut, poUsePath})
  var outp = outputStream(p)
  close inputStream(p)
  result.output = ""
  var line = ""
  while true:
    if outp.readLine(line):
      result.output.add(line)
      result.output.add("\n")
    else:
      result.exitCode = peekExitCode(p)
      if result.exitCode != -1:
        break
  close(p)
  if prev.len == 0:
    delEnv("AXIOM_GATE_BOND")
  else:
    putEnv("AXIOM_GATE_BOND", prev)

proc wrapWithCgroupsIfAvailable*(cmd: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # Low-overhead mode: skip cgroup wrapping entirely
  if getAxiomEnv(evLowOverhead) == "1":
    return cmd
  let systemdRun = findExe("systemd-run")
  if systemdRun.len == 0:
    return cmd
  result = systemdRun &
    " --user --scope --slice=axiom-gate" &
    " --property=CPUQuota=50%" &
    " --property=IOWeight=10" &
    " --property=MemoryHigh=6G" &
    " --property=MemoryMax=8G" &
    " --property=RuntimeMaxSec=300s" &
    " --quiet --collect" &
    " -- " & cmd

# ---------------------------------------------------------------------------
# Single gate execution
# ---------------------------------------------------------------------------
proc runSingleGateImpl*(gate: GateConfig; repoRoot: string;
                       changedFiles: seq[string]; stage: GateStage;
                       mode: GateRunMode; maxJobs: int;
                       effectiveTimeoutMs: int; updateBaseline: bool = false): GateResult {.gcsafe, raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let start = getTime()

  if gate.layer == glMeta and
     (gate.entry.contains("gate_hook") or gate.entry.contains("pre-commit")):
    logError("", "[gate-hook] BLOCKED: Meta gate " & gate.id &
                     " references orchestrator entry point: " & gate.entry)
    stderr.flushFile()
    return GateResult(
      ok: false, name: gate.name,
      stdout: "", stderr: "Meta gate references orchestrator entry point: " & gate.entry,
      duration: initDuration())

  var entry = gate.entry
  if entry.len == 0:
    return GateResult(
      ok: false, name: gate.name,
      stdout: "Gate entry is empty: " & gate.id,
      stderr: "", duration: initDuration())

  # DEBT#471: in-process dispatch first. registerGate-only runners (e.g.
  # trust-commit-scope) have no standalone main — their AOT CAS binary is an
  # empty shell that exits 0, so the subprocess path below cannot enforce
  # them. Allowlisted light gates execute their real judgment here; every
  # other gate falls through unchanged (allowlist miss → dispatched=false).
  let inProcCtx = InProcessGateContext(
    repoRoot: repoRoot,
    stagedFiles: changedFiles,
    gateId: gate.id,
    epoch: 0,
    subtreeRoot: "",
    stage: ord(stage),
    maxJobs: maxJobs,
    passFilenames: gate.passFilenames,
    effectiveTimeoutMs: effectiveTimeoutMs)
  # cast(gcsafe): the in-process registry is written once at init and only
  # read afterwards (inprocess_dispatch.nim contract) — reads are safe from
  # malebolgia worker threads that reach runSingleGateImpl.
  let inProcDispatch = block:
    {.cast(gcsafe).}:
      tryDispatchInProcess(gate, inProcCtx)
  if inProcDispatch.dispatched:
    return inProcDispatch.gateResult

  let srcPath = context.resolveGateSourcePath(entry)
  var execPath = entry

  # entry가 이미 존재하는 prebuilt 바이너리(bin/ 등)면 그대로 실행 — JIT 우회.
  # 소스 우선 정책은 CAS miss 시 깨진 러너 소스(.nim 본문 소실)를 JIT 컴파일하다
  # 실패시키므로, prebuilt entry가 있으면 그것을 신뢰한다 (2026-07 타임아웃 수정).
  let entryAbs = if entry.isAbsolute: entry else: repoRoot / entry
  let hasPrebuiltEntry = fileExists(entryAbs) and fpUserExec in getFilePermissions(entryAbs)

  if hasPrebuiltEntry:
    execPath = entryAbs
  elif srcPath.len > 0:
    let casBinPath = gate_cas.resolveCasBinaryPath(gate.id, srcPath, repoRoot)
    if casBinPath.len > 0:
      execPath = casBinPath
    else:
      let nimcacheDir = repoRoot / ".axiom" / "cache" / "nimcache" / gate.id
      # AOT enforcement: hook/CI stages (pre-commit/pre-push/ci) MUST fail-fast
      # on CAS miss instead of JIT-compiling; only manual CLI mode may JIT.
      # Interpreted-mode gates are excluded from the AOT precompile contract
      # (precompile_gates skips them: "no AOT"), so they must JIT-compile at
      # every stage or CI can never run them (CAS MISS fail-fast).
      let allowJit = (stage == gsManual) or gate.executionMode == "interpreted"
      let compiledPath = gate_cas.compileGateToCas(
        gate.id, entry, srcPath, nimcacheDir, repoRoot, allowJit = allowJit)
      if compiledPath.len == 0:
        return GateResult(
          ok: false, name: gate.name,
          stdout: "CAS compile failed for " & gate.id,
          stderr: "", duration: getTime() - start)
      execPath = compiledPath
  elif not fileExists(entry):
    return GateResult(
      ok: false, name: gate.name,
      stdout: "Gate entry not found and no source: " & entry,
      stderr: "", duration: initDuration())

  # execPath만 quoting — 인자를 포함한 cmd 전체를 quoteShell로 감싸면
  # "binary --stdin-files"라는 단일 파일명으로 exec을 시도해 즉시 실패한다
  # (910cfafca 회귀, 2026-07 수정).
  var cmd = quoteShell(execPath)
  for arg in gate.argsTemplate:
    if arg == "$repoRoot":
      cmd.add(" " & quoteShell(repoRoot))
    elif arg == "$mode":
      cmd.add(" " & $mode)
    elif arg == "$maxJobs":
      cmd.add(" " & $maxJobs)
    else:
      cmd.add(" " & quoteShell(arg))
  if stage == gsPreCommit and gate.id == "external-cli-smoke":
    cmd.add(" --skip-heavy")
  if gate.id == "integrity-workflow":
    cmd.add(" --allow-jit=" & $(stage == gsManual))
  # DEBT#493: passFilenames 게이트는 변경 파일 목록을 argsTemplate 뒤에 이어지는
  # 위치 argv 토큰으로 받는다 — 모든 passFilenames 게이트 바이너리가 실제로 파싱하는
  # 계약 형태(language_ban_gate: "orchestrator provides staged file paths as args",
  # import_encapsulation_gate usage "[files...]"). 이전 리터럴 '--stdin-files' 토큰 +
  # stdin write는 stdin을 읽지 않는 바이너리에 도달해 존재하지 않는 경로를 스캔하고
  # 공허 PASS를 냈다. argv가 한도를 초과하면 exec이 E2BIG으로 소리 내어 실패한다
  # (nonzero exit → gate FAIL) — 결정론적 fail-closed, 조용한 오전달 없음.
  if gate.passFilenames and changedFiles.len > 0:
    for f in changedFiles:
      cmd.add(" " & quoteShell(f))

  if updateBaseline:
    cmd.add(" --update-baseline")

  var p = startProcess("/bin/sh", args = @["-c", "exec setsid " & cmd], workingDir = repoRoot,
                       options = {poStdErrToStdOut, poUsePath})
  close inputStream(p)
  let exitCode = p.waitForExit(timeout = effectiveTimeoutMs)
  if exitCode == -1:
    var timeoutOutput = ""
    try:
      timeoutOutput = p.outputStream.readAll()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    p.kill()
    p.close()
    logError("", &"  FAIL  {gate.name} ({gate.id}) (TIMEOUT: {effectiveTimeoutMs}ms exceeded)")
    return GateResult(
      ok: false, name: gate.name,
      stdout: timeoutOutput, stderr: "TIMEOUT: " & $effectiveTimeoutMs & "ms exceeded",
      duration: getTime() - start)

  let outp = outputStream(p)
  let output = outp.readAll()
  p.close()
  return GateResult(ok: exitCode == 0, name: gate.name,
                    stdout: output, stderr: "",
                    duration: getTime() - start)

# ---------------------------------------------------------------------------
# Gate dispatch (single gate)
# ---------------------------------------------------------------------------
proc dispatchGate*(gate: GateConfig; repoRootParam: string;
                  cf: seq[string]; maxJobs: int; stage: GateStage;
                  effectiveTimeoutMs: int; telemetry: var TelemetryBuffer;
                  updateBaseline: bool = false): GateResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let monoStart = getMonoTime()
  let ctx = InProcessGateContext(
    repoRoot: repoRootParam,
    stagedFiles: cf,
    gateId: gate.id,
    epoch: 0,
    subtreeRoot: "",
    stage: ord(stage),
    maxJobs: maxJobs,
    passFilenames: gate.passFilenames,
    effectiveTimeoutMs: effectiveTimeoutMs)
  let (dispatched, inProcResult) = tryDispatchInProcess(gate, ctx)
  if dispatched:
    let durationNs = (getMonoTime() - monoStart).inNanoseconds
    logGate(telemetry, gate.id,
            if inProcResult.ok: "pass" else: "fail",
            durationNs, tier = gate.tier)
    return inProcResult

  let mode = if stage == gsPreCommit: grmIncremental else: grmExhaustive
  let res = runSingleGateImpl(gate, repoRootParam, cf, stage, mode, maxJobs, effectiveTimeoutMs,
                              updateBaseline)
  let durationNs = (getMonoTime() - monoStart).inNanoseconds
  logGate(telemetry, gate.id,
          if res.ok: "pass" else: "fail",
          durationNs, tier = gate.tier)
  res

# ---------------------------------------------------------------------------
# L2 gate polling with timeout
# ---------------------------------------------------------------------------
proc pollL2GatesWithTimeout*(
  running: seq[RunningGate],
  l2Gates: seq[GateConfig],
  timeoutMs: int,
  changedFiles: seq[string],
  repoRoot: string,
  epoch: int,
  telemetry: var TelemetryBuffer,
  vfs: MerkleVfs = nil;
  journal: SessionJournal = nil
): tuple[stillRunning: seq[RunningGate], allOk: bool] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var stillRunning: seq[RunningGate]
  var allOk = true
  for rg in running:
    let gateId = l2Gates[rg.gateIdx].id
    let gateTier = l2Gates[rg.gateIdx].tier
    let effectiveTimeoutMs = context.loadGateSla(gateId)
    when defined(posix):
      let ws = peekWaitStatus(rg.process)
      case ws.kind
      of wskRunning:
        if (getTime() - rg.startTime).inMilliseconds > effectiveTimeoutMs:
          var timeoutOutput = ""
          try:
            timeoutOutput = rg.process.outputStream.readAll()
          except CatchableError: discard  # axiom:best-effort(ioboundary catch)
          rg.process.kill()
          rg.process.close()
          let label = &"{l2Gates[rg.gateIdx].name} ({gateId})"
          logError("", &"  FAIL  {label}  (TIMEOUT: {effectiveTimeoutMs}ms exceeded)")
          if timeoutOutput.len > 0:
            memo.writeGateOutputToFile(gateId, timeoutOutput)
          logGate(telemetry, gateId, "timeout",
                  effectiveTimeoutMs.int64 * 1_000_000, tier = gateTier,
                  outputFile = ".axiom/cache/gate_output/" & gateId & ".log",
                  terminationReason = "timeout")
          allOk = false
          if journal != nil:
            context.recordResult(journal, gateId, orchestrator_types.GateRunRecord(
              status: grsTimeout, elapsedMs: effectiveTimeoutMs,
              failCategory: fcPermanent, failReason: "TIMEOUT"))
          stderr.flushFile()
        else:
          stillRunning.add(rg)
      of wskExited:
        var capturedOutput = ""
        try:
          capturedOutput = rg.process.outputStream.readAll()
        except CatchableError: discard  # axiom:best-effort(ioboundary catch)
        close(rg.process)
        let duration = getTime() - rg.startTime
        let durationNs = duration.inNanoseconds
        let label = &"{l2Gates[rg.gateIdx].name} ({gateId})"
        let gateSubtreeRoot = if vfs != nil: vfs.computeSubtreeRoot(l2Gates[rg.gateIdx].filesPattern) else: ""
        if ws.code == 0:
          memo.persistGateMemo(l2Gates[rg.gateIdx], changedFiles, true, repoRoot, epoch, gateSubtreeRoot)
          memo.deleteGateOutputFile(gateId)
          logGate(telemetry, gateId, "pass", durationNs, tier = gateTier)
          logInfo("", &"  PASS  {label}  ({duration.inMilliseconds}ms)")
          if journal != nil:
            context.recordResult(journal, gateId, orchestrator_types.GateRunRecord(
              status: grsSuccess, elapsedMs: duration.inMilliseconds.int))
        else:
          let (failCat, failReason) = classifyFailure(ws.code, capturedOutput)
          # DEBT#471 value closure: the memo stores finding coordinates mined
          # from the output — quoted stdout prose is not the reason of record.
          # The live journal keeps the prose for this session only.
          memo.persistGateMemo(l2Gates[rg.gateIdx], changedFiles, false, repoRoot, epoch, gateSubtreeRoot,
                          failCat, "", gateOutput = capturedOutput)
          if capturedOutput.len > 0:
            memo.writeGateOutputToFile(gateId, capturedOutput)
          logGate(telemetry, gateId, "fail", durationNs, tier = gateTier,
                  outputFile = ".axiom/cache/gate_output/" & gateId & ".log",
                  exitCode = ws.code, terminationReason = "error")
          logError("", &"  FAIL  {label}  ({duration.inMilliseconds}ms) [{failCat}]")
          allOk = false
          if journal != nil:
            context.recordResult(journal, gateId, orchestrator_types.GateRunRecord(
              status: grsFailed, elapsedMs: duration.inMilliseconds.int,
              failCategory: failCat, failReason: failReason))
        stderr.flushFile()
      of wskSignalKilled:
        var capturedOutput = ""
        try: capturedOutput = rg.process.outputStream.readAll()
        except CatchableError: discard  # axiom:best-effort(ioboundary catch)
        close(rg.process)
        let duration = getTime() - rg.startTime
        let label = &"{l2Gates[rg.gateIdx].name} ({gateId})"
        logInfo("", &"  CRASH  {label}  (signal {ws.code}: {signalName(ws.code)})")
        memo.writeGateOutputToFile(gateId, capturedOutput)
        logGate(telemetry, gateId, "crash", duration.inNanoseconds, tier = gateTier,
                outputFile = ".axiom/cache/gate_output/" & gateId & ".log",
                exitCode = ws.code, terminationReason = "signal")
        allOk = false
        if journal != nil:
          context.recordResult(journal, gateId, orchestrator_types.GateRunRecord(
            status: grsCrash, elapsedMs: duration.inMilliseconds.int,
            failCategory: fcPermanent,
            failReason: "SIGNAL " & $ws.code & " (" & signalName(ws.code) & ")"))
        stderr.flushFile()
    else:
      let exitCode = peekExitCode(rg.process)
      if exitCode == -1:
        if (getTime() - rg.startTime).inMilliseconds > effectiveTimeoutMs:
          var timeoutOutput = ""
          try: timeoutOutput = rg.process.outputStream.readAll()
          except CatchableError: discard  # axiom:best-effort(ioboundary catch)
          rg.process.kill()
          rg.process.close()
          let label = &"{l2Gates[rg.gateIdx].name} ({gateId})"
          logError("", &"  FAIL  {label}  (TIMEOUT: {effectiveTimeoutMs}ms exceeded)")
          if timeoutOutput.len > 0:
            memo.writeGateOutputToFile(gateId, timeoutOutput)
          logGate(telemetry, gateId, "timeout",
                  effectiveTimeoutMs.int64 * 1_000_000, tier = gateTier,
                  outputFile = ".axiom/cache/gate_output/" & gateId & ".log",
                  terminationReason = "timeout")
          allOk = false
          if journal != nil:
            context.recordResult(journal, gateId, orchestrator_types.GateRunRecord(
              status: grsTimeout, elapsedMs: effectiveTimeoutMs,
              failCategory: fcPermanent, failReason: "TIMEOUT"))
        else:
          stillRunning.add(rg)
      else:
        var capturedOutput = ""
        try: capturedOutput = rg.process.outputStream.readAll()
        except CatchableError: discard  # axiom:best-effort(ioboundary catch)
        close(rg.process)
        let duration = getTime() - rg.startTime
        let durationNs = duration.inNanoseconds
        let label = &"{l2Gates[rg.gateIdx].name} ({gateId})"
        let gateSubtreeRoot = if vfs != nil: vfs.computeSubtreeRoot(l2Gates[rg.gateIdx].filesPattern) else: ""
        if exitCode == 0:
          memo.persistGateMemo(l2Gates[rg.gateIdx], changedFiles, true, repoRoot, epoch, gateSubtreeRoot)
          memo.deleteGateOutputFile(gateId)
          logGate(telemetry, gateId, "pass", durationNs, tier = gateTier)
          logInfo("", &"  PASS  {label}  ({duration.inMilliseconds}ms)")
          if journal != nil:
            context.recordResult(journal, gateId, orchestrator_types.GateRunRecord(
              status: grsSuccess, elapsedMs: duration.inMilliseconds.int))
        else:
          let (failCat, failReason) = classifyFailure(exitCode, capturedOutput)
          # DEBT#471 value closure: coordinates into the memo, prose stays
          # session-local (journal above/below keeps failReason).
          memo.persistGateMemo(l2Gates[rg.gateIdx], changedFiles, false, repoRoot, epoch, gateSubtreeRoot,
                          failCat, "", gateOutput = capturedOutput)
          if capturedOutput.len > 0:
            memo.writeGateOutputToFile(gateId, capturedOutput)
          logGate(telemetry, gateId, "fail", durationNs, tier = gateTier,
                  outputFile = ".axiom/cache/gate_output/" & gateId & ".log",
                  exitCode = exitCode, terminationReason = "error")
          logError("", &"  FAIL  {label}  ({duration.inMilliseconds}ms) [{failCat}]")
          allOk = false
          if journal != nil:
            context.recordResult(journal, gateId, orchestrator_types.GateRunRecord(
              status: grsFailed, elapsedMs: duration.inMilliseconds.int,
              failCategory: failCat, failReason: failReason))
        stderr.flushFile()
  result = (stillRunning, allOk)

# ---------------------------------------------------------------------------
# Merkle VFS Cache (runtime-once)
# ---------------------------------------------------------------------------
var cachedVfs {.threadvar.}: MerkleVfs
var vfsCacheValid {.threadvar.}: bool
proc getOrBuildVfs*(repoRoot: string): MerkleVfs {.raises: [CatchableError].} =
  if vfsCacheValid and cachedVfs != nil:
    return cachedVfs

  let files = discoverFiles(repoRoot)
  if files.isErr:
    return nil

  let cacheRes = loadVfsCache(repoRoot)
  var cache = if cacheRes.isOk: cacheRes.get else: VfsCache()
  let (_, workQueue) = diffAgainstCache(files.get, cache)

  if workQueue.len > 0:
    var queue: seq[tuple[path: string, size: int64, mtime: int64]] = @[]
    for f in workQueue:
      queue.add((path: f.path, size: f.size, mtime: f.mtime))
    let (newHashes, errors) = hashFiles(repoRoot, queue)
    for relPath, hexHash in newHashes:
      var hashBytes: array[32, byte]
      for i in 0..<32:
        let hi = "0123456789abcdef".find(hexHash[i*2])
        let lo = "0123456789abcdef".find(hexHash[i*2+1])
        hashBytes[i] = byte((hi shl 4) or lo)
      for f in workQueue:
        if f.path == relPath:
          cache.entries[relPath] = VfsCacheEntry(
            mtime: f.mtime, size: f.size, hash: hashBytes)
          break
    cache.dirty = true
    if errors.len > 0:
      logError("", "[VFS] Warning: " & $errors.len & " files failed to hash")

  if cache.dirty:
    try:
      flushCache(cache, repoRoot)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  cachedVfs = buildVfsFromCache(cache, repoRoot)
  vfsCacheValid = true
  cachedVfs

# ---------------------------------------------------------------------------
# Malebolgia L2 Gate Worker (Phase Φ3-A)
# ---------------------------------------------------------------------------
type
  L2GateWorkerCtx* = object
    gate: GateConfig
    repoRoot: string
    stagedFiles: seq[string]
    maxJobs: int
    effectiveTimeoutMs: int
    stageOrd: int
    updateBaseline: bool

  L2GateWorkerResult* = object
    gateId: string
    ok: bool
    exitCode: int
    stdout: string
    durationMs: int

  HeavyGateContext* = object
    process*: Process
    pid*: int
    gateId*: string
    startTime*: times.Time

proc runL2GateWorker*(ctx: ptr L2GateWorkerCtx): L2GateWorkerResult {.used, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  {.cast(gcsafe).}:
    {.push warning[BareExcept]:off.}
    try:
      let stage = cast[GateStage](ctx.stageOrd)
      let mode = if stage == gsPreCommit: grmIncremental else: grmExhaustive
      let res = runSingleGateImpl(ctx.gate, ctx.repoRoot, ctx.stagedFiles,
                                   stage, mode, ctx.maxJobs, ctx.effectiveTimeoutMs,
                                   ctx.updateBaseline)
      let elapsedMs = res.duration.inMilliseconds
      result = L2GateWorkerResult(
        gateId: ctx.gate.id,
        ok: res.ok,
        exitCode: if res.ok: 0 else: 1,
        stdout: res.stdout,
        durationMs: elapsedMs)
    except CatchableError:
      result = L2GateWorkerResult(gateId: ctx.gate.id, ok: false, exitCode: -1,
                         stdout: "", durationMs: 0)
    except Exception:
      result = L2GateWorkerResult(gateId: ctx.gate.id, ok: false, exitCode: -1,
                         stdout: "", durationMs: 0)
    {.pop.}

proc cancelHeavyGates*(ctxs: var seq[HeavyGateContext]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for g in ctxs.mitems:
    if g.process != nil and g.process.running:
      try:
        g.process.terminate()
        discard g.process.waitForExit(200)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
      if g.process.running:
        g.process.kill()
      g.process.close()
      try:
        discard execCmd("kill -9 -" & $g.pid)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    g.process = nil

# ---------------------------------------------------------------------------
# runAllGatesParallel — Layer-aware parallel dispatcher
# ---------------------------------------------------------------------------
var cachedPushRefs: seq[PushRef] = @[]

proc setPushRefs*(refs: seq[PushRef]) =
  cachedPushRefs = refs

func normalizeScopePath*(path: string): string {.raises: [], noSideEffect.} =
  path.replace('\\', '/')

func normalizeScopePattern*(pattern: string): string {.raises: [], noSideEffect.} =
  normalizeScopePath(pattern.strip())

func conservativeWildcardMatch*(pattern: string; path: string): bool {.raises: [], noSideEffect.} =
  var pi = 0
  var fi = 0
  var star = -1
  var match = 0
  while fi < path.len:
    if pi < pattern.len and (pattern[pi] == '?' or pattern[pi] == path[fi]):
      inc pi
      inc fi
    elif pi < pattern.len and pattern[pi] == '*':
      star = pi
      inc pi
      match = fi
    elif star != -1:
      pi = star + 1
      inc match
      fi = match
    else:
      return false
  while pi < pattern.len and pattern[pi] == '*':
    inc pi
  result = pi == pattern.len

func pathMatchesScopePattern*(pattern: string; path: string): bool {.raises: [], noSideEffect.} =
  let p = normalizeScopePattern(pattern)
  let f = normalizeScopePath(path)
  if p.len == 0:
    return false
  if p == "**" or p == "**/*":
    return true
  if p.startsWith("**/"):
    let suffix = p[3 .. ^1]
    return f.endsWith(suffix) or f.contains("/" & suffix)
  if p.endsWith("/**"):
    let prefix = p[0 .. ^3]
    return f == prefix or f.startsWith(prefix & "/")
  if p.contains("/**/"):
    let first = p.find("/**/")
    let before = p[0 ..< first]
    let after = p[first + 4 .. ^1]
    return f.contains(before) and f.contains(after)
  if p.contains("**"):
    let parts = p.split("**")
    if parts.len == 2:
      return f.contains(parts[0]) and f.contains(parts[1])
    if parts.len == 3:
      return f.contains(parts[0]) and f.contains(parts[1]) and f.contains(parts[2])
  if p.contains('*') or p.contains('?'):
    return conservativeWildcardMatch(p, f)
  f.contains(p)

func routeByScope*(gates: seq[GateConfig]; changedFiles: seq[string]): HashSet[string] {.raises: [].} =
  if changedFiles.len == 0:
    return initHashSet[string]()
  for g in gates:
    if g.scope.len == 0:
      return initHashSet[string]()
  var matched = initHashSet[string]()
  for g in gates:
    for pat in g.scope:
      if pathMatchesScopePattern(pat, g.id) or pathMatchesScopePattern(pat, g.entry):
        matched.incl(g.id)
        break
      for f in changedFiles:
        if pathMatchesScopePattern(pat, f):
          matched.incl(g.id)
          break
      if g.id in matched:
        break
  result = matched

func isMandatoryIntegrityOrProofGate*(gate: GateConfig): bool {.raises: [], noSideEffect.} =
  gate.id in ["integrity-test", "manifest-integrity-gate", "proof-universe-lock-gate"] or
  gate.id.contains("integrity") or gate.id.contains("proof")

proc ensureAntiVacuityGates*(gates: var seq[GateConfig]; routedIds: HashSet[string]) {.raises: [].} =
  var hasIntegrityOrProof = false
  for g in gates:
    if g.id in routedIds and isMandatoryIntegrityOrProofGate(g):
      hasIntegrityOrProof = true
      break
  if hasIntegrityOrProof:
    return
  for g in gates:
    if g.id in routedIds and g.tier == 1:
      gates.add(g)
      return

let gitExe = findRealGit()

# A2: pure scheduler progress predicate — can any ready gate dispatch under the
# current token budget? If a scheduler iteration dispatches nothing, has nothing
# in flight, and this returns false, the loop is in a deterministic no-progress
# spin (cost > availableTokens forever). Extracted as a top-level pure function
# so the no-spin invariant is unit-testable in isolation.
func canDispatchAnyQueue(readyQueue: seq[GateConfig]; availableTokens: int): bool =
  var i = readyQueue.len
  while i > 0:
    dec i
    if readyQueue[i].weight.int <= availableTokens:
      return true
  false

proc runAllGatesParallel*(stage: GateStage; repoRoot: string;
                           maxJobs: int; epoch: int;
                           pushRefs: seq[PushRef] = @[];
                           forCommit: bool = false;
                           updateBaseline: bool = false): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  var reports: seq[GateReport] = @[]
  var reportedGates = initHashSet[string]()
  var log = analyzer.initOrchestratorLog()

  let snap = newGitSnapshot()
  # Deterministic change-set: a real commit operates on staged files, while a
  # --dry-run inspects the unstaged working tree (what would be committed next).
  let changedFiles = if forCommit: snap.stagedFiles else: snap.unstagedFiles
  let stageName = case stage
    of gsPreCommit: "pre-commit"
    of gsPrePush: "pre-push"
    of gsManual: "manual"
    of gsCI: "ci"
    of gsAnyCi: "ci"
  var telemetry = initTelemetry(initContext(stageName, changedFiles.len, epoch))
  log.log(&"[GATE] HEAD: {snap.headShort()}  staged: {snap.stagedFiles.len}  unstaged: {snap.unstagedFiles.len}")

  if not isDaemonRunning(repoRoot):
    discard startDaemon(repoRoot)

  var inheritedVfsRoot = getEnv("AXIOM_VFS_ROOT_HASH")
  var skipVfsIntern = false
  if inheritedVfsRoot.len > 0:
    skipVfsIntern = true
    log.log("[GATE] Inherited VFS root hash from parent — skipping re-intern")

  var salsaDb = initSalsaMemoDb()
  var symbolRegistry = initSymbolRegistry()
  var vfsIntern: VfsTable
  if not skipVfsIntern and changedFiles.len > 0:
    try:
      let vfsStats = internFromRepo(vfsIntern, repoRoot, changedFiles)
      log.log(&"[VFS-INTERN] {vfsStats.blobsInterned}/{vfsStats.blobsRequested} blobs interned, " &
              &"{vfsStats.totalContentBytes} bytes, {vfsStats.batchProcessTimeMs}ms")
    except CatchableError as e:
      log.log("[VFS-INTERN] WARN: batch interning failed (" & e.msg & "), falling back to per-file")

  if not skipVfsIntern:
    for f in changedFiles:
      try:
        let oldContent = if vfsExists(vfsIntern, f):
          readFromVfs(vfsIntern, f)
        else:
          execProcess("git show HEAD:" & quoteShell(f))
        let newContent = readFile(f)
        let report = processFileChange(salsaDb, symbolRegistry, f, oldContent, newContent)
        if report.affectedGates.len > 0:
          log.log(&"[SALSA] {f}: {report.affectedGates.len} gates affected by symbol changes")
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  context.setSalsaDbPtr(addr salsaDb)
  defer: context.setSalsaDbPtr(nil)
  log.log(&"[SALSA] Initialized: {salsaDb.nodes.len} entries, " &
          &"{salsaDb.dependents.len} dependency edges")

  initFileHashCache(repoRoot)

  template writeAttestationReport() =
    try:
      var att = AttestationManifest(
        version: 1, stage: stageName, commitHash: snap.head,
        treeHash: snap.treeHash,
        branch: execProcess(gitExe & " rev-parse --abbrev-ref HEAD").strip(),
        timestamp: int64(epochTime()),
        totalDurationNs: 0, gateCount: reports.len,
        passedCount: reports.countIt(it.ok),
        failedCount: reports.countIt(not it.ok),
        cachedCount: reports.countIt(it.category.contains("CACHED")),
        bottleneckId: "", bottleneckNs: 0,
        contextId: getAxiomEnv(evGateContextId),
        receiptHash: "", binaryFreshnessOk: true, manifestHash: "")
      var maxMs: int = 0
      for r in reports:
        if r.elapsedMs > maxMs: maxMs = r.elapsedMs; att.bottleneckId = r.id
      att.bottleneckNs = maxMs.int64 * 1_000_000
      discard writeAttestation(att, repoRoot)
    except CatchableError as e:
      logError("", "[GATE] Attestation write failed: " & e.msg)

  let vfs = getOrBuildVfs(repoRoot)
  log.log(&"[GATE] Merkle VFS: {vfs.fileCount()} files indexed, root={vfs.vfsRootHash()[0..15]}...")

  var ruleHashHex = ""
  let baseCommitHex = snap.head
  try:
    var ruleContent = ""
    let configPath = repoRoot / "config.nims"
    let debtPath = repoRoot / "data/architecture_debt.json"
    if fileExists(configPath):
      ruleContent &= readFile(configPath)
    if fileExists(debtPath):
      ruleContent &= readFile(debtPath)
    ruleHashHex = hash_kernel.sha256Hex(ruleContent)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  let allGatesDefs = allGates()
  var stageMatched = allGatesDefs.filterIt(shouldRun(it, stage, changedFiles))

  # ── Phase 3-C: Runtime config filtering (axiom:gate-config) ──────────────
  # Disabled gates are removed before any further processing.
  let runtimeCfg = loadGateRuntimeConfig()
  var disabledCount = 0
  for g in stageMatched:
    if not runtimeCfg.isEnabled(g.id):
      disabledCount += 1
      log.log(&"[GATE-CONFIG] DISABLED {g.name} ({g.id}) — enabled=false in runtime config")
  if disabledCount > 0:
    stageMatched = stageMatched.filterIt(runtimeCfg.isEnabled(it.id))
    log.log(&"[GATE-CONFIG] Filtered {disabledCount} disabled gate(s), {stageMatched.len} remaining")

  let scopeRoutingMode = getAxiomEnv(evScopeRouting)
  if scopeRoutingMode != "off" and scopeRoutingMode != "full":
    let routedIds = routeByScope(stageMatched, changedFiles)
    if routedIds.len > 0:
      var routedGates: seq[GateConfig]
      for g in stageMatched:
        if g.id in routedIds:
          routedGates.add(g)
      ensureAntiVacuityGates(routedGates, routedIds)
      stageMatched = routedGates
      log.log(&"[GATE-SCOPE] routed {routedIds.len}/{stageMatched.len} gate(s) by scope routing")

  block filesPatternPruning:
    # Deterministic scope routing (Lefthook/pre-commit pattern):
    # a gate with a filesPattern that matches nothing in the change-set is skipped,
    # regardless of layer. only alwaysRun gates survive an empty change-set.
    var retainedIds: HashSet[string]
    for g in stageMatched:
      if matchesFilesPattern(g, changedFiles) or g.alwaysRun:
        retainedIds.incl(g.id)
      else:
        log.log(&"[GATE-DAG] SKIP (filesPattern): {g.name} ({g.id}) pattern=\"{g.filesPattern}\"")
    if retainedIds.len < stageMatched.len:
      var kept: seq[GateConfig]
      for g in stageMatched:
        if g.id in retainedIds:
          kept.add(g)
      stageMatched = kept

  block createLedgerBlock:
    try:
      let stageId = case stage
        of gsPreCommit: 0'u8
        of gsPrePush: 1'u8
        of gsManual: 0'u8
        of gsCI: 3'u8
        of gsAnyCi: 3'u8
      let ledgerEntries = buildLedgerEntries(allGatesDefs, epoch, stage)
      createLedger(
        repoRoot,
        uint32(epoch),
        H_VOID,
        hashValueFromHex(ruleHashHex),
        computeBuildEnvHash(),
        H_VOID,
        sha1HexToBytes(baseCommitHex),
        stageId, 0'u8,
        ledgerEntries
      )
      putEnv("AXIOM_STATE_LEDGER_PATH", getLedgerPath(repoRoot))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  let (active, _) = filterDeferredGates(stageMatched)

  if active.len == 0:
    log.log("[GATE] No applicable gates for stage " & $stage)
    writeAttestationReport()
    return true

  var (l1Gates, l2Gates) = partitionByLayer(active)

  block l1FilesPatternPruning:
    var l1Active: seq[GateConfig]
    for g in l1Gates:
      if matchesFilesPattern(g, changedFiles):
        l1Active.add(g)
      else:
        log.log(&"[GATE] SKIP (filesPattern): {g.name} ({g.id}) pattern=\"{g.filesPattern}\"")
    if l1Active.len < l1Gates.len:
      log.log(&"[GATE] L1 filesPattern pruning: {l1Active.len}/{l1Gates.len} L1 gates retained")
    l1Gates = l1Active

  log.log(&"[GATE] Running {active.len} gate(s) — L1={l1Gates.len} sequential, L2={l2Gates.len} parallel (maxJobs={maxJobs})...")

  for g in l1Gates:
    let subtreeRoot = if vfs != nil: vfs.computeSubtreeRoot(g.filesPattern) else: ""
    let skip = memo.trySkipGate(g, changedFiles, repoRoot, epoch, subtreeRoot)
    if skip.isSome:
      let label = &"{g.name} ({g.id})"
      if skip.get.result:
        log.log(&"  PASS  {label}  (cached)")
        reports.add(GateReport(id: g.id, ok: true, exitCode: 0,
                               category: "PASS_CACHED", reason: "",
                               elapsedMs: 0, failureCategory: fcTransient))
        reportedGates.incl(g.id)
      else:
        let reasonStr = if skip.get.reason.len > 0: &" ({skip.get.reason})" else: ""
        log.log(&"  FAIL  {label}  (cached, {skip.get.category}){reasonStr}")
        reports.add(GateReport(id: g.id, ok: false, exitCode: 1,
                               category: "FAIL_CACHED",
                               reason: skip.get.reason,
                               elapsedMs: 0,
                               failureCategory: skip.get.category))
        reportedGates.incl(g.id)
        if analyzer.resolveEffectiveSeverity(g) == gsWarn:
          log.log(&"  WARN  {label}  (cached) [{skip.get.category}] — gsWarn, continuing")
          continue
        log.flushSummary()
        printDiagnosticMatrix(reports)
        log.log(&"[GATE] L1 Meta gate {g.id} FAILED (cached, {skip.get.category}). Aborting L2 dispatch.")
        writeAttestationReport()
        return false
      continue

    let res = dispatchGate(g, repoRoot, changedFiles, maxJobs, stage,
                           context.loadGateSla(g.id, forCommit = forCommit), telemetry,
                           updateBaseline)
    let label = &"{res.name} ({g.id})"
    if res.ok:
      memo.persistGateMemo(g, changedFiles, true, repoRoot, epoch, subtreeRoot)
      log.log(&"  PASS  {label}  ({res.duration.inMilliseconds}ms)")
      reports.add(GateReport(id: g.id, ok: true, exitCode: 0,
                             category: "PASS", reason: "",
                             elapsedMs: res.duration.inMilliseconds,
                             failureCategory: fcTransient))
      reportedGates.incl(g.id)
    else:
      # DEBT#471 value closure: the gate's own structured verdict fields are
      # authoritative when present; otherwise classifyFailure still supplies
      # the category, but stdout FAIL lines are never persisted as the reason.
      let (failCat, failReason) = if res.failureReason.len > 0:
          (res.failureCategory, res.failureReason)
        else:
          (classifyFailure(1, res.stdout).category, "")
      memo.persistGateMemo(g, changedFiles, false, repoRoot, epoch, subtreeRoot,
                      failCat, failReason, gateOutput = res.stdout)
      log.log(&"  FAIL  {label}  ({res.duration.inMilliseconds}ms) [{failCat}]")
      const maxL1OutputLen = 2048
      try:
        if res.stdout.len > 0:
          let truncated = if res.stdout.len > maxL1OutputLen:
            res.stdout[0 ..< maxL1OutputLen] & &"\n  ... (truncated {res.stdout.len - maxL1OutputLen} bytes)"
          else:
            res.stdout
          for line in truncated.splitLines():
            if line.len > 0:
              log.log("    " & line)
      except system.IOError:
        discard
      reports.add(GateReport(id: g.id, ok: false, exitCode: 1,
                             category: "FAIL", reason: failReason,
                             elapsedMs: res.duration.inMilliseconds,
                             failureCategory: failCat))
      reportedGates.incl(g.id)
      if analyzer.resolveEffectiveSeverity(g) == gsWarn:
        log.log(&"  WARN  {label}  ({res.duration.inMilliseconds}ms) [{failCat}] — gsWarn, continuing")
        continue
      log.flushSummary()
      printDiagnosticMatrix(reports)
      log.log(&"[GATE] L1 Meta gate {g.id} FAILED [{failCat}]. Aborting L2 dispatch.")
      writeAttestationReport()
      return false

  if l2Gates.len == 0:
    log.flushSummary()
    printDiagnosticMatrix(reports)
    writeAttestationReport()
    return true

  let dag = buildGateDag(l2Gates)
  let dagLayers = topologicalLayers(dag)

  let artifactTracker = buildArtifactTracker(l2Gates)
  let artifactLines = logArtifactSubscriptions(artifactTracker)
  if artifactLines.len > 0:
    log.log(&"[GATE-ARTIFACT] {artifactLines.len} subscription(s):")
    for line in artifactLines:
      log.log(&"[GATE-ARTIFACT]{line}")

  var affected: HashSet[string]
  block importTreeBlock:
    try:
      let coreDir = repoRoot / "src" / "core"
      let importGraph = buildImportGraph(coreDir)
      affected = findAffectedByImportTree(dag, changedFiles, importGraph, l2Gates)
      log.log(&"[GATE-IMPORT-TREE] {affected.len} gate(s) affected via import tree analysis")
    except CatchableError:
      affected = findAffectedGates(dag, changedFiles, l2Gates)
      log.log(&"[GATE-IMPORT-TREE] Import graph unavailable, falling back to filesPattern matching")

  var tier1Affected = initHashSet[string]()
  for g in l2Gates:
    if g.id in affected and g.tier == 1:
      tier1Affected.incl(g.id)

  var failedGates = initHashSet[string]()
  var skippedGates = initHashSet[string]()

  log.log(&"[GATE-DAG] {dagLayers.len} layer(s), {tier1Affected.len}/{l2Gates.len} gates affected (tier 1)")
  for li, layer in dagLayers:
    var layerNames: seq[string]
    for gateId in layer:
      if gateId in tier1Affected:
        layerNames.add(gateId)
    if layerNames.len > 0:
      log.log(&"[GATE-DAG] Layer {li}: {layerNames.join(\", \")}")
  for g in l2Gates:
    if g.id notin tier1Affected:
      log.log(&"[GATE-DAG] SKIP (unaffected): {g.name} ({g.id})")

  if tier1Affected.len == 0:
    log.log("[GATE-DAG] No tier-1 affected gates — all L2 gates skipped/unaffected")
    garbageCollectOldEpochs()
    flushFileHashCache(repoRoot)
    log.flushSummary()
    printDiagnosticMatrix(reports)
    writeAttestationReport()
    return true

  const MaxConcurrentL2 = 6
  const stageStrs = [gsPreCommit: "pre-commit", gsPrePush: "pre-push", gsManual: "manual", gsCI: "ci", gsAnyCi: "ci"]
  let stageStr = stageStrs[stage]

  let globalConcurrencyBudget = computeGlobalConcurrencyBudget()
  log.log(&"[GATE] Global concurrency budget: {globalConcurrencyBudget} workers (CPU cores: {cpuinfo.countProcessors()})")

  var allOk = true
  let journal = context.newSessionJournal()

  let critPath = computeCriticalPath(dag, l2Gates)

  var remainingDeps = initTable[string, int]()
  var depToGates = initTable[string, seq[string]]()
  var gateLookup = initTable[string, GateConfig]()
  var gateIdToIdx = initTable[string, int]()
  for i, g in l2Gates:
    gateLookup[g.id] = g
    gateIdToIdx[g.id] = i
    remainingDeps[g.id] = 0
  for g in l2Gates:
    for depId in g.after:
      if depId in tier1Affected:
        remainingDeps[g.id] = remainingDeps.getOrDefault(g.id, 0) + 1
        if depId notin depToGates:
          depToGates[depId] = @[]
        depToGates[depId].add(g.id)

  var readyQueue: seq[GateConfig]
  for g in l2Gates:
    if g.id in tier1Affected and remainingDeps.getOrDefault(g.id, 0) == 0:
      readyQueue.add(g)

  readyQueue.sort(proc(a, b: GateConfig): int =
    cmp(critPath.getOrDefault(b.id, 0), critPath.getOrDefault(a.id, 0)))

  let maxCp = if readyQueue.len > 0: critPath.getOrDefault(readyQueue[0].id, 0) else: 0
  log.log(&"[GATE-DAG] Eager scheduling: {readyQueue.len} gate(s) initially ready, " &
          &"{dagLayers.len} topological layer(s), critical path max={maxCp}")

  var availableTokens = GlobalMaxTokens
  var running: seq[RunningGate]
  var lightBatch: seq[GateConfig]
  var heavyContexts: seq[HeavyGateContext]

  while readyQueue.len > 0 or running.len > 0:
    var dispatchedAny = false
    while readyQueue.len > 0 and running.len < MaxConcurrentL2:
      let g = readyQueue[^1]
      readyQueue.setLen(readyQueue.len - 1)

      if g.id in skippedGates or g.id in failedGates:
        log.log(&"  SKIP  {g.name} ({g.id})  (upstream failed)")
        reports.add(GateReport(id: g.id, ok: false, exitCode: -1,
                               category: "SKIPPED",
                               reason: "upstream failed", elapsedMs: 0,
                               failureCategory: fcTransient))
        reportedGates.incl(g.id)
        continue

      let subtreeRoot = if vfs != nil: vfs.computeSubtreeRoot(g.filesPattern) else: ""
      let skip = memo.trySkipGate(g, changedFiles, repoRoot, epoch, subtreeRoot)
      if skip.isSome:
        let label = &"{g.name} ({g.id})"
        if skip.get.result:
          log.log(&"  PASS  {label}  (cached)")
          logGate(telemetry, g.id, "cached", 0, cached = true, tier = g.tier, dagLayer = -1)
          reports.add(GateReport(id: g.id, ok: true, exitCode: 0,
                                 category: "PASS_CACHED", reason: "",
                                 elapsedMs: 0, failureCategory: fcTransient))
          reportedGates.incl(g.id)
          for depId in depToGates.getOrDefault(g.id, @[]):
            remainingDeps[depId] = max(0, remainingDeps.getOrDefault(depId, 1) - 1)
            if remainingDeps[depId] == 0 and depId in tier1Affected and
               depId notin skippedGates and depId notin failedGates:
              readyQueue.add(gateLookup[depId])
        else:
          let reasonStr = if skip.get.reason.len > 0: &" ({skip.get.reason})" else: ""
          log.log(&"  FAIL  {label}  (cached, {skip.get.category}){reasonStr}")
          logGate(telemetry, g.id, "cached", 0, cached = true, tier = g.tier, dagLayer = -1)
          reports.add(GateReport(id: g.id, ok: false, exitCode: 1,
                                 category: "FAIL_CACHED",
                                 reason: skip.get.reason,
                                 elapsedMs: 0,
                                 failureCategory: skip.get.category))
          reportedGates.incl(g.id)
          if analyzer.resolveEffectiveSeverity(g) != gsWarn:
            failedGates.incl(g.id)
            allOk = false
        continue

      let cost = g.weight.int
      if cost > availableTokens:
        readyQueue.add(g)
        readyQueue.sort(proc(a, b: GateConfig): int =
          cmp(critPath.getOrDefault(b.id, 0), critPath.getOrDefault(a.id, 0)))
        break
      dispatchedAny = true
      availableTokens -= cost

      if g.weight >= gwHeavy:
        let activeGateCount = running.len + 1
        let childJobs = globalThrottledMaxJobs(cost, activeGateCount)
        putEnv("AXIOM_JOBS", $childJobs)
        putEnv("AXIOM_SINGLE_GATE_ID", g.id)
        putEnv("AXIOM_STAGED_FILES", changedFiles.join(","))
        if pushRefs.len > 0:
          putEnv("AXIOM_PUSH_COMMITS", pushRefs.mapIt(it.localSha).join(" "))
        if vfs != nil:
          putEnv("AXIOM_VFS_ROOT_HASH", vfs.vfsRootHash())
        putEnv("AXIOM_CI_EPOCH", $epoch)

        let childCmd = "bin/gate_hook " & quoteShell(stageStr) & " < /dev/null"
        let wrappedCmd = wrapWithCgroupsIfAvailable(childCmd)
        # A1: subprocess-launch can raise independently of gate logic. The heavy
        # gate's tokens were already deducted at :1049; restore them exactly once
        # so a launch failure cannot leak the token pool and strand the scheduler.
        var launched: Process
        try:
          launched = startProcess("/bin/sh", args = @["-c", wrappedCmd],
                                  workingDir = repoRoot,
                                  options = {poStdErrToStdOut, poUsePath})
        except CatchableError:
          availableTokens += cost
          log.log(&"SCHEDULER_DISPATCH_FAILURE: startProcess failed for {g.name} ({g.id}); " &
                  &"restored {cost} tokens")
          failedGates.incl(g.id)
          allOk = false
          break
        let p = launched
        let stableIdx = gateIdToIdx.getOrDefault(g.id, 0)
        running.add(RunningGate(process: p, gateIdx: stableIdx, startTime: getTime(),
                                allocatedTokens: cost, outputLog: ""))
        heavyContexts.add(HeavyGateContext(
          process: p, pid: p.processID(), gateId: g.id, startTime: getTime()))
        log.log(&"[GATE-Φ3A] HEAVY→subprocess: {g.name} ({g.id}) pid={p.processID()}")
      else:
        lightBatch.add(g)
        log.log(&"[GATE-Φ3A] LIGHT/MEDIUM→batch: {g.name} ({g.id}) weight={g.weight}")

    # A2: no-progress deadlock — nothing dispatched, nothing in flight, gates still
    # queued, and none of them can dispatch with the current token budget. Fail
    # closed with structured diagnostics instead of spinning until CI timeout.
    if not dispatchedAny and running.len == 0 and lightBatch.len == 0 and
       readyQueue.len > 0 and not canDispatchAnyQueue(readyQueue, availableTokens):
      let nextRequired = readyQueue[^1].weight.int
      log.log(&"SCHEDULER_DEADLOCK: ready={readyQueue.len} running=0 " &
              &"availableTokens={availableTokens} nextRequired={nextRequired}")
      allOk = false
      break

    if running.len == 0 and readyQueue.len == 0 and lightBatch.len == 0:
      break

    if lightBatch.len > 0:
      log.log(&"[GATE-Φ3A] Malebolgia batch: {lightBatch.len} light/medium gate(s)")
      let batchStart = getTime()

      # A1: exception-safe token accounting. The batch loop restores each light gate's
      # tokens on the normal path (:1178), but an exception mid-loop (memo persist,
      # logging, report append, or the malebolgia master itself) would leak the tokens
      # of every unhandled gate in the batch and leave ctxPtr allocations unfreed.
      # Wrap the whole batch in try/finally so exactly once, on any path, every
      # not-yet-restored gate is returned and every ctxPtr is deallocated. The
      # handledLightGates cursor prevents double-restore on the normal path.
      var handledLightGates = 0
      var ctxPtrs: seq[ptr L2GateWorkerCtx]
      try:
        var batchResults: seq[L2GateWorkerResult]
        batchResults.setLen(lightBatch.len)
        var master = createMaster()
        master.awaitAll:
          for i, g in lightBatch:
            let ctx = create(L2GateWorkerCtx)
            ctx[] = L2GateWorkerCtx(
              gate: g,
              repoRoot: repoRoot,
              stagedFiles: changedFiles,
              maxJobs: globalThrottledMaxJobs(g.weight.int, running.len + 1),
              effectiveTimeoutMs: context.loadGateSla(g.id),
              stageOrd: ord(stage),
              updateBaseline: updateBaseline)
            ctxPtrs.add(ctx)
            master.spawn runL2GateWorker(ctx) -> batchResults[i]

        for i, ctxPtr in ctxPtrs:
          let res = batchResults[i]
          let g = lightBatch[i]
          let subtreeRoot = if vfs != nil: vfs.computeSubtreeRoot(g.filesPattern) else: ""

          if res.ok:
            memo.persistGateMemo(g, changedFiles, true, repoRoot, epoch, subtreeRoot)
            logGate(telemetry, g.id, "pass", res.durationMs.int64 * 1_000_000,
                    tier = g.tier, dagLayer = -1)
            log.log(&"  PASS  {g.name} ({g.id})  ({res.durationMs}ms) [Φ3A-malebolgia]")
            reports.add(GateReport(id: g.id, ok: true, exitCode: 0,
                                   category: "PASS", reason: "",
                                   elapsedMs: res.durationMs,
                                   failureCategory: fcTransient))
            reportedGates.incl(g.id)

            for depId in depToGates.getOrDefault(g.id, @[]):
              remainingDeps[depId] = max(0, remainingDeps.getOrDefault(depId, 1) - 1)
              if remainingDeps[depId] == 0 and depId in tier1Affected and
                 depId notin skippedGates and depId notin failedGates:
                if depId in gateLookup:
                  readyQueue.add(gateLookup[depId])

            var completedSet = initHashSet[string]()
            completedSet.incl(g.id)
            let invalidated = findAffectedByArtifacts(artifactTracker, completedSet, l2Gates)
            for invId in invalidated:
              if invId notin tier1Affected and invId notin skippedGates and
                 invId notin failedGates and invId notin reportedGates:
                tier1Affected.incl(invId)
                log.log(&"[GATE-ARTIFACT] Invalidated {invId} (subscribes to artifact produced by {g.id})")
                if invId in gateLookup:
                  remainingDeps[invId] = 0
                  readyQueue.add(gateLookup[invId])
          else:
            # DEBT#471 value closure: category only + findings mining — the
            # worker result carries raw stdout, which is never the memo reason.
            let failCat = classifyFailure(res.exitCode, res.stdout).category
            memo.persistGateMemo(g, changedFiles, false, repoRoot, epoch, subtreeRoot,
                            failCat, "", gateOutput = res.stdout)
            logGate(telemetry, g.id, "fail", res.durationMs.int64 * 1_000_000,
                    tier = g.tier, dagLayer = -1)
            if res.stdout.len > 0:
              memo.writeGateOutputToFile(g.id, res.stdout)
            log.log(&"  FAIL  {g.name} ({g.id})  ({res.durationMs}ms) [{failCat}] [Φ3A-malebolgia]")
            reports.add(GateReport(id: g.id, ok: false, exitCode: res.exitCode,
                                   category: "FAIL", reason: "",
                                   elapsedMs: res.durationMs,
                                   failureCategory: failCat))
            reportedGates.incl(g.id)
            if analyzer.resolveEffectiveSeverity(g) != gsWarn:
              failedGates.incl(g.id)
              allOk = false

            if analyzer.resolveEffectiveSeverity(g) == gsWarn:
              for depId in depToGates.getOrDefault(g.id, @[]):
                remainingDeps[depId] = max(0, remainingDeps.getOrDefault(depId, 1) - 1)
                if remainingDeps[depId] == 0 and depId in tier1Affected and
                   depId notin skippedGates and depId notin failedGates:
                  if depId in gateLookup:
                    readyQueue.add(gateLookup[depId])

          # Restore the tokens this light (malebolgia) gate consumed while enqueued,
          # mirroring the heavy subprocess path (availableTokens += rg.allocatedTokens
          # in the poll loop below). Without this, all tokens are permanently consumed
          # by the first wave of L2 gates and any later readyQueue gate is re-enqueued
          # forever (cost > availableTokens) with nothing running -> infinite spin
          # -> CI step timeout (EXIT=124). FAIL-CLOSED: token accounting only.
          availableTokens += g.weight.int
          dealloc(ctxPtr)
          inc handledLightGates
      finally:
        # On any exception path, restore the tokens of light gates not yet handled
        # in the loop above, and free every worker context allocation. Exactly-once:
        # the handledLightGates cursor excludes gates already restored at :1178.
        for idx in handledLightGates ..< lightBatch.len:
          availableTokens += lightBatch[idx].weight.int
        for ctxPtr in ctxPtrs:
          dealloc(ctxPtr)

      let batchMs = (getTime() - batchStart).inMilliseconds
      log.log(&"[GATE-Φ3A] Malebolgia batch completed: {lightBatch.len} gate(s) in {batchMs}ms")
      lightBatch.setLen(0)

      if failedGates.len > 0:
        let prevSkipped = skippedGates
        skippedGates = propagateFailures(dag, failedGates)
        for gId in skippedGates:
          if gId notin prevSkipped and gId notin failedGates and gId in tier1Affected:
            log.log(&"[GATE-DAG] SKIP (upstream failed): {gId}")
            reports.add(GateReport(id: gId, ok: false, exitCode: -1,
                                   category: "SKIPPED",
                                   reason: "upstream dependency failed", elapsedMs: 0,
                                   failureCategory: fcTransient))
            reportedGates.incl(gId)
        var filteredQueue: seq[GateConfig]
        for g in readyQueue:
          if g.id notin skippedGates and g.id notin failedGates:
            filteredQueue.add(g)
        readyQueue = filteredQueue

    let prevRunning = running
    var nextRunning: seq[RunningGate]
    try:
      nextRunning = pollL2GatesWithTimeout(running, l2Gates, L2GateTimeoutMs,
        changedFiles, repoRoot, epoch, telemetry, vfs, journal = journal)[0]
    except CatchableError:
      # A1: subprocess-poll infrastructure failure. Every in-flight heavy gate still
      # holds allocatedTokens that were never returned on the normal completion path
      # (:1189). Restore them all and fail closed with a distinct structured error —
      # never leak the tokens and spin the caller, and never mask the infra failure.
      var held = 0
      for rg in prevRunning:
        availableTokens += rg.allocatedTokens
        held += rg.allocatedTokens
      log.log(&"SCHEDULER_POLL_FAILURE: pollL2GatesWithTimeout raised; " &
              &"restored {prevRunning.len} in-flight heavy gate(s) totaling {held} tokens")
      allOk = false
      break

    for rg in prevRunning:
      var stillActive = false
      for nr in nextRunning:
        if nr.gateIdx == rg.gateIdx:
          stillActive = true
          break
      if not stillActive:
        availableTokens += rg.allocatedTokens
        let completedId = l2Gates[rg.gateIdx].id

        if journal.isFailed(completedId):
          let completedGate = l2Gates[rg.gateIdx]
          if analyzer.resolveEffectiveSeverity(completedGate) == gsWarn:
            log.log(&"[GATE-DAG] WARN (non-blocking): {completedGate.name} ({completedId})")
          else:
            failedGates.incl(completedId)
            allOk = false

        for depId in depToGates.getOrDefault(completedId, @[]):
          remainingDeps[depId] = max(0, remainingDeps.getOrDefault(depId, 1) - 1)
          if remainingDeps[depId] == 0 and depId in tier1Affected and
             depId notin skippedGates and depId notin failedGates:
            if depId in gateLookup:
              readyQueue.add(gateLookup[depId])

        if completedId notin failedGates:
          var completedSet = initHashSet[string]()
          completedSet.incl(completedId)
          let invalidated = findAffectedByArtifacts(artifactTracker, completedSet, l2Gates)
          for invId in invalidated:
            if invId notin tier1Affected and invId notin skippedGates and
               invId notin failedGates and invId notin reportedGates:
              tier1Affected.incl(invId)
              log.log(&"[GATE-ARTIFACT] Invalidated {invId} (subscribes to artifact produced by {completedId})")
              if invId in gateLookup:
                remainingDeps[invId] = 0
                readyQueue.add(gateLookup[invId])

    if failedGates.len > 0:
      let prevSkipped = skippedGates
      skippedGates = propagateFailures(dag, failedGates)
      for gId in skippedGates:
        if gId notin prevSkipped and gId notin failedGates and gId in tier1Affected:
          log.log(&"[GATE-DAG] SKIP (upstream failed): {gId}")
          reports.add(GateReport(id: gId, ok: false, exitCode: -1,
                                 category: "SKIPPED",
                                 reason: "upstream dependency failed", elapsedMs: 0,
                                 failureCategory: fcTransient))
          reportedGates.incl(gId)
      var filteredQueue: seq[GateConfig]
      for g in readyQueue:
        if g.id notin skippedGates and g.id notin failedGates:
          filteredQueue.add(g)
      readyQueue = filteredQueue

    readyQueue.sort(proc(a, b: GateConfig): int =
      cmp(critPath.getOrDefault(b.id, 0), critPath.getOrDefault(a.id, 0)))

    running = nextRunning
    if running.len > 0 and readyQueue.len > 0:
      sleep(10)

  garbageCollectOldEpochs()
  flushFileHashCache(repoRoot)
  memo.gcVerificationReceipts()

  for g in l2Gates:
    if g.id in tier1Affected and g.id notin reportedGates:
      let rec = journal.entries.getOrDefault(g.id)
      if g.id in failedGates:
        reports.add(GateReport(id: g.id, ok: false, exitCode: 1,
                               category: "FAIL", reason: rec.failReason,
                               elapsedMs: rec.elapsedMs,
                               failureCategory: rec.failCategory))
      elif g.id in skippedGates:
        reports.add(GateReport(id: g.id, ok: false, exitCode: -1,
                               category: "SKIPPED",
                               reason: "downstream dependency failed", elapsedMs: 0,
                               failureCategory: fcTransient))
        logGate(telemetry, g.id, "skip", 0, tier = g.tier)
      elif rec.status == grsSuccess:
        reports.add(GateReport(id: g.id, ok: true, exitCode: 0,
                               category: "PASS", reason: "",
                               elapsedMs: rec.elapsedMs,
                               failureCategory: fcTransient))
      else:
        logError("", &"[GATE] UNKNOWN STATUS for gate {g.id} — category not recognized; reporting as FAIL per §0.9")
        reports.add(GateReport(id: g.id, ok: false, exitCode: 1,
                                category: "FAIL_UNKNOWN_STATUS",
                                reason: "status category not recognized",
                                elapsedMs: 0, failureCategory: fcUnknown))
        allOk = false
      reportedGates.incl(g.id)

  log.flushSummary()
  flushToDisk(telemetry)
  printDiagnosticMatrix(reports)
  # writeTreeReceipt removed — verification receipt system deleted

  writeAttestationReport()

  if allOk:
    try:
      let transHash = computeTransitiveHash(repoRoot)
      if transHash.len > 0:
        var gateResults: Table[string, bool]
        for r in reports:
          gateResults[r.id] = r.ok
        let buildEnvHash = computeBuildEnvHash(repoRoot)
        let entry = CasEntry(
          transitiveHash: transHash,
          artifacts: @["bin/axiom"],
          timestamp: epochTime(),
          gateResults: gateResults,
          buildEnvHash: buildEnvHash
        )
        persistCas(entry)
        log.log(&"[GATE-CAS] Persisted CAS entry: transitiveHash={transHash[0..15]}... ({reports.len} gates)")
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  allOk

# ---------------------------------------------------------------------------
# Exported entry points for gate_hook.nim
# ---------------------------------------------------------------------------
proc runPreCommit*(epoch: int; forCommit: bool = false; updateBaseline: bool = false) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let repoRoot = getCurrentDir()
  let maxJobs = safeParseInt(getAxiomEnv(evJobs, $GlobalMaxTokens)).getOrDefault(GlobalMaxTokens)
  let exitCode = if runAllGatesParallel(gsPreCommit, repoRoot, maxJobs, epoch, forCommit = forCommit,
                                       updateBaseline = updateBaseline): 0 else: 1
  quit(exitCode)

proc runPrePush*(epoch: int; updateBaseline: bool = false) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let repoRoot = getCurrentDir()
  let maxJobs = safeParseInt(getAxiomEnv(evJobs, $GlobalMaxTokens)).getOrDefault(GlobalMaxTokens)
  let exitCode = if runAllGatesParallel(gsPrePush, repoRoot, maxJobs, epoch,
                                         cachedPushRefs, updateBaseline = updateBaseline): 0 else: 1
  quit(exitCode)

proc runCi*(epoch: int; updateBaseline: bool = false) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let repoRoot = getCurrentDir()
  let maxJobs = safeParseInt(getAxiomEnv(evJobs, $GlobalMaxTokens)).getOrDefault(GlobalMaxTokens)
  let ok = runAllGatesParallel(gsAnyCi, repoRoot, maxJobs, epoch, updateBaseline = updateBaseline)
  quit(if ok: 0 else: 1)

proc runPrepareCommitMsg*() =
  if isEmergencyBypass():
    logInfo("", "[AXIOM GUARD] Emergency bypass acknowledged. Must be documented post-hoc.")
  quit(0)

# ---------------------------------------------------------------------------
