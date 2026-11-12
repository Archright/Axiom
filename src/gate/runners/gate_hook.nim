import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Axiom Unified Sentry — Consensus Gate Pipeline
##
## Executable wrapper over orchestrator_hook.nim, which is the data-driven gate
## dispatcher using gate_list.nim as SSOT.
##
## All gate definitions live in gate_list.nim (single source of truth).

import std/os
import std/options
import std/osproc
import std/strformat
import std/strutils
import std/sequtils
import std/streams
import std/times
import std/json

import gate/orchestrator_hook as orch
import gate/gate_contract
import gate/gate_registry
import core/gate/gate_cas
import core/gate/gate_memo
import core/gate/gate_cas_gc
import infrastructure/provenance_probe
import generated/build_env
import gate/runners/fail_secure_state
import infrastructure/cas_index       # Φ3-B: O(1) atomic CAS cache check
import core/trusted/bypass_verify
import core/trusted/env_access
import gate/git
import std/posix
import infrastructure/logging_facade
import core/trusted/stdlib_shield
import core/axiom_pragmas
import gate/cache/soundness_cache_types
import gate/cache/soundness_cache_io
# axiomIoBoundary

# Binary Freshness Guard: compile-time timestamp injection.
# Bash Shim passes -d:AxiomCompileTime=$(date +%s) on every rebuild.
# Changing the -d value forces nimcache SHA1 recompilation, ensuring
# this constant is always fresh (bypasses incremental cache staleness).
const AxiomCompileTime* {.intdefine.}: int = 0
  ## Epoch seconds when this binary was compiled. Injected by Bash Shim.
  ## gate_self_check.nim uses this to detect source files modified after compilation.


proc isDuplicateAuditEntry(auditPath: string, currentTs: int): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if the last 5 entries in the audit log share the same timestamp.
  ## Prevents duplicate entries from rapid successive bypass attempts.
  try:
    if not fileExists(auditPath): return false
    let content = readFile(auditPath)
    let lines = content.splitLines()
    var checked = 0
    for i in countdown(lines.len - 1, max(0, lines.len - 5)):
      let line = lines[i].strip()
      if line.len == 0: continue
      try:
        let j = parseJson(line)
        if j.hasKey("ts") and j{"ts"}.getInt(0) == currentTs:
          return true
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
      inc checked
      if checked >= 5: break
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return false

# ---------------------------------------------------------------------------
# Executable entry point (used by CI, setup-hooks, and direct invocation)
# ---------------------------------------------------------------------------

when isMainModule:
  let args = commandLineParams()
  let invokedAs = paramStr(0).extractFilename()

  # B-layer cache provenance probe contract: strict self-check verdict only —
  # no stage resolution, no gate pipeline, no side effects (mismatch
  # FATAL-exits 1 inside verifyProvenanceOrFatal).
  if isProvenanceSelfCheckRequest(args):
    verifyProvenanceOrFatal("bin" / "gate_hook")
    logInfo("gate_hook", "[OK] gate_hook provenance self-check: embedded BuildSourceHash == live src tree (" & BuildSourceHash & ")")
    quit(0)

  let stage = orch.resolveStageFromArgs(invokedAs, args)
  if stage.len == 0:
    logInfo("gate_hook", "usage: gate_hook <pre-commit|pre-push|post-commit|pre-merge-commit|post-rewrite|post-checkout|ci>")
    quit(1)

  # Early guard: detect hooksPath=/dev/null integrity bypass attempt
  block hooksPathGuard:
    try:
      let hooksPath = execProcess("git config --get core.hooksPath 2>/dev/null").strip()
      if hooksPath == "/dev/null":
        logError("gate_hook", "[AXIOM GUARD] CRITICAL: core.hooksPath=/dev/null detected! " &
                 "This bypasses all integrity gates. Use bin/agent-bypass-commit for proper bypass.")
        # Log to audit trail (dedup: skip if same ts in last 5 entries)
        let currentTs = int(getTime().toUnix())
        let auditEntry = """{"ts":""" & $currentTs &
                         ""","reason":"hooksPath=/dev/null integrity bypass detected","type":"guard-triggered"}"""
        if not isDuplicateAuditEntry(".axiom/bypass_audit.jsonl", currentTs):
          try:
            createDir(".axiom")
            let f = open(".axiom/bypass_audit.jsonl", fmAppend)
            f.writeLine(auditEntry)
            f.close()
          except CatchableError:
            discard  # axiom:best-effort(ioboundary catch)
        quit(1)
    except CatchableError:
      discard  # git config failure -> non-fatal, continue  # axiom:best-effort(ioboundary catch)

  let (repoRoot, maxJobs) = orch.bootstrapGateEnvironment()

  # --purge-cache: advance cache epoch and exit
  for arg in args:
    if arg == "--purge-cache":
      discard gate_memo.advanceCacheEpoch()
      logInfo("gate_hook", "[CACHE] Cache epoch advanced successfully.")
      quit(0)

  # --rebaseline: thread the flag explicitly — runners receive --update-baseline
  # via parameters (DEBT#478: no ambient env transport)
  var rebaselineMode = false
  for arg in args:
    if arg == "--rebaseline":
      rebaselineMode = true
      logInfo("gate_hook", "[GATE] Rebaseline mode: --update-baseline will be passed to all baseline-aware gates.")
      break

  # Emergency bypass — env var + Ed25519 signature required (SA-4 protocol)
  if isEmergencyBypass():
    let sigHex = getAxiomEnv(evBypassSignature, "")
    let pubHex = getAxiomEnv(evBypassPubkey, "")
    let reason = getAxiomEnv(evBypassReason, "agent-emergency")
    if sigHex.len == 128 and pubHex.len == 64 and
       verifyBypassSignature(reason, sigHex, pubHex):
      logInfo("gate_hook", "[AXIOM GUARD] Signed emergency bypass verified. Skipping all gates.")
      # Audit log (dedup: skip if same ts in last 5 entries)
      let auditPath = repoRoot / ".axiom" / "bypass_audit.jsonl"
      let currentTs = int(getTime().toUnix())
      if not isDuplicateAuditEntry(auditPath, currentTs):
        try:
          let entry = "{\"ts\":$1,\"reason\":\"$2\",\"pubkey\":\"$3\",\"window\":$4,\"type\":\"ephemeral\"}" %
            [$currentTs, reason, pubHex[0..15], $currentTimeWindow()]
          let f = open(auditPath, fmAppend)
          f.writeLine(entry)
          f.close()
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
      quit(0)
    else:
      logError("gate_hook", "[AXIOM GUARD] BLOCKED: Emergency bypass requires Ed25519 signature.")
      logInfo("gate_hook", "[AXIOM GUARD] Use: bin/agent-bypass-commit --reason \"your-reason\" --message \"your-message\"")
      logInfo("gate_hook", "[AXIOM GUARD] Or set AXIOM_BYPASS_SIGNATURE + AXIOM_BYPASS_PUBKEY env vars.")
      logInfo("gate_hook", "[AXIOM GUARD] See: docs/spec/gate_cgroup_isolation.md §12")
      quit(1)

  # Context Token — prevent double execution in gateway commit pipeline.

  # Fail-closed short-circuit (Theater §0.9): a pre-commit invocation may skip
  # gate execution ONLY when ALL of the following hold:
  #   (1) context token present,
  #   (2) token equals the current staged index (git write-tree) — freshness,
  #   (3) receipt exists and parses as JSON,
  #   (4) receipt.treeHash == token,            (receipt is for THIS tree)
  #   (5) receipt.failedCount == 0.             (previous run really passed)
  # Stale / missing / corrupt / mismatch receipts fall through to the normal
  # gate path (fail-closed); an identical fresh-pass state keeps the 0-token skip.
  if stage == "pre-commit":
    let ctxId = getAxiomEnv(evGateContextId)
    if ctxId.len > 0:
      let receiptPath = repoRoot / ".axiom" / "gate_receipt.json"
      var currentTree = ""
      try:
        currentTree = execProcess("git write-tree").strip()
      except CatchableError:  # axiom:best-effort(freshness probe failed -> no short-circuit)
        currentTree = ""
      if currentTree.len == 0:
        logWarn("gate_hook", "[GATE] Context token present but freshness unverifiable — running gates")
        delEnv("AXIOM_GATE_CONTEXT_ID")
      elif currentTree != ctxId:
        logWarn("gate_hook", "[GATE] Context token STALE (current write-tree != token) — running gates")
        delEnv("AXIOM_GATE_CONTEXT_ID")
      elif fileExists(receiptPath):
        var receiptValid = false
        try:
          let receipt = parseFile(receiptPath)
          let receiptTree = receipt{"treeHash"}.getStr("")
          let failedCount = receipt{"failedCount"}.getInt(-1)
          receiptValid = receiptTree == ctxId and failedCount == 0
        except CatchableError:  # axiom:best-effort(corrupt/non-JSON receipt -> invalid)
          receiptValid = false
        if receiptValid:
          logInfo("gate_hook", "[GATE] Context token verified — short-circuit (0ms)")
          quit(0)
        logWarn("gate_hook", "[GATE] Context token present but receipt invalid (corrupt/mismatch/failed) — running gates")
        delEnv("AXIOM_GATE_CONTEXT_ID")
      else:
        # No receipt found → run gates normally
        logInfo("gate_hook", "[GATE] Context token present but no receipt — running gates")
        delEnv("AXIOM_GATE_CONTEXT_ID")

  # Fail-Secure reconciliation: verify audit log integrity before gate execution
  if stage == "commit-msg":
    let auditPath = repoRoot / ".axiom" / "bypass_audit.jsonl"
    let commitMsgPath = if args.len > 1: args[^1] else: ""
    let failState = computeState(auditPath, commitMsgPath)
    if not canBypass(failState):
      logError("gate_hook", &"[GATE] Fail-Secure state: {stateDescription(failState)}")
      logError("gate_hook", "[GATE] Audit log integrity check failed. Blocking commit.")
      quit(1)
    logError("gate_hook", &"[GATE] Fail-Secure state: {stateDescription(failState)} — OK")

  let gateStage = orch.resolveGateStage(stage)

  # Epoch-based cache initialization
  gate_memo.migrateFromFlat()
  let cacheEpoch = gate_memo.currentCacheEpoch()

  # CAS GC trigger: rate-limited, inline fast mode
  if gate_cas_gc.shouldRunCasGc():
    gate_cas_gc.recordCasGcRun()
    gate_cas_gc.runCasGc(repoRoot)

  # Symlink health check: remove any dangling symlinks in bin/
  let binDir = repoRoot / "bin"
  if dirExists(binDir):
    for kind, path in walkDir(binDir):
      if kind == pcLinkToFile or kind == pcLinkToDir:
        if not fileExists(path):
          try:
            removeFile(path)
            logInfo("gate_hook", "[GATE] Removed dangling symlink: " & path.extractFilename())
          except CatchableError:
            discard  # axiom:best-effort(ioboundary catch)

  logInfo("gate_hook", &"[GATE] Axiom gate hook — stage={stage} jobs={maxJobs} epoch={cacheEpoch}")

  # Manifest integrity check (configuration drift guard).
  # v27: Skip in L2 children — parent already validated via State Ledger.
  if getAxiomEnv(evStateLedgerPath).len == 0:
    if not orch.checkManifestIntegrity():
      quit(1)

  # --- Moved from .githooks/ thin proxies ---

  if stage == "pre-commit":
    let changedFiles = gitDiffCachedNames()

    # Contract boundary guard: gate_contract.nim is READ-ONLY
    # Modifications require [Arch-Review-Verified] in commit message (AGENTS.md §-1)
    for f in changedFiles:
      if f.endsWith("gate_contract.nim"):
        # Check if this is a NEW file (initial creation) — allowed without verification
        let isNewOutput = execProcess(
          "git diff --cached --diff-filter=A --name-only -- " & f).strip()
        if isNewOutput.len == 0:
          # Existing file modification — require [Arch-Review-Verified]
          let commitMsgPath = repoRoot / ".git" / "COMMIT_EDITMSG"
          if fileExists(commitMsgPath):
            let commitMsg = readFile(commitMsgPath)
            if "[Arch-Review-Verified]" notin commitMsg:
              logInfo("gate_hook", "[FAIL] [Axiom Guard] gate_contract.nim is a READ-ONLY contract boundary.")
              logInfo("gate_hook", "   Modifications require [Arch-Review-Verified] in commit message.")
              logInfo("gate_hook", "   See: AGENTS.md §-1, gate_contract.nim header")
              quit(1)
            logInfo("gate_hook", "✅ [Axiom Guard] Contract modification approved ([Arch-Review-Verified] found)")
        else:
          logInfo("gate_hook", "✅ [Axiom Guard] Contract initial creation — permitted")

    # Empty .feature file rejection
    for f in changedFiles:
      if f.endsWith(".feature"):
        if fileExists(f):
          let content = readFile(f)
          if "Scenario:" notin content:
            logInfo("gate_hook", "[FAIL] [Axiom Guard] Empty .feature file rejected: " & f)
            logInfo("gate_hook", "   Must contain at least one 'Scenario:' line.")
            quit(1)

    # Manifest freshness: regenerate if .feature files changed
    var hasFeatureChanges = false
    for f in changedFiles:
      if f.endsWith(".feature"):
        hasFeatureChanges = true
        break
    if hasFeatureChanges:
      logInfo("gate_hook", "⚡ [Axiom] .feature files changed. Regenerating manifest...")
      discard execProcess("nim c -r --hints:off tools/feature_manifest_generator.nim")
      discard execProcess("git add data/feature_manifest.json")

  if stage == "pre-merge-commit":
    # E2E Merge Verification Pipeline (moved from .githooks/pre-merge-commit)
    # Verify semantic integrity of merged .nim files via axiom-merge-verify.
    let changedNim = execProcess(
      "git diff --cached --name-only --diff-filter=ACMR -- '*.nim' 2>/dev/null || true").strip()
    if changedNim.len > 0:
      let verifyBin = repoRoot / "bin" / "axiom-merge-verify"
      if fileExists(verifyBin):
        let nimFiles = changedNim.splitLines().filterIt(it.len > 0)
        logInfo("gate_hook", "[Axiom Merge Verify] Checking " & $nimFiles.len & " merged .nim file(s)...")
        try:
          let p = startProcess(verifyBin, args = ["--files"])
          p.inputStream.write(changedNim & "\n")
          p.close()
          let exitCode = p.waitForExit()
          if exitCode != 0:
            logError("gate_hook", "[FAIL] [Axiom Merge Verify] Semantic verification failed (exit=" & $exitCode & "). Merge aborted.")
            quit(1)
        except CatchableError as e:
          logError("gate_hook", "[FAIL] [Axiom Merge Verify] Failed: " & e.msg)
          quit(1)
    # Fall through to pre-commit gate suite below

  if stage == "post-commit":
    # Git LFS post-commit (moved from .githooks/post-commit)
    if findExe("git-lfs") != "":
      discard execProcess("git lfs post-commit")
    # Post-commit hooks
    # Continue to deferred gate execution below

  if stage == "post-rewrite":
    # Tree receipt creation (moved from .githooks/post-rewrite)
    # stdin format: <old-sha> <new-sha> [<extra-info>] LF
    let receiptDir = repoRoot / ".axiom" / "cache" / "verification_receipts"
    createDir(receiptDir)
    let zeroSha = "0000000000000000000000000000000000000000"
    let input = stdin.readAll()
    for line in input.splitLines():
      let trimmed = line.strip()
      if trimmed.len == 0: continue
      let parts = trimmed.split(' ')
      if parts.len < 2: continue
      let newSha = parts[1]
      if newSha == zeroSha: continue
      try:
        let treeSha = execProcess("git rev-parse " & newSha & "^{tree}").strip()
        let receiptPath = receiptDir / treeSha
        if not fileExists(receiptPath):
          let timestamp = getTime().toUnix()
          writeFile(receiptPath & ".tmp", "0|" & $timestamp)
          safeMoveFile(receiptPath & ".tmp", receiptPath)
      except CatchableError, FileMoveError:
        discard
    quit(0)

  if stage == "post-checkout":
    # Git LFS post-checkout (moved from .githooks/post-checkout)
    if findExe("git-lfs") != "":
      discard execProcess("git lfs post-checkout")
    quit(0)

  # Φ3-B: Soundness-aware CAS cache check (§0.9 Theater fix — verify pass/fail status)
  # Computes a transitive hash over commit + all blob hashes + config + manifest.
  # Only skips execution if the hash matches a PREVIOUSLY PASSED gate run.
  var transHash = ""
  block casEarlyExit:
    try:
      transHash = computeTransitiveHash(repoRoot)
      if transHash.len > 0:
        let cachePath = repoRoot / ".axiom" / "cache" / "gate_hook_soundness.json"
        let soundnessCache = loadAndValidateCache(cachePath)
        let cachedStatus = lookupSoundnessCache(soundnessCache, "gate-hook-cas", transHash)

        if cachedStatus.isNone():
          logInfo("gate_hook", "[GATE-CAS] Cache miss — transitiveHash=" & transHash[0..15] & "... — running gates")
        elif cachedStatus.get() == gvsPass:
          logInfo("gate_hook", "[GATE-CAS] Cache HIT (PASS): transitiveHash=" & transHash[0..15] & "... — skipping execution")
          quit(0)
        else:
          logWarn("gate_hook", "[GATE-CAS] Cache HIT but PREVIOUS RUN FAILED — transitiveHash=" & transHash[0..15] & "... — re-running gates (fail-closed)")
      else:
        logInfo("gate_hook", "[GATE-CAS] Transitive hash computation failed — running gates")
    except CatchableError:
      discard  # CAS check failure is non-fatal — run gates normally  # axiom:best-effort(ioboundary catch)

  # Single gate mode (used by parallel L2 dispatcher)
  let singleResult = orch.runSingleGateIfRequested(gateStage, repoRoot, maxJobs, cacheEpoch,
                                                   updateBaseline = rebaselineMode)
  if singleResult.isSome:
    quit(if singleResult.get: 0 else: 1)

  # ── CI pre-flight: guarantee AOT precompile (no JIT nim c) ──
  if stage == "ci":
    putEnv("AXIOM_FAST_BUILD", "1")
    block ciAotGuard:
      try:
        let gates = allGates()
        var needsPrecompile = false
        for g in gates:
          if gsPreCommit in g.stages or gsPrePush in g.stages or gsCI in g.stages:
            let srcPath = repoRoot / g.entry
            if fileExists(srcPath):
              if gate_cas.resolveCasBinaryPath(g.id, srcPath, repoRoot).len == 0:
                needsPrecompile = true
                break
        if needsPrecompile and fileExists(repoRoot / "bin" / "precompile_gates"):
          logInfo("gate_hook", "[GATE] CI: CAS miss detected — running bin/precompile_gates")
          let (outp, code) = execCmdEx("bin/precompile_gates")
          if code != 0:
            logError("gate_hook", "[GATE] CI: precompile_gates failed: " & outp)
            quit(1)
          logInfo("gate_hook", "[GATE] CI: precompile_gates done")
      except CatchableError:
        discard  # fail-open: proceed without precompile  # axiom:best-effort(ioboundary catch)
    orch.runCi(cacheEpoch, updateBaseline = rebaselineMode)
  elif stage == "pre-commit" or stage == "pre-merge-commit":
    orch.runPreCommit(cacheEpoch, updateBaseline = rebaselineMode)
  elif stage == "pre-push":
    # Ingestion Boundary: parse pre-push stdin (Git spec: always 40-char full hashes)
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
    orch.setPushRefs(pushRefs)
    orch.runPrePush(cacheEpoch, updateBaseline = rebaselineMode)
  elif stage == "commit-msg":
    # Fail-Secure check already passed above — no additional gates needed
    discard
  else:
    logInfo("gate_hook", "usage: gate_hook <pre-commit|pre-push|pre-merge-commit|ci>")
    quit(1)

  ## Save CAS soundness cache entry (orchestrator completed without quitting)
  if transHash.len > 0:
    try:
      let cachePath = repoRoot / ".axiom" / "cache" / "gate_hook_soundness.json"
      let entry = VerificationCacheEntry(
        schemaVersion: SoundnessCacheSchemaVersion,
        compositeLockHash: transHash,
        sourceHash: transHash,
        status: gvsPass,
        timestamp: epochTime().float,
        gateId: "gate-hook-cas"
      )
      saveCacheEntry(cachePath, entry)
    except CatchableError:
      discard  # axiom:best-effort(cache write failure is non-fatal for the hook) — gate verdict unaffected

{.pop.}
