{.push raises: [CatchableError].}

## Tests for Merkle VFS — In-Memory Virtual File System
##
## Verifies: buildVfs, getFileHash, getFilesMatching, fileCount,
## markDirty, rebuildRootHash, Merkle root determinism.

import std/unittest
import std/os
import std/tables
import std/options
import std/strutils
import core/gate/merkle_vfs
import core/gate/file_hash_cache  # for VfsCache, VfsCacheEntry, loadVfsCache, flushCache
import core/gate/vfs_hasher       # for hashFile, parallelHash

suite "Merkle VFS":
  setup:
    # Create a temporary directory with test files
    let tmpDir = getTempDir() / "axiom_vfs_test_" & $getCurrentProcessId()
    createDir(tmpDir)
    createDir(tmpDir / "src")
    writeFile(tmpDir / "src" / "a.nim", "echo \"hello\"")
    writeFile(tmpDir / "src" / "b.nim", "echo \"world\"")
    writeFile(tmpDir / "README.md", "# Test")

  teardown:
    removeDir(tmpDir)

  test "buildVfs indexes all files":
    let vfs = buildVfs(tmpDir)
    check vfs.fileCount() == 3
    check vfs.fileIndex.len >= 3

  test "getFileHash returns hash for existing file":
    let vfs = buildVfs(tmpDir)
    let h = vfs.getFileHash("src/a.nim")
    check isSome(h)
    check get(h).len > 0

  test "getFileHash returns none for missing file":
    let vfs = buildVfs(tmpDir)
    let h = vfs.getFileHash("nonexistent.nim")
    check isNone(h)

  test "getFilesMatching returns all files for empty pattern":
    let vfs = buildVfs(tmpDir)
    let files = vfs.getFilesMatching("")
    check files.len == 3

  test "getFilesMatching filters by pattern":
    let vfs = buildVfs(tmpDir)
    let nimFiles = vfs.getFilesMatching(".nim")
    check nimFiles.len == 2

  test "getFilesMatching supports pipe-separated patterns":
    let vfs = buildVfs(tmpDir)
    let files = vfs.getFilesMatching(".nim|README")
    check files.len == 3

  test "Merkle root is deterministic":
    let vfs1 = buildVfs(tmpDir)
    let vfs2 = buildVfs(tmpDir)
    check vfs1.vfsRootHash() == vfs2.vfsRootHash()

  test "Merkle root changes when file content changes":
    let vfs1 = buildVfs(tmpDir)
    writeFile(tmpDir / "src" / "a.nim", "echo \"modified\"")
    let vfs2 = buildVfs(tmpDir)
    check vfs1.vfsRootHash() != vfs2.vfsRootHash()

  test "markDirty updates file hash":
    let vfs = buildVfs(tmpDir)
    let oldHash = get(vfs.getFileHash("src/a.nim"))
    writeFile(tmpDir / "src" / "a.nim", "echo \"dirty\"")
    vfs.markDirty(tmpDir / "src" / "a.nim")
    # Note: markDirty expects absolute path

  test "rebuildRootHash recomputes after modifications":
    let vfs = buildVfs(tmpDir)
    let oldRoot = vfs.vfsRootHash()
    writeFile(tmpDir / "src" / "a.nim", "echo \"rebuilt\"")
    # markDirty uses fileIndex keys (relative paths)
    vfs.markDirty("src/a.nim")
    vfs.rebuildRootHash()
    # Root should change after content modification
    check vfs.vfsRootHash() != oldRoot

  test "fileCount excludes directories":
    let vfs = buildVfs(tmpDir)
    # Should count 3 files, not directories
    check vfs.fileCount() == 3

suite "VFS Pipeline":
  setup:
    let tmpDir = getTempDir() / "axiom_pipeline_test_" & $getCurrentProcessId()
    createDir(tmpDir)
    createDir(tmpDir / "src")
    writeFile(tmpDir / "src" / "a.nim", "echo \"hello\"")
    writeFile(tmpDir / "src" / "b.nim", "echo \"world\"")
    writeFile(tmpDir / "README.md", "# Test")
    # Ensure cache dir exists
    createDir(tmpDir / ".axiom" / "cache")

  teardown:
    removeDir(tmpDir)

  test "discoverFiles finds all files recursively":
    let files = discoverFiles(tmpDir)
    check files.len == 3
    # Verify paths are relative
    for f in files:
      check not f.path.startsWith("/")
      check f.size > 0

  test "discoverFiles skips hidden directories":
    createDir(tmpDir / ".hidden")
    writeFile(tmpDir / ".hidden" / "secret.nim", "secret")
    let files = discoverFiles(tmpDir)
    check files.len == 3  # .hidden excluded

  test "discoverFiles skips nimcache":
    createDir(tmpDir / "nimcache")
    writeFile(tmpDir / "nimcache" / "cached.nim", "cached")
    let files = discoverFiles(tmpDir)
    check files.len == 3  # nimcache excluded

  test "discoverFiles returns deterministic order":
    let files1 = discoverFiles(tmpDir)
    let files2 = discoverFiles(tmpDir)
    check files1.len == files2.len
    for i in 0..<files1.len:
      check files1[i].path == files2[i].path

  test "diffAgainstCache detects new files":
    let files = discoverFiles(tmpDir)
    var emptyCache = VfsCache(entries: initTable[string, VfsCacheEntry](), dirty: false)
    let (unchanged, workQueue) = diffAgainstCache(files, emptyCache)
    check unchanged.len == 0
    check workQueue.len == 3

  test "diffAgainstCache detects unchanged files":
    let files = discoverFiles(tmpDir)
    var cache = VfsCache(entries: initTable[string, VfsCacheEntry](), dirty: false)
    # Populate cache with matching entries
    for f in files:
      cache.entries[f.path] = VfsCacheEntry(mtime: f.mtime, size: f.size, hash: default(array[32, byte]))
    let (unchanged, workQueue) = diffAgainstCache(files, cache)
    check unchanged.len == 3
    check workQueue.len == 0

  test "hashFile computes consistent SHA-256":
    let absPath = tmpDir / "src" / "a.nim"
    let h1 = hashFile(absPath)
    let h2 = hashFile(absPath)
    check h1 == h2
    check h1.len == 64  # hex string

  test "hashFile raises IOError for missing file":
    expect IOError:
      discard hashFile(tmpDir / "nonexistent.nim")

  test "VfsCache binary round-trip":
    var cache = VfsCache(entries: initTable[string, VfsCacheEntry](), dirty: true)
    # Add a test entry
    var testHash: array[32, byte]
    for i in 0..<32: testHash[i] = byte(i)
    cache.entries["src/a.nim"] = VfsCacheEntry(mtime: 1000, size: 42, hash: testHash)
    cache.entries["README.md"] = VfsCacheEntry(mtime: 2000, size: 100, hash: testHash)
    # Flush to disk
    flushCache(cache, tmpDir)
    check not cache.dirty
    # Load from disk
    let loaded = loadVfsCache(tmpDir)
    check loaded.entries.len == 2
    check loaded.entries["src/a.nim"].mtime == 1000
    check loaded.entries["src/a.nim"].size == 42
    check loaded.entries["README.md"].mtime == 2000

  test "buildVfsFromCache produces valid MerkleVfs":
    var cache = VfsCache(entries: initTable[string, VfsCacheEntry](), dirty: false)
    var testHash: array[32, byte]
    for i in 0..<32: testHash[i] = byte(i)
    cache.entries["src/a.nim"] = VfsCacheEntry(mtime: 1000, size: 42, hash: testHash)
    let vfs = buildVfsFromCache(cache, tmpDir)
    check vfs.fileCount() == 1
    check vfs.rootHash.len > 0
    check isSome(vfs.getFileHash("src/a.nim"))

{.pop.}
