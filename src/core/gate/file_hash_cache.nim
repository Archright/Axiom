import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

import checksums/sha2
import core/trusted/axiom_pragmas
import core/trusted/stdlib_shield  # safeMoveFile: Exception isolation for stdlib moveFile quirk
import core/types/results
import std/[os, json, tables, times, algorithm]
type
  FileCacheEntry* = object
    mtime*: int64       ## Unix timestamp of last modification
    hash*: string       ## SHA-256 hex digest

  FileHashCache* = object
    entries*: Table[string, FileCacheEntry]  ## path → (mtime, hash)
    dirty*: bool  ## true if any new entries were added (needs save)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func cachePath(repoRoot: string): string =
  repoRoot / ".axiom" / "cache" / "file_hashes.json"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseCacheEntry(val: JsonNode): FileCacheEntry {.raises: [].} =
  ## Extract a FileCacheEntry from a JSON node. Returns empty on bad data.
  result.mtime = val{"mtime"}.getBiggestInt(0).int64
  result.hash = val{"hash"}.getStr("")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseCacheEntries(j: JsonNode): Table[string, FileCacheEntry] {.raises: [].} =
  ## Parse all valid entries from a JSON object into a table.
  result = initTable[string, FileCacheEntry]()
  if j.kind != JObject:
    return
  for key, val in j:
    if val.kind != JObject:
      continue
    let entry = parseCacheEntry(val)
    if entry.hash.len > 0:
      result[key] = entry
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadFileHashCache*(repoRoot: string): FileHashCache {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load persistent hash cache from disk. Returns empty cache on any error.
  result.entries = initTable[string, FileCacheEntry]()
  result.dirty = false
  let path = cachePath(repoRoot)
  if not fileExists(path):
    return
  try:
    let content = readFile(path)
    let j = parseJson(content)
    result.entries = parseCacheEntries(j)
  except CatchableError:
    discard  # Corrupt cache → start fresh  # axiom:best-effort(ioboundary catch)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeFileHash*(path: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of file contents. Returns "" if file doesn't exist.
  ## NOTE: Large files (>1MB, e.g. bin/ax at 9MB, data/seed_symbol_graph.json)
  ## should be hashed sequentially after small-file parallel batch completes.
  ## The mtime-based cache (getOrComputeHash) mitigates repeated I/O for
  ## unchanged files, but first-time hashing of large binaries blocks the
  ## caller. A size-based batch separator should be added to the VFS pipeline
  ## when malebolgia parallelism is introduced for hashing.
  if not fileExists(path):
    return ""
  $secureHash(Sha_256, "\x00" & readFile(path))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getFileMtime*(path: string): int64 {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Get file modification time as Unix timestamp. Returns 0 if not found.
  try:
    result = getLastModificationTime(path).toUnix()
  except CatchableError:
    result = 0
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getOrComputeHash*(cache: var FileHashCache; path: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Get cached hash for a file, recomputing only if mtime changed.
  ## Returns "" if file doesn't exist.
  if not fileExists(path):
    return ""

  let currentMtime = getFileMtime(path)
  let existing = cache.entries.getOrDefault(path)

  if existing.hash.len > 0 and existing.mtime == currentMtime:
    return existing.hash

  # Cache miss or stale — recompute
  let hash = computeFileHash(path)
  if hash.len > 0:
    cache.entries[path] = FileCacheEntry(mtime: currentMtime, hash: hash)
    cache.dirty = true
  hash
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc save*(cache: var FileHashCache; repoRoot: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Persist cache to disk. Only writes if dirty. Best-effort (never propagates errors).
  if not cache.dirty:
    return
  let path = cachePath(repoRoot)
  try:
    let dir = path.parentDir()
    if not dirExists(dir):
      createDir(dir)
    var j = newJObject()
    for key, entry in cache.entries:
      j[key] = %*{"mtime": entry.mtime, "hash": entry.hash}
    writeFile(path, $j & "\n")
    cache.dirty = false
  except CatchableError:
    discard  # Best-effort persistence  # axiom:best-effort(ioboundary catch)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func pairwiseHash(a, b: string): string {.raises: [].} =
  ## Hash two sibling nodes in the Merkle tree.
  $secureHash(Sha_256, "\x01" & a & b)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func pairwiseReduceLayer(layer: seq[string]): seq[string] {.raises: [].} =
  ## Reduce one Merkle tree layer to the next via pairwise hashing.
  result = @[]
  var i = 0
  while i < layer.len:
    if i + 1 < layer.len:
      result.add(pairwiseHash(layer[i], layer[i + 1]))
    else:
      result.add(layer[i])
    i += 2
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func reduceHashes(hashes: seq[string]): string {.raises: [].} =
  ## Reduce a list of hashes to a single Merkle root via pairwise hashing.
  var layer = hashes
  while layer.len > 1:
    layer = pairwiseReduceLayer(layer)
  layer[0]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc collectHashes(cache: var FileHashCache; files: seq[string]): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Collect file hashes using the cache, sorted deterministically.
  result = @[]
  for f in files.sorted():
    let hash = cache.getOrComputeHash(f)
    if hash.len > 0:
      result.add(hash)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeMerkleRootCached*(cache: var FileHashCache;
  files: seq[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute Merkle root using cached file hashes.
  ## Falls back to readFile for cache misses, updates cache on hit.
  let hashes = collectHashes(cache, files)
  if hashes.len == 0:
    return ""
  if hashes.len == 1:
    return hashes[0]
  reduceHashes(hashes)
# ─── VFS Binary Cache (new pipeline) ─────────────────────────────────────

const
  VFS_MAGIC* = 0x41584653'u32  # "AXFS"
  VFS_VERSION* = 1'u16
type
  VfsCacheEntry* = object
    mtime*: int64           # Unix timestamp (8 bytes)
    size*: int64            # File size in bytes (8 bytes)
    hash*: array[32, byte]  # SHA-256 raw bytes (32 bytes)
type
  VfsCache* {.acyclic.} = ref object
    entries*: Table[string, VfsCacheEntry]
    dirty*: bool
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func vfsCachePath*(repoRoot: string): string =
  repoRoot / ".axiom" / "cache" / "vfs.bin"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadVfsCache*(repoRoot: string): Result[VfsCache, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load the binary VFS cache from disk. Returns empty cache on any error.
  let cachePath = vfsCachePath(repoRoot)
  var vfsCache = VfsCache(entries: initTable[string, VfsCacheEntry](), dirty: false)
  if not fileExists(cachePath):
    return ok(vfsCache)
  try:
    var f: File
    if not open(f, cachePath, fmRead):
      return ok(vfsCache)
    defer: f.close()
    # Header: magic(u32) + version(u16) + count(u32) + pad(u16) = 12 bytes, padded to 16
    var magic: uint32
    discard f.readBuffer(addr magic, sizeof(uint32))
    if magic != VFS_MAGIC:
      return ok(vfsCache)  # Corrupt or different format
    var version: uint16
    discard f.readBuffer(addr version, sizeof(uint16))
    var count: uint32
    discard f.readBuffer(addr count, sizeof(uint32))
    f.setFilePos(16)  # Skip padding to 16-byte boundary
    vfsCache.entries = initTable[string, VfsCacheEntry](count.int)
    for _ in 0..<count.int:
      var mtime: int64
      discard f.readBuffer(addr mtime, sizeof(int64))
      var fileSize: int64
      discard f.readBuffer(addr fileSize, sizeof(int64))
      var hash: array[32, byte]
      discard f.readBuffer(addr hash[0], 32)
      var pathLen: uint16
      discard f.readBuffer(addr pathLen, sizeof(uint16))
      var path = newString(pathLen.int)
      if pathLen > 0:
        discard f.readBuffer(addr path[0], pathLen.int)
      # Skip padding to 8-byte boundary
      let payloadBytes = 8 + 8 + 32 + 2 + pathLen.int  # mtime+size+hash+pathLen+path
      let padding = (8 - (payloadBytes mod 8)) mod 8
      if padding > 0:
        f.setFilePos(f.getFilePos() + padding.int64)
      vfsCache.entries[path] = VfsCacheEntry(mtime: mtime, size: fileSize, hash: hash)
    ok(vfsCache)
  except CatchableError as e:
    err("loadVfsCache(" & repoRoot & "): " & e.msg)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc flushCache*(cache: var VfsCache; repoRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError], warning[BareExcept]: off.} =
  ## Flush binary VFS cache to disk via atomic tmp+rename.
  if not cache.dirty:
    return
  let cacheDir = repoRoot / ".axiom" / "cache"
  if not dirExists(cacheDir):
    createDir(cacheDir)
  let finalPath = vfsCachePath(repoRoot)
  let tmpPath = finalPath & ".tmp"
  var f: File
  if not open(f, tmpPath, fmWrite):
    raise newException(system.IOError, "Cannot write VFS cache: " & tmpPath)
  # Header: magic(4) + version(2) + count(4) + pad(2) = 12 → pad to 16
  var magic = VFS_MAGIC
  discard f.writeBuffer(addr magic, sizeof(uint32))
  var ver = VFS_VERSION
  discard f.writeBuffer(addr ver, sizeof(uint16))
  var cnt = uint32(cache.entries.len)
  discard f.writeBuffer(addr cnt, sizeof(uint32))
  var pad16 = uint16(0)
  discard f.writeBuffer(addr pad16, sizeof(uint16))
  # Additional 4 bytes padding to reach 16-byte boundary
  var pad32 = uint32(0)
  discard f.writeBuffer(addr pad32, sizeof(uint32))
  for path, entry in cache.entries:
    # Record: mtime(8) + size(8) + hash(32) = 48 bytes (8-byte aligned)
    # Then: pathLen(2) + path(var) + padding
    var mtime = entry.mtime
    discard f.writeBuffer(addr mtime, sizeof(int64))
    var fileSize = entry.size
    discard f.writeBuffer(addr fileSize, sizeof(int64))
    var hashCopy = entry.hash
    discard f.writeBuffer(addr hashCopy[0], 32)
    var pathLen = uint16(path.len)
    discard f.writeBuffer(addr pathLen, sizeof(uint16))
    if path.len > 0:
      discard f.writeBuffer(unsafeAddr path[0], path.len)
    let padding = (8 - ((8 + 8 + 32 + 2 + path.len) mod 8)) mod 8
    for _ in 0..<padding:
      var z = uint8(0)
      discard f.writeBuffer(addr z, sizeof(uint8))
  f.flushFile()
  f.close()
  try:
    safeMoveFile(tmpPath, finalPath)
  except CatchableError:
    discard  # Best-effort atomic rename  # axiom:best-effort(ioboundary catch)
  cache.dirty = false

{.pop.}

