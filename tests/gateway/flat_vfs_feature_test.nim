{.push raises: [CatchableError].}
## BDD feature test for flat_vfs.feature
## Verifies FlatVfs sorted-seq VFS: hash determinism, binary search,
## file counting, and Merkle root computation.

import std/unittest
import std/tables
import std/algorithm
import core/gate/flat_vfs

func makeEntry(path, contentHash: string; isDir = false): FlatVfsEntry =
  FlatVfsEntry(
    pathHash: hashPath(path),
    path: path,
    contentHash: contentHash,
    mtime: 0,
    isDir: isDir
  )

func sortedEntries(entries: openArray[FlatVfsEntry]): seq[FlatVfsEntry] =
  result = @entries
  result.sort(proc(a, b: FlatVfsEntry): int {.raises: [].} = cmp(a.pathHash, b.pathHash))

suite "FlatVfs — hashPath determinism":

  test "hashPath returns same value for same input":
    let h1 = hashPath("src/core/gate/flat_vfs.nim")
    let h2 = hashPath("src/core/gate/flat_vfs.nim")
    check h1 == h2

  test "hashPath returns different values for different inputs":
    let h1 = hashPath("src/core/gate/flat_vfs.nim")
    let h2 = hashPath("src/core/gate/gate_memo.nim")
    check h1 != h2

  test "hashPath returns non-zero for non-empty string":
    check hashPath("any/path") != 0'u64

  test "hashPath returns 0 for empty string":
    check hashPath("") == 0xcbf29ce484222325'u64  # FNV offset basis unchanged for empty

suite "FlatVfs — findEntry and binary search":

  test "findEntry locates an existing entry":
    let entries = sortedEntries([
      makeEntry("a.nim", "aaa"),
      makeEntry("b.nim", "bbb"),
      makeEntry("c.nim", "ccc"),
    ])
    var vfs = FlatVfs(entries: entries, projectRoot: "/tmp")
    let h = findEntry(vfs, "b.nim")
    check h != VfsHandle(nil)
    check pathOf(h) == "b.nim"
    check contentHashOf(h) == "bbb"

  test "findEntry returns nil handle for missing path":
    let entries = sortedEntries([
      makeEntry("a.nim", "aaa"),
      makeEntry("b.nim", "bbb"),
    ])
    var vfs = FlatVfs(entries: entries, projectRoot: "/tmp")
    let h = findEntry(vfs, "z.nim")
    check h == VfsHandle(nil)

  test "findEntry on empty vfs returns nil handle":
    var vfs = FlatVfs(entries: @[], projectRoot: "/tmp")
    let h = findEntry(vfs, "anything.nim")
    check h == VfsHandle(nil)

  test "nil handle accessors return defaults":
    check pathOf(VfsHandle(nil)) == ""
    check contentHashOf(VfsHandle(nil)) == ""
    check hashOf(VfsHandle(nil)) == 0'u64
    check isDirOf(VfsHandle(nil)) == false

suite "FlatVfs — fileCount":

  test "fileCount excludes directories":
    let entries = sortedEntries([
      makeEntry("dir/", "", isDir = true),
      makeEntry("a.nim", "aaa"),
      makeEntry("b.nim", "bbb"),
    ])
    var vfs = FlatVfs(entries: entries, projectRoot: "/tmp")
    check fileCount(vfs) == 2

  test "fileCount returns 0 for empty vfs":
    var vfs = FlatVfs(entries: @[], projectRoot: "/tmp")
    check fileCount(vfs) == 0

suite "FlatVfs — collectFilesMatching":

  test "collectFilesMatching with prefix pattern":
    let entries = sortedEntries([
      makeEntry("src/core/flat_vfs.nim", "h1"),
      makeEntry("src/core/gate_memo.nim", "h2"),
      makeEntry("tests/unit/flat_vfs_test.nim", "h3"),
    ])
    var vfs = FlatVfs(entries: entries, projectRoot: "/tmp")
    let matched = collectFilesMatching(vfs, "src/")
    check matched.len == 2

  test "collectFilesMatching with empty pattern returns all files":
    let entries = sortedEntries([
      makeEntry("a.nim", "h1"),
      makeEntry("b.nim", "h2"),
    ])
    var vfs = FlatVfs(entries: entries, projectRoot: "/tmp")
    let matched = collectFilesMatching(vfs, "")
    check matched.len == 2

suite "FlatVfs — collectChangedFiles":

  test "collectChangedFiles detects new files":
    let entries1 = sortedEntries([makeEntry("a.nim", "h1")])
    let entries2 = sortedEntries([makeEntry("a.nim", "h1"), makeEntry("b.nim", "h2")])
    var vfs1 = FlatVfs(entries: entries1, projectRoot: "/tmp")
    var vfs2 = FlatVfs(entries: entries2, projectRoot: "/tmp")
    let changed = collectChangedFiles(vfs2, vfs1)
    check changed.len == 1
    check changed[0] == "b.nim"

  test "collectChangedFiles detects content changes":
    let entries1 = sortedEntries([makeEntry("a.nim", "old_hash")])
    let entries2 = sortedEntries([makeEntry("a.nim", "new_hash")])
    var vfs1 = FlatVfs(entries: entries1, projectRoot: "/tmp")
    var vfs2 = FlatVfs(entries: entries2, projectRoot: "/tmp")
    let changed = collectChangedFiles(vfs2, vfs1)
    check changed.len == 1

  test "collectChangedFiles returns empty for identical snapshots":
    let entries = sortedEntries([makeEntry("a.nim", "h1")])
    var vfs1 = FlatVfs(entries: entries, projectRoot: "/tmp")
    var vfs2 = FlatVfs(entries: entries, projectRoot: "/tmp")
    let changed = collectChangedFiles(vfs2, vfs1)
    check changed.len == 0

suite "FlatVfs — getMerkleRoot":

  test "getMerkleRoot is deterministic":
    let entries = sortedEntries([
      makeEntry("a.nim", "aaa"),
      makeEntry("b.nim", "bbb"),
    ])
    var vfs = FlatVfs(entries: entries, projectRoot: "/tmp")
    let r1 = getMerkleRoot(vfs)
    let r2 = getMerkleRoot(vfs)
    check r1 == r2
    check r1.len > 0

  test "getMerkleRoot returns empty for no files":
    var vfs = FlatVfs(entries: @[], projectRoot: "/tmp")
    check getMerkleRoot(vfs) == ""

  test "getMerkleRoot returns the single hash for one file":
    let entries = sortedEntries([makeEntry("only.nim", "single_hash_value")])
    var vfs = FlatVfs(entries: entries, projectRoot: "/tmp")
    check getMerkleRoot(vfs) == "single_hash_value"

suite "FlatVfs — VfsHandle equality":

  test "VfsHandle nil equals nil":
    check VfsHandle(nil) == VfsHandle(nil)

  test "VfsHandle non-nil differs from nil":
    let entries = sortedEntries([makeEntry("a.nim", "h1")])
    var vfs = FlatVfs(entries: entries, projectRoot: "/tmp")
    let h = findEntry(vfs, "a.nim")
    check h != VfsHandle(nil)

{.pop.}
