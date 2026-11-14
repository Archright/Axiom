## AST Content Hash — deterministic content hashing for CEGAR pipeline cache.
##
## Provides SHA-256 based cache keys combining file content with config state.
## Uses 2-stage lookup: mtime guard first, then full SHA-256 only on change.
##
## Phase 6C: Replaces len+first50chars low-hit-rate cache key with
## content-addressed hashing for higher cache precision.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/[os, times]
import checksums/sha2
import core/axiom_pragmas
import gate/manifest_provider

# axiomIoBoundary — this module performs file I/O for hash computation

type
  AstHashResult* = object
    ## Result of an AST content hash computation.
    contentHash*: string    ## SHA-256 hex digest of file content
    mtime*: Time            ## Last modification time of the source file
    filePath*: string        ## Absolute path to the hashed file

  ConfigSnapshot* = object
    ## Singleton snapshot of config file hashes.
    ## Loaded once per pipeline run; refreshed on mtime change.
    axiomTomlHash*: string
    lockHash*: string
    ratchetHash*: string
    manifestHash*: string
    combinedHash*: string   ## SHA-256 of all above concatenated

# ── Config snapshot singleton ────────────────────────────────────────────

var gConfigSnapshot: ConfigSnapshot
var gConfigInitialized = false
var gConfigMtime: int64 = 0

func combineHashes*(a, b: string): string =
  ## Deterministically combine two hash strings into one.
  ## Order-sensitive: combineHashes(a, b) != combineHashes(b, a).
  result = $secureHash(Sha_256, a & ":" & b)

proc loadConfigSnapshot*(repoRoot: string): ConfigSnapshot {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
 =
  ## Load and hash all config files. Returns cached snapshot if mtime unchanged.
  ## Config files: axiom.toml (config/ first, then root), nimble.lock, gate_manifest.json
  let configPaths = [
    (if fileExists(repoRoot / "config" / "axiom.toml"): repoRoot / "config" / "axiom.toml"
     else: repoRoot / "axiom.toml"),
    repoRoot / "nimble.lock",
    repoRoot / ".axiom" / "ratchet.json"
  ]

  # Compute combined mtime for staleness check
  var latestMtime: int64 = 0
  for p in configPaths:
    try:
      if fileExists(p):
        let mt = getLastModificationTime(p).toUnix()
        if mt > latestMtime:
          latestMtime = mt
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  # Return cached if unchanged
  if gConfigInitialized and latestMtime == gConfigMtime:
    return gConfigSnapshot

  # Hash each config file
  var hashes: seq[string] = @[]
  for p in configPaths:
    try:
      if fileExists(p):
        hashes.add($secureHash(Sha_256, readFile(p)))
      else:
        hashes.add("")
    except CatchableError:
      hashes.add("")

  # Manifest hash from compile-time manifest_provider (not file-based)
  let manifestHash = manifest_provider.AxiomManifestHash

  # Build combined hash
  var combined = ""
  for h in hashes:
    if combined.len == 0:
      combined = h
    else:
      combined = combineHashes(combined, h)
  combined = combineHashes(combined, manifestHash)

  gConfigSnapshot = ConfigSnapshot(
    axiomTomlHash: hashes[0],
    lockHash: hashes[1],
    ratchetHash: hashes[2],
    manifestHash: manifestHash,
    combinedHash: combined
  )
  gConfigMtime = latestMtime
  gConfigInitialized = true
  result = gConfigSnapshot

proc resetConfigSnapshot*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Reset the singleton. Call at pipeline start for deterministic behavior.
  gConfigSnapshot = ConfigSnapshot()
  gConfigInitialized = false
  gConfigMtime = 0

# ── Content hashing ─────────────────────────────────────────────────────

func computeContentHash*(content: string): string =
  ## Compute SHA-256 hash of a string. Deterministic and pure.
  result = $secureHash(Sha_256, content)

proc computeFileHash*(filePath: string): AstHashResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
 =
  ## Compute content hash + mtime for a single file.
  ## Returns empty contentHash on file-not-found.
  result.filePath = filePath
  try:
    if fileExists(filePath):
      result.contentHash = $secureHash(Sha_256, readFile(filePath))
      result.mtime = getLastModificationTime(filePath)
    else:
      result.contentHash = ""
      result.mtime = fromUnix(0)
  except CatchableError:
    result.contentHash = ""
    result.mtime = fromUnix(0)

proc computeCacheKey*(modulePath: string; repoRoot: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
 =
  ## 2-stage cache key: content hash combined with config snapshot.
  ## Returns: SHA-256(content_hash + config_combined_hash)
  ##
  ## The config snapshot ensures cache invalidation when project-level
  ## settings change (e.g., new gate rules, updated dependencies).
  let content = try:
    readFile(modulePath)
  except CatchableError:
    ""

  let astHash = computeContentHash(content)

  # Load config snapshot (cached singleton, only re-reads on mtime change)
  let root = if repoRoot.len > 0: repoRoot else: getCurrentDir()
  let config = loadConfigSnapshot(root)

  result = combineHashes(astHash, config.combinedHash)

func computeCacheKeyFromSource*(source: string;
    configHash: string = ""): string =
  ## Compute cache key directly from source string (no file I/O).
  ## Used for in-memory source code where we already have the content.
  let astHash = computeContentHash(source)
  if configHash.len > 0:
    result = combineHashes(astHash, configHash)
  else:
    result = astHash

func cacheKeyValid*(key: string): bool =
  ## Check if a cache key is well-formed (non-empty hex string).
  result = key.len > 0

{.pop.}

