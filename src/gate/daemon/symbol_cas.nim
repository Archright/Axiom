import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}
## File-Level CAS Cache Bridge
##
## Connects invalidation_trigger (normalized-content-hash diff) with salsa_memo
## (Red-Green MemoDb) to enable file-level cache invalidation.
##
## Flow:
##   1. Source file changes → invalidation_trigger.detectChanges()
##   2. Content hash mismatch → mark all symbols from file as dirty
##   3. SalsaMemoDb.markDirty(symbolName) → cascading Red to dependent gates
##
## When a file's normalized content hash changes, every symbol registered for
## that file is marked dirty. Cosmetic-only edits (comments, whitespace) produce
## matching hashes and skip invalidation entirely.

import std/[sets, hashes, tables, sequtils, algorithm, strutils]
import checksums/sha2
import gate/daemon/salsa_memo
import gate/daemon/invalidation_trigger

type
  SymbolHash* = distinct string
    ## SHA-256 hash of a symbol's definition (name + kind + source bytes).
    ## Used as the dependency key in SalsaMemoDb.

  SymbolRegistry* = object
    ## Maps symbol names to their current hash values.
    ## Used to track which gates depend on which symbols.
    symbols*: Table[string, SymbolHash]     ## name → current hash
    symbolToGates*: Table[string, seq[string]] ## symbolName → gateIds

  FileSnapshot* = object
    ## Captures a file's source content and its symbol hashes at a point in time.
    path*: string
    source*: string
    symbolHashes*: Table[string, SymbolHash] ## symbolName → hash

# ══════════════════════════════════════════════════════════════════════════════
# Symbol Hashing
# ══════════════════════════════════════════════════════════════════════════════

proc computeSymbolHash*(name, kind: string; sourceSlice: string): SymbolHash {.inline.} =
  ## Compute a deterministic hash for a symbol definition.
  ## Includes name, kind, and the source text of the symbol.
  let content = name & "|" & kind & "|" & sourceSlice
  SymbolHash($secureHash(Sha_256, content))

proc computeSymbolHashFromSource*(name, kind: string; source: string;
                                   startByte, endByte: uint32): SymbolHash {.inline.} =
  ## Extract source slice and compute symbol hash.
  let startIdx = min(int(startByte), source.len)
  let endIdx = min(int(endByte), source.len)
  if startIdx >= endIdx:
    return computeSymbolHash(name, kind, "")
  computeSymbolHash(name, kind, source[startIdx ..< endIdx])

# ══════════════════════════════════════════════════════════════════════════════
# Symbol Registry — Gate ↔ Symbol Dependency Tracking
# ══════════════════════════════════════════════════════════════════════════════

proc initSymbolRegistry*(): SymbolRegistry {.inline.} =
  SymbolRegistry(
    symbols: initTable[string, SymbolHash](),
    symbolToGates: initTable[string, seq[string]]()
  )

proc registerGate*(reg: var SymbolRegistry; gateId: string;
                   symbolNames: HashSet[string]) {.inline.} =
  ## Register that a gate depends on a set of symbols.
  for name in symbolNames:
    if name notin reg.symbolToGates:
      reg.symbolToGates[name] = @[]
    var gates = reg.symbolToGates.getOrDefault(name, @[])
    var found = false
    for existing in gates:
      if existing == gateId:
        found = true
        break
    if not found:
      gates.add(gateId)
      reg.symbolToGates[name] = gates

proc updateSymbolHash*(reg: var SymbolRegistry; name: string;
                        h: SymbolHash) {.inline.} =
  ## Update the hash for a symbol (after source change).
  reg.symbols[name] = h

proc getAffectedGates*(reg: SymbolRegistry;
                       changedSymbols: HashSet[string]): seq[string] {.inline.} =
  ## Get all gate IDs that depend on any of the changed symbols.
  var gateSet = initHashSet[string]()
  for name in changedSymbols:
    for gateId in reg.symbolToGates.getOrDefault(name):
      gateSet.incl(gateId)
  var gates: seq[string]
  for g in gateSet:
    gates.add(g)
  gates

# ══════════════════════════════════════════════════════════════════════════════
# Invalidation Pipeline — AST Diff → Selective Cache Invalidation
# ══════════════════════════════════════════════════════════════════════════════

type
  InvalidationReport* = object
    ## Report from a symbol-level invalidation pass.
    filePath*: string
    changedSymbols*: seq[string]
    affectedGates*: seq[string]
    dirtiedEntries*: int
    isFullInvalidation*: bool
    reason*: string

proc processFileChange*(
    salsaDb: var SalsaMemoDb;
    registry: var SymbolRegistry;
    filePath, oldSource, newSource: string
): InvalidationReport =
  ## Process a file change through the invalidation pipeline.
  ##
  ## 1. Compare normalized content hashes (comments+whitespace invariant)
  ## 2. If hashes differ → mark every registered symbol from this file as dirty
  ## 3. Return report with stats
  ##
  ## Cosmetic-only edits (comment changes, whitespace reformatting) produce
  ## matching hashes and skip invalidation entirely.
  result = InvalidationReport(filePath: filePath)

  # Step 1: Detect changes via tree-sitter
  let invalidation = detectChanges(oldSource, newSource)

  if invalidation.isFullInvalidation:
    # Structural change or parse failure — dirty everything for this file
    result.isFullInvalidation = true
    result.reason = "full invalidation (structural change or parse failure)"
    # Mark all symbols from this file as dirty
    for name, _ in registry.symbols:
      for gateId in registry.symbolToGates.getOrDefault(name):
        let stats = salsaDb.markDirty(name)
        result.dirtiedEntries += stats.dirtiedCount
    return

  if invalidation.affectedSymbols.len == 0:
    result.reason = "no symbols changed"
    return

  # Step 2: Update symbol hashes for changed symbols
  result.changedSymbols = toSeq(invalidation.affectedSymbols.items)
  for name in invalidation.affectedSymbols:
    let h = computeSymbolHash(name, "changed", newSource)
    registry.updateSymbolHash(name, h)

  # Step 3: Find affected gates and mark dirty
  result.affectedGates = registry.getAffectedGates(invalidation.affectedSymbols)

  # Mark dirty by symbol name (symbol name acts as subtree root in SalsaMemoDb)
  for name in invalidation.affectedSymbols:
    let stats = salsaDb.markDirty(name)
    result.dirtiedEntries += stats.dirtiedCount

proc snapshotFile*(path: string; source: string): FileSnapshot {.inline.} =
  ## Create a snapshot of a file's symbols and their hashes.
  ## Used to build the initial dependency graph.
  result = FileSnapshot(path: path, source: source,
                        symbolHashes: initTable[string, SymbolHash]())
  let invalidation = detectChanges("", source)
  for name in invalidation.affectedSymbols:
    let h = computeSymbolHash(name, "snapshot", source)
    result.symbolHashes[name] = h

# ══════════════════════════════════════════════════════════════════════════════
# Gate Cache Key — Symbol-Hash-Aware
# ══════════════════════════════════════════════════════════════════════════════

proc computeSymbolAwareCacheKey*(
    gateId: string;
    symbolHashes: HashSet[string]
): string {.inline.} =
  ## Compute a cache key that incorporates symbol-level hashes.
  ## Different from file-level compositeLockHash — this key changes only
  ## when the specific symbols the gate depends on change.
  if symbolHashes.len == 0:
    return ""
  var sortedHashes = toSeq(symbolHashes)
  sortedHashes.sort()
  let combined = gateId & "|" & sortedHashes.join(",")
  $secureHash(Sha_256, combined)

{.pop.}

