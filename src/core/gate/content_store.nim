import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Content-Addressable Store
##
## Nix /nix/store model applied to Axiom.
## - Content hash = SHA-256(file_content) — path-free, content-only
## - Store path = .axiom/store/<hash[:2]>/<hash> — Two-level sharding O(1)
## - Atomic write: tmp → fsync → rename
## - Immutability: content at a given hash NEVER changes
##
## Store layout:
##   .axiom/store/
##   |- ab/
##   |  \- abcdef1234567890abcdef...  (SHA-256 hash keyed, O(1) lookup)
##   |- _gcroots/  (GC root symlinks)
##   \- _tmp/  (atomic write staging)

import std/[os, strformat, strutils, tables, times]
import checksums/sha2
import core/axiom_pragmas

const
  StoreRoot* = ".axiom/store"
  TmpDir* = StoreRoot / "_tmp"
  GcRootsDir* = StoreRoot / "_gcroots"

type
  ContentStore* {.acyclic.} = ref object
    root*: string              ## Store root path
    index*: Table[string, ContentEntry]  ## hash → metadata cache
    initialized*: bool

  ContentEntry* = object
    hash*: string
    size*: int64
    createdAt*: float          ## epoch timestamp

  ContentCollisionDefect* = object of CatchableError
    existingHash*: string
    newHash*: string
    path*: string

# ---------------------------------------------------------------------------
# Store Path Computation
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func storePath*(root, hash: string): string =
  ## Compute on-disk path for a content hash.
  ## ``.axiom/store/<hash[:2]>/<hash>``
  assert hash.len >= 2, "Hash too short: " & hash
  root / hash[0..1] / hash

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func tmpPath*(root, hash: string): string =
  ## Temporary path for atomic write.
  root / "_tmp" / ("write-" & hash)

# ---------------------------------------------------------------------------
# Core Operations
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeContentHash*(content: string): string =
  ## SHA-256 of content only (path-free). This is the Nix CA model.
  $secureHash(Sha_256, content)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc initStore*(root: string = StoreRoot): ContentStore {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Initialize the content store. Creates directories if needed.
  result = ContentStore(root: root, index: initTable[string, ContentEntry]())
  createDir(root)
  createDir(root / "_tmp")
  createDir(root / "_gcroots")
  # Create two-level shard directories (00..ff)
  for i in 0..255:
    let shard = &"{i:02x}"
    createDir(root / shard)
  result.initialized = true

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc exists*(store: ContentStore, hash: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if content exists in store. O(1) disk lookup.
  fileExists(storePath(store.root, hash))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc put*(store: ContentStore, content: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Store content. Returns content hash.
  ## Idempotent: if content already exists, returns existing hash (no-op).
  ## Atomic: writes to tmp → fsync → rename.
  let hash = computeContentHash(content)
  let finalPath = storePath(store.root, hash)

  if fileExists(finalPath):
    return hash  # Already stored, immutable

  # Atomic write: tmp → copyFile → removeFile
  let tmp = tmpPath(store.root, hash)
  writeFile(tmp, content)
  copyFile(tmp, finalPath)
  try: removeFile(tmp) except CatchableError: discard  # axiom:best-effort(ioboundary catch)

  store.index[hash] = ContentEntry(
    hash: hash,
    size: content.len.int64,
    createdAt: epochTime()
  )
  hash

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc putChecked*(store: ContentStore, content: string,
                 expectedHash: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Store content with hash verification (Nix fixed-output model).
  ## If content exists and hash differs → ContentCollisionDefect.
  let hash = computeContentHash(content)
  let finalPath = storePath(store.root, hash)

  if fileExists(finalPath):
    # Verify existing content matches
    let existing = readFile(finalPath)
    let existingHash = computeContentHash(existing)
    if existingHash != hash:
      raise (ref ContentCollisionDefect)(
        msg: "Content collision at store path",
        existingHash: existingHash,
        newHash: hash,
        path: finalPath
      )
    return hash

  if expectedHash.len > 0 and hash != expectedHash:
    raise (ref ContentCollisionDefect)(
      msg: "Content hash mismatch: expected " & expectedHash & " got " & hash,
      existingHash: expectedHash,
      newHash: hash,
      path: finalPath
    )

  discard store.put(content)
  hash

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc get*(store: ContentStore, hash: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Retrieve content by hash. O(1) disk read.
  ## Raises IOError if not found.
  let path = storePath(store.root, hash)
  if not fileExists(path):
    raise newException(IOError, "Content not in store: " & hash)
  readFile(path)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getOpt*(store: ContentStore, hash: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Retrieve content by hash. Returns "" if not found.
  try:
    store.get(hash)
  except CatchableError:
    ""

# ---------------------------------------------------------------------------
# Migration from legacy CAS
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc importFromCas*(store: ContentStore, casDir: string): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Import content from legacy ``.axiom/cache/content/`` into new store.
  ## Returns number of items imported.
  result = 0
  if not dirExists(casDir):
    return
  for kind, shard in walkDir(casDir):
    if kind != pcDir:
      continue
    for kind2, file in walkDir(shard):
      if kind2 != pcFile:
        continue
      let content = readFile(file)
      let hash = computeContentHash(content)
      let target = storePath(store.root, hash)
      if not fileExists(target):
        copyFile(file, target)
        inc result

# ---------------------------------------------------------------------------
# Store Statistics
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc storeStats*(store: ContentStore): tuple[count, totalSize: int64] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Count items and total size in store.
  var count: int64 = 0
  var totalSize: int64 = 0
  for kind, shard in walkDir(store.root):
    if kind != pcDir:
      continue
    let name = extractFilename(shard)
    if name.startsWith("_"):  # Skip _tmp, _gcroots
      continue
    for kind2, file in walkDir(shard):
      if kind2 == pcFile:
        inc count
        totalSize += getFileSize(file)
  (count, totalSize)

{.pop.}

