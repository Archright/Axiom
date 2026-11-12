import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import ../../infrastructure/git_ops
import ./types
import core/interfaces/logging_hub
import infrastructure/logging_facade
import core/trusted/axiom_pragmas
import ../crypto/hash_kernel
import std/[os, osproc, json, tables, times, strutils]

type
  SyncProtocolError* = object of CatchableError

let gitExe* = findRealGit()
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc sha256hex(content: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = hash_kernel.sha256Hex(content)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeConfigHash*(repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Hash config.nims + axiom.nimble for config-level change detection.
  var hasherInput = ""
  let configPath = repoRoot / "config.nims"
  if fileExists(configPath):
    try: hasherInput &= readFile(configPath)
    except CatchableError as e:
      logError("[state_hash] Config file read failure: " & e.msg) # axiom:best-effort(config file missing → partial hash)
  let nimblePath = repoRoot / "axiom.nimble"
  if fileExists(nimblePath):
    try: hasherInput &= readFile(nimblePath)
    except CatchableError as e:
      logError("[state_hash] Nimble file read failure: " & e.msg) # axiom:best-effort(optional file → partial hash)
  result = sha256hex(hasherInput)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeGateHash*(repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Hash all gate source files in src/gate/ for gate-level change detection.
  var content = ""
  let gateDir = repoRoot / "src" / "gate"
  if not dirExists(gateDir): return ""
  try:
    for path in walkDirRec(gateDir):
      if path.endsWith(".nim"):
        try: content &= readFile(path)
        except CatchableError as e:
          logError("[state_hash] Gate file read failure: " & e.msg) # axiom:best-effort(gate file read failure → partial gate hash)
  except CatchableError as e:
    logError("[state_hash] walkDirRec failure: " & e.msg) # axiom:best-effort(walkDirRec failure → empty gate hash)
  result = sha256hex(content)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeStateHash*(pm: ProjectMap; repoRoot: string): StateHash {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute deterministic project state identifier.
  ## combined = SHA-256(sourceHash + configHash + gateHash)
  ## If combined matches cached state, all results are reusable.
  result.sourceHash = pm.sourceHash
  result.configHash = computeConfigHash(repoRoot)
  result.gateHash = computeGateHash(repoRoot)
  result.combined = sha256hex(result.sourceHash & result.configHash & result.gateHash)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isStateValid*(cachePath: string; currentHash: StateHash): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if cached state matches current state.
  if not fileExists(cachePath): return false
  try:
    let content = readFile(cachePath)
    let j = parseJson(content)
    let cachedCombined = j{"stateHash"}{"combined"}.getStr("")
    return cachedCombined.len > 0 and cachedCombined == currentHash.combined
  except CatchableError:
    return false  # axiom:best-effort(cache read failure → state invalid)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadCachedGateResults*(cachePath: string): Table[string, bool] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load per-gate pass/fail results from cache.
  ## Returns empty table if cache is missing or corrupt.
  result = initTable[string, bool]()
  if not fileExists(cachePath): return
  try:
    let j = parseJson(readFile(cachePath))
    let gates = j{"gateResults"}
    if gates.isNil or gates.kind != JObject: return
    for gateId, node in gates:
      if node.hasKey("ok"):
        result[gateId] = node["ok"].getBool(false)
  except CatchableError as e:
    logWarn("[state_hash]", "Cache load failed, returning empty results: " & e.msg)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isSourceOnlyChange*(cachePath: string;
 currentHash: StateHash): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## True when source changed but config+gate hashes are identical.
  ## Enables incremental re-run: only source-dependent gates need execution.
  if not fileExists(cachePath): return false
  try:
    let j = parseJson(readFile(cachePath))
    let cachedConfig = j{"stateHash"}{"configHash"}.getStr("")
    let cachedGate = j{"stateHash"}{"gateHash"}.getStr("")
    return currentHash.configHash == cachedConfig and
           currentHash.gateHash == cachedGate
  except CatchableError:
    return false # axiom:best-effort(cache read failure → assume stale)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc saveStateHash*(cachePath: string; state: StateHash;
                    buildOk: bool;
                    gateResults: Table[string, bool])  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Persist state hash + results to .axiom_state.json.
  var gateJson = newJObject()
  for gateId, ok in gateResults:
    gateJson[gateId] = %*{"ok": ok}

  let j = %*{
    "stateHash": {
      "sourceHash": state.sourceHash,
      "configHash": state.configHash,
      "gateHash": state.gateHash,
      "combined": state.combined
    },
    "buildOk": buildOk,
    "gateResults": gateJson,
    "timestamp": $now().utc()
  }

  try:
    let dir = cachePath.parentDir()
    if not dirExists(dir):
      createDir(dir)
    writeFile(cachePath, j.pretty() & "\n")
  except CatchableError as e:
    logError("[state_hash] State hash persistence failure: " & e.msg) # axiom:best-effort(persistence; zero correctness impact)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc gatherGitMetadata*(repoRoot: string): GitMetadata {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Gather git state for Gate 0 protocol enforcement.
  ## External state → internal data (State Internalization pattern).
  result = GitMetadata()
  try:
    # Get current branch
    let branchOutput = execProcess(gitExe & " -C " & quoteShell(repoRoot) & " rev-parse --abbrev-ref HEAD 2>/dev/null")
    result.currentBranch = branchOutput.strip()
    result.isDetached = result.currentBranch == "HEAD"

    # Get HEAD hash
    result.headHash = execProcess(gitExe & " -C " & quoteShell(repoRoot) & " rev-parse HEAD 2>/dev/null").strip()

    # Get remote tracking branch
    let upstream = execProcess(gitExe & " -C " & quoteShell(repoRoot) & " rev-parse --abbrev-ref @{upstream} 2>/dev/null").strip()
    if upstream.len > 0:
      result.remoteBranch = upstream
      result.remoteHash = execProcess(gitExe & " -C " & quoteShell(repoRoot) & " rev-parse " & upstream & " 2>/dev/null").strip()

    # Check for uncommitted changes
    let statusOutput = execProcess(gitExe & " -C " & quoteShell(repoRoot) & " status --porcelain 2>/dev/null")
    result.hasUncommittedChanges = statusOutput.strip().len > 0

    # Check sync authorization (git config — deterministic, persists across process boundaries)
    let syncAuth = execProcess(gitExe & " config --local --get axiom.sync-authorized 2>/dev/null").strip()
    result.syncBranchToken = syncAuth == "true"
  except CatchableError as e:
    logError("[state_hash] Git metadata gather failure: " & e.msg) # axiom:best-effort(git metadata; default fields on failure)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc assertSyncProtocol*(meta: GitMetadata): bool {.raises: [SyncProtocolError].} =
  ## Gate 0: Verify sync protocol compliance.
  ## Raises SyncProtocolError on violation (Fail-Closed).
  
  if meta.isDetached:
    try: stderr.writeLine("""{"event":"gate_0","status":"fail","reason":"detached_head"}""")
    except CatchableError: discard  # axiom:best-effort(audit log; protocol violation raised regardless)
    raise newException(SyncProtocolError, "Gate 0: Detached HEAD detected")
  
  if meta.hasUncommittedChanges:
    try: stderr.writeLine("""{"event":"gate_0","status":"fail","reason":"uncommitted"}""")
    except CatchableError: discard  # axiom:best-effort(audit log; protocol violation raised regardless)
    raise newException(SyncProtocolError, "Gate 0: Uncommitted changes detected")
  
  if not (meta.syncBranchToken or meta.currentBranch == "main"):
    try: stderr.writeLine("""{"event":"gate_0","status":"fail","reason":"sync_violation"}""")
    except CatchableError: discard  # axiom:best-effort(audit log; protocol violation raised regardless)
    raise newException(SyncProtocolError, "Gate 0: Sync protocol violation")
  
  return true
{.pop.}

