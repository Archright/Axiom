## CAS Index — Unified Content-Addressable Storage index for artifact caching
##
## Computes a deterministic transitive hash over the entire repository state:
##   commit hash + all tracked blob hashes + build config hash + gate manifest hash
##
## The hash uniquely identifies a repository snapshot. When two worktrees share
## the same transitive hash, build artifacts (binaries) can be reused directly.
##
## Index file: `.axiom/cas_index.json`
## API:
##   computeTransitiveHash(repoRoot) → hash
##   lookupCas(hash)                → Option[CasEntry]
##   persistCas(entry)              → write to index
##   isCacheHit(repoRoot)          → bool convenience wrapper
##
## Module is an I/O boundary — all procs perform disk reads/writes or subprocess calls.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[algorithm, json, os, osproc, times, options, strutils, tables]
import checksums/sha2
import core/axiom_pragmas
import core/trusted/stdlib_shield
import core/trusted/env_access

axiomIoBoundary()

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  CasEntry* = object
    ## A single CAS index entry mapping a transitive hash to build artifacts.
    transitiveHash*: string               ## SHA-256 of full repo state
    artifacts*: seq[string]               ## binary paths relative to repo root
    timestamp*: float                     ## Unix epoch of cache write
    gateResults*: Table[string, bool]     ## gate-id → pass/fail
    buildEnvHash*: string                 ## hash of build environment snapshot

  CasIndex* = object
    ## The full CAS index (persisted as JSON).
    version*: string                      ## schema version
    entries*: seq[CasEntry]               ## all cached entries

  GatesMetaSidecar* = object
    version*: string
    gateDirPath*: string
    fileCount*: int
    metadataDigest*: string
    runnerHash*: string

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  CasIndexVersion* = "1.0"
  CasIndexFileName* = ".axiom/cas_index.json"
  ConfigNimsPath* = "config.nims"
  GateManifestPath* = "src/gate/manifest.d/_index.json"
  GatesMetaFileName* = "gates_meta.json"
  GatesMetaVersion* = "1.0"
  DomainSeparator* = "\x03"              ## distinct from transitive_hash.nim's "\x02"

# ---------------------------------------------------------------------------
# Pure computations (func)
# ---------------------------------------------------------------------------

func computeSha256*(data: string): string {.raises: [], noSideEffect.} =
  ## Compute SHA-256 hex digest of data. Pure function.
  $secureHash(Sha_256, data)

func computeSha256OfFile*(content: string): string {.raises: [], noSideEffect.} =
  ## Compute SHA-256 hex digest of file content string. Pure function.
  $secureHash(Sha_256, content)

func combineHashes*(parts: openArray[string]): string {.raises: [], noSideEffect.} =
  ## Combine multiple hash components into a single deterministic hash.
  ## Uses domain separator to prevent length-extension ambiguity.
  var combined = DomainSeparator
  for part in parts:
    combined &= $part.len & ":" & part
  $secureHash(Sha_256, combined)

func serializeEntry*(entry: CasEntry): JsonNode {.raises: [].} =
  ## Serialize a CasEntry to JSON node.
  var gateResultsNode = newJObject()
  for k, v in entry.gateResults:
    gateResultsNode[k] = newJBool(v)

  %*{
    "transitiveHash": entry.transitiveHash,
    "artifacts": entry.artifacts,
    "timestamp": entry.timestamp,
    "gateResults": gateResultsNode,
    "buildEnvHash": entry.buildEnvHash
  }

func deserializeEntry*(node: JsonNode): CasEntry {.raises: [].} =
  ## Deserialize a JSON node to CasEntry. Missing fields get defaults.
  var gateResults: Table[string, bool]
  let grNode = node{"gateResults"}
  if grNode != nil and grNode.kind == JObject:
    for k, v in grNode:
      gateResults[k] = v.getBool(false)

  CasEntry(
    transitiveHash: node{"transitiveHash"}.getStr(""),
    artifacts:
      block:
        let artNode = node{"artifacts"}
        if artNode != nil and artNode.kind == JArray:
          var s: seq[string]
          for item in artNode:
            s.add(item.getStr())
          s
        else: @[],
    timestamp: node{"timestamp"}.getFloat(0.0),
    gateResults: gateResults,
    buildEnvHash: node{"buildEnvHash"}.getStr("")
  )

func serializeIndex*(index: CasIndex): JsonNode {.raises: [].} =
  ## Serialize full CAS index to JSON.
  var entriesArr = newJArray()
  for entry in index.entries:
    entriesArr.add(serializeEntry(entry))

  %*{
    "version": index.version,
    "entries": entriesArr
  }

func deserializeIndex*(root: JsonNode): CasIndex {.raises: [].} =
  ## Deserialize JSON to CasIndex.
  var entries: seq[CasEntry]
  let entriesNode = root{"entries"}
  if entriesNode != nil and entriesNode.kind == JArray:
    for node in entriesNode:
      entries.add(deserializeEntry(node))

  CasIndex(
    version: root{"version"}.getStr(CasIndexVersion),
    entries: entries
  )

func isHexChar(c: char): bool {.inline, raises: [], noSideEffect.} =
  c in {'0'..'9', 'a'..'f', 'A'..'F'}

func sortBlobHashes*(hashes: var seq[string]) {.raises: [], noSideEffect.} =
  ## Sort blob hashes in-place for deterministic ordering.
  hashes.sort(system.cmp)

# ---------------------------------------------------------------------------
# I/O boundary — git operations
# ---------------------------------------------------------------------------

proc gitRevParseHead*(repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Get commit hash of HEAD. Returns "" on error.
  let cmd = "git -C " & quoteShell(repoRoot) & " rev-parse HEAD"
  try:
    let output = execProcess(cmd).strip()
    if output.len == 40:
        var valid = true
        for c in output:
          if not isHexChar(c): valid = false; break
        if valid: return output
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return ""

proc gitLsTreeBlobHashes*(repoRoot: string): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Get sorted SHA-1 blob hashes of all tracked files via `git ls-tree -r HEAD`.
  ## Returns empty seq on error.
  result = @[]
  let cmd = "git -C " & quoteShell(repoRoot) &
            " ls-tree -r HEAD --format=%(objectname)"
  try:
    let output = execProcess(cmd).strip()
    if output.len == 0:
      return
    for line in output.splitLines():
      let h = line.strip()
      if h.len == 40:
        var valid = true
        for c in h:
          if not isHexChar(c): valid = false; break
        if valid:
          result.add(h)
    result.sort(system.cmp)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# I/O boundary — index file operations
# ---------------------------------------------------------------------------

proc readIndexFile*(indexPath: string): CasIndex {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Read CAS index from disk. Returns empty index if file missing or malformed.
  result = CasIndex(version: CasIndexVersion, entries: @[])
  if not fileExists(indexPath):
    return
  try:
    let content = readFile(indexPath)
    let root = parseJson(content)
    result = deserializeIndex(root)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc writeIndexFile*(indexPath: string, index: CasIndex) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomically write CAS index to disk (temp + rename).
  let dir = indexPath.parentDir()
  if dir.len > 0 and not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError:
      return

  let tmpPath = indexPath & ".tmp"
  try:
    let json = serializeIndex(index)
    writeFile(tmpPath, json.pretty())
    safeMoveFile(tmpPath, indexPath)
  except CatchableError, FileMoveError:
    # Cleanup temp file on failure
    if fileExists(tmpPath):
      try:
        removeFile(tmpPath)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

proc fileContentHash*(filePath: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## SHA-256 of a file's content. Returns "" on error.
  try:
    if fileExists(filePath):
      return $secureHash(Sha_256, readFile(filePath))
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return ""

proc gatesMetaSidecarPath*(repoRoot: string): string {.raises: [], noSideEffect.} =
  repoRoot / ".axiom" / "cache" / GatesMetaFileName

proc normalizePathForDigest*(path: string): string {.raises: [], noSideEffect.} =
  path.replace('\\', '/')

proc collectGateEntries*(gateDir: string): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  if not dirExists(gateDir):
    return
  try:
    for p in walkDirRec(gateDir):
      result.add(p)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  result.sort(system.cmp)

proc computeGateRunnerHash*(gateDir: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = ""
  for p in collectGateEntries(gateDir):
    result &= fileContentHash(p)

proc computeGateMetadataDigest*(gateDir: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var metadata = ""
  for p in collectGateEntries(gateDir):
    let normalized = normalizePathForDigest(p)
    metadata.add(normalized)
    metadata.add('\t')
    try:
      let info = getFileInfo(p)
      metadata.add($info.lastWriteTime.toUnix())
      metadata.add('\t')
      metadata.add($info.size)
    except CatchableError:
      metadata.add("0")
      metadata.add('\t')
      metadata.add("0")
    metadata.add('\n')
  result = computeSha256(metadata)

proc readGatesMetaSidecar*(sidecarPath: string): GatesMetaSidecar {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = GatesMetaSidecar(version: "", gateDirPath: "", fileCount: 0,
                            metadataDigest: "", runnerHash: "")
  if not fileExists(sidecarPath):
    return
  try:
    let root = parseJson(readFile(sidecarPath))
    result.version = root{"version"}.getStr("")
    result.gateDirPath = root{"gateDirPath"}.getStr("")
    result.fileCount = root{"fileCount"}.getInt(0)
    result.metadataDigest = root{"metadataDigest"}.getStr("")
    result.runnerHash = root{"runnerHash"}.getStr("")
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc writeGatesMetaSidecar*(sidecarPath: string; meta: GatesMetaSidecar) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = sidecarPath.parentDir()
  if dir.len > 0 and not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError:
      return
  try:
    let tmpPath = sidecarPath & ".tmp"
    let node = %*{
      "version": meta.version,
      "gateDirPath": meta.gateDirPath,
      "fileCount": meta.fileCount,
      "metadataDigest": meta.metadataDigest,
      "runnerHash": meta.runnerHash
    }
    writeFile(tmpPath, node.pretty())
    safeMoveFile(tmpPath, sidecarPath)
  except CatchableError, FileMoveError:
    let tmpPath = sidecarPath & ".tmp"
    if fileExists(tmpPath):
      try:
        removeFile(tmpPath)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

proc computeGatesMetaSidecar*(gateDir: string): GatesMetaSidecar {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result.version = GatesMetaVersion
  result.gateDirPath = gateDir
  result.fileCount = collectGateEntries(gateDir).len
  result.metadataDigest = computeGateMetadataDigest(gateDir)
  result.runnerHash = computeGateRunnerHash(gateDir)

proc casHashModeFull(): bool {.raises: [], noSideEffect.} =
  getAxiomEnv(evCasHashMode) == "full"

# ---------------------------------------------------------------------------
# Core API — transitive hash computation
# ---------------------------------------------------------------------------

proc computeTransitiveHash*(repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Compute the full transitive hash of the repository state.
  ##
  ## Hash components (3 git/subprocess calls max):
  ##   1. git rev-parse HEAD         → commit hash
  ##   2. git ls-tree -r HEAD        → all tracked file blob hashes (sorted)
  ##   3. SHA-256(config.nims)       → build config hash (pure file read)
  ##   4. SHA-256(manifest.d/_index.json) → gate config hash (pure file read)
  ##
  ## All four are combined into a single deterministic SHA-256.
  ## Returns "" if critical components fail.
  result = ""

  # Component 1: commit hash (git call #1)
  let commitHash = gitRevParseHead(repoRoot)
  if commitHash.len == 0:
    return ""

  # Component 2: all tracked blob hashes (git call #2)
  let blobHashes = gitLsTreeBlobHashes(repoRoot)
  var blobHashesStr: string
  for h in blobHashes:
    blobHashesStr &= h

  # Component 3: build config hash (file read, no git call)
  let configPath = repoRoot / ConfigNimsPath
  let configHash = fileContentHash(configPath)

  # Component 4: gate manifest hash (file read, no git call)
  let manifestPath = repoRoot / GateManifestPath
  let manifestHash = fileContentHash(manifestPath)

  # Combine all components deterministically
  result = combineHashes([commitHash, blobHashesStr, configHash, manifestHash])

proc computeSoundCasHash*(repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Sound deterministic CAS hash for pre-commit early-exit.
  ##
  ## Unlike `computeTransitiveHash` (which only hashes the committed tree),
  ## this includes the STAGED index via `git write-tree` and the AOT gate
  ## runner binaries. Two worktrees with the same HEAD but DIFFERENT staged
  ## changes now produce DIFFERENT hashes, so the early-exit can only HIT when
  ## the exact same staged tree + gate binaries + manifest were already
  ## verified. This removes the prior integrity bypass (pre-commit receipt
  ## could be reused across different uncommitted states).
  ##
  ## Safety guards (all degrade to "" = cache MISS = force full gate run):
  ##   - git write-tree fails on unmerged/merge-conflict index (exit != 0)
  ##   - .axiom/cache/gates missing → empty runner hash (deterministic)
  result = ""

  # Component 0: staged tree (CWD-bound via git -C, exit-code + length guard)
  let wtCmd = "git -C " & quoteShell(repoRoot) & " write-tree"
  var wtOut = ""
  var wtCode = 1
  try:
    wtOut = execProcess(wtCmd).strip()
    wtCode = 0
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  if wtCode != 0 or wtOut.len != 40:
    return ""  # merge conflict / git error → force full gate run (MISS)

  # Component 1: AOT gate runner binary hashes
  # dir-exists guard prevents OSError on fresh clone / cleared cache.
  # sort() makes the combined hash deterministic across OS readdir order.
  let gateDir = repoRoot / ".axiom" / "cache" / "gates"
  let sidecarPath = gatesMetaSidecarPath(repoRoot)

  var runnerHash = ""
  var gatesMeta = GatesMetaSidecar()
  if not casHashModeFull():
    gatesMeta = readGatesMetaSidecar(sidecarPath)
    if gatesMeta.version == GatesMetaVersion and
       gatesMeta.gateDirPath == gateDir and
       gatesMeta.metadataDigest.len > 0 and
       gatesMeta.runnerHash.len > 0:
      let metadataDigest = computeGateMetadataDigest(gateDir)
      if metadataDigest == gatesMeta.metadataDigest:
        runnerHash = gatesMeta.runnerHash
      else:
        gatesMeta = computeGatesMetaSidecar(gateDir)
        writeGatesMetaSidecar(sidecarPath, gatesMeta)
        runnerHash = gatesMeta.runnerHash
    else:
      gatesMeta = computeGatesMetaSidecar(gateDir)
      writeGatesMetaSidecar(sidecarPath, gatesMeta)
      runnerHash = gatesMeta.runnerHash
  else:
    gatesMeta = computeGatesMetaSidecar(gateDir)
    writeGatesMetaSidecar(sidecarPath, gatesMeta)
    runnerHash = gatesMeta.runnerHash

  # Component 2: hook driver binary hash
  # Missing bin/gate_hook contributes an empty hash deterministically.
  let gateHookHash = fileContentHash(repoRoot / "bin" / "gate_hook")

  # Components 3-6: existing repository-state components
  let commitHash = gitRevParseHead(repoRoot)
  if commitHash.len == 0:
    return ""
  let blobHashes = gitLsTreeBlobHashes(repoRoot)
  var blobHashesStr: string
  for h in blobHashes:
    blobHashesStr &= h
  let configHash = fileContentHash(repoRoot / ConfigNimsPath)
  let manifestHash = fileContentHash(repoRoot / GateManifestPath)

  result = combineHashes([wtOut.strip(), runnerHash, gateHookHash, commitHash, blobHashesStr, configHash, manifestHash])

# ---------------------------------------------------------------------------
# Core API — CAS lookup
# ---------------------------------------------------------------------------

proc lookupCas*(hash: string, indexPath: string = CasIndexFileName): Option[CasEntry] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Look up a CAS entry by its transitive hash.
  ## Returns none if not found.
  let index = readIndexFile(indexPath)
  for entry in index.entries:
    if entry.transitiveHash == hash:
      return some(entry)
  return none(CasEntry)

proc lookupCasByHash*(hash: string): Option[CasEntry] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Convenience: look up in default index location.
  lookupCas(hash, CasIndexFileName)

# ---------------------------------------------------------------------------
# Core API — CAS persistence
# ---------------------------------------------------------------------------

proc persistCas*(entry: CasEntry, indexPath: string = CasIndexFileName) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Persist a CAS entry to the index file.
  ## If an entry with the same transitiveHash exists, it is replaced.
  ## Otherwise, the entry is appended.
  var index = readIndexFile(indexPath)

  # Replace existing entry or append new one
  var replaced = false
  for i, existing in index.entries:
    if existing.transitiveHash == entry.transitiveHash:
      index.entries[i] = entry
      replaced = true
      break

  if not replaced:
    index.entries.add(entry)

  index.version = CasIndexVersion
  writeIndexFile(indexPath, index)

proc persistCasEntry*(entry: CasEntry) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Convenience: persist to default index location.
  persistCas(entry, CasIndexFileName)

# ---------------------------------------------------------------------------
# Core API — cache hit check
# ---------------------------------------------------------------------------

proc isCacheHit*(repoRoot: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Check if the current repo state has a CAS cache hit.
  ## Computes the transitive hash and looks it up in the index.
  let hash = computeTransitiveHash(repoRoot)
  if hash.len == 0:
    return false
  let entry = lookupCas(hash)
  result = entry.isSome()

proc isCacheHitForHash*(hash: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Convenience: check cache hit for a pre-computed hash.
  if hash.len == 0:
    return false
  let entry = lookupCas(hash)
  result = entry.isSome()

# ---------------------------------------------------------------------------
# Core API — index management
# ---------------------------------------------------------------------------

proc indexSize*(indexPath: string = CasIndexFileName): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Return the number of entries in the CAS index.
  let index = readIndexFile(indexPath)
  result = index.entries.len

proc evictStale*(maxAge: float = 604800.0, ## default: 7 days in seconds
                 indexPath: string = CasIndexFileName): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect, TimeEffect].} =
  ## Remove entries older than maxAge seconds. Returns count of evicted entries.
  var index = readIndexFile(indexPath)
  let now = epochTime()
  var kept: seq[CasEntry]

  for entry in index.entries:
    if (now - entry.timestamp) < maxAge:
      kept.add(entry)

  let evictedCount = index.entries.len - kept.len
  if evictedCount > 0:
    index.entries = kept
    writeIndexFile(indexPath, index)

  result = evictedCount

proc clearIndex*(indexPath: string = CasIndexFileName) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Clear the entire CAS index (write empty index).
  let empty = CasIndex(version: CasIndexVersion, entries: @[])
  writeIndexFile(indexPath, empty)

{.pop.}

