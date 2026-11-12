## gate_memo_test.nim
## Business scenario tests for core/gate/gate_memo.nim — the memoization engine.
##
## This module is the #4 hotspot (24 changes). It provides deterministic
## Merkle-based caching for gate execution results via True CAS addressing.
## Tests cover: CAS integrity, Merkle root, epoch management, save/load
## round-trip, and cache policy enforcement.

import std/[unittest, os, strutils, times, options, json]
import core/gate/gate_memo
import core/types/gate_types

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: CAS (Content-Addressed Storage) Addressing
# Every memo entry is stored at a path derived from its SHA-256 hash.
# The filename IS the hash — file existence IS integrity proof.
# ══════════════════════════════════════════════════════════════════════════════

suite "CasAddress: content-addressed integrity":
  test "computeCasAddress returns 64-char hex SHA-256":
    let ca = computeCasAddress("hello world")
    check string(ca).len == 64
    # Verify it's valid hex
    for c in string(ca):
      check c in "0123456789abcdef"

  test "same content produces same CAS address (deterministic)":
    let ca1 = computeCasAddress("test content")
    let ca2 = computeCasAddress("test content")
    check string(ca1) == string(ca2)

  test "different content produces different CAS address":
    let ca1 = computeCasAddress("content A")
    let ca2 = computeCasAddress("content B")
    check string(ca1) != string(ca2)

  test "casSubdir returns first 2 hex chars":
    let ca = computeCasAddress("test")
    check ca.casSubdir().len == 2
    check string(ca)[0..1] == ca.casSubdir()

  test "casFilename returns remaining 62 hex chars":
    let ca = computeCasAddress("test")
    check ca.casFilename().len == 62
    check string(ca)[2..^1] == ca.casFilename()

  test "casPath combines epochDir / subdir / filename":
    let ca = computeCasAddress("test")
    let path = casPath("epoch_0", ca)
    check path.contains("epoch_0")
    check path.contains(ca.casSubdir())
    check path.contains(ca.casFilename())

  test "isValid returns true for 64-char hex address":
    let ca = computeCasAddress("test")
    check ca.isValid()

  test "isValid returns false for short string":
    let ca = CasAddress("abc123")
    check not ca.isValid()

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Merkle Root Computation
# The Merkle root hashes file contents to create a tamper-proof fingerprint.
# Changing any file MUST change the root. Empty file lists return "".
# ══════════════════════════════════════════════════════════════════════════════

suite "computeMerkleRoot: file content fingerprinting":
  test "empty file list returns empty string":
    let root = computeMerkleRoot(@[])
    check root.len == 0

  test "single file returns its SHA-256 hash":
    # Create a temp file with known content
    let tmpDir = getTempDir() / "axiom_merkle_test"
    createDir(tmpDir)
    let tmpFile = tmpDir / "test_file.txt"
    writeFile(tmpFile, "hello world")
    defer: removeFile(tmpFile)
    defer: removeDir(tmpDir)

    let root = computeMerkleRoot(@[tmpFile])
    check root.len == 64  # SHA-256 hex

  test "same files in different order produce same root (sorted)":
    let tmpDir = getTempDir() / "axiom_merkle_test2"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f1 = tmpDir / "a.txt"
    let f2 = tmpDir / "b.txt"
    writeFile(f1, "aaa")
    writeFile(f2, "bbb")
    defer: removeFile(f1)
    defer: removeFile(f2)

    let root1 = computeMerkleRoot(@[f1, f2])
    let root2 = computeMerkleRoot(@[f2, f1])
    check root1 == root2  # Deterministic regardless of input order

  test "different files produce different roots":
    let tmpDir = getTempDir() / "axiom_merkle_test3"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f1 = tmpDir / "x.txt"
    let f2 = tmpDir / "y.txt"
    writeFile(f1, "content A")
    writeFile(f2, "content B")
    defer: removeFile(f1)
    defer: removeFile(f2)

    let root1 = computeMerkleRoot(@[f1])
    let root2 = computeMerkleRoot(@[f2])
    check root1 != root2

  test "nonexistent files are excluded from Merkle root":
    let tmpDir = getTempDir() / "axiom_merkle_test4"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let realFile = tmpDir / "exists.txt"
    writeFile(realFile, "data")
    defer: removeFile(realFile)

    let rootWithMissing = computeMerkleRoot(@[realFile, "/nonexistent/file.txt"])
    let rootWithout = computeMerkleRoot(@[realFile])
    check rootWithMissing == rootWithout

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Memo Path Generation
# Memo files are stored in epoch-partitioned directories for cache isolation.
# Path correctness prevents cross-epoch cache pollution.
# ══════════════════════════════════════════════════════════════════════════════

suite "memoPath: epoch-partitioned storage":
  test "epoch 0 generates correct path":
    let path = memoPath("import-check", 0)
    check path.contains("epoch_0")
    check path.endsWith("import-check.json")

  test "epoch 42 generates correct path":
    let path = memoPath("gate-abc", 42)
    check path.contains("epoch_42")
    check path.endsWith("gate-abc.json")

  test "gate ID is preserved in path":
    let path = memoPath("my-custom-gate-123", 5)
    check path.contains("my-custom-gate-123")

  test "base directory is consistent":
    let path = memoPath("g", 0)
    check path.startsWith(GateMemoBaseDir)

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Save/Load Round-Trip
# Gate results must be saved to CAS and loaded back correctly.
# The CAS integrity check verifies SHA-256(content) == filename.
# Phase B: Pure content-addressed caching — no time-based expiry on load.
# ══════════════════════════════════════════════════════════════════════════════

suite "saveGateMemo / loadGateMemo: persistence round-trip":
  # Helper: create tmpDir with full GateMemoBaseDir tree (createDir is non-recursive)
  proc makeMemoTmpDir(prefix: string): string =
    let tmpDir = getTempDir() / (prefix & $epochTime().int)
    createDir(tmpDir / ".axiom" / "cache" / "gate_memo")
    return tmpDir

  test "save then load PASS result":
    let tmpDir = makeMemoTmpDir("axiom_memo_rt_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "test-pass-gate"
    let lockHash = "abc123def456"

    saveGateMemo(gateId, lockHash, true, testEpoch)
    let loaded = loadGateMemo(gateId, lockHash, testEpoch)
    check loaded.isSome
    check loaded.get.result == true
    check loaded.get.compositeLockHash == lockHash
    check loaded.get.failureCategory == fcTransient  # default

  test "save then load FAIL with fcTransient includes TTL":
    let tmpDir = makeMemoTmpDir("axiom_memo_fail_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "test-fail-gate"
    let lockHash = "xyz789"

    saveGateMemo(gateId, lockHash, false, testEpoch, fcTransient, "network timeout")
    let loaded = loadGateMemo(gateId, lockHash, testEpoch)
    check loaded.isSome
    check loaded.get.result == false
    check loaded.get.failureReason == "network timeout"

  test "fcPermanent failures are never cached (load returns none)":
    let tmpDir = makeMemoTmpDir("axiom_memo_perm_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "test-perm-gate"
    let lockHash = "perm123"

    saveGateMemo(gateId, lockHash, false, testEpoch, fcPermanent, "missing config")
    let loaded = loadGateMemo(gateId, lockHash, testEpoch)
    check loaded.isNone  # fcPermanent → not cached

  test "fcUnknown failures are never cached (load returns none)":
    let tmpDir = makeMemoTmpDir("axiom_memo_unknown_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "test-unknown-gate"
    let lockHash = "unknown123"

    saveGateMemo(gateId, lockHash, false, testEpoch, fcUnknown, "theater detection: cannot classify")
    let loaded = loadGateMemo(gateId, lockHash, testEpoch)
    # fcUnknown has cacheTtl=0 and must NOT be cached/reused — always re-execute.
    check loaded.isNone  # fcUnknown → not cached

  test "fcUnknown failures are never cached via legacy flat-file path (loadLegacyGateMemo returns none)":
    let tmpDir = makeMemoTmpDir("axiom_memo_legacy_unknown_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "test-legacy-unknown-gate"
    let lockHash = "legacyUnknown123"

    # Ensure the epoch_0 dir exists (saveGateMemo creates it via existsOrCreateDirOpt).
    saveGateMemo(gateId, lockHash, true, testEpoch)
    # Write a flat legacy memo file with fcUnknown FAIL at the legacy flat path
    # (epoch_0/<gateId>.json), which loadLegacyGateMemo reads.
    let epochDir = joinPath(getCurrentDir(), GateMemoBaseDir, "epoch_" & $testEpoch)
    let legacyPath = joinPath(epochDir, gateId & ".json")
    let j = %*{
      "compositeLockHash": lockHash,
      "result": false,
      "timestamp": getTime().toUnix(),
      "failureCategory": $fcUnknown,
      "failureReason": "theater detection: cannot classify"
    }
    writeFile(legacyPath, $j & "\n")
    let loaded = loadLegacyGateMemo(gateId, testEpoch)
    # fcUnknown → not cached even via legacy flat-file path
    check loaded.isNone

  test "fcValidation failures are cached with pure content-addressed invalidation":
    let tmpDir = makeMemoTmpDir("axiom_memo_valid_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "test-val-gate"
    let lockHash = "val456"

    saveGateMemo(gateId, lockHash, false, testEpoch, fcValidation, "import cycle")
    let loaded = loadGateMemo(gateId, lockHash, testEpoch)
    # Phase B: fcValidation failures ARE cached — invalidation is purely via
    # compositeLockHash change, not time-based expiry.
    check loaded.isSome
    check loaded.get.result == false
    check loaded.get.failureCategory == fcValidation
    check loaded.get.failureReason == "import cycle"

  test "matching lock hash returns cached entry":
    let tmpDir = makeMemoTmpDir("axiom_memo_miss_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    saveGateMemo("gate-a", "hash1", true, testEpoch)
    let loaded = loadGateMemo("gate-a", "hash1", testEpoch)
    check loaded.isSome

  test "nonexistent gate returns none":
    let tmpDir = makeMemoTmpDir("axiom_memo_none_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let loaded = loadGateMemo("nonexistent-gate", "any-hash", 0)
    check loaded.isNone

  test "overload with compositeLockHash finds matching entry via CAS":
    let tmpDir = makeMemoTmpDir("axiom_memo_hash_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "hash-filter-gate"
    let lockHash = "specific_hash_123"
    saveGateMemo(gateId, lockHash, true, testEpoch)

    # Matching hash returns the entry
    let found = loadGateMemo(gateId, lockHash, testEpoch)
    check found.isSome
    check found.get.result == true
    check found.get.compositeLockHash == lockHash

  test "wrong hash falls through CAS miss to legacy flat path (fail-closed)":
    let tmpDir = makeMemoTmpDir("axiom_memo_fb_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let testEpoch = 0
    let gateId = "hash-fb-gate"
    saveGateMemo(gateId, "real_hash", true, testEpoch)

    # CAS scan misses (wrong hash). Phase B saveGateMemo writes the CAS layout
    # only, so the legacy flat path has no file either → no cached verdict:
    # live re-judgment (fail-closed). (Stale pre-Phase-B expectation corrected —
    # machine-observed failing identically on pristine main 5dc62ebba; the
    # legacy fallback can only surface hand-written flat entries.)
    check loadGateMemo(gateId, "wrong_hash", testEpoch).isNone

    # A genuine pre-Phase-B flat entry IS surfaced by the legacy fallback,
    # which ignores compositeLockHash by design:
    let epochDir = joinPath(getCurrentDir(), GateMemoBaseDir, "epoch_" & $testEpoch)
    let legacyPath = joinPath(epochDir, gateId & ".json")
    let j = %*{
      "compositeLockHash": "real_hash",
      "result": true,
      "timestamp": getTime().toUnix(),
    }
    writeFile(legacyPath, $j & "\n")
    let fallback = loadGateMemo(gateId, "wrong_hash", testEpoch)
    check fallback.isSome  # legacy path ignores compositeLockHash
    check fallback.get.result == true

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Lock Staleness Detection
# Migration locks protect concurrent access. Stale locks (dead process
# or timeout) must be automatically detected to prevent deadlocks.
# ══════════════════════════════════════════════════════════════════════════════

suite "isLockStale: migration lock validity":
  test "lock with old timestamp is stale":
    let tmpDir = getTempDir() / "axiom_lock_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let lockPath = tmpDir / ".migration_lock"
    # Write a lock with PID 1 (always dead) and very old timestamp
    writeFile(lockPath, "1|1000000\n")
    check isLockStale(lockPath)

  test "lock with malformed content is stale":
    let tmpDir = getTempDir() / "axiom_lock_test2"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let lockPath = tmpDir / ".migration_lock"
    writeFile(lockPath, "bad_content\n")
    check isLockStale(lockPath)

  test "lock with missing pipe separator is stale":
    let tmpDir = getTempDir() / "axiom_lock_test3"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let lockPath = tmpDir / ".migration_lock"
    writeFile(lockPath, "12345\n")
    check isLockStale(lockPath)

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Cache Policy via FailureCategory (legacy note)
# Phase B: cacheTtl is deprecated — pure content-addressed caching is now used.
# cacheTtl() is kept for backward API compatibility only.
# - fcPermanent: never cached (always re-execute)
# - fcTransient: cached until compositeLockHash changes
# - fcValidation: cached until compositeLockHash changes
# ══════════════════════════════════════════════════════════════════════════════

suite "cacheTtl: deterministic cache policy":
  test "fcPermanent has zero TTL":
    check fcPermanent.cacheTtl() == 0

  test "fcTransient has 300s TTL":
    check fcTransient.cacheTtl() == 300

  test "fcValidation has zero TTL":
    check fcValidation.cacheTtl() == 0

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Epoch-Based Cache Isolation
# Cache epochs partition gate memo into isolated directories.
# Advancing the epoch creates a fresh namespace for new results.
# ══════════════════════════════════════════════════════════════════════════════

suite "epoch management: cache isolation":
  test "currentCacheEpoch returns non-negative":
    let epoch = currentCacheEpoch()
    check epoch >= 0

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Epoch GC hygiene
# GC removes only epochs that fell out of the retention window. Directory
# names the epoch contract cannot produce (non-numeric suffix) are foreign
# garbage and get reclaimed; a numeric epoch above the current one is foreign
# or the documented manual-rollback state and must survive GC.
# ══════════════════════════════════════════════════════════════════════════════

proc makeGcSandbox(prefix: string): string =
  let tmpDir = getTempDir() / (prefix & $epochTime().int)
  createDir(tmpDir / ".axiom" / "cache" / "gate_memo")
  return tmpDir

suite "garbageCollectOldEpochs: retention window and ghost-dir guard":
  test "old epoch dirs removed, retention window retained":
    let tmpDir = makeGcSandbox("axiom_memo_gc_window_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)
    let cur = currentCacheEpoch()
    createDir(GateMemoBaseDir / ("epoch_" & $(cur - 3)))
    createDir(GateMemoBaseDir / ("epoch_" & $(cur - 2)))
    createDir(GateMemoBaseDir / ("epoch_" & $(cur - 1)))
    createDir(GateMemoBaseDir / ("epoch_" & $cur))
    garbageCollectOldEpochs()
    check not dirExists(GateMemoBaseDir / ("epoch_" & $(cur - 3)))
    check dirExists(GateMemoBaseDir / ("epoch_" & $(cur - 2)))
    check dirExists(GateMemoBaseDir / ("epoch_" & $(cur - 1)))
    check dirExists(GateMemoBaseDir / ("epoch_" & $cur))

  test "non-numeric epoch dir (foreign format) is reclaimed":
    let tmpDir = makeGcSandbox("axiom_memo_gc_ghost_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)
    createDir(GateMemoBaseDir / "epoch_not_a_number")
    garbageCollectOldEpochs()
    check not dirExists(GateMemoBaseDir / "epoch_not_a_number")

  test "epoch dir above current epoch is kept (manual-rollback contract)":
    let tmpDir = makeGcSandbox("axiom_memo_gc_future_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)
    # The field-observed ghost: a bit-pattern epoch far above any real counter
    # (docs/spec/nim_2_2_10_stdlib_quirks.md Q-010).
    createDir(GateMemoBaseDir / "epoch_4745300579805605544")
    createDir(GateMemoBaseDir / ("epoch_" & $(currentCacheEpoch() + 1)))
    garbageCollectOldEpochs()
    check dirExists(GateMemoBaseDir / "epoch_4745300579805605544")
    check dirExists(GateMemoBaseDir / ("epoch_" & $(currentCacheEpoch() + 1)))
