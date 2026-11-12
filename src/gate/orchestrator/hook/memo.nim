## memo.nim — Cache key, memoization, skip logic for orchestrator hook.
## (domain: memo)

import core/trusted/layer_declaration
axiomLayer "gate"
import gate/orchestrator/hook/context  # for gSalsaDbPtr, captureContext, computeEnvHash
import core/gate/gate_cas  # for computeTransitiveSourceHash (verification_dag_contract §3/§5, DEBT#449/#450)
import core/trusted/stdlib_shield
import std/os
import std/tables
import core/results
import checksums/sha2  # for secureHash, Sha_256
import core/gate/gate_memo  # for computeMerkleRootFromPaths
import core/parsers/safe_parsers
import std/strutils
import std/options
import std/sets
import std/times
import gate/daemon/salsa_memo  # for SalsaMemoDb
import gate/daemon/gate_daemon_types  # for CacheEntry
import gate/daemon/gate_daemon_client  # for isDaemonRunning
import gate/slice_hash  # for toInputSlice, computeSliceHash
import gate/gate_run_context  # for GateRunContext
import gate/gate_contract  # for GateConfig (with entry, depsDirs)
import core/gate/trust_commit_scope_scan  # TrustCommitScopeGateId, judgmentClosureDigest (DEBT#471 enforcement-path slice)
import infrastructure/logging_facade  # for logInfo, logError
import core/trusted/axiom_pragmas_lite  # for axiomEffect
import core/crypto/hash_kernel  # for sha256Hex (scope-axis digest, DEBT#471)
import std/algorithm  # for sorted (scope-axis digest, DEBT#471)

## DEBT#471 (FIXED 2026-10-08): memo identity closure — the composite key now
## carries the producing gate's hash (restored gateHash slot) plus a
## scan-scope/staged scope digest, and memo values carry structured finding
## coordinates instead of quoted stdout prose; every memo read path re-renders
## findings with the current formatter, and the daemon/salsa persistence sinks
## share the CAS layer's classifyMemoOutcome verdict-axis guard.
## QUIRK(DEBT#471): memo identity closure quirk site — §0.5c dual binding with
## the {.axiomDebt.} pragma carrier below; narrative in data/debt_registry.json.
const debtMarker471 {.axiomDebt: "DEBT#471".} = true

## DEBT#417 (FIXED 2026-10-05): the `.git/index` term is gone from the
## config.nims hermetic envHash — VCS state is incidental input, never build
## input. This proc hashes declared gate env dependencies (dkGitConfig /
## dkEnvVar) only; it never reads `.git/index`.
## See docs/spec/config_nims_hermetic_cache_quirk.md.
const debtMarker417 {.axiomDebt: "DEBT#417".} = true

var gMemoIndex: MemoIndex
var gMemoIndexLoaded: bool = false

# ---------------------------------------------------------------------------
# Verification receipt GC (absorbed from git_ops.nim)
# ---------------------------------------------------------------------------
proc gcVerificationReceipts*() {.axiomEffect: IOEffect.} =
  ## 7일 이상 된 영수증 파일 정리
  const maxAge = 604800  # 7 days in seconds
  let receiptDir = getCurrentDir() / ".axiom" / "cache" / "verification_receipts"
  if not dirExists(receiptDir): return
  let now = getTime().toUnix()
  for kind, path in walkDir(receiptDir):
    if kind == pcFile and not path.endsWith(".tmp"):
      try:
        let content = readFile(path)
        let tsRes = safeParseInt(content.split("|")[1].strip())
        if tsRes.isOk and now - tsRes.get > maxAge: removeFile(path)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# Gate output capture
# ---------------------------------------------------------------------------
proc writeGateOutputToFile*(gateId: string; output: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = ".axiom" / "cache" / "gate_output"
  createDir(dir)
  writeFile(dir / gateId & ".log", output)

proc deleteGateOutputFile*(gateId: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let path = ".axiom" / "cache" / "gate_output" / gateId & ".log"
  if fileExists(path):
    safeRemoveFile(path)

proc readGateOutputFile*(gateId: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let path = ".axiom" / "cache" / "gate_output" / gateId & ".log"
  if fileExists(path):
    return readFile(path)
  return ""

# ---------------------------------------------------------------------------
# Gate hash resolution
# ---------------------------------------------------------------------------
proc resolveGateHash*(gate: GateConfig; srcRoot: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## verification_dag_contract.md §3/§5: gate hash = transitive import closure
  ## Merkle root (subsumes the single-file hash — DEBT#449). Unresolved ("") →
  ## no cache key → fail-closed execution, reason logged (DEBT#450).
  if gate.entry.len > 0:
    let src = context.resolveGateSourcePath(gate.entry)
    if fileExists(src):
      let transHash = computeTransitiveSourceHash(src, srcRoot)
      if transHash.len == 0:
        logWarn("orchestrator_memo", "axiom: transitive closure unresolved for " & gate.id &
          " — no cache key, forcing execution (fail-closed reuse, DEBT#449/#450)")
        return ""
      return transHash
  if gate.depsDirs.len > 0:
    return computeMerkleRootFromPaths(gate.depsDirs)
  return ""

## DEBT#417 (FIXED 2026-10-05): the `.git/index` term is gone from the
## config.nims hermetic envHash — VCS state is incidental input, never build
## input. This proc hashes declared gate env dependencies (dkGitConfig /
## dkEnvVar) only; it never reads `.git/index`.
## See docs/spec/config_nims_hermetic_cache_quirk.md.
proc computeEnvHash*(deps: seq[EnvDependency];
                     snapshot: EnvContextSnapshot): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if deps.len == 0: return ""
  var parts: seq[string] = @[]
  for dep in deps:
    let prefix = case dep.kind
      of dkGitConfig: "git:"
      of dkEnvVar: "env:"
    let val = snapshot.values.getOrDefault(dep.key, "__AXIOM_MISSING__")
    parts.add(prefix & dep.key & "=" & val)
  if parts.len == 0: return ""
  $secureHash(Sha_256, parts.join("|"))

proc getRunnerBinaryHash*(): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let appPath = getAppFilename()
    if appPath.len == 0:
      logInfo("orchestrator_memo", "axiom: getRunnerBinaryHash: getAppFilename() returned empty (sandbox/container?), falling back to sentinel")
      return "__BINARY_HASH_UNKNOWN__"
    $secureHash(Sha_256, readFile(appPath))
  except system.IOError, system.OSError:
    logError("orchestrator_memo", "axiom: getRunnerBinaryHash: failed to read runner binary, falling back to sentinel")
    "__BINARY_HASH_UNKNOWN__"

# ---------------------------------------------------------------------------
# Cache key computation
# ---------------------------------------------------------------------------
proc computeScopeAxisDigest*(slice: InputSlice; changedFiles: seq[string]): string {.raises: [].} =
  ## DEBT#471 key closure: bind the scan-scope/staged axes into the memo key.
  ## computeSliceHash hashes only the CHANGED files that fall inside the
  ## slice's pattern — an empty filtered set hashes to a constant regardless
  ## of which scope produced it (staged=0 full-src/ scan vs staged=1 partial
  ## scan once shared one key). The digest binds the slice identity (kind,
  ## paths, excludes) plus the staged axis (the full sorted changed-file list
  ## and its cardinality), so distinct evaluation contexts cannot collide.
  ## Conservative by design: distinct staged sets yield distinct keys —
  ## under-keying is unsound, over-keying only costs a re-run.
  hash_kernel.sha256Hex(
    $slice.kind & "\x1f" & slice.paths.join("\x1f") & "\x1f" &
    slice.excludePatterns.join("\x1f") & "\x1f" & $changedFiles.len & "\x1f" &
    changedFiles.sorted().join("\x1f"))

func daemonMemoVerdict*(passed: bool; failCategory: string;
                        failReason: string): MemoOutcome {.raises: [].} =
  ## DEBT#471: the daemon checkCache path must apply the same verdict-axis
  ## semantics as the CAS layer. A cached response whose (result, category,
  ## reason) triple classifies as moNotEvaluated (tool failure, unclassifiable
  ## category, or failure with no evidence) is an execution state, not a
  ## verdict — it must not be consumed as a cache hit.
  classifyMemoOutcome(passed, parseEnum(failCategory, fcTransient), failReason)

proc computeGateCacheKey*(gate: GateConfig; changedFiles: seq[string];
                          repoRoot: string; subtreeRoot: string = ""): string {.raises: [CatchableError].} =
  # DEBT#471 (enforcement-path slice): an empty subtree root means the VFS
  # content axis is absent — the key would not bind what the gate judged.
  # Fail closed: no cache identity, forced execution.
  if subtreeRoot.len == 0:
    return ""
  let gateHash = resolveGateHash(gate, repoRoot / "src")
  if gateHash.len == 0:
    return ""
  let binHash = getRunnerBinaryHash()
  let snapshot = captureContext(gate.envDependencies).get()
  let envHash = computeEnvHash(gate.envDependencies, snapshot)
  let slice = gate.toInputSlice()
  if slice.kind == skAlways:
    return ""
  var inputHash = computeSliceHash(slice, changedFiles, repoRoot)
  if gate.id == TrustCommitScopeGateId:
    # DEBT#471 (enforcement-path slice): the patternless slice hashes staged
    # PATHS only — the staged CONTENT axis (index tree OID) must be folded
    # into the input axis, or a verdict under one staged tree replays under
    # a mutated one (PASS cached across a content flip is fail-open).
    let closure = judgmentClosureDigest(repoRoot, changedFiles)
    if closure.len == 0:
      return ""
    inputHash = hash_kernel.sha256Hex(inputHash & "|" & closure)
  # DEBT#471: gateHash is the already-resolved transitive-closure digest —
  # consumed verbatim by the composite (restored gateHash slot); scopeHash
  # binds the scan-scope/staged axes.
  let scopeAxis = computeScopeAxisDigest(slice, changedFiles)
  computeCompositeLockHash(inputHash, gateHash, repoRoot, subtreeRoot, binHash, envHash, "", scopeAxis)

proc computeCacheKey*(gate: GateConfig; ctx: GateRunContext): string {.raises: [CatchableError].} =
  let subtreeRoot = ctx.vfsComputeSubtreeRoot(gate.filesPattern)
  # DEBT#471 (enforcement-path slice): vfs-nil → no content axis → no memo
  # identity (see computeGateCacheKey).
  if subtreeRoot.len == 0:
    return ""
  let gateHash = resolveGateHash(gate, ctx.repoRoot / "src")
  if gateHash.len == 0:
    return ""
  let
    binHash = getRunnerBinaryHash()
    snapshot = captureContext(gate.envDependencies).get()
    envHash = computeEnvHash(gate.envDependencies, snapshot)
    slice = gate.toInputSlice()
  if slice.kind == skAlways:
    return ""
  var inputHash = computeSliceHash(slice, ctx.stagedFiles, ctx.repoRoot)
  if gate.id == TrustCommitScopeGateId:
    # DEBT#471 (enforcement-path slice): fold the staged content axis (see
    # computeGateCacheKey).
    let closure = judgmentClosureDigest(ctx.repoRoot, ctx.stagedFiles)
    if closure.len == 0:
      return ""
    inputHash = hash_kernel.sha256Hex(inputHash & "|" & closure)
  # DEBT#471: gateHash digest consumed verbatim + scope/staged axis bound.
  let scopeAxis = computeScopeAxisDigest(slice, ctx.stagedFiles)
  computeCompositeLockHash(inputHash, gateHash, ctx.repoRoot, subtreeRoot, binHash, envHash, "", scopeAxis)

# ---------------------------------------------------------------------------
# Gate skip logic
# ---------------------------------------------------------------------------
proc trySkipGate*(gate: GateConfig; changedFiles: seq[string];
                  repoRoot: string; epoch: int; subtreeRoot: string = ""): Option[tuple[result: bool, category: FailureCategory, reason: string]] {.raises: [CatchableError].} =
  let cacheKey = computeGateCacheKey(gate, changedFiles, repoRoot, subtreeRoot)
  if cacheKey.len == 0:
    return none(tuple[result: bool, category: FailureCategory, reason: string])
  if gSalsaDbPtr != nil:
    let salsa = cast[ptr SalsaMemoDb](gSalsaDbPtr)
    # DEBT#471 (enforcement-path slice): the dependency set is never empty —
    # an empty current-input set passes lookupGreen's subset check vacuously,
    # so any stored green entry would be consumed regardless of what it was
    # computed against. Binding the composite key makes the green check
    # invalidate whenever the memo identity changes.
    let greenEntry = salsa[].lookupGreen(gate.id, subtreeRoot,
      toHashSet(["memokey:" & cacheKey]))
    if greenEntry.gateId.len > 0 and greenEntry.result:
      return some((true, fcTransient, "salsa_green"))
  if isDaemonRunning(repoRoot):
    try:
      var dclient = initDaemonClient(repoRoot)
      let dresp = dclient.checkCache(gate.id, subtreeRoot, epoch, cacheKey)
      if dresp.ok and dresp.cached:
        # DEBT#471: same verdict-axis semantics as the CAS layer — a cached
        # response that classifies as moNotEvaluated (tool failure, no
        # evidence) is an execution state and is not consumed as a hit.
        if daemonMemoVerdict(dresp.result, dresp.failCategory, dresp.reason) == moNotEvaluated:
          discard  # fall through to the disk memo index
        else:
          let category = parseEnum(dresp.failCategory, fcTransient)
          # DEBT#471 read-time closure: memo-stored reason text is not
          # replayed as authority. Daemon entries carry no finding
          # coordinates, so the replay renders the category only — the
          # current formatter, not past vocabulary.
          if dresp.result:
            return some((dresp.result, category, ""))
          if gate.hermeticity != ghTransient:
            return some((dresp.result, category, ""))
          return none(tuple[result: bool, category: FailureCategory, reason: string])
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  if not gMemoIndexLoaded:
    let epochDir = GateMemoBaseDir / "epoch_" & $epoch
    gMemoIndex = loadMemoIndex(epochDir)
    gMemoIndexLoaded = true
  let indexed = lookupMemo(gMemoIndex, gate.id, cacheKey)
  if indexed.isSome:
    # DEBT#471 read-time closure: the replayed reason is rendered by the
    # current formatter from the stored finding coordinates — stored prose is
    # never echoed. Legacy entries (findings empty) replay the verdict with
    # the category alone.
    let rendered = renderMemoFindings(indexed.get.findings)
    if indexed.get.result:
      return some((indexed.get.result, indexed.get.failureCategory, rendered))
    if gate.hermeticity == ghTransient:
      return none(tuple[result: bool, category: FailureCategory, reason: string])
    if indexed.get.failureCategory == fcUnknown:
      return none(tuple[result: bool, category: FailureCategory, reason: string])
    return some((indexed.get.result, indexed.get.failureCategory, rendered))
  none(tuple[result: bool, category: FailureCategory, reason: string])

proc trySkipGateOptimized*(gate: GateConfig; ctx: GateRunContext): Option[tuple[result: bool, category: FailureCategory, reason: string]] {.raises: [CatchableError].} =
  let cacheKey = gate.computeCacheKey(ctx)
  if cacheKey.len == 0:
    return none(tuple[result: bool, category: FailureCategory, reason: string])
  let salsaPtr = if ctx.salsaDb != nil: ctx.salsaDb else: gSalsaDbPtr
  let subtreeRoot = ctx.vfsComputeSubtreeRoot(gate.filesPattern)
  if salsaPtr != nil:
    let salsa = cast[ptr SalsaMemoDb](salsaPtr)
    # DEBT#471 (enforcement-path slice): never-empty dependency set + real
    # subtree node (see trySkipGate).
    let greenEntry = salsa[].lookupGreen(gate.id, subtreeRoot,
      toHashSet(["memokey:" & cacheKey]))
    if greenEntry.gateId.len > 0 and greenEntry.result:
      return some((true, fcTransient, "salsa_green"))
  if isDaemonRunning(ctx.repoRoot):
    try:
      var dclient = initDaemonClient(ctx.repoRoot)
      let dresp = dclient.checkCache(gate.id, subtreeRoot, ctx.epoch, cacheKey)
      if dresp.ok and dresp.cached:
        # DEBT#471: verdict-axis guard on the daemon read path (see trySkipGate).
        if daemonMemoVerdict(dresp.result, dresp.failCategory, dresp.reason) == moNotEvaluated:
          discard  # fall through to the disk memo index
        else:
          let category = parseEnum(dresp.failCategory, fcTransient)
          # DEBT#471 read-time closure: category-only replay for daemon hits.
          if dresp.result:
            return some((dresp.result, category, ""))
          if gate.hermeticity == ghTransient:
            return none(tuple[result: bool, category: FailureCategory, reason: string])
          if ctx.stage == gsPrePush:
            return none(tuple[result: bool, category: FailureCategory, reason: string])
          return some((dresp.result, category, ""))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  if not gMemoIndexLoaded:
    let epochDir = GateMemoBaseDir / "epoch_" & $ctx.epoch
    gMemoIndex = loadMemoIndex(epochDir)
    gMemoIndexLoaded = true
  let indexed = lookupMemo(gMemoIndex, gate.id, cacheKey)
  if indexed.isSome:
    # DEBT#471 read-time closure: findings rendered by the current formatter.
    let rendered = renderMemoFindings(indexed.get.findings)
    if indexed.get.result:
      return some((indexed.get.result, indexed.get.failureCategory, rendered))
    if gate.hermeticity == ghTransient:
      return none(tuple[result: bool, category: FailureCategory, reason: string])
    if indexed.get.failureCategory == fcUnknown:
      return none(tuple[result: bool, category: FailureCategory, reason: string])
    if ctx.stage == gsPrePush:
      return none(tuple[result: bool, category: FailureCategory, reason: string])
    return some((indexed.get.result, indexed.get.failureCategory, rendered))
  none(tuple[result: bool, category: FailureCategory, reason: string])

# ---------------------------------------------------------------------------
# Memo persistence
# ---------------------------------------------------------------------------
proc persistGateMemo*(gate: GateConfig; changedFiles: seq[string]; ok: bool;
                      repoRoot: string; epoch: int; subtreeRoot: string = "";
                      failureCategory: FailureCategory = fcTransient;
                      failureReason: string = "";
                      gateOutput: string = "") {.raises: [CatchableError].} =
  ## Persist a gate outcome to every memo sink under ONE verdict-axis guard.
  ## DEBT#471 value closure: gateOutput is mined for structured finding
  ## coordinates at write time; the stored value carries those coordinates
  ## (failureReason prose is auxiliary — the gate's own summary field, never
  ## quoted stdout). DEBT#471 daemon guard: the CAS layer, the daemon MemoDb
  ## and the in-process salsa db share the same classifyMemoOutcome semantics
  ## — an outcome that is not a verdict (tool failure, unclassifiable, or
  ## unevidenced) persists nowhere.
  let cacheKey = computeGateCacheKey(gate, changedFiles, repoRoot, subtreeRoot)
  if cacheKey.len == 0:
    return
  let findings = parseFindingsFromOutput(gateOutput)
  let outcome = if findings.len > 0:
    classifyStructuredMemoOutcome(ok, failureCategory, failureReason, findings)
  else:
    classifyMemoOutcome(ok, failureCategory, failureReason)
  if outcome == moNotEvaluated:
    return
  saveGateMemo(gate.id, cacheKey, ok, epoch, failureCategory, failureReason, findings)
  if isDaemonRunning(repoRoot):
    try:
      var dclient = initDaemonClient(repoRoot)
      discard dclient.persistResult(gate.id, subtreeRoot, epoch, ok, cacheKey,
                                    $failureCategory, failureReason)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  if gSalsaDbPtr != nil:
    let salsa = cast[ptr SalsaMemoDb](gSalsaDbPtr)
    let entry = CacheEntry(
      gateId: gate.id,
      subtreeRoot: subtreeRoot,
      result: ok,
      epoch: epoch,
      failCategory: $failureCategory,
      failReason: failureReason,
      timestamp: int64(getTime().toUnix())
    )
    # DEBT#471 (enforcement-path slice): persist the composite key as the
    # dependency — never an empty input set (see trySkipGate).
    salsa[].persist(entry, toHashSet(["memokey:" & cacheKey]))
