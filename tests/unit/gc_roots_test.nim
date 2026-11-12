{.push raises: [CatchableError].}

## GC Roots Unit Tests
## Verifies Nix-model root-based garbage collection for content-addressable store.

import std/[os, sets, strutils, times, unittest]
import core/gate/gc_roots

var testDir: string
var origDir: string

proc setup() =
  origDir = getCurrentDir()
  testDir = getTempDir() / "axiom_gc_roots_test_" & $epochTime().int
  createDir(testDir)
  setCurrentDir(testDir)

proc teardown() =
  setCurrentDir(origDir)
  removeDir(testDir)

suite "GcRoots":
  setup()

  test "registerGcRoot creates file with hashes":
    let hashes = @["abc123", "def456", "ghi789"]
    registerGcRoot("pipeline-001", hashes)
    let gcRootsFile = GcRootsDir / "pipeline-001"
    check fileExists(gcRootsFile)
    let content = readFile(gcRootsFile)
    check "abc123" in content
    check "def456" in content
    check "ghi789" in content

  test "listGcRoots returns registered roots":
    if dirExists(GcRootsDir): removeDir(GcRootsDir)
    initGcRoots()
    registerGcRoot("gate-integrity", @["hash_a"])
    registerGcRoot("pipeline-001", @["hash_b", "hash_c"])
    let roots = listGcRoots()
    check roots.len == 2
    var foundIntegrity = false
    var foundPipeline = false
    for root in roots:
      if root.name == "gate-integrity":
        foundIntegrity = true
        check root.storeHashes.len == 1
        check "hash_a" in root.storeHashes
      if root.name == "pipeline-001":
        foundPipeline = true
        check root.storeHashes.len == 2
    check foundIntegrity
    check foundPipeline

  test "collectLiveHashes aggregates all hashes from all roots":
    if dirExists(GcRootsDir): removeDir(GcRootsDir)
    initGcRoots()
    registerGcRoot("root1", @["h1", "h2"])
    registerGcRoot("root2", @["h2", "h3"])
    let live = collectLiveHashes()
    check live.len == 3  # h1, h2 (deduplicated), h3
    check "h1" in live
    check "h2" in live
    check "h3" in live

  test "removeGcRoot deletes root file":
    if dirExists(GcRootsDir): removeDir(GcRootsDir)
    initGcRoots()
    registerGcRoot("to-delete", @["hash_x"])
    check fileExists(GcRootsDir / "to-delete")
    removeGcRoot("to-delete")
    check not fileExists(GcRootsDir / "to-delete")

  test "sweep removes unreferenced store entries":
    let storeDir = testDir / "store"
    createDir(storeDir / "shard1")
    createDir(storeDir / "shard2")
    writeFile(storeDir / "shard1" / "hash_live", "live content")
    writeFile(storeDir / "shard1" / "hash_dead", "dead content")
    writeFile(storeDir / "shard2" / "hash_also_dead", "also dead")

    var live = initHashSet[string]()
    live.incl("hash_live")
    let deleted = sweep(storeDir, live)
    check deleted == 2
    check fileExists(storeDir / "shard1" / "hash_live")
    check not fileExists(storeDir / "shard1" / "hash_dead")
    check not fileExists(storeDir / "shard2" / "hash_also_dead")
    check dirExists(storeDir / "shard1")
    check not dirExists(storeDir / "shard2")

  test "sweep skips _tmp and _gcroots prefixed dirs":
    let storeDir = testDir / "store2"
    createDir(storeDir / "_tmp")
    createDir(storeDir / "_gcroots")
    createDir(storeDir / "shard1")
    writeFile(storeDir / "_tmp" / "temp_file", "temp")
    writeFile(storeDir / "_gcroots" / "root_file", "root")
    writeFile(storeDir / "shard1" / "orphan", "orphan")

    var live = initHashSet[string]()
    let deleted = sweep(storeDir, live)
    check deleted == 1
    check fileExists(storeDir / "_tmp" / "temp_file")
    check fileExists(storeDir / "_gcroots" / "root_file")

  test "gc performs full mark-and-sweep cycle":
    if dirExists(GcRootsDir): removeDir(GcRootsDir)
    initGcRoots()
    registerGcRoot("active-pipeline", @["kept_hash"])

    let storeDir = testDir / "gc_store"
    createDir(storeDir / "ab")
    writeFile(storeDir / "ab" / "kept_hash", "keep me")
    writeFile(storeDir / "ab" / "removed_hash", "delete me")

    let deleted = gc(storeDir)
    check deleted == 1
    check fileExists(storeDir / "ab" / "kept_hash")
    check not fileExists(storeDir / "ab" / "removed_hash")

teardown()
