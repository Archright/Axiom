import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

import core/crypto/hash_kernel
import core/gate/file_hash_cache  # mtime-based per-file hash cache
import core/json/json_utils
import core/json/std_redirect
import core/parsers/safe_parsers
import core/trusted/axiom_pragmas_lite
import core/types/gate_types  # FailureCategory for type-safe cache policy
import core/types/results
import core/utils/io_utils
import std/algorithm
import std/options
import std/os
import std/osproc
import std/posix
import std/sets
import std/strutils
import std/tables
import std/times
import core/interfaces/logging_hub
# axiomIoBoundary

# =============================================================================
# CAS (Content-Addressed Storage) Addressing for Memo Entries
# =============================================================================
# True CAS: filenames ARE the SHA-256 hash of their content.
# Directory layout: epoch_<N>/<hash[:2]>/<hash[2:]>
# File existence IS integrity proof — no sidecar files needed.
# =============================================================================

const GateMemoBaseDir* = ".axiom/cache/gate_memo"
  ## Single source of truth for gate memo storage location.
  ## DEBT#237: Unified with binary CAS at .axiom/cache/ to eliminate split-brain.
type CasAddress* = distinct string
  ## A 64-char hex SHA-256 hash that uniquely identifies content.
  ## The first 2 chars form the subdirectory, the remaining 62 form the filename.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc casSubdir*(ca: CasAddress): string {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The 2-char directory prefix (hash[:2]).
  string(ca)[0..1]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc casFilename*(ca: CasAddress): string {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The 62-char filename portion (hash[2:]).
  string(ca)[2..^1]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func casPath*(epochDir: string; ca: CasAddress): string {.inline, raises: [].} =
  ## Full CAS path: epochDir / hash[:2] / hash[2:]
  epochDir / ca.casSubdir() / ca.casFilename()
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeCasAddress*(content: string): CasAddress {.inline, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of content and return as CasAddress.
  CasAddress(hash_kernel.sha256Hex(content))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isValid*(ca: CasAddress): bool {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## True if the address is a valid 64-char hex string.
  string(ca).len == 64

# =============================================================================
# Split Build Environment Hash Cache
# =============================================================================
# The build environment hash is split into code-related and env-var components
# for selective cache invalidation. computeBuildEnvHash combines both in the
# original interleaved order for backward compatibility (identical output).
#
# Previously computeBuildEnvHash() called execProcess("nim dumpConfig") on EVERY
# invocation — O(N) subprocess spawns across N gate cache checks. Now: compute
# once at first call, cache in thread-local storage for the process lifetime.
# Uses runtime hashing (not staticExec) to avoid host-dependency staleness:
# the hash reflects the ACTUAL runtime environment, not the compile-time host.
# =============================================================================
type
  BuildEnvPart = tuple[category: string, hash: string]
var cachedBuildEnvParts {.threadvar.}: seq[BuildEnvPart]
var buildEnvPartsCacheValid {.threadvar.}: bool
var cachedCodeHash {.threadvar.}: string
var codeHashCacheValid {.threadvar.}: bool
var cachedEnvVarHash {.threadvar.}: string
var envVarCacheValid {.threadvar.}: bool
var cachedBuildEnvHash {.threadvar.}: string
var buildEnvCacheValid {.threadvar.}: bool
var cachedToolchainSalt {.threadvar.}: string
var toolchainSaltValid {.threadvar.}: bool

# =============================================================================
# Optional File Hash Cache (initialized at orchestrator startup)
# =============================================================================
var globalFileHashCache {.threadvar.}: FileHashCache
var fileHashCacheInitialized {.threadvar.}: bool
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc initFileHashCache*(repoRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Initialize the global file hash cache from persistent storage.
  ## Call once at orchestrator startup. If not called, computeMerkleRoot
  ## falls back to direct readFile (backward-compatible).
  globalFileHashCache = loadFileHashCache(repoRoot)
  fileHashCacheInitialized = true
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc flushFileHashCache*(repoRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Persist the file hash cache to disk. Call after gate batch completes.
  if fileHashCacheInitialized:
    globalFileHashCache.save(repoRoot)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeMerkleRoot*(files: seq[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute a simple Merkle root over file contents using SHA-256.
  ## Files are sorted to ensure deterministic ordering.
  ## Uses FileHashCache when initialized (mtime-based dedup); falls back to readFile.
  var hashes: seq[string] = @[]
  if fileHashCacheInitialized:
    for f in files.sorted():
      let hash = globalFileHashCache.getOrComputeHash(f)
      if hash.len > 0:
        hashes.add(hash)
  else:
    for f in files.sorted():
      if fileExists(f):
        hashes.add(hash_kernel.sha256Hex("\x00" & readFile(f)))
  if hashes.len == 0:
    return ""
  if hashes.len == 1:
    return hashes[0]
  while hashes.len > 1:
    var next: seq[string] = @[]
    var i = 0
    while i < hashes.len:
      if i + 1 < hashes.len:
        next.add(hash_kernel.sha256Hex("\x01" & hashes[i] & hashes[i + 1]))
      else:
        next.add(hashes[i])
      i += 2
    hashes = next
  hashes[0]

# ---------------------------------------------------------------------------
# Internal: compute all hash parts in original interleaved order (cached)
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc ensureBuildEnvPartsComputed(repoRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute all build environment hash parts in the original interleaved order.
  ## Results are tagged by category ("code" or "env") and cached for sub-function use.
  if buildEnvPartsCacheValid:
    return
  var parts: seq[BuildEnvPart] = @[]
  # Code-related: config files, compiler identity, platform
  let configNimsPath = repoRoot / "config.nims"
  if fileExists(configNimsPath):
    parts.add(("code", hash_kernel.sha256Hex(readFile(configNimsPath))))
  let nimblePath = repoRoot / "axiom.nimble"
  if fileExists(nimblePath):
    parts.add(("code", hash_kernel.sha256Hex(readFile(nimblePath))))
  # REMOVED: architecture_debt.json — project-level data file that changes
  # frequently but does not affect gate execution logic. Including it in
  # buildEnvHash caused unnecessary global cache invalidation (58 gates).
  parts.add(("code", hash_kernel.sha256Hex(NimVersion)))
  parts.add(("code", hash_kernel.sha256Hex(hostOS)))
  parts.add(("code", hash_kernel.sha256Hex(hostCPU)))
  # Phase 4 CAS hardening: OS identity (replaces compile-time gorge("uname -r"))
  parts.add(("code", hash_kernel.sha256Hex(hostOS & "-" & hostCPU)))
  # env vars removed from buildEnvHash: precompile/hook 환경 차이로 CAS 키 불일치 유발 (2026-07 타임아웃 수정)
  # Phase 5 hermetic: nim --version captures compiler identity (replaces dumpConfig subprocess).
  # dumpConfig was O(N) per gate; nim --version is ~10ms once. Compile flags are captured
  # via config.nims hash above, making dumpConfig redundant for cache invalidation.
  let nimExe = findExe("nim")
  if nimExe.len > 0:
    let nimVersionOutput = execProcess(nimExe & " --version 2>&1 | head -1")
    parts.add(("code", hash_kernel.sha256Hex(nimVersionOutput.strip())))
    # Nim stdlib hash (stdlib updates change runtime behavior)
    let libPath = nimExe.parentDir() / "lib" / "system.nim"
    if fileExists(libPath):
      parts.add(("code", hash_kernel.sha256Hex(readFile(libPath))))
    else:
      parts.add(("code", hash_kernel.sha256Hex("no-lib")))
  else:
    parts.add(("code", hash_kernel.sha256Hex("no-nim")))
  cachedBuildEnvParts = parts
  buildEnvPartsCacheValid = true

# ---------------------------------------------------------------------------
# Public: split hash functions
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeCodeHash*(repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of code-related build environment parts only.
  ## Includes: config.nims, axiom.nimble, NimVersion, hostOS, hostCPU,
  ## nim --version, system.nim. Cached at runtime.
  if codeHashCacheValid:
    return cachedCodeHash
  ensureBuildEnvPartsComputed(repoRoot)
  var parts: seq[string] = @[]
  for p in cachedBuildEnvParts:
    if p.category == "code":
      parts.add(p.hash)
  cachedCodeHash = hash_kernel.sha256Hex(parts.join(""))
  codeHashCacheValid = true
  cachedCodeHash
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeEnvVarHash*(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of environment variable parts only.
  ## Includes: AXIOM_JOBS, AXIOM_TIMEOUT_SLA, AXIOM_GATE_BOND. Cached at runtime.
  if envVarCacheValid:
    return cachedEnvVarHash
  ensureBuildEnvPartsComputed("")
  var parts: seq[string] = @[]
  for p in cachedBuildEnvParts:
    if p.category == "env":
      parts.add(p.hash)
  cachedEnvVarHash = hash_kernel.sha256Hex(parts.join(""))
  envVarCacheValid = true
  cachedEnvVarHash
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeToolchainSalt*(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute a toolchain salt for cache layout versioning.
  ## Includes schema version to force cache invalidation on layout changes.
  ## Cached at runtime — first call computes, subsequent calls return cached result.
  if toolchainSaltValid:
    return cachedToolchainSalt
  # DEBT#471: memo key layout changed — the composite now carries a restored
  # gateHash slot plus a scan-scope/staged scope slot. Bumping the schema
  # version invalidates every pre-closure entry in one deterministic step.
  let schemaVer = "v3"
  let nimExe = findExe("nim")
  let nimVer = if nimExe.len > 0:
    execProcess(nimExe & " --version 2>&1 | head -1").strip()
  else:
    "no-nim"
  cachedToolchainSalt = hash_kernel.sha256Hex(schemaVer & nimVer)
  toolchainSaltValid = true
  cachedToolchainSalt
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeBuildEnvHash*(repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of build environment. Cached at runtime — first call computes,
  ## subsequent calls return cached result (zero overhead).
  ## Backward compatible: identical output to pre-split version.
  ## Internally delegates to ensureBuildEnvPartsComputed and combines code + env parts.
  if buildEnvCacheValid:
    return cachedBuildEnvHash
  ensureBuildEnvPartsComputed(repoRoot)
  # Original interleaved order for backward compatibility
  var parts: seq[string] = @[]
  for p in cachedBuildEnvParts:
    parts.add(p.hash)
  cachedBuildEnvHash = hash_kernel.sha256Hex(parts.join(""))
  buildEnvCacheValid = true
  cachedBuildEnvHash
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeCompositeLockHash*(inputFiles: seq[string]; gateSourcePath: string;
                              repoRoot: string; subtreeRoot: string = "";
                              binaryHash: string = "";
                              envHash: string = "";
                              transitiveHash: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute a composite lock hash: Merkle(inputFiles) + SHA-256(gate source) + SHA-256(repoRoot) + SHA-256(build env) + subtreeRoot + binaryHash + transitiveHash.
  ## Changing any of the target files, gate validator, repo root, build environment, compiled binary, or transitive dependencies invalidates the cache.
  ## This prevents cross-worktree and cross-toolchain cache pollution.
  ## subtreeRoot is a Merkle subtree root for per-gate files, replacing dirtyHash.
  ## binaryHash is the SHA-256 of the CAS-compiled gate binary (unified CAS+Memo key).
  ## envHash is the hash of external state dependencies (context-aware cache key).
  ## transitiveHash is the Merkle root of the gate's full transitive dependency tree.
  let inputHash = computeMerkleRoot(inputFiles)
  var gateHash = ""
  if fileExists(gateSourcePath):
    gateHash = hash_kernel.sha256Hex(readFile(gateSourcePath))
  let rootHash = hash_kernel.sha256Hex(repoRoot)
  let buildEnvHash = computeBuildEnvHash(repoRoot)
  let toolchainSalt = computeToolchainSalt()
  hash_kernel.sha256Hex(inputHash & "|" & gateHash & "|" & rootHash & "|" & buildEnvHash & "|" & subtreeRoot & "|" & binaryHash & "|" & envHash & "|" & toolchainSalt & "|" & transitiveHash)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeCompositeLockHash*(precomputedInputHash: string; gateHash: string;
                              repoRoot: string; subtreeRoot: string = "";
                              binaryHash: string = "";
                              envHash: string = "";
                              transitiveHash: string = "";
                              scopeHash: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Overload accepting a pre-computed input hash (e.g. from computeSliceHash)
  ## and a PRE-RESOLVED gateHash digest — the producing gate's identity (the
  ## transitive import-closure Merkle root from resolveGateHash).
  ## DEBT#471: this slot previously re-read a file from a path parameter, so
  ## callers that passed an already-computed digest silently collapsed the
  ## gateHash component to "" — the producing gate never entered its own memo
  ## key. The digest is now consumed verbatim, restoring the gateHash slot.
  ## scopeHash (DEBT#471 key closure) binds the scan-scope/staged axes: two
  ## evaluations that observe the same (possibly empty) changed-set under
  ## different scan scopes must not share a key.
  let rootHash = hash_kernel.sha256Hex(repoRoot)
  let buildEnvHash = computeBuildEnvHash(repoRoot)
  let toolchainSalt = computeToolchainSalt()
  hash_kernel.sha256Hex(precomputedInputHash & "|" & gateHash & "|" & rootHash & "|" & buildEnvHash & "|" & subtreeRoot & "|" & binaryHash & "|" & envHash & "|" & toolchainSalt & "|" & transitiveHash & "|" & scopeHash)

type
  HashDiffReport* = object
    changed*: seq[string]
    details*: seq[tuple[name, oldHash, newHash: string]]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func compareCompositeComponents*(
    oldComposite, newComposite: string;
    oldComponents, newComponents: seq[tuple[name, hash: string]]): HashDiffReport {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compare two composite hash states component by component.
  ## Returns which components changed.
  result.changed = @[]
  result.details = @[]
  if oldComposite == newComposite:
    return  # Identical
  for i in 0 ..< min(oldComponents.len, newComponents.len):
    if oldComponents[i].hash != newComponents[i].hash:
      result.changed.add(oldComponents[i].name)
      result.details.add((oldComponents[i].name, oldComponents[i].hash, newComponents[i].hash))

const HashComponents* = [
  "inputFiles",
  "gateSource",
  "repoRoot",
  "buildEnv",
  "subtreeRoot",
  "binaryHash",
  "envHash",
  "toolchainSalt",
  "transitiveHash",
]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auditHashCompleteness*(repoRoot: string): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify that all known external inputs are covered by computeCompositeLockHash.
  ## Returns list of missing components (empty = complete).
  result = @[]
  let buildEnv = computeBuildEnvHash(repoRoot)
  if buildEnv.len == 0:
    result.add("buildEnvHash is empty")
  let toolchainSalt = computeToolchainSalt()
  if toolchainSalt.len == 0:
    result.add("toolchainSalt is empty")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeMerkleRootFromPaths*(paths: seq[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Recursively collect files from the given paths (files or directories),
  ## sort them, and compute a Merkle root.
  var files: seq[string] = @[]
  for p in paths:
    if fileExists(p):
      files.add(p)
    elif dirExists(p):
      for f in walkDirRec(p):
        if fileExists(f):
          files.add(f)
  computeMerkleRoot(files)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc memoPath*(gateId: string; epoch: int): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  GateMemoBaseDir / "epoch_" & $epoch & "/" & gateId & ".json"
var cachedEpoch {.threadvar.}: int
var epochInitialized {.threadvar.}: bool
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc currentCacheEpoch*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns current cache epoch. Reads .epoch file once, caches in memory.
  if not epochInitialized:
    let epochPath = GateMemoBaseDir / ".epoch"
    if fileExists(epochPath):
      let parsed = safeParseInt(readFile(epochPath).strip())
      cachedEpoch = if parsed.isOk: parsed.get() else: 0
    else:
      cachedEpoch = 0
    epochInitialized = true
  cachedEpoch

# ============================================================================ {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
# Legacy Location Migration (DEBT#237)
# =============================================================================
# One-time migration: move gate memo from logs/.gate_memo/ to .axiom/cache/gate_memo/.
# This eliminates the split-brain between binary CAS (.axiom/cache/) and memo cache.
var legacyMigrationDone {.threadvar.}: bool
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc migrateFromLegacyLocation*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## One-time migration: move gate memo from logs/.gate_memo/ to .axiom/cache/gate_memo/.
  ## Fixes DEBT#237: split-brain between CAS and memo cache locations.
  ## When CAS (.axiom/cache/) is cleared, gate memo is now also cleared.
  if legacyMigrationDone:
    return
  legacyMigrationDone = true
  let legacyDir = "logs/.gate_memo"
  if not dirExists(legacyDir):
    return
  discard existsOrCreateDirOpt(GateMemoBaseDir)
  try:
    for kind, path in walkDir(legacyDir):
      let name = path.extractFilename()
      if name == ".migration_lock":
        continue  # Skip lock files
      let dest = GateMemoBaseDir / name
      case kind
      of pcFile, pcLinkToFile:
        if not fileExists(dest):
          copyFile(path, dest)
      of pcDir, pcLinkToDir:
        discard existsOrCreateDirOpt(dest)
  except IOError, OSError:
    discard  # Best-effort migration; legacy dir will be cleaned up on next run.

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc advanceCacheEpoch*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomically advance the cache epoch. Returns the new epoch value.
  migrateFromLegacyLocation()
  let old = currentCacheEpoch()
  let newEpoch = old + 1
  let epochPath = GateMemoBaseDir / ".epoch"
  ## intentional-discard: epoch cache is recomputed on restart; write is best-effort
  discard writeFileOpt(epochPath, $newEpoch & "\n")
  cachedEpoch = newEpoch
  epochInitialized = true
  newEpoch

const MigrationLockStaleSec* = 60
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isLockStale*(lockPath: string): bool {.tags: [ReadIOEffect, TimeEffect], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if a migration lock file is stale (old process or timed out).
  try:
    let content = readFile(lockPath).strip()
    let parts = content.split('|')
    if parts.len < 2: return true
    let lockPid = safeParseInt(parts[0])
    let lockTime = safeParseInt(parts[1])
    if lockPid.isErr or lockTime.isErr: return true
    let now = getTime().toUnix()
    if now - lockTime.get() > MigrationLockStaleSec: return true
    # Check process alive (POSIX kill(pid, 0))
    try:
      let ret = kill(Pid(lockPid.get()), 0)
      if ret != 0: return true
    except OSError:
      return true
    return false
  except CatchableError:
    return true
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc acquireMigrationLock*(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ReadIOEffect, RootEffect, TimeEffect].} =
  ## Acquire migration lock. Returns true if lock acquired.
  let lockDir = GateMemoBaseDir
  discard existsOrCreateDirOpt(lockDir)
  let lockPath = lockDir / ".migration_lock"
  if fileExists(lockPath):
    if not isLockStale(lockPath):
      return false
  let lockContent = $getCurrentProcessId() & "|" & $getTime().toUnix()
  ## intentional-discard: lock file write is idempotent; conflicts resolved by PID comparison
  discard writeFileOpt(lockPath, lockContent & "\n")
  true
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc releaseMigrationLock*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Release migration lock.
  let lockPath = GateMemoBaseDir / ".migration_lock"
  if fileExists(lockPath):
    try:
      removeFile(lockPath)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc migrateFromFlat*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ReadIOEffect, RootEffect, TimeEffect].} =
  ## Migrate existing flat memo files into epoch_0 directory.
  ## Uses stale-aware lock to prevent concurrent migrations.
  if not acquireMigrationLock():
    return
  try:
    let memoDir = GateMemoBaseDir
    let epochDir = memoDir / "epoch_0"
    discard existsOrCreateDirOpt(epochDir)
    for kind, path in walkDir(memoDir):
      if kind == pcFile:
        let name = path.extractFilename()
        if name.endsWith(".json") and not name.startsWith("."):
          let dest = epochDir / name
          if not fileExists(dest):
            copyFile(path, dest)
    # Create .epoch file if not present (do NOT touch module cache here;
    # currentCacheEpoch() must read the file fresh on first use).
    let epochPath = memoDir / ".epoch"
    if not fileExists(epochPath):
      ## intentional-discard: zero epoch is a sentinel; write is best-effort
      discard writeFileOpt(epochPath, "0\n")
  finally:
    releaseMigrationLock()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc garbageCollectOldEpochs*(maxRetained: int = 3) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Remove epoch directories older than maxRetained from current epoch.
  ##
  ## Epoch contract (docs/spec/cache_policy.md): epoch dirs exist only as
  ## "epoch_" & $int at the current epoch, and the counter advances explicitly
  ## by +1 (advanceCacheEpoch). Consequences enforced here:
  ## - a non-numeric suffix cannot come from the memo layer -> foreign
  ##   garbage, reclaimed (observed: test wrote cast[int](epochTime())
  ##   bit-pattern epochs; see docs/spec/nim_2_2_10_stdlib_quirks.md);
  ## - a numeric epoch above `current` is foreign or the documented
  ##   manual-rollback state -> detected + logged, never removed (removal
  ##   could also race a concurrent process's legitimate epoch advance).
  let current = currentCacheEpoch()
  let memoDir = GateMemoBaseDir
  for kind, path in walkDir(memoDir):
    if kind == pcDir:
      let name = path.extractFilename()
      if name.startsWith("epoch_"):
        let epochNum = safeParseInt(name[6..^1])
        if epochNum.isErr:
          try:
            removeDir(path)
            logError("[gate_memo] GC: reclaimed non-numeric epoch dir " & name)
          except CatchableError:
            logError("[gate_memo] GC: failed to remove " & name)
        elif current - epochNum.get() >= maxRetained:
          try:
            removeDir(path)
            logInfo("[gate_memo] GC: removed " & name)
          except CatchableError:
            logError("[gate_memo] GC: failed to remove " & name)
        elif epochNum.get() > current:
          logError("[gate_memo] GC: epoch dir " & name & " is above current epoch " &
                   $current & " — foreign or manual-rollback state; kept, not removed")
# ---------------------------------------------------------------------------
# Outcome axis: verdict vs. execution state
# ---------------------------------------------------------------------------
# `result: bool` alone conflates two different claims: "this gate FAILED" (a
# verdict about the property it checks) and "this gate could not be evaluated"
# (a statement about the tool). Only the first may be memoized as durable truth
# — a tool that failed to run says nothing about the property it was asked to
# check, so promoting it to a verdict is false authority.
#
# A FAIL therefore carries a verdict only when it carries failure evidence. The
# evidence test is the same fail-closed reading the decision algebra applies to
# an absent summary count (`src/core/utils/decision_algebra.nim` `countOrUnset`):
# "no failures recorded" is a claim that must be readable to be believed.
# ---------------------------------------------------------------------------
type
  MemoOutcome* = enum
    moVerdictPass   ## the gate was evaluated and passed — durable verdict
    moVerdictFail   ## the gate was evaluated and rejected with evidence — durable verdict
    moNotEvaluated  ## no evaluable result — execution state, never a verdict

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func classifyMemoOutcome*(passed: bool; category: FailureCategory;
                          reason: string): MemoOutcome {.inline, raises: [].} =
  ## Split a recorded gate outcome into the verdict axis and the execution-state
  ## axis. Total and deterministic: every (result, category, reason) triple lands
  ## on exactly one outcome, and anything unreadable as a verdict fails closed to
  ## moNotEvaluated.
  if passed:
    return moVerdictPass
  if category in {fcPermanent, fcUnknown}:
    return moNotEvaluated
  if reason.strip().len == 0:
    return moNotEvaluated
  moVerdictFail

type
  MemoFinding* = tuple[file: string, line: int, detail: string]
    ## Structured decision-finding coordinates — the durable evidence shape of
    ## a memoized FAIL (DEBT#471). Quoted stdout prose is never the reason of
    ## record; the coordinate tuple (file, line, rule/detail) is.

  GateMemoEntry* = tuple[
    compositeLockHash: string,
    result: bool,
    timestamp: int64,
    failureCategory: FailureCategory,
    failureReason: string,
    findings: seq[MemoFinding]]
  MemoIndex* = object
    entries*: Table[string, GateMemoEntry]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func classifyStructuredMemoOutcome*(passed: bool; category: FailureCategory;
                                    reason: string;
                                    findings: seq[MemoFinding]): MemoOutcome {.inline, raises: [].} =
  ## classifyMemoOutcome extended with structured evidence: finding coordinates
  ## are failure evidence, so a FAIL that carries findings but no prose is
  ## still a durable verdict (DEBT#471 value closure). Total and deterministic
  ## — anything unreadable as a verdict fails closed to moNotEvaluated.
  if passed:
    return moVerdictPass
  if category in {fcPermanent, fcUnknown}:
    return moNotEvaluated
  if reason.strip().len == 0 and findings.len == 0:
    return moNotEvaluated
  moVerdictFail

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc parseFindingsFromOutput*(output: string): seq[MemoFinding] {.raises: [].} =
  ## Extract structured finding coordinates from gate output at memo-write
  ## time (DEBT#471). Recognizes coordinate lines of the shape
  ##   <path>:<line>[:<col>] [separator] [detail]
  ## where path looks like a file ('/' or '.' present). Prose headers, FAIL
  ## banners, and lines without a coordinate anchor are ignored — the parser
  ## is deliberately conservative: a finding must be locatable.
  result = @[]
  for raw in output.splitLines():
    let line = raw.strip()
    if line.len == 0:
      continue
    # Locate the coordinate anchor: first ':' that is followed by digits.
    var colonIdx = -1
    for i in 0 ..< line.len:
      if line[i] == ':' and i + 1 < line.len and line[i + 1] in {'0'..'9'}:
        colonIdx = i
        break
    if colonIdx <= 0:
      continue
    let file = line[0 ..< colonIdx]
    if file.len == 0 or ('/' notin file and '.' notin file):
      continue
    var rest = line[colonIdx + 1 ..^ 1]
    # Line number: leading digits.
    var numEnd = 0
    while numEnd < rest.len and rest[numEnd] in {'0'..'9'}:
      inc numEnd
    if numEnd == 0:
      continue
    var lineNo = 0
    for k in 0 ..< numEnd:
      lineNo = lineNo * 10 + (rest[k].ord - '0'.ord)
    rest = rest[numEnd ..^ 1]
    # Optional :<col> — skipped, not part of the finding shape.
    if rest.startsWith(":"):
      var colEnd = 1
      while colEnd < rest.len and rest[colEnd] in {'0'..'9'}:
        inc colEnd
      if colEnd > 1:
        rest = rest[colEnd ..^ 1]
    # Single separator between coordinates and detail (" — ", " - ", ": ", " | ").
    var detail = rest.strip()
    for sep in ["—", "-", ":", "|"]:
      if detail.len > sep.len and detail.startsWith(sep):
        detail = detail[sep.len ..^ 1].strip()
        break
    if lineNo <= 0:
      continue
    result.add((file, lineNo, detail))
    if result.len >= 64:
      return

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func renderMemoFindings*(findings: seq[MemoFinding]): string {.raises: [].} =
  ## Current-vocabulary replay renderer (DEBT#471 read-time closure): a memo
  ## HIT is rendered from stored finding coordinates by TODAY's formatter —
  ## never by echoing the prose that was current when the entry was written.
  ## Empty findings (legacy entries) render to "".
  if findings.len == 0:
    return ""
  var parts: seq[string] = @[]
  for f in findings:
    if f.detail.len > 0:
      parts.add(f.file & ":" & $f.line & " (" & f.detail & ")")
    else:
      parts.add(f.file & ":" & $f.line)
  parts.join("; ")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadLegacyGateMemo*(gateId: string; epoch: int): Option[GateMemoEntry] =
  ## Legacy lookup: flat file at epochDir/gateId.json. Used for migration fallback.
  ## Phase B: Pure content-addressed caching — no time-based expiry.
  ## Cache invalidation is driven solely by compositeLockHash change.
  ## Legacy entries carry no findings (pre-DEBT#471 layout): they are read
  ## under the prose-evidence rule (classifyMemoOutcome) and surface with an
  ## empty findings sequence.
  let path = memoPath(gateId, epoch)
  if not fileExists(path):
    return none(GateMemoEntry)
  try:
    let readRes = readFileOpt(path)
    if readRes.isErr: return
    let j = parseJsonOpt(readRes.get).get(newJObject())
    let hash = j["compositeLockHash"].getStr()
    let res = j["result"].getBool()
    let ts = j["timestamp"].getBiggestInt().int64
    # Parse failure category (backward compat: missing field → fcTransient)
    let category = parseEnum(j{"failureCategory"}.getStr("fcTransient"), fcTransient)
    let reason = j{"failureReason"}.getStr("")
    if classifyMemoOutcome(res, category, reason) == moNotEvaluated:
      return none(GateMemoEntry)
    var entry: GateMemoEntry
    entry.compositeLockHash = hash
    entry.result = res
    entry.timestamp = ts
    entry.failureCategory = category
    entry.failureReason = reason
    entry.findings = @[]
    return some(entry)
  except CatchableError:
    return none(GateMemoEntry)

# ---------------------------------------------------------------------------
# Internal: parse GateMemoEntry from JSON content (shared by CAS and legacy)
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc parseMemoEntry(j: JsonNode): Option[GateMemoEntry] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse a memo entry from JSON. Pure content-addressed: no time-based expiry.
  ## Cache validity is determined solely by compositeLockHash match in the caller.
  ## Only outcomes on the verdict axis are reusable; moNotEvaluated (an
  ## unclassifiable or unevidenced failure — e.g. the gate tool itself failed)
  ## is dropped here, so a memo persisted by any producer, in any past layout,
  ## can never re-enter the index as a verdict.
  ## Entries carrying a findings array (DEBT#471 structured layout) are judged
  ## by classifyStructuredMemoOutcome — coordinates count as evidence; legacy
  ## layouts keep the prose-evidence rule (classifyMemoOutcome).
  let hash = j["compositeLockHash"].getStr()
  let res = j["result"].getBool()
  let ts = j["timestamp"].getBiggestInt().int64
  let category = parseEnum(j{"failureCategory"}.getStr("fcTransient"), fcTransient)
  let reason = j{"failureReason"}.getStr("")
  var findings: seq[MemoFinding] = @[]
  var hasFindings = false
  let findingsNode = j{"findings"}  # {} returns nil when the key is absent
  if findingsNode != nil and findingsNode.kind == JArray:
    hasFindings = true
    for f in findingsNode:
      findings.add((f{"file"}.getStr(""), f{"line"}.getInt(0), f{"detail"}.getStr("")))
  let outcome = if hasFindings:
    classifyStructuredMemoOutcome(res, category, reason, findings)
  else:
    classifyMemoOutcome(res, category, reason)
  if outcome == moNotEvaluated:
    return none(GateMemoEntry)
  # Named-variable construction: Nim 2.2.10 liftdestructors asserts on
  # anonymous tuple literals carrying a seq into Option[...].
  var entry: GateMemoEntry
  entry.compositeLockHash = hash
  entry.result = res
  entry.timestamp = ts
  entry.failureCategory = category
  entry.failureReason = reason
  entry.findings = findings
  some(entry)

# ---------------------------------------------------------------------------
# O(1) MemoIndex lookup
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadMemoIndex*(epochDir: string): MemoIndex {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load all CAS entries into an O(1) lookup table.
  ## Called once at pipeline start.
  result.entries = initTable[string, GateMemoEntry]()
  if not dirExists(epochDir): return
  for subdir in walkDir(epochDir):
    if subdir.kind != pcDir: continue
    for file in walkDir(subdir.path):
      if file.kind != pcFile: continue
      try:
        let readRes = readFileOpt(file.path)
        if readRes.isErr: continue
        let content = readRes.get
        let nodeOpt = parseJsonOpt(content)
        if nodeOpt.isNone: continue
        let entry = parseMemoEntry(nodeOpt.get())
        if entry.isSome:
          let gateId = nodeOpt.get(){"gateId"}.getStr("")
          if gateId.len > 0:
            # Multi-entry index: key = (gateId, compositeLockHash) so that
            # SEVERAL distinct cache keys for the same gateId coexist in one
            # epoch (e.g. experiment replays with different canonical
            # VerificationIdentity digests). Previously the last-walked file
            # silently overwrote earlier entries (single entry per gateId).
            # Separator \x1f cannot appear in gateIds or sha256-hex lockHashes.
            let compoundKey = gateId & "\x1f" & entry.get().compositeLockHash
            result.entries[compoundKey] = entry.get()
      except CatchableError:
        continue

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc lookupMemo*(index: MemoIndex; gateId, compositeLockHash: string): Option[GateMemoEntry] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## O(1) lookup by (gateId, compositeLockHash) compound key.
  ## Multi-entry: each distinct (gateId, lockHash) pair is independently
  ## addressable within one epoch (no last-walk-wins collapse).
  let compoundKey = gateId & "\x1f" & compositeLockHash
  if compoundKey in index.entries: some(index.entries[compoundKey])
  else: none(GateMemoEntry)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc pruneStaleEntries*(epochDir: string; activeGateIds: HashSet[string]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Remove CAS entries not in the active set.
  if not dirExists(epochDir): return
  for subdir in walkDir(epochDir):
    if subdir.kind != pcDir: continue
    for file in walkDir(subdir.path):
      if file.kind != pcFile: continue
      try:
        let readRes = readFileOpt(file.path)
        if readRes.isErr:
          removeFile(file.path)
          continue
        let content = readRes.get
        let nodeOpt = parseJsonOpt(content)
        if nodeOpt.isNone:
          removeFile(file.path)
          continue
        let gateId = nodeOpt.get(){"gateId"}.getStr("")
        if gateId.len > 0 and gateId notin activeGateIds:
          removeFile(file.path)
      except CatchableError:
        try:
          removeFile(file.path)
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# CAS-aware loadGateMemo
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadGateMemo*(gateId, compositeLockHash: string; epoch: int): Option[GateMemoEntry] =
  ## CAS-aware lookup: scan epoch directory for content-addressed entries.
  ## Verifies SHA-256(content) == filename (CAS integrity) and gateId match.
  ## Falls back to legacy flat-file path for migration.
  let epochDir = GateMemoBaseDir / "epoch_" & $epoch
  if dirExists(epochDir):
    for kind, subdir in walkDir(epochDir):
      if kind != pcDir: continue
      let dirName = subdir.extractFilename()
      if dirName.len != 2: continue  # CAS subdirectories are exactly 2 hex chars
      for fileKind, filePath in walkDir(subdir):
        if fileKind != pcFile: continue
        try:
          let readRes = readFileOpt(filePath)
          if readRes.isErr: continue
          let content = readRes.get
          # CAS integrity: SHA-256(content) must match the directory + filename
          let expectedAddr = computeCasAddress(content)
          if dirName != expectedAddr.casSubdir():
            continue
          if filePath.extractFilename() != expectedAddr.casFilename():
            continue
          let j = parseJsonOpt(content).get(newJObject())
          # Verify gateId and compositeLockHash match
          if j{"gateId"}.getStr() != gateId:
            continue
          if j{"compositeLockHash"}.getStr() != compositeLockHash:
            continue
          return parseMemoEntry(j)
        except CatchableError:
          continue
  # Fallback: legacy flat-file lookup
  loadLegacyGateMemo(gateId, epoch)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc saveGateMemo*(gateId, compositeLockHash: string; result: bool; epoch: int;
                   failureCategory: FailureCategory = fcTransient;
                   failureReason: string = "";
                   findings: seq[MemoFinding] = @[]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Save gate memo using True CAS addressing.
  ## The filename IS the SHA-256 hash of the file content.
  ## Directory layout: epoch_<N>/<hash[:2]>/<hash[2:]>
  ## Phase B: Pure content-addressed caching — expiresAt is written for backward
  ## compat but is NOT used for cache policy. Invalidation is purely via
  ## compositeLockHash change (input files, gate binary, build env).
  ##
  ## Only outcomes on the verdict axis are durable. A moNotEvaluated outcome is
  ## not written at all: persisting it would durably assert "this gate FAILED"
  ## for a run that never evaluated the gate (compile/tool failure, crash, or an
  ## exit code that carries no failure evidence). Re-running is the only sound
  ## answer, and a gate that produced no evidence has no verdict to preserve.
  ## DEBT#471 value closure: a FAIL entry carries structured finding
  ## coordinates; failureReason prose is auxiliary at most (the gate's own
  ## summary field), never quoted stdout. Structured entries are judged by
  ## classifyStructuredMemoOutcome — coordinates are evidence.
  let outcome = if findings.len > 0:
    classifyStructuredMemoOutcome(result, failureCategory, failureReason, findings)
  else:
    classifyMemoOutcome(result, failureCategory, failureReason)
  if outcome == moNotEvaluated:
    return
  let epochDir = GateMemoBaseDir / "epoch_" & $epoch
  discard existsOrCreateDirOpt(epochDir)
  let now = getTime().toUnix()
  var j = %*{
    "gateId": gateId,
    "compositeLockHash": compositeLockHash,
    "result": result,
    "timestamp": now,
    "epoch": epoch
  }
  # Phase B: Pure content-addressed caching policy.
  # Reached only for verdict-axis outcomes (see the outcome guard above),
  # so every FAIL recorded here uses compositeLockHash as its sole invalidation
  # mechanism. expiresAt is still written for backward compatibility with older
  # cache readers but is NOT checked during cache lookup.
  if not result:
    j["expiresAt"] = %*(0)
    j["failureCategory"] = %*($failureCategory)
    j["failureReason"] = %*(failureReason)
    if findings.len > 0:
      var findingsArr = newJArray()
      for f in findings:
        findingsArr.add(%*{"file": f.file, "line": f.line, "detail": f.detail})
      j["findings"] = findingsArr
  else:
    j["expiresAt"] = %*(0)
  let jsonContent = $j & "\n"
  let casAddr = computeCasAddress(jsonContent)
  let casFilePath = casPath(epochDir, casAddr)
  discard existsOrCreateDirOpt(casFilePath.parentDir())
  ## intentional-discard: CAS entry is content-addressed and re-derivable; write is best-effort
  discard writeFileOpt(casFilePath, jsonContent)

{.pop.}
