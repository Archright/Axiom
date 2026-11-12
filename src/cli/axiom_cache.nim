import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## axiom cache — Cache management CLI
##
## Commands:
##   ax cache --status          Show cache state (epoch, entries, daemon)
##   ax cache --clear           Advance epoch (safe invalidation)
##   ax cache --clear --force   Wipe cache directory (poisoning recovery)
##   ax cache --clear --gate X  Invalidate specific gate
##   ax cache --gc              Run garbage collection
##   ax cache --shadow-status   Show shadow worker state

import std/[os, strutils, strformat, json, times]
import core/gate/gate_memo
import gate/daemon/gate_daemon_client
import core/axiom_pragmas
import core/utils/repo_root
import core/parsers/safe_parsers
import core/results

proc findRepoRoot(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Find repo root by delegating to the SSOT in repo_root.nim.
  repo_root.findRepoRoot(getCurrentDir())

proc showCacheStatus(repoRoot: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let epoch = currentCacheEpoch()
  let memoBase = repoRoot / GateMemoBaseDir
  let memoDir = memoBase / "epoch_" & $epoch

  # Count entries in current epoch
  var entryCount = 0
  if dirExists(memoDir):
    for f in walkDirRec(memoDir):
      if not f.endsWith(".tmp"):
        inc entryCount

  # Check daemon
  let daemonRunning = isDaemonRunning(repoRoot)

  echo &"Cache Status:"
  echo &"  Epoch: {epoch}"
  echo &"  Entries: {entryCount}"
  echo &"  Memo dir: {memoDir}"
  let daemonStr = if daemonRunning: "running" else: "stopped"
  echo &"  Daemon: {daemonStr}"

  # Check shadow worker
  let shadowPath = repoRoot / ".axiom/cache/shadow_progress.json"
  if fileExists(shadowPath):
    try:
      let j = parseJson(readFile(shadowPath))
      let status = j{"status"}.getStr("unknown")
      echo &"  Shadow Worker: {status}"
      if status == "running":
        let completed = j{"completedGates"}.getInt(0)
        let total = j{"totalGates"}.getInt(0)
        let current = j{"currentGate"}.getStr("")
        echo &"    Progress: {completed}/{total} ({current})"
    except CatchableError:
      echo &"  Shadow Worker: (unreadable progress file)"
  else:
    echo &"  Shadow Worker: not started"

proc atomicCacheReset(repoRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## POSIX atomic directory replacement.
  ## moveDir uses rename() — atomic on same filesystem.
  ## Power failure scenarios:
  ##   During step 1: old cache still at `base`, trash doesn't exist yet → safe.
  ##   During step 3: trash exists, but cache at `base` is fresh and consistent.
  let base = repoRoot / ".axiom" / "cache"
  if not dirExists(base):
    echo "Cache directory does not exist: " & base
    return
  # 1. Atomic move (POSIX rename)
  let trash = base & "_trash_" & $int(epochTime())
  moveDir(base, trash)
  # 2. Immediately create fresh empty cache directory
  createDir(base)
  echo "Cache atomically reset: " & base
  # 3. Safe background cleanup (failure is non-fatal)
  try:
    removeDir(trash)
    echo "Trash cleaned: " & trash
  except CatchableError:
    echo "Warning: trash cleanup failed (non-fatal): " & trash

proc clearCache(repoRoot: string; force: bool; gateId: string = "") {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if gateId.len > 0:
    # Invalidate specific gate
    if isDaemonRunning(repoRoot):
      var client = initDaemonClient(repoRoot)
      discard client.invalidate(gateId)
    echo &"Invalidated cache for gate: {gateId}"
    return

  if force:
    # Atomic cache reset — POSIX rename, safe during power failure
    atomicCacheReset(repoRoot)
    # Also invalidate daemon
    if isDaemonRunning(repoRoot):
      var client = initDaemonClient(repoRoot)
      discard client.ping()
      echo "Daemon notified (restart recommended after force clear)"
  else:
    # Safe: advance epoch
    discard advanceCacheEpoch()
    echo &"Cache epoch advanced to {currentCacheEpoch()}"
    echo "Previous epoch entries will be garbage collected on next run."

proc runGarbageCollection(repoRoot: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let memoBase = repoRoot / GateMemoBaseDir
  var removed = 0
  let currentEp = currentCacheEpoch()
  if dirExists(memoBase):
    for entry in walkDir(memoBase):
      if entry.kind == pcDir and entry.path.extractFilename.startsWith("epoch_"):
        let epNum = safeParseInt(entry.path.extractFilename[6..^1]).getOrDefault(-1)
        if epNum >= 0 and epNum < currentEp - 1:
          removeDir(entry.path)
          inc removed
  echo &"Garbage collected {removed} old epoch directories"

proc showShadowStatus(repoRoot: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let shadowPath = repoRoot / ".axiom/cache/shadow_progress.json"
  if not fileExists(shadowPath):
    echo "Shadow Worker: not started"
    return
  try:
    let j = parseJson(readFile(shadowPath))
    let status = j{"status"}.getStr("unknown")
    let startedAt = j{"startedAt"}.getInt(0)
    let totalGates = j{"totalGates"}.getInt(0)
    let completedGates = j{"completedGates"}.getInt(0)
    let currentGate = j{"currentGate"}.getStr("(none)")
    let elapsedMs = j{"elapsedMs"}.getInt(0)
    echo &"Shadow Worker Status: {status}"
    echo &"  Started: {startedAt}"
    echo &"  Total gates: {totalGates}"
    echo &"  Completed: {completedGates}"
    echo &"  Current: {currentGate}"
    echo &"  Elapsed: {elapsedMs}ms"
    let failed = j{"failedGates"}
    if failed.len > 0:
      echo "  Failed gates:"
      for f in failed:
        echo "    - " & f.getStr()
  except CatchableError:
    echo "Shadow Worker: (unreadable progress file)"

proc runCacheCli*(args: seq[string])  =
  ## Entry point for `ax cache` subcommand.
  var showStatus = false
  var clear = false
  var force = false
  var gc = false
  var shadowStatus = false
  var gateId = ""

  var i = 0
  while i < args.len:
    case args[i]
    of "--status": showStatus = true
    of "--clear": clear = true
    of "--force": force = true
    of "--gc": gc = true
    of "--shadow-status": shadowStatus = true
    of "--gate":
      inc i
      if i < args.len:
        gateId = args[i]
    else:
      echo "Unknown option: " & args[i]
      echo "Usage: ax cache [--status] [--clear [--force] [--gate <id>]] [--gc] [--shadow-status]"
      return
    inc i

  let repoRoot = findRepoRoot()

  try:
    if showStatus:
      showCacheStatus(repoRoot)
    elif clear:
      clearCache(repoRoot, force, gateId)
    elif gc:
      runGarbageCollection(repoRoot)
    elif shadowStatus:
      showShadowStatus(repoRoot)
    else:
      # Default: show status
      showCacheStatus(repoRoot)
  except CatchableError as e:
    echo "Error: " & e.msg

# ─── Standalone Entry Point ───────────────────────────────────────────────────

when isMainModule:
  let args = commandLineParams()
  runCacheCli(args)

{.pop.}
