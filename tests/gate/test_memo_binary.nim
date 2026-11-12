{.push raises: [CatchableError].}

## Binary CAS Memo Test — Validates gate memoization engine.
## Tests Merkle root computation, composite lock hash determinism,
## save/load round-trip, and epoch management.

import std/[os, unittest, options]
import core/gate/gate_memo

{.push warning[BareExcept]:off.}
suite "Gate Memo Binary CAS":
  setup:
    let testDir = getTempDir() / "axiom_memo_test_" & $getCurrentProcessId()
    createDir(testDir)
    createDir(testDir / GateMemoBaseDir)

  teardown:
    removeDir(testDir)

  test "Merkle root is deterministic":
    # Create test files
    let f1 = testDir / "test1.nim"
    let f2 = testDir / "test2.nim"
    writeFile(f1, "echo \"hello\"")
    writeFile(f2, "echo \"world\"")
    
    let hash1 = computeMerkleRoot(@[f1, f2])
    let hash2 = computeMerkleRoot(@[f1, f2])
    check hash1 == hash2
    check hash1.len > 0

  test "Merkle root changes with content":
    let f1 = testDir / "test.nim"
    writeFile(f1, "version 1")
    let hash1 = computeMerkleRoot(@[f1])
    
    writeFile(f1, "version 2")
    let hash2 = computeMerkleRoot(@[f1])
    check hash1 != hash2

  test "Composite lock hash is deterministic":
    let f1 = testDir / "test.nim"
    writeFile(f1, "proc main() = discard")
    
    let h1 = computeCompositeLockHash(@[f1], "", testDir)
    let h2 = computeCompositeLockHash(@[f1], "", testDir)
    check h1 == h2
    check h1.len > 0

  test "Memo save and load round-trip":
    let gateId = "test-gate"
    let hash = "abc123def456"
    let epoch = 0
    
    # Save
    let memoDir = testDir / GateMemoBaseDir / "epoch_0"
    createDir(memoDir)
    
    # Temporarily change working directory for memo operations
    let origDir = getCurrentDir()
    setCurrentDir(testDir)
    
    saveGateMemo(gateId, hash, true, epoch)
    
    # Load
    let loaded = loadGateMemo(gateId, epoch)
    check loaded.isSome
    check loaded.get.compositeLockHash == hash
    check loaded.get.result == true
    
    setCurrentDir(origDir)

  test "shouldSkipGate returns none on cache miss":
    let origDir = getCurrentDir()
    setCurrentDir(testDir)
    
    let result = shouldSkipGate("nonexistent-gate", @["file.nim"], "", testDir)
    check result.isNone
    
    setCurrentDir(origDir)

  test "Epoch management":
    let origDir = getCurrentDir()
    setCurrentDir(testDir)
    
    # Initial epoch should be 0
    let epoch0 = currentCacheEpoch()
    check epoch0 >= 0
    
    setCurrentDir(origDir)
{.pop.}
