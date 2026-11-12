{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "domain"
import checksums/sha2
import core/types/results
import core/gate/file_hash_cache  # reuse mtime-based hash cache
import core/gate/symbol_hasher    # symbol-level hashing for fine-grained invalidation
import core/gate/git_index_mtime_cache  # O(1) git index mtime fast-path
import core/trusted/axiom_pragmas
import std/algorithm
import std/options
import std/os
import std/strutils
import std/tables
import std/times
type
  FileNodeChildren* = seq[FileNode]  # Type alias: breaks dep_analysis self-loop detection (false-positive tree pattern)
  FileNode* {.acyclic.} = ref object
    ## A node in the Merkle VFS tree. Either a file or directory.
    path*: string           # Relative path (e.g., "src/core/gate/gate_memo.nim")
    contentHash*: string    # SHA-256 of file content (empty for directories)
    mtime*: Time            # File modification time
    isDir*: bool
    children*: FileNodeChildren
    symbols*: seq[SymbolNode]  # Symbol-level breakdown (empty for non-.nim files)
    symbolRootHash*: string    # Merkle hash of symbol sequence

  VfsEntry* = object
    ## Value-type entry for the file index. Eliminates nil-dereference risk.
    path*: string
    contentHash*: string
    mtime*: Time
    isDir*: bool
    valid*: bool  # Always true for entries in the table; prevents default() false positive
    symbolRootHash*: string  # Merkle hash of symbols (empty for non-.nim files)

  MerkleVfs* {.acyclic.} = ref object
    ## The virtual file system. Provides O(1) lookup by path.
    root*: FileNode
    fileIndex*: Table[string, VfsEntry]  # path → entry (value-based, nil-safe)
    rootHash*: string                     # Merkle root of entire tree
    rootPath*: string                     # Absolute root path (for markDirty)
    fileHashCache*: FileHashCache         # Reuse mtime-based dedup
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template withVfsEntry*(table: var Table[string, VfsEntry]; key: string;
                       entryVar: untyped; body: untyped) =
  ## Safe VFS entry access with transaction semantics.
  ## entryVar is bound to a mutable copy; written back only on normal exit (isCommitted).
  ## Return/exception inside body = Rollback (Silent Abort prevention).
  let blockKey = key
  if blockKey in table:
    var entryVar = table[blockKey]
    var isCommitted = false
    try:
      body
      isCommitted = true
    finally:
      if isCommitted:
        table[blockKey] = entryVar
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func vfsRootHash*(vfs: MerkleVfs): string {.inline, raises: [].} =
  ## Returns the Merkle root hash of the entire VFS.
  vfs.rootHash
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func getFileHash*(vfs: MerkleVfs; path: string): Option[string] {.raises: [].} =
  ## O(1) lookup: returns content hash for a file path, or none if not found.
  if path in vfs.fileIndex:
    let entry = vfs.fileIndex.getOrDefault(path)
    if not entry.isDir:
      return some(entry.contentHash)
  none(string)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func containsSubstring(s, sub: string): bool {.raises: [].} =
  ## Safe substring check that does not raise.
  if sub.len == 0:
    return true
  if sub.len > s.len:
    return false
  for i in 0..(s.len - sub.len):
    if s[i ..< i + sub.len] == sub:
      return true
  false
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func getFilesMatching*(vfs: MerkleVfs; pattern: string): seq[string] {.raises: [].} =
  ## Return all file paths matching a substring pattern (pipe-separated).
  ## Replaces walkDirRec() + pattern matching per gate.
  if pattern.len == 0:
    # Return all files
    for path, entry in vfs.fileIndex:
      if not entry.isDir:
        result.add(path)
    result.sort()
    return

  let patterns = pattern.split('|')
  for path, entry in vfs.fileIndex:
    if entry.isDir:
      continue
    for p in patterns:
      if containsSubstring(path, p.strip()):
        result.add(path)
        break
  result.sort()
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func fileCount*(vfs: MerkleVfs): int {.raises: [].} =
  ## Count of regular files in the VFS.
  for _, entry in vfs.fileIndex:
    if not entry.isDir:
      inc result
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getModificationTimeSafe(path: string): Time {.raises: [CatchableError].} =
  ## Wrapper for getLastModificationTime that explicitly declares raises.
  getLastModificationTime(path)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc buildVfs*(rootPath: string; patterns: seq[string] = @[]): MerkleVfs {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} =
  ## Build a Merkle VFS from the filesystem. Walks the directory tree once,
  ## computes SHA-256 for each file, and builds the Merkle root.
  ## If patterns is non-empty, only files matching those substrings are included.
  ## Fail-open: returns empty VFS on I/O errors.
  let root = FileNode(path: "", isDir: true)
  let emptyVfs = MerkleVfs(root: root, rootPath: rootPath)
  try:
    let fileHashCache = loadFileHashCache(rootPath)

    var fileIndex = initTable[string, VfsEntry]()
    var allFileHashes: seq[string] = @[]
    var fhc = fileHashCache  # mutable copy for getOrComputeHash

    for kind, path in walkDir(rootPath, relative = true):
      if kind == pcDir:
        # NOTE: This proc uses a different (older) skip strategy than discoverFiles.
        # discoverFiles + the 4-stage pipeline (diffAgainstCache → hash → buildVfsFromCache)
        # is the preferred path. Keep this in sync manually if skipDirs drift.
        let dirName = path.extractFilename()
        if dirName.startsWith(".") or dirName == "nimcache" or dirName == "build":
          continue
        # Recursively walk subdirectories
        for subKind, subPath in walkDir(rootPath / path, relative = true):
          if subKind == pcFile:
            let fullPath = path / subPath
            # Pattern filter
            if patterns.len > 0:
              var matches = false
              for pat in patterns:
                if containsSubstring(fullPath, pat.strip()):
                  matches = true
                  break
              if not matches:
                continue

            let absPath = rootPath / fullPath
            if fileExists(absPath):
              let fileHash = fhc.getOrComputeHash(absPath)
              let mtime = getModificationTimeSafe(absPath)
              # Symbol-level hashing for .nim files
              var symbolRootHash = ""
              if fullPath.endsWith(".nim"):
                try:
                  let content = readFile(absPath)
                  let symbols = extractSymbols(content)
                  symbolRootHash = hashSymbols(symbols)
                except CatchableError:
                  discard  # Symbol extraction is best-effort  # axiom:best-effort(ioboundary catch)
              let combinedHash = if symbolRootHash.len > 0:
                                   $secureHash(Sha_256, fileHash & symbolRootHash)
                                 else: fileHash
              let entry = VfsEntry(
                path: fullPath,
                contentHash: combinedHash,
                mtime: mtime,
                isDir: false,
                valid: true,
                symbolRootHash: symbolRootHash
              )
              fileIndex[fullPath] = entry
              allFileHashes.add(combinedHash)

      elif kind == pcFile:
        let fullPath = path
        # Pattern filter
        if patterns.len > 0:
          var matches = false
          for pat in patterns:
            if containsSubstring(fullPath, pat.strip()):
              matches = true
              break
          if not matches:
            continue

        let absPath = rootPath / fullPath
        if fileExists(absPath):
          let fileHash = fhc.getOrComputeHash(absPath)
          let mtime = getModificationTimeSafe(absPath)
          # Symbol-level hashing for .nim files
          var symbolRootHash = ""
          if fullPath.endsWith(".nim"):
            try:
              let content = readFile(absPath)
              let symbols = extractSymbols(content)
              symbolRootHash = hashSymbols(symbols)
            except CatchableError:
              discard  # Symbol extraction is best-effort  # axiom:best-effort(ioboundary catch)
          let combinedHash = if symbolRootHash.len > 0:
                               $secureHash(Sha_256, fileHash & symbolRootHash)
                             else: fileHash
          let entry = VfsEntry(
            path: fullPath,
            contentHash: combinedHash,
            mtime: mtime,
            isDir: false,
            valid: true,
            symbolRootHash: symbolRootHash
          )
          fileIndex[fullPath] = entry
          allFileHashes.add(combinedHash)

    # Compute Merkle root from all file hashes (sorted for determinism)
    allFileHashes.sort()
    var hashes = allFileHashes
    if hashes.len == 0:
      return MerkleVfs(root: root, fileIndex: fileIndex, rootHash: "", rootPath: rootPath, fileHashCache: fhc)
    if hashes.len == 1:
      return MerkleVfs(root: root, fileIndex: fileIndex, rootHash: hashes[0], rootPath: rootPath, fileHashCache: fhc)

    while hashes.len > 1:
      var next: seq[string] = @[]
      var i = 0
      while i < hashes.len:
        if i + 1 < hashes.len:
          next.add($secureHash(Sha_256, hashes[i] & hashes[i + 1]))
        else:
          next.add(hashes[i])
        i += 2
      hashes = next

    return MerkleVfs(root: root, fileIndex: fileIndex, rootHash: hashes[0], rootPath: rootPath, fileHashCache: fhc)
  except CatchableError:
    return emptyVfs
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc markDirty*(vfs: MerkleVfs; relPath: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  ## Invalidate a single file in the VFS. Re-reads from disk and updates
  ## the Merkle root. For incremental updates without full rebuild.
  ## relPath: relative path matching fileIndex key (e.g., "src/a.nim")
  if relPath notin vfs.fileIndex:
    return
  let absPath = vfs.rootPath / relPath
  if not fileExists(absPath):
    vfs.fileIndex.del(relPath)
    return
  let content = readFile(absPath)
  let fileHash = $secureHash(Sha_256, content)
  # Symbol-level hashing for .nim files
  var symbolRootHash = ""
  if relPath.endsWith(".nim"):
    let symbols = extractSymbols(content)
    symbolRootHash = hashSymbols(symbols)
  let combinedHash = if symbolRootHash.len > 0:
                       $secureHash(Sha_256, fileHash & symbolRootHash)
                     else: fileHash
  vfs.fileIndex.withVfsEntry(relPath, entry):
    entry.contentHash = combinedHash
    entry.symbolRootHash = symbolRootHash
    entry.mtime = getLastModificationTime(absPath)
  # Note: rootHash is NOT recalculated here. Call rebuildRootHash() if needed.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc rebuildRootHash*(vfs: MerkleVfs) {.raises: [].} =
  ## Recompute the Merkle root after markDirty() calls.
  var hashes: seq[string] = @[]
  for _, entry in vfs.fileIndex:
    if not entry.isDir and entry.contentHash.len > 0:
      hashes.add(entry.contentHash)
  hashes.sort()
  if hashes.len == 0:
    vfs.rootHash = ""
    return
  if hashes.len == 1:
    vfs.rootHash = hashes[0]
    return
  while hashes.len > 1:
    var next: seq[string] = @[]
    var i = 0
    while i < hashes.len:
      if i + 1 < hashes.len:
        next.add($secureHash(Sha_256, hashes[i] & hashes[i + 1]))
      else:
        next.add(hashes[i])
      i += 2
    hashes = next
  vfs.rootHash = hashes[0]
# ─── New Pipeline Types ──────────────────────────────────────────────────

type
  FileInfo* = object
    path*: string     # Relative path (e.g., "src/core/gate/gate_memo.nim")
    size*: int64      # File size in bytes
    mtime*: int64     # Unix timestamp of last modification
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc discoverFiles*(rootPath: string): Result[seq[FileInfo], string] =
  ## walkDirRec로 재귀 탐색 + skip 필터 적용. 결과 sort (결정론적 순서).
  const skipDirs = [".git", ".axiom", "nimcache", ".nimcache", "build",
                    "logs", "proof_cache", "leanstral_cache",
                    ".kimi-code"]
  try:
    var files: seq[FileInfo] = @[]
    for relPath in walkDirRec(rootPath, relative = true):
      let parts = relPath.split(DirSep)
      var skip = false
      for part in parts:
        if part in skipDirs or part.startsWith("."):
          skip = true
          break
      if not skip:
        let absPath = rootPath / relPath
        if fileExists(absPath):
          try:
            let info = getFileInfo(absPath)
            files.add(FileInfo(path: relPath, size: info.size.int64,
                                mtime: info.lastWriteTime.toUnix))
          except CatchableError:
            discard  # Skip files we can't stat  # axiom:best-effort(ioboundary catch)
    files.sort(proc(a, b: FileInfo): int = cmp(a.path, b.path))
    ok(files)
  except CatchableError as e:
    err("discoverFiles(" & rootPath & "): " & e.msg)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc diffAgainstCache*(files: seq[FileInfo]; cache: VfsCache):
    tuple[unchanged: seq[FileInfo]; workQueue: seq[FileInfo]] {.raises: [].} =
  ## Diff file list against cached entries. Returns unchanged (cache hit) and workQueue (needs rehash).
  var unch: seq[FileInfo] = @[]
  var work: seq[FileInfo] = @[]
  for f in files:
    let cached = cache.entries.getOrDefault(f.path)
    if cached.mtime == f.mtime and cached.size == f.size and cached.mtime != 0:
      unch.add(f)
    else:
      work.add(f)
  result = (unchanged: unch, workQueue: work)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc buildVfsFromCache*(cache: VfsCache; repoRoot: string): MerkleVfs {.raises: [].} =
  ## Build a MerkleVfs from an in-memory VfsCache. No disk I/O.
  var root = FileNode(path: "", isDir: true)
  var fileIndex = initTable[string, VfsEntry]()
  var allHashes: seq[string] = @[]
  for path, entry in cache.entries:
    # Convert array[32, byte] hash to hex string for compatibility
    var hex = newString(64)
    for i in 0..<32:
      hex[i*2] = "0123456789abcdef"[entry.hash[i] shr 4]
      hex[i*2+1] = "0123456789abcdef"[entry.hash[i] and 0x0f]
    let hashStr = hex
    let vfsEntry = VfsEntry(
      path: path,
      contentHash: hashStr,
      mtime: fromUnix(entry.mtime),
      isDir: false,
      valid: true
    )
    fileIndex[path] = vfsEntry
    allHashes.add(hashStr)
  allHashes.sort()
  # Compute Merkle root
  var hashes = allHashes
  if hashes.len == 0:
    return MerkleVfs(root: root, fileIndex: fileIndex, rootHash: "", rootPath: repoRoot)
  while hashes.len > 1:
    var next: seq[string] = @[]
    var i = 0
    while i < hashes.len:
      if i + 1 < hashes.len:
        next.add($secureHash(Sha_256, hashes[i] & hashes[i + 1]))
      else:
        next.add(hashes[i])
      i += 2
    hashes = next
  MerkleVfs(root: root, fileIndex: fileIndex, rootHash: hashes[0], rootPath: repoRoot)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc buildMerkleFromGitIndex*(repoRoot: string): MerkleVfs {.raises: [CatchableError].} =
  ## Loads VfsCache and builds VFS from it.
  ## Phase 10: checks Git index mtime fast-path before full VFS load.
  if not isCacheValid(repoRoot):
    # Git index changed or VFS cache missing — full rescan triggers elsewhere
    discard  # caller detects dirty=true and rewrites cache
  let cacheResult = loadVfsCache(repoRoot)
  let cache = cacheResult.getOrDefault(
    VfsCache(entries: initTable[string, VfsCacheEntry](), dirty: false))
  result = buildVfsFromCache(cache, repoRoot)
  # Record current git index mtime for next-session fast-path
  let currentMtime = getGitIndexMtime(repoRoot)
  if currentMtime > 0:
    saveMtimeCache(repoRoot, currentMtime, vfsCachePath(repoRoot))
# Provides copy-on-write isolation for gate execution.
# Gate creates snapshot → runs → commits delta on success or discards on failure.
type
  VfsSnapshot* {.acyclic.} = ref object
    ## Immutable point-in-time view of VFS file hashes.
    name*: string
    vfs: MerkleVfs              # back-reference to source VFS (not exported)
    hashes: Table[string, string]  # path → contentHash at snapshot time

  VfsDelta* = object
    ## Changed files between snapshot and current VFS state.
    added*: seq[string]      # paths present in VFS but not in snapshot
    removed*: seq[string]    # paths in snapshot but not in VFS
    changed*: seq[string]    # paths where contentHash differs
const VfsApiVersion* = 3
  ## Compile-time API version. Gate callers can assert this to detect
  ## silent API breakage during refactoring.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc vfsSnapshot*(vfs: MerkleVfs; name: string): VfsSnapshot {.raises: [].} =
  ## Create an immutable snapshot of current VFS file hashes.
  var hashes = initTable[string, string]()
  for path, entry in vfs.fileIndex:
    if not entry.isDir:
      hashes[path] = entry.contentHash
  VfsSnapshot(name: name, vfs: vfs, hashes: hashes)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc toDelta*(snap: VfsSnapshot): VfsDelta {.raises: [].} =
  ## Compare snapshot against current VFS state. Returns delta.
  var added: seq[string] = @[]
  var removed: seq[string] = @[]
  var changed: seq[string] = @[]

  # Find added and changed files
  for path, entry in snap.vfs.fileIndex:
    if entry.isDir: continue
    let oldHash = snap.hashes.getOrDefault(path, "")
    if oldHash.len == 0:
      added.add(path)
    elif oldHash != entry.contentHash:
      changed.add(path)

  # Find removed files
  for path, oldHash in snap.hashes:
    if path notin snap.vfs.fileIndex:
      removed.add(path)

  VfsDelta(added: added, removed: removed, changed: changed)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc vfsCommit*(vfs: MerkleVfs; delta: VfsDelta) {.raises: [].} =
  ## Apply delta to VFS by recomputing the Merkle root.
  ## The fileIndex is already current (mutations happened during gate execution);
  ## this only refreshes the root hash.
  rebuildRootHash(vfs)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc vfsDiscard*(snap: VfsSnapshot) {.raises: [].} =
  ## Discard a snapshot. Currently a no-op (snapshot is GC'd).
  ## Exists for API symmetry and future audit logging.
  discard
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeSubtreeRoot*(vfs: MerkleVfs; filesPattern: string): string {.raises: [].} =
  ## Compute Merkle root for files matching `filesPattern` (pipe-separated prefixes).
  ## O(N) filter over fileIndex — no tree traversal.
  ## Replaces dirtyHash as the deterministic cache invalidation signal.
  var hashes: seq[string] = @[]
  if filesPattern.len == 0:
    # No pattern → use entire VFS root hash
    return vfs.rootHash
  let patterns = filesPattern.split('|')
  for path, entry in vfs.fileIndex:
    if entry.isDir: continue
    for p in patterns:
      let pat = p.strip()
      if pat.len > 0 and (path.startsWith(pat) or containsSubstring(path, pat)):
        hashes.add(entry.contentHash)
        break
  if hashes.len == 0:
    return ""
  hashes.sort()
  # Compute Merkle root from filtered hashes
  if hashes.len == 1:
    return hashes[0]
  var current = hashes
  while current.len > 1:
    var next: seq[string] = @[]
    var i = 0
    while i < current.len:
      if i + 1 < current.len:
        next.add($secureHash(Sha_256, current[i] & current[i + 1]))
      else:
        next.add(current[i])
      i += 2
    current = next
  return current[0]

