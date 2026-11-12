## local_purity_check.nim — Fresh-checkout purity verification in a persistent worktree
##
## RUNS the FULL 15-gate `make local-verify-static-full` inside an isolated git
## worktree, OUTSIDE the repo (under getHomeDir()/.cache/axiom/purity-check) so
## Nim's parent-config search never also loads the main repo's config.nims.
## Simulates a fresh checkout without polluting the developer's working tree,
## catching the "untracked-file-missing / fresh-checkout masking" bug classes
## before push.
##
## Exit codes:
##   0 = all gates passed
##   1 = a gate / mutation failed (make non-zero; the normal product-level
##       failure — incl. a mutant escaping — propagated from the executed command)
##   2 = repo root not found
##   3 = git setup failure (worktree list/add/reset/clean)
##   4 = stub write failure
##   5 = infra recovery / cleanup failure (stale-orphaned-dir removal failed, or
##       post-run original-tree contamination / leftover-worktree check failed) —
##       FAIL-CLOSED, never swallowed
##   6 = slot identity failure (the run's content stamp could not be computed, or
##       its lock could not be taken) — FAIL-CLOSED: without an isolated slot the
##       run would re-enter the shared-path defect this file now prevents
##
## ─── Isolation: content-addressed slot + per-slot flock ────────────────────
## The worktree was ONCE pinned at a single fixed path
## (`~/.cache/axiom/purity-check`) and written with no locking, so two concurrent
## invocations (the verify-contract fan-out, or two local runs) fought over one
## mutable git worktree: `reset --hard` / `clean -ffdx` / `worktree remove
## --force` from one run mutated or deleted the tree the other was executing in.
## That is the same defect family as DEBT#481.
##
## The slot is now the CONTENT IDENTITY of the run (SHA-256 over the build
## inputs, the Nim version line and the cache-format version — no clock, no pid),
## which fixes three things at once:
##   1. two runs on DIFFERENT inputs never share a path, so they cannot collide
##      at all;
##   2. the slot path stays STABLE for a given input set, which the warm nimcache
##      requires — Nim's incremental database (ax.json) records the absolute
##      worktree path of every source file, so a per-invocation path would make
##      every cache entry dangle and silently destroy the cache;
##   3. two runs on the SAME inputs share a slot BY CONSTRUCTION, so that case is
##      serialised by an exclusive flock on the slot (they are the same
##      computation; the waiter also inherits the cache the holder publishes).
##
## The lock is the invariant, not an optimisation: the kernel releases it on
## process death, so a crashed run cannot wedge a slot. Lock files are 0-byte
## inodes that are deliberately NEVER unlinked — unlinking a flock target while
## another process may be waiting on it would let a newcomer lock a fresh inode
## while the waiter holds the old one, i.e. the exact exclusion failure this
## file exists to prevent.
##
## Worktree lifecycle is deterministic: the temp worktree is created, reused via
## reset --hard, or recovered (exactly once) from a stale orphaned dir; always
## removed and prune-confirmed afterwards, with the original tree verified
## unchanged. Worktrees (and staging dirs) of slots whose lock is free are
## reclaimed at the start of every run, so a crashed run leaks nothing.
##
## Usage:
##   nim c -o:bin/local_purity_check tools/local_purity_check.nim
##   bin/local_purity_check              # runs make local-verify-static-full
##   bin/local_purity_check --exec ci-payload  # runs make ci-payload
##   bin/local_purity_check --exec-cmd 'bash tools/invariant_mutation_harness.sh'
##                                       # runs a raw shell command in the isolated
##                                       # worktree (used for invariant mutation
##                                       # harness which must never mutate the main
##                                       # working tree)
import std/[os, osproc, parseopt, posix, strutils]
import checksums/sha2
import core/utils/repo_root

## Raw C rename(2) — not exposed by std/posix (Nim's std/os reserves the name).
## POSIX rename over an existing symlink is an atomic replacement on the same
## filesystem, which is what the warm-cache `active` symlink flip relies on (T4).
proc cRename(src, dest: cstring): cint {.importc: "rename", header: "<stdio.h>", raises: [].}

## POSIX flock(2) — not re-exported by std/posix on Linux. Inline import because
## std/osproc's withFlock requires a non-capturing proc (same precedent as
## tools/rule_proposal.nim).
proc c_flock(fd: cint, operation: cint): cint
  {.importc: "flock", header: "<sys/file.h>", sideEffect.}

const
  lockExclusive = 2      ## LOCK_EX
  lockUnlock = 8         ## LOCK_UN
  lockNonBlocking = 4    ## LOCK_NB

{.push raises: [CatchableError].}

## Slot ROOT (formerly the single fixed worktree path). Every run gets its own
## content-addressed child directory; the root itself is never a worktree.
## Rationale for staying OUTSIDE the repo: a worktree NESTED under the repo root
## (e.g. .axiom/worktree/fresh) makes Nim walk UP from the worktree CWD and find
## the MAIN repo's config.nims too — both `--path:src` get added, loading every
## module twice (ambiguous symbol errors). An external worktree has no parent
## config leak.
const PureCheckRoot = getHomeDir() / ".cache" / "axiom" / "purity-check"

## Warm nimcache persistence (O1).
## Cache lives outside the worktree so it survives worktree removal.
const WarmCacheVersion = "warm-nimcache-v2"
  ## v2: a cache unit is now named by its CONTENT STAMP and the worktree path is
  ## content-addressed under PureCheckRoot. A v1 unit (`unit-<unix ts>`) can
  ## never collide with a v2 name, so v1 units are cold by construction.
const WarmCachePersistDir = getHomeDir() / ".cache" / "axiom" / "purity-nimcache"
const WarmCacheActive = WarmCachePersistDir / "active"
const WarmCacheUnits = WarmCachePersistDir / "units"

## Files whose CONTENT defines the run slot (and the warm-cache unit).
const SlotInputFiles = [
  "nimble.lock", "config.nims", "config/lint.nims", "config/strict.nims",
  "axiom.nimble", "tools/hermetic_build.nim", "src/gate/topology_spec.nim",
  "config/gates.manifest.toml", "src/generated/build_env.nim.default",
  "tools/local_purity_check.nim", "tools/invariant_mutation_harness.sh",
  "Makefile",
]

type SlotLock = object
  ## Held for the whole run. Lifetime IS the process: every exit path ends in
  ## `quit()`, and the kernel drops an flock when its fd is closed at process
  ## exit — so there is no path that can leave a slot wedged.
  fd: cint

# Stub content is built from parts so no source line starts with "import "
# (the layer-enforcement gate line-scans for `startsWith("import")` and would
# otherwise false-positive on the embedded mutation-harness stub source).
# The emitted bytes MUST be identical to the tracked bin/axiom.nim: the
# worktree purity gate inside this tool runs `git status --porcelain` after
# the stub is written, and any divergence from the tracked artifact would
# report the tool's own stub as a dirty tree (observed 2026-10-08).
const StubScannerModule = "gate" & "/static_gate_scanner"
const StubContent = "import " & StubScannerModule & "\n" &
  "\n" &
  "# Compile-time gate stub detection\n" &
  "static:\n" &
  "  scanGateRegistryStubs()\n"

proc git(repoDir, args: string): (string, int) =
  execCmdEx("git -C " & quoteShell(repoDir) & " " & args)

## Read a symbolic link target. Returns "" on error (broken or non-symlink).
## NOTE: must NOT do `result = $buf[0..<len]` — that stringifies a seq[char]
## into `@['u','n',...]` (Nim debug repr), not the link text. Build the string
## from the raw bytes instead.
func readLink*(path: string): string {.raises: [].} =
  var buf: array[4096, char]
  let len = posix.readlink(path.cstring, cast[cstring](buf[0].addr), buf.len)
  if len <= 0: return ""
  result = newString(len)
  copyMem(result[0].addr, buf[0].addr, len)

## Stamp computation — pure func, no I/O, no raises.
## Length-delimited concat of all inputs, then SHA-256 hex digest.
## Each element is prefixed with its byte length as 8 lowercase hex chars.
## The worktree path is deliberately NOT an input: the slot path is DERIVED
## from this digest (feeding it back would be circular), and a warm-cache unit
## is only valid for the worktree path it was built in — which the
## content-addressed slot directory now guarantees by construction.
func computeStamp*(fileContents: seq[string]; nimVersionLine, version: string): string {.raises: [].} =
  var buf = ""
  for c in fileContents:
    buf.add c.len.toHex(8) & c
  buf.add nimVersionLine.len.toHex(8) & nimVersionLine
  buf.add version.len.toHex(8) & version
  result = $secureHash(Sha_256, buf)

proc slotStamp(repoRoot: string; nimVersionLine, version: string): string =
  ## Content identity of this run's slot. A pure function of the inputs — no
  ## clock, no pid, no wall-clock — so identical inputs always resolve to the
  ## same slot (determinism, §0.2).
  var contents: seq[string] = @[]
  for rel in SlotInputFiles:
    contents.add(readFile(repoRoot / rel))
  computeStamp(contents, nimVersionLine, version)

proc acquireSlotLock(lockPath: string): SlotLock =
  ## Blocking exclusive flock. Runs on DIFFERENT inputs never reach the same
  ## lock; runs on the SAME inputs share a slot by construction and are
  ## serialised here. The kernel drops the lock when the process dies, so a
  ## crash cannot wedge the slot.
  createDir(lockPath.parentDir())
  let fd = posix.open(lockPath.cstring, posix.O_CREAT or posix.O_RDWR, Mode(0o600))
  if fd < 0:
    raise newException(OSError, "cannot open slot lock '" & lockPath & "'")
  if c_flock(fd, cint(lockExclusive)) != 0:
    discard posix.close(fd)
    raise newException(OSError, "cannot acquire slot lock '" & lockPath & "'")
  result.fd = fd

proc slotLockFree(lockPath: string): bool =
  ## True iff no run holds — or is waiting for — the slot. Fail-CLOSED: an
  ## unprobeable lock counts as BUSY, so a reclaim sweep can never delete a slot
  ## a live run is using (that deletion is exactly what made concurrent runs
  ## lose their worktree mid-execution).
  if not fileExists(lockPath):
    return true
  let fd = posix.open(lockPath.cstring, posix.O_RDWR)
  if fd < 0:
    return false
  if c_flock(fd, cint(lockExclusive or lockNonBlocking)) != 0:
    discard posix.close(fd)
    return false
  discard c_flock(fd, cint(lockUnlock))
  discard posix.close(fd)
  true

proc sweepStaleSlots(repoRoot, keepSlotId, registeredWorktrees: string) =
  ## Reclaim everything a crashed run left under PureCheckRoot, EXCEPT the slot
  ## this process holds. A slot is in use iff its lock is busy; live peers are
  ## therefore never touched. Staging directories are named after their slot
  ## (`<slot>.staging`) and are reclaimed by the same sweep, so they need no
  ## separate lifetime rule.
  if not dirExists(PureCheckRoot):
    return
  createDir(PureCheckRoot)
  for entry in walkDir(PureCheckRoot):   # non-recursive: slot dirs / staging dirs only
    let name = entry.path.splitFile().name
    if name == keepSlotId or not dirExists(entry.path):
      continue
    if not slotLockFree(PureCheckRoot / (name & ".lock")):
      echo "  slot in use by a live run — left untouched: ", name
      continue
    let slotDir = entry.path
    if slotDir in registeredWorktrees:
      discard git(repoRoot, "worktree remove --force " & quoteShell(slotDir))
    try:
      removeDir(slotDir)
      echo "  reclaimed stale slot: ", name
    except CatchableError as e:
      echo "WARN: failed to reclaim stale slot '", slotDir, "': ", e.msg

proc main() =
  echo "=== Axiom Local Purity Check ==="

  # 1. 인자 파싱 (parseopt)
  var targetCmd = "local-verify-static-full"
  var execCmd = ""
  var warmCacheDir = ""
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      if p.key == "exec":
        if p.val.len > 0:           # --exec="ci-payload"
          targetCmd = p.val
        else:                        # --exec ci-payload
          p.next()
          if p.kind == cmdArgument:
            targetCmd = p.key
      elif p.key == "exec-cmd":
        if p.val.len > 0:           # --exec-cmd='bash ...'
          execCmd = p.val
        else:                        # --exec-cmd 'bash ...'
          p.next()
          if p.kind == cmdArgument:
            execCmd = p.key
      elif p.key == "warm-nimcache":
        # Boolean enable flag (defaults to the persistent cache dir). Must NOT
        # probe p.next() for a value here: parseopt can't rewind, and probing
        # would swallow the next option (e.g. an `--exec-cmd` that follows),
        # leaving it silently unparsed. Optional `=` form overrides the path.
        if p.val.len > 0:
          warmCacheDir = p.val
        else:
          warmCacheDir = WarmCachePersistDir.string
    of cmdArgument:
      discard

  let repoRoot = findRepoRoot()
  if repoRoot.len == 0:
    echo "ERROR: Axiom repo root (.axiom_root) not found from cwd."
    quit(2)

  # Warm nimcache defaults to the persistent cache dir.
  if warmCacheDir.len == 0:
    warmCacheDir = WarmCachePersistDir.string

  # --- Slot identity + exclusive lock -------------------------------------
  # The slot is this run's CONTENT IDENTITY. It must be established BEFORE any
  # shared path is touched: without it the run would re-enter the fixed-path
  # defect this tool exists to avoid, so every failure here is FAIL-CLOSED (6).
  const ExitSlotIdentity = 6
  var nimVersionLine: string
  var slotId: string
  try:
    nimVersionLine = execCmdEx("nim --version").output.splitLines()[0]
    slotId = slotStamp(repoRoot, nimVersionLine, WarmCacheVersion)
  except CatchableError as e:
    echo "ERROR: slot identity could not be computed (", e.msg,
         ") — FAIL-CLOSED; refusing to fall back to a shared purity-check path"
    quit(ExitSlotIdentity)

  let wtPath = PureCheckRoot / slotId
  let slotLockPath = PureCheckRoot / (slotId & ".lock")
  try:
    discard acquireSlotLock(slotLockPath)
  except CatchableError as e:
    echo "ERROR: slot lock '", slotLockPath, "' could not be acquired (", e.msg,
         ") — FAIL-CLOSED"
    quit(ExitSlotIdentity)
  echo "  slot: ", slotId
  echo "  slot worktree: ", wtPath

  # --- Start-of-run: reclaim slots no live run is using --------------------
  let (sweepWtList, sweepWtCode) = execCmdEx("git worktree list")
  if sweepWtCode != 0:
    echo "ERROR: 'git worktree list' failed (exit=", sweepWtCode, ") — FAIL-CLOSED"
    quit(3)
  sweepStaleSlots(repoRoot, slotId, sweepWtList)

  # --- Deterministic worktree lifecycle ------------------------------------
  # The worktree path is a transient, verifier-owned artifact OUTSIDE the repo.
  # It is created here and removed at the end of every run. A stale/orphaned
  # directory can therefore be left behind by a crashed or interrupted run, and
  # a subsequent `git worktree add` will fail with "already exists" even though
  # the path is not registered in `git worktree list`. Guard against that with
  # exactly-once recovery: prune stale metadata, remove only the verifier-owned
  # orphaned directory, then re-attempt add once. Never delete any live worktree
  # or touch the main working tree.
  #
  # Failure classes (distinct exit codes):
  #   runCode (1)  = gate / mutation failure (a mutant escaping, a gate breaking) —
  #                  the normal product-level failure, propagated from the command.
  #   3            = git setup / infra failure (worktree list/add/reset/clean).
  #   5            = infra recovery / cleanup failure (stale-dir removal or the
  #                  post-run orig-tree contamination check failing) — FAIL-CLOSED,
  #                  never swallowed.
  const ExitInfraCleanup = 5

  # 1. Original-tree contiguity proof (before any worktree work).
  let (origOrgTree, origOrgCode) = git(repoRoot, "status --short")
  let (origWtList, origWtCode) = execCmdEx("git worktree list --porcelain")
  if origOrgCode != 0 or origWtCode != 0:
    echo "ERROR: unable to snapshot original tree state (status/worktree-list)."
    quit(3)

  # 2. Best-effort prune of stale worktree metadata (requires a live repo).
  discard execCmdEx("git -C " & quoteShell(repoRoot) & " worktree prune")

  let (listOut, listCode) = execCmdEx("git worktree list")
  if listCode != 0:
    echo "ERROR: 'git worktree list' failed (exit=", listCode, "):", listOut
    quit(3)
  let wtRegistered = wtPath in listOut
  let wtDirExists = dirExists(wtPath)

  # 3. Acquire (reuse or create) the worktree.
  if wtRegistered:
    # Reuse path: sync the worktree to the MAIN repo's current HEAD. A plain
    # `reset --hard HEAD` would reset to the worktree's own (possibly stale)
    # detached HEAD — so resolve main HEAD explicitly first.
    let (headOut, headCode) = git(repoRoot, "rev-parse HEAD")
    if headCode != 0:
      echo "ERROR: 'git rev-parse HEAD' failed (exit=", headCode, "):", headOut
      quit(3)
    let mainHead = headOut.strip()
    let (resetOut, resetCode) = git(wtPath, "reset --hard " & quoteShell(mainHead))
    if resetCode != 0:
      echo "ERROR: 'git reset --hard' failed (exit=", resetCode, "):", resetOut
      quit(3)
  else:
    let (addOut, addCode) = git(repoRoot, "worktree add --detach " & quoteShell(wtPath) & " HEAD")
    if addCode != 0:
      # Exactly-once recovery: an orphaned physical directory (not registered in
      # `git worktree list`) blocks `worktree add`. Remove ONLY that verifier-owned
      # stale directory, prune, then re-attempt add once. Never retry infinitely.
      echo "WARN: 'git worktree add' failed (exit=", addCode, ") — attempting stale-path recovery:"
      echo "  ", addOut.strip()
      if wtDirExists and not wtRegistered:
        try:
          removeDir(wtPath)
          echo "  removed stale orphaned worktree dir: ", wtPath
        except CatchableError as e:
          echo "ERROR: failed to remove stale orphaned worktree dir '", wtPath,
               "': ", e.msg, " — FAIL-CLOSED"
          quit(ExitInfraCleanup)
      else:
        echo "ERROR: 'git worktree add' failed but no verifier-owned orphaned dir at '",
             wtPath, "' (dirExists=", wtDirExists, ") — not removing anything."
        quit(3)
      discard execCmdEx("git -C " & quoteShell(repoRoot) & " worktree prune")
      let (retryOut, retryCode) = git(repoRoot,
        "worktree add --detach " & quoteShell(wtPath) & " HEAD")
      if retryCode != 0:
        echo "ERROR: 'git worktree add' still failed after stale-path recovery (exit=",
             retryCode, "):", retryOut
        quit(3)

  let (cleanOut, cleanCode) = git(wtPath,
    "clean -ffdx -e build/nimcache -e .axiom/cache -e proofs/.lake")
  if cleanCode != 0:
    echo "ERROR: 'git clean' failed (exit=", cleanCode, "):", cleanOut
    quit(3)

  # Defensive: git-lfs with filter.lfs.required=true makes `git worktree add`
  # drop a stray `--global` hook-template dir into the worktree root (untracked).
  # Remove it so it can never trip the worktree's git purity gate.
  discard execCmdEx("rm -rf " & quoteShell(wtPath / "--global"))

  let stubFile = wtPath / "bin" / "axiom.nim"
  try:
    createDir(stubFile.parentDir())
    writeFile(stubFile, StubContent)
  except CatchableError as e:
    echo "ERROR: failed to write mutation-harness stub '", stubFile, "': ", e.msg
    quit(4)

  putEnv("AXIOM_ENV", "dev")

  # --- Warm nimcache copy-in (O1) ----------------------------------------
  # Before nimble build, check whether a valid warm cache exists.
  # If so, restore its nimcache into the worktree so Nim skips
  # recompilation.  Fail-closed: any problem (missing files, stamp
  # mismatch, missing active link) silently falls through to a cold build.
  # The slot was resolved (and locked) before this point, so `slotId` IS the
  # expected stamp — no second computation that could drift from the slot.
  let currentStamp = slotId
  if warmCacheDir.len > 0 and dirExists(warmCacheDir):
    let activeLink = warmCacheDir / "active"
    # `active` is a symlink to a UNIT DIRECTORY, so fileExists() (followSymlinks)
    # is false — the target is a dir, not a regular file. Detect the link itself.
    if symlinkExists(activeLink):
      try:
        let activeTarget = readLink(activeLink)
        let unitDir = warmCacheDir / activeTarget
        let stampFile = unitDir / "stamp"
        let nimcacheDir = unitDir / "nimcache"
        if dirExists(nimcacheDir) and fileExists(stampFile):
          let savedStamp = readFile(stampFile).strip()
          if savedStamp == currentStamp:
            # Copy-in: restore nimcache into the worktree build dir.
            if dirExists(wtPath / "build" / "nimcache"):
              removeDir(wtPath / "build" / "nimcache")
            copyDir(nimcacheDir, wtPath / "build" / "nimcache")
            echo "  warm nimcache restored (stamp match) — copy-in done"
          else:
            echo "  warm nimcache stamp mismatch — cold build"
        else:
          echo "  warm nimcache unit incomplete — cold build"
      except CatchableError as e:
        echo "  warm nimcache copy-in failed: ", e.msg, " — cold build"
  # Protect the build/nimcache from config.nims' hermetic cache purge: it
  # rmDir's build/nimcache on an envHash MISS unless AXIOM_CI_PRESERVE_CACHE=1.
  # Needed on BOTH warm and cold runs — a cold run still must keep its built
  # nimcache so copy-out can persist it for the next run.
  if warmCacheDir.len > 0:
    putEnv("AXIOM_CI_PRESERVE_CACHE", "1")

  # Prebuild the core engine + gate binaries — env-check asserts `bin/ax`/
  # `bin/run_gate` exists and the compile-time static_gate_scanner asserts
  # `bin/gate_self_check`; a fresh worktree has none.
  let (buildOut, buildCode) = execCmdEx("nimble build", workingDir = wtPath)
  if buildCode != 0:
    echo "ERROR: 'nimble build' failed (exit=", buildCode, "):", buildOut
    quit(4)

  # Self-heal: a warm-nimcache copy-in from an interrupted prior run can leave
  # nim's incremental state convinced `bin/ax` is up-to-date while the binary
  # itself is absent (observed on CI reruns after a job timeout).
  # One-shot cold recovery: wipe the copied-in nimcache and rebuild once.
  if not fileExists(wtPath / "bin" / "ax"):
    echo "WARN: bin/ax missing after 'nimble build' — warm nimcache poisoned; cold rebuild"
    try:
      removeDir(wtPath / "build" / "nimcache")
    except CatchableError as e:
      echo "WARN: nimcache removal failed (cold build proceeds anyway): ", e.msg
    let (rebuildOut, rebuildCode) = execCmdEx("nimble build", workingDir = wtPath)
    if rebuildCode != 0 or not fileExists(wtPath / "bin" / "ax"):
      echo "ERROR: bin/ax still missing after cold rebuild (exit=", rebuildCode, "):", rebuildOut
      quit(4)

  let (gatesOut, gatesCode) = execCmdEx("nimble buildGates", workingDir = wtPath)
  if gatesCode != 0:
    echo "ERROR: 'nimble buildGates' failed (exit=", gatesCode, "):", gatesOut
    quit(4)

  # --- Warm nimcache copy-out (O1) ----------------------------------
  # After build, persist the nimcache so the next run can reuse it.
  # The worktree is still created fresh and deleted — only the nimcache
  # survives across runs (isolation semantics preserved).
  #
  # NOTE: this runs unconditionally (when --warm-nimcache is active), NOT only
  # when the copy-in above reused a cache. A COLD run still produced a valid
  # nimcache from a successful build — persisting it is what enables the NEXT run
  # to start warm. Gate copy-out only on build success (we are past the
  # `quit(4)` on buildGates failure above) and on the flag.
  if warmCacheDir.len > 0:
    try:
      # The unit is named by its CONTENT STAMP, so publishing is idempotent:
      # two runs that produced the same cache converge on the same directory
      # instead of racing on a shared name (the old `unit-<unix ts>` collided
      # for any two publishes in the same second). Staging lives INSIDE this
      # run's slot (`<slot>.staging`) and is therefore covered by this run's
      # own lock and by the start-of-run slot sweep — no separate lifetime.
      let unitDir = WarmCacheUnits / currentStamp
      let stagingDir = PureCheckRoot / (slotId & ".staging")
      let alreadyPublished =
        dirExists(unitDir) and fileExists(unitDir / "stamp") and
        readFile(unitDir / "stamp").strip() == currentStamp
      if alreadyPublished:
        echo "  warm nimcache already published for this slot — copy-out skipped"
      else:
        if dirExists(stagingDir):
          removeDir(stagingDir)
        createDir(stagingDir)
        # Copy nimcache to staging.
        copyDir(wtPath / "build" / "nimcache", stagingDir / "nimcache")
        # Write stamp + owning slot (the slot id lets the reclaim sweep below
        # tell "stale" from "another live run's").
        writeFile(stagingDir / "stamp", currentStamp)
        writeFile(stagingDir / "slot", slotId)
        # Promote staging → units/<stamp>. Use raw posix.rename (C atomic rename,
        # no Nim exception surface — the surrounding raise discipline is
        # {.raises: [CatchableError].}). POSIX refuses to rename a directory
        # onto an existing non-empty one, so a concurrent publisher of the SAME
        # content address is detected by that refusal — the existing unit is by
        # definition the same content, so it is kept and the staging copy dropped.
        createDir(WarmCacheUnits)
        let rc = cRename(stagingDir.cstring, unitDir.cstring)
        if rc != 0:
          if dirExists(unitDir):
            echo "  warm nimcache unit already present (concurrent publish) — kept"
            removeDir(stagingDir)
          else:
            echo "WARN: warm nimcache publish failed (rename rc=", rc,
                 ") — cold build next time"
        else:
          # Atomically flip active symlink: create tmp symlink, then rename
          # (POSIX rename over an existing symlink is an atomic replacement — no
          # absence window, T4). Skipped when it already resolves to this unit.
          if readLink(WarmCacheActive) != ("units/" & currentStamp):
            let activeTmp = WarmCachePersistDir / "active.tmp"
            discard posix.symlink(("units/" & currentStamp).cstring, activeTmp.cstring)
            discard cRename(activeTmp.cstring, WarmCacheActive.cstring)
          # Delete stale units: every unit whose CONTENT address is not this
          # slot's, skipping any whose owning slot is currently locked by a live
          # run (deleting a peer's cache is at best a lost warm start, never a
          # wrong result — but it is still another actor's state, so the lock
          # decides). Keep no fallback: durability is an explicit NON-goal (F4).
          var staleUnits: seq[string] = @[]
          if dirExists(WarmCacheUnits):
            for entry in walkDir(WarmCacheUnits, relative = true, checkDir = true):
              if entry.path.splitFile().name != currentStamp:
                staleUnits.add(WarmCacheUnits / entry.path)
          for d in staleUnits:
            let owner = if fileExists(d / "slot"): readFile(d / "slot").strip() else: ""
            if owner.len > 0 and not slotLockFree(PureCheckRoot / (owner & ".lock")):
              echo "  kept unit of live slot: ", d.splitFile().name
              continue
            try:
              removeDir(d)
              echo "  removed stale unit: ", d.splitFile().name
            except CatchableError: # axiom:best-effort(stale-unit-cleanup-non-goal: durability F4 NON-goal, a lost unit forces a cold build next run)
              discard
          echo "  warm nimcache copy-out done — ", currentStamp
    except CatchableError as e:
      echo "WARN: warm nimcache copy-out failed: ", e.msg, " — cold build next time"

  # 2. 격리 워크트리 내에서 실시간 스트리밍 실행
  var runCode: int
  if execCmd.len > 0:
    # Raw shell command mode (--exec-cmd): e.g. invariant mutation harness that
    # mutates tracked source in the worktree via sed and restores via git checkout.
    # It must never touch the main working tree, so it runs here in isolation.
    echo "=== [Clean-Room Exec] Running (shell): ", execCmd, " inside ", wtPath
    let sh = startProcess(
      "bash",
      args = @["-lc", execCmd],
      workingDir = wtPath,
      options = {poParentStreams, poUsePath}
    )
    runCode = sh.waitForExit()
    sh.close()
  else:
    echo "=== [Clean-Room Exec] Running: make ", targetCmd, " inside ", wtPath
    let process = startProcess(
      "make",
      args = @[targetCmd],
      workingDir = wtPath,
      options = {poParentStreams, poUsePath}
    )
    runCode = process.waitForExit()
    process.close()

  # 3. 보증된 worktree 정리
  let (rmOut, rmCode) = git(repoRoot, "worktree remove --force " & quoteShell(wtPath))
  if rmCode != 0:
    # The worktree may already be gone; don't fail the whole run on a best-effort
    # remove, but do surface it. A stale physical dir is still cleaned below.
    echo "WARN: 'git worktree remove' returned exit=", rmCode, ": ", rmOut.strip()
  if dirExists(wtPath):
    try:
      removeDir(wtPath)
    except CatchableError as e:
      echo "ERROR: failed to remove leftover worktree dir '", wtPath, "': ", e.msg,
           " — FAIL-CLOSED"
      quit(ExitInfraCleanup)

  # 4. Lifecycle closed: prune re-confirmation + original-tree contamination check.
  #    Prove the original working tree is byte-identical in dirtiness to before the
  #    run, and that no verifier-owned worktree metadata remains registered.
  discard execCmdEx("git -C " & quoteShell(repoRoot) & " worktree prune")
  let (postWtList, postWtCode) = execCmdEx("git worktree list --porcelain")
  if postWtCode != 0:
    echo "ERROR: 'git worktree list --porcelain' (post-run) failed (exit=",
         postWtCode, "):", postWtList
    quit(ExitInfraCleanup)
  if wtPath in postWtList:
    echo "ERROR: verifier-owned worktree '", wtPath,
         "' still registered after cleanup — FAIL-CLOSED"
    quit(ExitInfraCleanup)
  let (postOrgTree, postOrgCode) = git(repoRoot, "status --short")
  if postOrgCode != 0:
    echo "ERROR: unable to verify original tree state (post-run) — FAIL-CLOSED"
    quit(ExitInfraCleanup)
  # Nim compiler byproducts: concurrent legitimate builds in the original tree
  # (e.g. the parallel contract subtargets) can drop linker-args temp files at
  # repo root. They are compiler droppings, not verifier contamination — filter
  # them from the before/after comparison so the guard keeps detecting real
  # source/state contamination.
  proc stripNimByproducts(s: string): string =
    result = ""
    for line in s.splitLines():
      if line.strip().len == 0: continue
      if "main_linkerArgs.txt" in line or "project_linkerArgs.txt" in line: continue
      result.add(line); result.add("\n")
  if stripNimByproducts(postOrgTree) != stripNimByproducts(origOrgTree):
    echo "ERROR: original working tree dirtiness changed across the run — FAIL-CLOSED"
    echo "  before: ", origOrgTree.strip()
    echo "  after : ", postOrgTree.strip()
    quit(ExitInfraCleanup)

  echo "=== worktree lifecycle closed: temp worktree removed, original tree unchanged ==="
  echo "=== done (exit ", runCode, ") ==="
  quit(runCode)

when isMainModule:
  main()
