import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

import core/crypto/hash_kernel
import core/gate/file_hash_cache
import std/algorithm
import std/strutils
import std/tables
type
  FlatVfsEntry* = object
    ## Single file entry in the flat VFS.
    pathHash*: uint64       # precomputed hash for binarySearch
    path*: string           # relative path (e.g., "src/core/gate/gate_memo.nim")
    contentHash*: string    # SHA-256 of file content
    mtime*: int64           # Unix timestamp
    isDir*: bool

  FlatVfs* = object
    ## Flat sorted-seq VFS. Entries sorted by pathHash for binary search.
    entries*: seq[FlatVfsEntry]
    projectRoot*: string

  VfsHandle* = distinct pointer
    ## Opaque handle — ARC-invisible, zero-cost.
    ## Substrate-agnostic: works for sorted seq, HAMT, or any future structure.

  VfsCursor* = object
    ## Read-only cursor for iteration. Prevents accidental mutation.
    vfs: ptr FlatVfs
    pos: int
func `==`*(a, b: VfsHandle): bool {.inline, raises: [].} =
  ## Equality for distinct pointer type.
  pointer(a) == pointer(b)
# ─── Hash helpers ──────────────────────────────────────────────────────────

func hashPath*(path: string): uint64 {.inline, raises: [].} =
  ## FNV-1a hash for path strings. Fast, deterministic, good distribution.
  var h: uint64 = 0xcbf29ce484222325'u64  # FNV offset basis
  for c in path:
    h = h xor uint64(c.uint8)
    h = h * 0x100000001b3'u64  # FNV prime
  h
func findEntry*(vfs: FlatVfs; path: string): VfsHandle {.inline, raises: [].} =
  ## Binary search by pathHash. Returns opaque VfsHandle.
  ## Returns nil handle if not found.
  let targetHash = hashPath(path)
  var lo = 0
  var hi = vfs.entries.len - 1
  while lo <= hi:
    let mid = (lo + hi) shr 1
    let cmp = cmp(vfs.entries[mid].pathHash, targetHash)
    if cmp == 0:
      # Hash collision possible — linear scan for exact match
      var i = mid
      while i >= 0 and vfs.entries[i].pathHash == targetHash:
        if vfs.entries[i].path == path:
          return cast[VfsHandle](addr vfs.entries[i])
        dec i
      i = mid + 1
      while i < vfs.entries.len and vfs.entries[i].pathHash == targetHash:
        if vfs.entries[i].path == path:
          return cast[VfsHandle](addr vfs.entries[i])
        inc i
      return VfsHandle(nil)
    elif cmp < 0:
      lo = mid + 1
    else:
      hi = mid - 1
  VfsHandle(nil)
func hashOf*(h: VfsHandle): uint64 {.inline, raises: [].} =
  ## Accessor: get pathHash from opaque handle. No coupling to internal repr.
  if h == VfsHandle(nil): return 0
  cast[ptr FlatVfsEntry](h)[].pathHash
func pathOf*(h: VfsHandle): string {.inline, raises: [].} =
  ## Accessor: get path from opaque handle.
  if h == VfsHandle(nil): return ""
  cast[ptr FlatVfsEntry](h)[].path
func contentHashOf*(h: VfsHandle): string {.inline, raises: [].} =
  ## Accessor: get content hash from opaque handle.
  if h == VfsHandle(nil): return ""
  cast[ptr FlatVfsEntry](h)[].contentHash
func isDirOf*(h: VfsHandle): bool {.inline, raises: [].} =
  ## Accessor: check if entry is a directory.
  if h == VfsHandle(nil): return false
  cast[ptr FlatVfsEntry](h)[].isDir
func collectChangedFiles*(vfs: FlatVfs; other: FlatVfs): seq[string] {.raises: [].} =
  ## Find files that differ between two VFS snapshots.
  result = @[]
  for entry in vfs.entries:
    if entry.isDir: continue
    let otherHandle = findEntry(other, entry.path)
    if otherHandle == VfsHandle(nil):
      result.add(entry.path)  # new file
    elif contentHashOf(otherHandle) != entry.contentHash:
      result.add(entry.path)  # changed
func collectFilesMatching*(vfs: FlatVfs; pattern: string): seq[string] {.raises: [].} =
  ## Return paths matching a substring pattern (pipe-separated).
  result = @[]
  let patterns = pattern.split('|')
  for entry in vfs.entries:
    if entry.isDir: continue
    if pattern.len == 0:
      result.add(entry.path)
    else:
      for p in patterns:
        let pat = p.strip()
        if pat.len > 0 and (entry.path.startsWith(pat) or (pat in entry.path)):
          result.add(entry.path)
          break
  result.sort()
func fileCount*(vfs: FlatVfs): int {.raises: [].} =
  ## Count of regular files.
  for entry in vfs.entries:
    if not entry.isDir:
      inc result
func getMerkleRoot*(vfs: FlatVfs): string {.raises: [].} =
  ## Compute Merkle root from all file hashes. Deterministic (sorted).
  var hashes: seq[string] = @[]
  for entry in vfs.entries:
    if not entry.isDir and entry.contentHash.len > 0:
      hashes.add(entry.contentHash)
  hashes.sort()
  if hashes.len == 0: return ""
  if hashes.len == 1: return hashes[0]
  var current = hashes
  while current.len > 1:
    var next: seq[string] = @[]
    var i = 0
    while i < current.len:
      if i + 1 < current.len:
        next.add(hash_kernel.sha256Hex(current[i] & current[i + 1]))
      else:
        next.add(current[i])
      i += 2
    current = next
  current[0]
func buildFlatVfs*(cache: VfsCache; projectRoot: string): FlatVfs {.raises: [].} =
  ## Build a FlatVfs from VfsCache. No disk I/O.
  var entries: seq[FlatVfsEntry] = @[]
  for path, entry in cache.entries:
    var hex = newString(64)
    for i in 0..<32:
      hex[i*2] = "0123456789abcdef"[entry.hash[i] shr 4]
      hex[i*2+1] = "0123456789abcdef"[entry.hash[i] and 0x0f]
    entries.add(FlatVfsEntry(
      pathHash: hashPath(path),
      path: path,
      contentHash: hex,
      mtime: entry.mtime,
      isDir: false
    ))
  entries.sort(proc(a, b: FlatVfsEntry): int {.raises: [].} = cmp(a.pathHash, b.pathHash))
  FlatVfs(entries: entries, projectRoot: projectRoot)
func initCursor*(vfs: ptr FlatVfs): VfsCursor {.raises: [].} =
  VfsCursor(vfs: vfs, pos: 0)
func next*(cursor: var VfsCursor): VfsHandle {.raises: [].} =
  ## Advance cursor and return current entry as VfsHandle.
  if cursor.pos >= cursor.vfs[].entries.len:
    return VfsHandle(nil)
  result = cast[VfsHandle](addr cursor.vfs[].entries[cursor.pos])
  inc cursor.pos
{.pop.}  # noSideEffect
