import std/[os, unittest]
import core/results
import core/topology/[merkle_cache, topology_engine]

## Issue #368 — cache fidelity: the persisted Merkle entry must carry the
## ENRICHED hasAxiomImpl flag, so a warm run (no changed files) still sees
## the {.axiomImpl.} pragma instead of the raw pre-enrichment value.

suite "issue #368 — Merkle cache persists the enriched hasAxiomImpl flag":
  test "cold scan reports hasAxiomImpl=true and the warm load preserves it":
    let tmp = getTempDir() / ("ax_368_" & $getCurrentProcessId())
    removeDir(tmp)
    createDir(tmp / "src")
    writeFile(tmp / "src" / "sample.nim",
      "proc myImpl(x: int): int {.axiomImpl.} = x + 1\nproc plainFn(x: int): int = x\n")
    try:
      var eng1 = MerkleQueryEngine()
      let r1 = analyzeTopologySourceRootIncremental(tmp / "src", eng1)
      check r1.isOk
      let cold = r1.get
      check cold.symbols.len == 2
      var coldImpl = false
      for s in cold.symbols:
        if s.functionName == "myImpl":
          coldImpl = s.hasAxiomImpl
      check coldImpl == true

      let cachePath = tmp / "topology_merkle.json"
      check saveCache(eng1, cachePath).isOk
      let loadedRes = loadCache(cachePath)
      check loadedRes.isOk
      var eng2 = loadedRes.get
      let r2 = analyzeTopologySourceRootIncremental(tmp / "src", eng2)
      check r2.isOk
      let warm = r2.get
      check warm.changedFileCount == 0
      var warmImpl = false
      for s in warm.symbols:
        if s.functionName == "myImpl":
          warmImpl = s.hasAxiomImpl
      check warmImpl == true
    finally:
      removeDir(tmp)
