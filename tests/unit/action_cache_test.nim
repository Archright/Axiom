{.push raises: [CatchableError].}

## Action Cache Unit Tests
## Verifies Bazel-model action cache: store, lookup, invalidate, verify.

import std/[os, options, strutils, tables, times, unittest]
import gate/action_cache

var testDir: string
var origDir: string

proc setup() =
  origDir = getCurrentDir()
  testDir = getTempDir() / "axiom_action_cache_test_" & $epochTime().int
  createDir(testDir)
  setCurrentDir(testDir)

proc teardown() =
  setCurrentDir(origDir)
  removeDir(testDir)

suite "ActionCache":
  setup()

  test "initActionCache creates root directory":
    let cacheDir = testDir / "cache_dir_a"
    let cache = initActionCache(cacheDir)
    check dirExists(cacheDir)
    check cache.root == cacheDir

  test "cachePath computes shard layout correctly":
    let cacheDir = testDir / "cache_dir_b"
    let cache = initActionCache(cacheDir)
    let path = cache.cachePath("abcdef1234567890")
    check path.endsWith("abcdef1234567890")
    check path.endsWith("ab/abcdef1234567890")

  test "store and lookup round-trip preserves all fields":
    let cacheDir = testDir / "cache_dir_c"
    let cache = initActionCache(cacheDir)
    let key = "test_roundtrip_key_aabbccdd"
    let result = ActionResult(
      ok: true,
      stdout: "build succeeded",
      stderr: "",
      exitCode: 0,
      outputHashes: {"build/main": "out_hash_1", "build/lib": "out_hash_2"}.toTable,
      inputHashes: {"src/main.nim": "in_hash_1"}.toTable,
      pathManifestHash: "toolchain_v3",
      cachedAt: 0.0
    )
    cache.store(key, result)

    let found = cache.lookup(key)
    check found.isSome
    let loaded = found.get()
    check loaded.ok == true
    check loaded.stdout == "build succeeded"
    check loaded.stderr == ""
    check loaded.exitCode == 0
    check loaded.outputHashes["build/main"] == "out_hash_1"
    check loaded.outputHashes["build/lib"] == "out_hash_2"
    check loaded.inputHashes["src/main.nim"] == "in_hash_1"
    check loaded.pathManifestHash == "toolchain_v3"

  test "lookup returns None for missing key":
    let cacheDir = testDir / "cache_dir_d"
    let cache = initActionCache(cacheDir)
    let found = cache.lookup("nonexistent_key_12345678")
    check found.isNone

  test "invalidate removes cached entry":
    let cacheDir = testDir / "cache_dir_e"
    let cache = initActionCache(cacheDir)
    let key = "key_to_invalidate_aabbcc"
    cache.store(key, ActionResult(ok: true, exitCode: 0))
    check cache.lookup(key).isSome

    cache.invalidate(key)
    check cache.lookup(key).isNone

  test "invalidate is safe on non-existent key":
    let cacheDir = testDir / "cache_dir_f"
    let cache = initActionCache(cacheDir)
    # Should not raise
    cache.invalidate("never_stored_key_aabbccdd")

  test "storing different keys produces independent entries":
    let cacheDir = testDir / "cache_dir_g"
    let cache = initActionCache(cacheDir)
    let key1 = "key_alpha_123456789012345"
    let key2 = "key_beta_abcdef1234567890"
    cache.store(key1, ActionResult(ok: true, stdout: "alpha", exitCode: 0))
    cache.store(key2, ActionResult(ok: false, stdout: "beta", exitCode: 1))

    let r1 = cache.lookup(key1).get()
    let r2 = cache.lookup(key2).get()
    check r1.stdout == "alpha"
    check r1.exitCode == 0
    check r2.stdout == "beta"
    check r2.exitCode == 1

  test "store overwrites existing entry":
    let cacheDir = testDir / "cache_dir_h"
    let cache = initActionCache(cacheDir)
    let key = "overwrite_key_123456789012"
    cache.store(key, ActionResult(ok: false, stdout: "old", exitCode: 1))
    cache.store(key, ActionResult(ok: true, stdout: "new", exitCode: 0))

    let loaded = cache.lookup(key).get()
    check loaded.ok == true
    check loaded.stdout == "new"
    check loaded.exitCode == 0

  test "verifyOutputs returns true when all outputs exist":
    let cacheDir = testDir / "cache_dir_i"
    let cache = initActionCache(cacheDir)
    let key = "verify_key_abc123def456ghi"
    let storeDir = testDir / "store_true"
    createDir(storeDir)

    cache.store(key, ActionResult(
      ok: true,
      exitCode: 0,
      outputHashes: {"out/file1": "live_hash", "out/file2": "also_live"}.toTable
    ))
    writeFile(storeDir / "live_hash", "content")
    writeFile(storeDir / "also_live", "content")

    let storeExists = proc(h: string): bool =
      fileExists(storeDir / h)
    check cache.verifyOutputs(key, storeExists) == true

  test "verifyOutputs returns false when any output missing":
    let cacheDir = testDir / "cache_dir_j"
    let cache = initActionCache(cacheDir)
    let key = "verify_missing_abc123def45"
    let storeDir = testDir / "store_false"
    createDir(storeDir)

    cache.store(key, ActionResult(
      ok: true,
      exitCode: 0,
      outputHashes: {"out/file1": "exists_hash", "out/file2": "gone_hash"}.toTable
    ))
    writeFile(storeDir / "exists_hash", "content")

    let storeExists = proc(h: string): bool =
      fileExists(storeDir / h)
    check cache.verifyOutputs(key, storeExists) == false

  test "verifyOutputs returns false for missing key":
    let cacheDir = testDir / "cache_dir_k"
    let cache = initActionCache(cacheDir)
    let storeExists = proc(h: string): bool = true
    check cache.verifyOutputs("nonexistent_key_12345678", storeExists) == false

teardown()
