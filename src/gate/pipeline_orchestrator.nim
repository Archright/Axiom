import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/gate/content_store
import core/gate/deterministic_env
import core/gate/gc_roots
import core/gate/hermetic_sandbox
import core/gate/merkle_vfs
import core/gate/overlay_mount
import core/gate/post_mortem
import core/observer
import gate/action_cache
import gate/action_key
import gate/gate_registry
import gate/gate_types
import gate/in_process_gates
import gate/pipeline
import std/[os, strutils, tables, times, options]
import infrastructure/cache_gc
import infrastructure/logging_facade
import gate/cache/soundness_cache_types
import gate/cache/soundness_cache_io
type
  InProcessGate* = proc(pm: ProjectMap; repoRoot: string;
                        changedFiles: seq[string]): bool {.nimcall, raises: [].}
    ## Fast gate that runs in-process using ProjectMap directly.
    ## No subprocess overhead, no file re-read.

  GateRegistration* = object
    gateId*: string
    runner*: InProcessGate
    timeoutMs*: int

  HermeticPipelineConfig* = object
    ## Phase 3: Hermetic Build Engine configuration.
    ## Holds all state needed for deterministic, cached, isolated gate execution.
    store*: ContentStore
    cache*: ActionCache
    detEnv*: DeterministicEnv
    mountTier*: MountTier
    scratchDir*: string
    pipelineHashes*: seq[string]  ## All content hashes produced in this run (for GC root)
# ─── In-Process Gate Registry ──────────────────────────────────────────────
# Gates registered here run as function calls (O(1) overhead).
# All other gates dispatch via hermetic subprocess (Wave 5C-1).

# Phase 10: TLS-Safe shared state.
# Previous design used {.threadvar.} for registeredGates, globalMerkleVfs,
# and globalHermeticConfig. Each malebolgia worker thread got its own empty
# copy, causing: in-process gates not found, VFS nil → silent pass-through,
# hermetic config empty → broken sandbox. Fix: heap-allocated ref object
# shared across all threads via raw pointer (same pattern as GateWorkerContext).

type
  SharedPipelineState {.acyclic.} = ref object
    ## Heap-allocated shared state for pipeline parallelism.
    ## Set once on main thread before spawning workers.
    ## Read-only access from malebolgia worker threads — no locks needed.
    registeredGates: seq[GateRegistration]
    merkleVfs: MerkleVfs
    hermeticConfig: HermeticPipelineConfig

# NOT {.threadvar.} — this pointer is shared across all threads.
# Main thread sets it; worker threads read via cast in gcsafe wrappers.
var sharedPipelineState: SharedPipelineState
proc ensureSharedState() {.axiomEffect: IOEffect.} =
  ## Lazily allocate shared pipeline state (called once from main thread).
  if sharedPipelineState == nil:
    sharedPipelineState = SharedPipelineState()
proc setGlobalMerkleVfs*(vfs: MerkleVfs) {.axiomEffect: IOEffect.} =
  ## axiomIoBoundary
  ## Set the global Merkle VFS for hermetic subprocess dispatch.
  ensureSharedState()
  sharedPipelineState.merkleVfs = vfs
proc registerInProcessGate*(gateId: string; runner: InProcessGate;
                            timeoutMs: int = 5000) {.axiomEffect: IOEffect.} =
  ## Register a gate for in-process execution via ProjectMap.
  ## Call this at module init time for gates that can run without subprocess.
  ensureSharedState()
  sharedPipelineState.registeredGates.add(GateRegistration(
    gateId: gateId, runner: runner, timeoutMs: timeoutMs))
proc findInProcessGate(gateId: string): GateRegistration {.raises: [], axiomEffect: IOEffect.} =
  ## Find a registered in-process gate. Returns empty registration if not found.
  if sharedPipelineState == nil:
    return GateRegistration(gateId: "", runner: nil, timeoutMs: 0)
  for reg in sharedPipelineState.registeredGates:
    if reg.gateId == gateId:
      return reg
  GateRegistration(gateId: "", runner: nil, timeoutMs: 0)
proc registerDefaultInProcessGates*() {.axiomEffect: IOEffect.} =
  ## Register the top in-process gates that benefit from ProjectMap.
  ## Call once at pipeline startup.
  # Import encapsulation: pure text analysis on ProjectMap content
  registerInProcessGate("import-encapsulation-gate",
    proc(pm: ProjectMap; repoRoot: string;
         cf: seq[string]): bool {.nimcall, raises: [].} =
      runImportEncapsulationInProcess(pm, repoRoot))
  # Debt reduction: baseline comparison on ProjectMap content
  registerInProcessGate("debt-reduction-gate",
    proc(pm: ProjectMap; repoRoot: string;
         cf: seq[string]): bool {.nimcall, raises: [].} =
      runDebtReductionInProcess(pm, repoRoot))
  # Monotonic whitelist: architecture policy lock file check
  registerInProcessGate("monotonic-whitelist-gate",
    proc(pm: ProjectMap; repoRoot: string;
         cf: seq[string]): bool {.nimcall, raises: [].} =
      runMonotonicWhitelistInProcess(pm, repoRoot))
  # Nimtry: architecture integrity check (was subprocess, now in-process)
  registerInProcessGate("nimtry",
    proc(pm: ProjectMap; repoRoot: string;
         cf: seq[string]): bool {.nimcall, raises: [].} =
      runNimtryGateInProcess(pm, repoRoot))
func resolveGateEntry(gateId: string): string {.raises: [].} =
  ## Look up the gate entry from the gate registry.
  ## For now, return "bin/" + gateId (convention).
  ## This will be enhanced when gate_manifest integration is complete.
  "bin/" & gateId
proc gateRunnerCallback(gateId: string; ctx: PipelineContext): bool
    {.nimcall, raises: [], axiomEffect: IOEffect.} =
  ## Dispatch gate to in-process or hermetic subprocess execution.
  ## For in-process gates, calls directly. For others, dispatches via
  ## hermetic subprocess with Merkle VFS snapshot isolation.
  ## Phase 10: Reads from sharedPipelineState (heap-allocated ref) instead of
  ## {.threadvar.} — safe to call from malebolgia worker threads.
  let st = sharedPipelineState
  if st == nil:
    logError("pipeline_orchestrator", "[PIPELINE] Shared pipeline state not initialized — no gates can run; failing closed per §0.9")
    return false

  let reg = findInProcessGate(gateId)
  if reg.runner != nil:
    return reg.runner(ctx.pm, ctx.repoRoot, @[])

  # Non-in-process gates: dispatch via hermetic subprocess
  if st.merkleVfs == nil:
    logError("pipeline_orchestrator", "[PIPELINE] Merkle VFS not available for gate " & gateId & " — cannot dispatch hermetic subprocess; failing closed per §0.9")
    return false

  # Create snapshot for this gate
  var snap = vfsSnapshot(st.merkleVfs, gateId)

  # Build hermetic config for this gate
  let config = buildHermeticConfig(st.merkleVfs.rootPath)
  let provider = hermeticSubprocessProvider(config)

  # Resolve gate entry path
  let entry = resolveGateEntry(gateId)
  if entry.len == 0:
    logError("pipeline_orchestrator", "[PIPELINE] Cannot resolve entry path for gate " & gateId & " — no executable; failing closed per §0.9")
    return false

  # Execute via hermetic sandbox
  let procResult = provider(entry, @[])

  # Commit on success, discard on failure
  if procResult.exitCode == 0:
    try:
      let delta = toDelta(snap)
      vfsCommit(st.merkleVfs, delta)
    except Defect:
      vfsDiscard(snap)
      return false
  else:
    vfsDiscard(snap)
    return false

  true
# Phase 3: Deterministic, cached, isolated gate execution (Wave 7D-3)
# Phase 10: hermeticConfig is now stored in sharedPipelineState (heap-allocated)
# instead of {.threadvar.} — safe from malebolgia worker threads.
proc initHermeticConfig*(repoRoot: string): HermeticPipelineConfig {.axiomEffect: IOEffect.} =
  ## axiomIoBoundary
  ## Initialize hermetic build engine. Creates store, cache, and frozen env.
  let store = initStore(repoRoot / ".axiom" / "store")
  let cache = initActionCache(repoRoot / ".axiom" / "cache" / "actions")
  let detEnv = buildDeterministicEnv()
  var tier = mtCopy
  try:
    tier = detectBestTier()
  except CatchableError:
    tier = mtCopy  # fallback if detection fails
  let scratchDir = repoRoot / ".axiom" / "scratch"
  createDir(scratchDir)

  logInfo("pipeline_orchestrator", "[HERMETIC] Store initialized: " & store.root)
  logInfo("pipeline_orchestrator", "[HERMETIC] Mount tier: " & $tier)
  logInfo("pipeline_orchestrator", "[HERMETIC] SOURCE_DATE_EPOCH: " & $detEnv.sourceDateEpoch)
  stderr.flushFile()

  HermeticPipelineConfig(
    store: store,
    cache: cache,
    detEnv: detEnv,
    mountTier: tier,
    scratchDir: scratchDir,
    pipelineHashes: @[]
  )
proc hermeticGateRunnerCallback(gateId: string; ctx: PipelineContext): bool
    {.nimcall, raises: [], axiomEffect: IOEffect.} =
  ## Hermetic gate runner: Action Cache → Overlay Mount → Namespace → Execute.
  ## Wraps all I/O in try/except to maintain {nimcall, raises: []} signature.
  ## Phase 10: Reads from sharedPipelineState (heap-allocated ref) instead of
  ## {.threadvar.} — safe to call from malebolgia worker threads.
  let st = sharedPipelineState
  if st == nil:
    logError("pipeline_orchestrator", "[HERMETIC] Shared pipeline state not initialized — no gates can run; failing closed per §0.9")
    return false

  # Step 1: In-process gates bypass hermetic overhead
  let reg = findInProcessGate(gateId)
  if reg.runner != nil:
    return reg.runner(ctx.pm, ctx.repoRoot, @[])

  # Step 2: Compute Action Key
  let hcfg = st.hermeticConfig
  var inputHashes = initTable[string, string]()
  try:
    for relPath, entry in ctx.pm.files.pairs:
      inputHashes[relPath] = entry.contentHash
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  let actionKey = computeActionKey(
    inputHashes = inputHashes,
    pathManifestHash = buildDeterministicHash(hcfg.detEnv),
    sourceDateEpoch = hcfg.detEnv.sourceDateEpoch,
    command = "gate:" & gateId,
    env = @[]
  )

  # Step 3: Action Cache lookup
  try:
    let cached = hcfg.cache.lookup(string(actionKey))
    if cached.isSome():
      let res = cached.get()
      if res.ok:
        try:
          logInfo("pipeline_orchestrator", "[HERMETIC] Cache HIT: " & gateId &
                           " key=" & shortKey(actionKey))
          stderr.flushFile()
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
        return true
      else:
        try:
          logError("pipeline_orchestrator", "[HERMETIC] Cache HIT (FAIL): " & gateId)
          stderr.flushFile()
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
        return false
  except Defect:
    logError("pipeline_orchestrator", "[HERMETIC] Cache lookup failed for gate " & gateId &
                     " key=" & shortKey(actionKey))
    return false
  except CatchableError as e:
    logError("pipeline_orchestrator", "[HERMETIC] Cache lookup failed for gate " & gateId &
                     " key=" & shortKey(actionKey) & ": " & e.msg)
    return false

  try:
    logInfo("pipeline_orchestrator", "[HERMETIC] Cache MISS: " & gateId &
                     " key=" & shortKey(actionKey))
    stderr.flushFile()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  # Step 4: Mount overlay for isolated execution
  var mountResult = MountResult(tier: mtCopy, mergedDir: "", upperDir: "")
  try:
    mountResult = mountForGate(
      hcfg.store.root, ctx.repoRoot, hcfg.scratchDir, gateId, hcfg.mountTier)
  except CatchableError:
    discard  # overlay_mount.nim may raise on mount failure  # axiom:best-effort(ioboundary catch)

  # Step 5: Execute gate (fallback to existing hermetic subprocess)
  var gatePassed = false
  var gateStdout = ""
  var gateStderr = ""
  var gateExitCode = 0

  if st.merkleVfs != nil:
    try:
      var snap = vfsSnapshot(st.merkleVfs, gateId)
      let config = buildHermeticConfig(ctx.repoRoot)
      let provider = hermeticSubprocessProvider(config)
      let entry = resolveGateEntry(gateId)
      if entry.len > 0:
        let procResult = provider(entry, @[])
        gateExitCode = procResult.exitCode
        gatePassed = procResult.exitCode == 0
        if gatePassed:
          try:
            let delta = toDelta(snap)
            vfsCommit(st.merkleVfs, delta)
          except Defect:
            vfsDiscard(snap)
            gatePassed = false
        else:
          vfsDiscard(snap)
      else:
        logError("pipeline_orchestrator", "[HERMETIC] Cannot resolve entry path for gate " & gateId &
                         " — no executable; failing closed per §0.9 (no pass-through allowed)")
        vfsDiscard(snap)
        gatePassed = false
    except CatchableError:
      gatePassed = false
  else:
    logError("pipeline_orchestrator", "[HERMETIC] Merkle VFS not available in hermetic runner for gate " & gateId & " — cannot execute; failing closed per §0.9")
    gatePassed = false

  # Step 6: Store result in Action Cache
  try:
    let orchestratorResult = ActionResult(
      ok: gatePassed,
      stdout: gateStdout,
      stderr: gateStderr,
      exitCode: gateExitCode,
      inputHashes: inputHashes,
      pathManifestHash: buildDeterministicHash(hcfg.detEnv)
    )
    hcfg.cache.store(string(actionKey), orchestratorResult)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  # Step 7: On failure → preserve post-mortem
  if not gatePassed:
    try:
      preserveFailed(PostMortemRecord(
        actionKey: string(actionKey),
        gateId: gateId,
        failedAt: epochTime(),
        stdout: gateStdout,
        stderr: gateStderr,
        exitCode: gateExitCode,
        inputs: inputHashes,
        namespaceConfig: ""
      ))
      try:
        logInfo("pipeline_orchestrator", "[HERMETIC] Post-mortem preserved: " &
                         shortKey(actionKey))
        stderr.flushFile()
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  # Step 8: Cleanup mount
  try:
    cleanupMount(mountResult)
  except CatchableError:
    discard  # overlay_mount.nim may raise on cleanup failure  # axiom:best-effort(ioboundary catch)

  gatePassed
proc createPipelineContext*(repoRoot: string; mode: PipelineMode;
                            scanDirs: seq[string] = @["src"]): PipelineContext
 {.axiomEffect: IOEffect.} =
  ## Factory: Create immutable PipelineContext with Gate 0 enforcement.
  ## Gate 0 (assertSyncProtocol) blocks context creation on protocol violation.

  # Step 1: Gather git metadata (external state → internal data)
  logInfo("pipeline_orchestrator", "[PIPELINE] Gate 0: Gathering git metadata...")
  stderr.flushFile()
  let metadata = gatherGitMetadata(repoRoot)
  logInfo("pipeline_orchestrator", "[PIPELINE] Gate 0: branch=" & metadata.currentBranch &
                   ", detached=" & $metadata.isDetached &
                   ", dirty=" & $metadata.hasUncommittedChanges &
                   ", syncToken=" & $metadata.syncBranchToken)
  stderr.flushFile()

  # Step 2: Gate 0 enforcement — doAssert blocks on violation
  discard assertSyncProtocol(metadata)
  logInfo("pipeline_orchestrator", "[PIPELINE] Gate 0: Sync protocol verified")
  stderr.flushFile()

  # Step 3: Scan project → ProjectMap
  logInfo("pipeline_orchestrator", "[PIPELINE] Scanning project...")
  stderr.flushFile()
  let pm = scanProject(repoRoot, scanDirs = scanDirs)
  logInfo("pipeline_orchestrator", "[PIPELINE] Scanned " & $pm.fileCount & " files in " &
                   formatFloat(pm.scanDurationMs, ffDecimal, 1) & "ms")
  stderr.flushFile()

  # Step 4: Build AST cache (if unified mode)
  var ast = astCache()
  if mode == pmUnified:
    logInfo("pipeline_orchestrator", "[PIPELINE] Building AST cache...")
    stderr.flushFile()
    ast = buildASTCache(pm)
    logError("pipeline_orchestrator", "[PIPELINE] AST cache: " & $ast.totalParsed &
                     " parsed, " & $ast.totalFailed & " failed in " &
                     formatFloat(ast.parseDurationMs, ffDecimal, 1) & "ms")
    stderr.flushFile()

  # Step 5: Compute state hash
  let state = computeStateHash(pm, repoRoot)
  logInfo("pipeline_orchestrator", "[PIPELINE] State hash: " & state.combined[0..min(11, state.combined.high)] & "...")
  stderr.flushFile()

  # Step 6: Assemble immutable PipelineContext
  PipelineContext(
    pm: pm,
    ast: ast,
    state: state,
    repoRoot: repoRoot,
    mode: mode,
    repoState: metadata
  )
proc runPipeline*(stage: GateStage; repoRoot: string;
                  maxJobs: int; epoch: int;
                  scanDirs: seq[string] = @["src"]): bool
 {.axiomEffect: IOEffect.} =
  ## Unified pipeline entry point.
  ## Gate 0 → Factory → Cache check → DAG build → DAG execute → Save state.
  ##
  ## Returns true iff all gates pass.

  # Register default in-process gates (idempotent)
  registerDefaultInProcessGates()

  # Step 1: Create PipelineContext (includes Gate 0)
  let ctx = createPipelineContext(repoRoot, pmGate, scanDirs)

  # Initialize Merkle VFS for gate execution
  let merkleVfs = buildMerkleFromGitIndex(repoRoot)
  setGlobalMerkleVfs(merkleVfs)

  # Step 2: Soundness cache check (§0.9 Theater fix — verify pass/fail status)
  let cachePath = repoRoot / ".axiom" / "cache" / ".axiom_state.json"
  let sourceHash = computeProjectSourceHash(repoRoot)
  let soundnessCache = loadAndValidateCache(cachePath)
  let cachedStatus = lookupSoundnessCache(soundnessCache, "pipeline-state", sourceHash)

  if cachedStatus.isNone():
    ## Cache miss — proceed to run gates
  elif cachedStatus.get() == gvsPass:
    ## Cache hit with PASS — results are reusable
    logInfo("pipeline_orchestrator", "[SOUNDNESS] Cache HIT (PASS): pipeline state unchanged, results reusable.")
    stderr.flushFile()
    return true
  else:
    ## Cache hit with FAIL — MUST re-run gates (fail-closed)
    logWarn("pipeline_orchestrator", "[SOUNDNESS] Cache HIT but PREVIOUS RUN FAILED — re-running gates instead of returning true")
    stderr.flushFile()

  # Step 3: Load gate configs for this stage
  let stageGates = findGateConfigs(allGates(), stage)
  logInfo("pipeline_orchestrator", "[PIPELINE] " & $stageGates.len & " gates for stage " & $stage)
  stderr.flushFile()

  # Step 4: Build DAG
  let dag = buildDAG(stageGates)
  if dag.len == 0:
    logError("pipeline_orchestrator", "[PIPELINE] DAG build failed (cycle detected or no gates)")
    stderr.flushFile()
    return false
  logInfo("pipeline_orchestrator", "[PIPELINE] DAG: " & $dag.len & " layers")
  stderr.flushFile()

  # Step 5: Execute DAG
  let dagResult = executeDAG(dag, ctx, gateRunnerCallback, maxJobs)

  # Step 6: Log results
  for layerIdx, layer in dagResult.layers:
    for lr in layer:
      let status = if lr.passed: "PASS" else: "FAIL"
      logInfo("pipeline_orchestrator", "[PIPELINE]   [" & status & "] " & lr.gateId &
                       " (" & formatFloat(lr.durationMs, ffDecimal, 1) & "ms)")
      stderr.flushFile()

  logInfo("pipeline_orchestrator", "[PIPELINE] DAG execution: " &
                   formatFloat(dagResult.totalDurationMs, ffDecimal, 1) &
                   "ms, allPassed=" & $dagResult.allPassed)
  stderr.flushFile()

  # Step 7: Persist state hash
  var gateResults = initTable[string, bool]()
  for layer in dagResult.layers:
    for lr in layer:
      gateResults[lr.gateId] = lr.passed
  saveStateHash(cachePath, ctx.state, dagResult.allPassed, gateResults)

  ## Persist soundness cache entry (gate result tracking)
  try:
    let soundnessEntry = VerificationCacheEntry(
      schemaVersion: SoundnessCacheSchemaVersion,
      compositeLockHash: ctx.state.combined,
      sourceHash: sourceHash,
      status: if dagResult.allPassed: gvsPass else: gvsFail,
      timestamp: epochTime().float,
      gateId: "pipeline-state"
    )
    saveCacheEntry(cachePath, soundnessEntry)
  except CatchableError:
    discard  ## axiom:best-effort(ioboundary catch)

  # Step 8: Cache GC — budget eviction + log rotation (rate-limited, best-effort)
  try:
    let gcCacheDir = repoRoot / ".axiom" / "cache" / "gate_memo"
    let gcHistoryPath = repoRoot / ".axiom" / "gate_history.jsonl"
    runCacheGC(gcCacheDir, @[gcHistoryPath])
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  dagResult.allPassed
# Phase 3: Deterministic, cached, isolated pipeline (Wave 7D-3)
proc runHermeticPipeline*(stage: GateStage; repoRoot: string;
                          maxJobs: int; epoch: int;
                          scanDirs: seq[string] = @["src"]): bool {.axiomEffect: IOEffect.}
 =
  ## Hermetic pipeline entry point.
  ## Action Cache → Overlay Mount → Namespace Sandbox → Execute → GC Root → Deploy.
  ##
  ## Returns true iff all gates pass.

  # Step 1: Initialize hermetic build engine
  let hcfg = initHermeticConfig(repoRoot)
  ensureSharedState()
  sharedPipelineState.hermeticConfig = hcfg

  # Initialize post-mortem and GC roots
  initPostMortem()
  initGcRoots()

  # Register default in-process gates (idempotent)
  registerDefaultInProcessGates()

  # Step 2: Create PipelineContext (includes Gate 0)
  let ctx = createPipelineContext(repoRoot, pmGate, scanDirs)

  # Initialize Merkle VFS for gate execution
  let merkleVfs = buildMerkleFromGitIndex(repoRoot)
  setGlobalMerkleVfs(merkleVfs)

  # Step 3: Soundness cache check (§0.9 Theater fix — verify pass/fail status)
  let cachePath = repoRoot / ".axiom" / "cache" / ".axiom_state.json"
  let sourceHash = computeProjectSourceHash(repoRoot)
  let soundnessCache = loadAndValidateCache(cachePath)
  let cachedStatus = lookupSoundnessCache(soundnessCache, "pipeline-state", sourceHash)

  if cachedStatus.isNone():
    ## Cache miss — proceed to run gates
  elif cachedStatus.get() == gvsPass:
    logInfo("pipeline_orchestrator", "[SOUNDNESS] Cache HIT (PASS): hermetic pipeline state unchanged, results reusable.")
    stderr.flushFile()
    return true
  else:
    logWarn("pipeline_orchestrator", "[SOUNDNESS] Cache HIT but PREVIOUS RUN FAILED — re-running gates (fail-closed)")
    stderr.flushFile()

  # Step 4: Load gate configs for this stage
  let stageGates = findGateConfigs(allGates(), stage)
  logInfo("pipeline_orchestrator", "[HERMETIC] " & $stageGates.len & " gates for stage " & $stage)
  stderr.flushFile()

  # Step 5: Build DAG
  let dag = buildDAG(stageGates)
  if dag.len == 0:
    logError("pipeline_orchestrator", "[HERMETIC] DAG build failed (cycle detected or no gates)")
    stderr.flushFile()
    return false
  logInfo("pipeline_orchestrator", "[HERMETIC] DAG: " & $dag.len & " layers")
  stderr.flushFile()

  # Step 6: Execute DAG with hermetic callback
  let dagResult = executeDAG(dag, ctx, hermeticGateRunnerCallback, maxJobs)

  # Step 7: Log results
  for layerIdx, layer in dagResult.layers:
    for lr in layer:
      let status = if lr.passed: "PASS" else: "FAIL"
      logInfo("pipeline_orchestrator", "[HERMETIC]   [" & status & "] " & lr.gateId &
                       " (" & formatFloat(lr.durationMs, ffDecimal, 1) & "ms)")
      stderr.flushFile()

  logInfo("pipeline_orchestrator", "[HERMETIC] DAG execution: " &
                   formatFloat(dagResult.totalDurationMs, ffDecimal, 1) &
                   "ms, allPassed=" & $dagResult.allPassed)
  stderr.flushFile()

  # Step 8: Persist state hash
  var gateResults = initTable[string, bool]()
  for layer in dagResult.layers:
    for lr in layer:
      gateResults[lr.gateId] = lr.passed
  saveStateHash(cachePath, ctx.state, dagResult.allPassed, gateResults)

  ## Persist soundness cache entry (gate result tracking)
  try:
    let soundnessEntry = VerificationCacheEntry(
      schemaVersion: SoundnessCacheSchemaVersion,
      compositeLockHash: ctx.state.combined,
      sourceHash: sourceHash,
      status: if dagResult.allPassed: gvsPass else: gvsFail,
      timestamp: epochTime().float,
      gateId: "pipeline-state"
    )
    saveCacheEntry(cachePath, soundnessEntry)
  except CatchableError:
    discard  ## axiom:best-effort(ioboundary catch)

  # Step 9: On success → register GC root + clean old post-mortems
  if dagResult.allPassed:
    let pipelineId = "pipeline-" & ctx.state.combined[0..min(15, ctx.state.combined.high)]
    let st = sharedPipelineState
    if st != nil:
      registerGcRoot(pipelineId, st.hermeticConfig.pipelineHashes)
      logInfo("pipeline_orchestrator", "[HERMETIC] GC root registered: " & pipelineId &
                       " (" & $st.hermeticConfig.pipelineHashes.len & " hashes)")
      stderr.flushFile()

    # Clean old post-mortem records (7-day TTL)
    try:
      cleanPostMortem()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

    # Step 10: Cache GC — budget eviction + log rotation (rate-limited, best-effort)
    try:
      let gcCacheDir = repoRoot / ".axiom" / "cache" / "gate_memo"
      let gcHistoryPath = repoRoot / ".axiom" / "gate_history.jsonl"
      runCacheGC(gcCacheDir, @[gcHistoryPath])
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  dagResult.allPassed

{.pop.}
