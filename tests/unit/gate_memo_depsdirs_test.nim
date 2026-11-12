## Gate Memo depsDirs Unit Test
## Verifies Merkle computation and caching for entry-less gates.

import std/[options, os, times]
import core/gate/gate_memo

proc main() =
  echo "[gate_memo_depsdirs_test] starting"

  # Test 1: computeMerkleRootFromPaths returns non-empty hash for existing paths
  let paths = @["tests/gateway/", "bin/gateway_test_gate"]
  let hash1 = computeMerkleRootFromPaths(paths)
  doAssert hash1.len > 0, "Merkle root must be non-empty for existing paths"
  echo "[gate_memo_depsdirs_test] computeMerkleRootFromPaths non-empty PASS"

  # Test 2: Determinism — same input produces same hash
  let hash2 = computeMerkleRootFromPaths(paths)
  doAssert hash1 == hash2, "Merkle root must be deterministic"
  echo "[gate_memo_depsdirs_test] determinism PASS"

  # Test 3: computeCompositeLockHash includes gate source hash + repoRoot
  let inputFiles = @["src/core/gate/gate_memo.nim"]
  let gateSource = "src/core/gate/gate_memo.nim"
  let testRoot = "/tmp/test-repo"
  let composite = computeCompositeLockHash(inputFiles, gateSource, testRoot)
  doAssert composite.len > 0, "Composite hash must be non-empty"
  echo "[gate_memo_depsdirs_test] composite hash (isPath=false) PASS"

  # Test 4: loadGateMemo / saveGateMemo roundtrip — sandboxed into a temp cwd
  # (GateMemoBaseDir is cwd-relative) so the suite never writes into the real
  # repo memo cache, and at the contract-valid epoch 0. The previous
  # cast[int](epochTime()) epoch was a float bit-pattern reinterpretation that
  # leaked garbage-epoch dirs into the repo cache
  # (docs/spec/nim_2_2_10_stdlib_quirks.md Q-010).
  let tmpDir = getTempDir() / ("axiom_memo_depsdirs_" & $epochTime().int)
  createDir(tmpDir / ".axiom" / "cache" / "gate_memo")
  let savedDir = getCurrentDir()
  setCurrentDir(tmpDir)
  let gateId = "unit-test-depsdirs-" & $epochTime().int
  let epoch = 0
  let skipBefore = loadGateMemo(gateId, composite, epoch)
  doAssert skipBefore.isNone, "Cache miss before save"
  saveGateMemo(gateId, composite, true, epoch)
  let skipAfter = loadGateMemo(gateId, composite, epoch)
  doAssert skipAfter.isSome, "Cache hit after save"
  doAssert skipAfter.get.result == true, "Cached result must match saved value"
  echo "[gate_memo_depsdirs_test] shouldSkipGate roundtrip PASS"
  setCurrentDir(savedDir)
  removeDir(tmpDir)

  echo "[gate_memo_depsdirs_test] ALL PASSED"

main()
