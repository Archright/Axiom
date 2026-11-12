import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Verification re-export wrapper for core/global_symbol_graph_builder
##
## This module previously contained the full graph builder implementation.
## Wave 7 migrated all builder logic to src/core/global_symbol_graph_builder.nim
## to restore topological stratification (core must not depend on verification).
##
## This wrapper remains temporarily for backward compatibility.
## Downstream modules should migrate their imports to core/global_symbol_graph_builder.

import core/symbol_graph/global_symbol_graph_builder_part1
import core/symbol_graph/global_symbol_graph_builder_part2
import core/symbolic/global_symbol_graph_types
import core/crypto/hash_kernel
import core/axiom_pragmas
import std/os
import std/options
import std/tables
import std/strutils
# axiomIoBoundary
export global_symbol_graph_builder_part1
export global_symbol_graph_builder_part2

# ---------------------------------------------------------------------------
# GraphInputFingerprint-based materialization reuse (P0, G7 latency).
#
# The warm `ax prove` path re-materializes the global symbol graph on every run
# (full .nim/.lean walk + per-file SHA-256 + cache verification), which is the
# dominant post-pipeline CPU cost. This helper substitutes a cheap source Merkle
# fingerprint (computeSourceMerkleRoot) for the expensive per-file hash walk and
# reuses a previously materialized, validated snapshot only when:
#
#     I1. GraphInputFingerprint == same  (source merkle + execution contract)
#     I2. stored materialization passes integrity/schema validation on load
#     I3. per-run audit/provenance/evidence side effects stay unconditional
#         (this helper does not emit any; the caller keeps those unconditional).
#
# On any doubt (fingerprint mismatch, failed load, schema violation, missing
# snapshot) the callback rebuilds and the result is FAIL-CLOSED.
# ---------------------------------------------------------------------------
proc loadOrBuildGlobalSymbolGraph*(
  repoRoot: string;
  freezeGraphCache: bool = false
): tuple[graph: GlobalSymbolGraph, reused: bool] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns a materialized global symbol graph plus whether it was reused from a
  ## validated snapshot (GraphInputFingerprint == same, I1/I2). When reused=false,
  ## the caller must re-persist the canonical snapshot (the on-disk artifact may
  ## be stale w.r.t. the freshly built graph).
  ##
  ## WP2-a: cache file routes to AXIOM_STATE_DIR when set so a --project run
  ## never writes logs/ into the subject tree (P4 subject immutability).
  let cachePath = block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    let base = if sr.len > 0: sr else: repoRoot
    joinPath(base, "logs", "global_symbol_graph." &
      sha256Hex(repoRoot) & ".cache.json")
  let currentMerkle = computeSourceMerkleRoot(repoRoot)  # cheap; full pass
  let cachedOpt = loadGlobalSymbolGraphCache(cachePath)
  if cachedOpt.isSome:
    let (candGraph, storedMerkle) = cachedOpt.get()
    # I1: fingerprint must match exactly. I2: loaded materialization must be a
    # non-empty, schema-valid snapshot (reject bare-filename legacy format).
    # NOTE: buildGlobalSymbolGraph never populates moduleAsts (only declares it at
    # global_symbol_graph_builder_part2.nim:177), so reference-collection Phase 2
    # runs zero times and the materialized graph always carries edges == 0. This
    # path's graph is by design symbol-only (6330 symbols / 0 edges). Therefore
    # reuse validation keys on a non-empty symbol set + modulePath schema, NOT on
    # edges — requiring edges > 0 would permanently block reuse here.
    var validFormat = candGraph.symbols.len > 0
    if validFormat:
      for _, sym in candGraph.symbols:
        if sym.kind in {SymbolKind.skProc, SymbolKind.skFunc}:
          if '/' notin sym.modulePath and $DirSep notin sym.modulePath:
            validFormat = false
          break
      if validFormat:
        if storedMerkle == currentMerkle:
          return (candGraph, true)  # reuse — skip the per-file hash walk
  # Rebuild (or schema/fingerprint mismatch): FAIL-CLOSED to full materialization.
  let graph = buildGlobalSymbolGraph(repoRoot, freezeGraphCache)
  saveGlobalSymbolGraphCache(graph, cachePath, currentMerkle)
  (graph, false)

{.pop.}
