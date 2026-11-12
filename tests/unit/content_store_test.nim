## Unit tests for ContentStore — content-addressable store round-trip,
## existence checks, idempotency, and stats.

import std/[unittest, os]
import core/gate/content_store

suite "ContentStore":
  test "put and get round-trip preserves content":
    let tmpDir = getTempDir() / "axiom_cs_test_" & $getCurrentProcessId()
    let storeRoot = tmpDir / "store"
    let store = initStore(storeRoot)

    let content = "hello axiom world"
    let hash = store.put(content)

    # Hash returned must match manual computation
    check hash == computeContentHash(content)
    # Content retrievable by hash
    check store.get(hash) == content
    # File exists on disk
    check store.exists(hash)

    removeDir(tmpDir)

  test "exists returns false for missing hash":
    let tmpDir = getTempDir() / "axiom_cs_miss_" & $getCurrentProcessId()
    let store = initStore(tmpDir / "store")

    check not store.exists("deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
    check not store.exists("aa")

    removeDir(tmpDir)

  test "idempotent put stores same content twice without error":
    let tmpDir = getTempDir() / "axiom_cs_idem_" & $getCurrentProcessId()
    let store = initStore(tmpDir / "store")

    let content = "idempotent data"
    let h1 = store.put(content)
    let h2 = store.put(content)

    # Same hash both times
    check h1 == h2
    # Content still retrievable
    check store.get(h1) == content

    removeDir(tmpDir)

  test "different content produces different hashes":
    let tmpDir = getTempDir() / "axiom_cs_diff_" & $getCurrentProcessId()
    let store = initStore(tmpDir / "store")

    let h1 = store.put("alpha")
    let h2 = store.put("beta")
    check h1 != h2

    removeDir(tmpDir)

  test "storeStats counts inserted items":
    let tmpDir = getTempDir() / "axiom_cs_stats_" & $getCurrentProcessId()
    let store = initStore(tmpDir / "store")

    discard store.put("first")
    discard store.put("second")
    discard store.put("third")

    let stats = store.storeStats()
    check stats.count == 3
    # Total size = len("first") + len("second") + len("third")
    check stats.totalSize == 5 + 6 + 5

    removeDir(tmpDir)

  test "putChecked rejects mismatched expected hash":
    let tmpDir = getTempDir() / "axiom_cs_chk_" & $getCurrentProcessId()
    let store = initStore(tmpDir / "store")

    let content = "checked content"
    let wrongHash = "0000000000000000000000000000000000000000000000000000000000000000"

    var raised = false
    try:
      discard store.putChecked(content, wrongHash)
    except ContentCollisionDefect:
      raised = true
    check raised

    removeDir(tmpDir)

  test "computeContentHash is deterministic":
    let a = computeContentHash("deterministic input")
    let b = computeContentHash("deterministic input")
    check a == b
    # Different input produces different hash
    check a != computeContentHash("different input")
