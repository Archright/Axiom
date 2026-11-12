{.push raises: [CatchableError].}

## Hermetic Cache Key Test — Validates unified CAS+Memo cache key system.
## Verifies determinism, invalidation on source/binary/build-env changes,
## and epoch isolation.

import std/[os, unittest, options]
import core/gate/gate_memo
import core/gate/gate_cas

{.push warning[BareExcept]:off.}
suite "Hermetic Cache Key":
  test "Same inputs produce same key (determinism)":
    let key1 = computeCompositeLockHash("test-gate", "/tmp", "dirty1",
                                       @["file1.nim"], "binary1")
    let key2 = computeCompositeLockHash("test-gate", "/tmp", "dirty1",
                                       @["file1.nim"], "binary1")
    check key1 == key2
    check key1.len > 0

  test "Binary hash change invalidates key":
    let key1 = computeCompositeLockHash("test-gate", "/tmp", "dirty1",
                                       @["file1.nim"], "binary1")
    let key2 = computeCompositeLockHash("test-gate", "/tmp", "dirty1",
                                       @["file1.nim"], "binary2")
    check key1 != key2

  test "DirtyHash change invalidates key":
    let key1 = computeCompositeLockHash("test-gate", "/tmp", "dirty1",
                                       @["file1.nim"], "binary1")
    let key2 = computeCompositeLockHash("test-gate", "/tmp", "dirty2",
                                       @["file1.nim"], "binary1")
    check key1 != key2

  test "Empty binary hash is backward-compatible":
    let keyOld = computeCompositeLockHash("test-gate", "/tmp", "dirty1",
                                         @["file1.nim"])
    let keyNew = computeCompositeLockHash("test-gate", "/tmp", "dirty1",
                                         @["file1.nim"], "")
    check keyOld == keyNew

  test "Gate source change invalidates key":
    let key1 = computeCompositeLockHash(@["file1.nim"], "src_a.nim",
                                       true, "/tmp", "dirty1")
    let key2 = computeCompositeLockHash(@["file1.nim"], "src_b.nim",
                                       true, "/tmp", "dirty1")
    check key1 != key2

  test "Binary hash invalidates key via isPath overload":
    let key1 = computeCompositeLockHash(@["file1.nim"], "src.nim",
                                       true, "/tmp", "dirty1", "binA")
    let key2 = computeCompositeLockHash(@["file1.nim"], "src.nim",
                                       true, "/tmp", "dirty1", "binB")
    check key1 != key2

  test "getBinaryHash returns empty for nonexistent binary":
    let hash = getBinaryHash("nonexistent-key", "/tmp")
    check hash.len == 0

suite "Hermetic Cache Key — shouldSkipGate":
  setup:
    let testDir = getTempDir() / "axiom_hermetic_test_" & $getCurrentProcessId()
    createDir(testDir)
    createDir(testDir / GateMemoBaseDir)

  teardown:
    removeDir(testDir)

  test "shouldSkipGate returns none on cache miss":
    let origDir = getCurrentDir()
    setCurrentDir(testDir)
    let result = shouldSkipGate("nonexistent-gate", @["file.nim"], "", testDir)
    check result.isNone
    setCurrentDir(origDir)

  test "shouldSkipGate with binaryHash returns none on miss":
    let origDir = getCurrentDir()
    setCurrentDir(testDir)
    let result = shouldSkipGate("nonexistent-gate", @["file.nim"], "", testDir,
                               binaryHash = "somehash")
    check result.isNone
    setCurrentDir(origDir)
