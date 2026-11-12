import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Symbol Interning — Data-Oriented Topological Refactoring (Phase 1)
##
## Maps runtime strings (module paths, function names, canonical node IDs)
## to dense `distinct uint32` handles. Keeps the public string-based API
## intact while enabling O(1) ordinal lookups and cache-friendly arrays.

import std/hashes  # REQUIRED: Hash type for Table/HashSet {.borrow.} procs below
import std/options
import std/tables
import std/strutils
import core/sorter/sorter_core_index_base

const
  InternPoolSizeGuard* = 1_000_000'u32
    ## Hard guard to catch runaway growth before uint32 overflow.
    ## Current project has ~5k symbols; 1M leaves comfortable headroom.
  IdNotFoundSentinel* = high(uint32)
    ## Sentinel for mgetOrPut absence check; never overlaps real IDs
    ## because InternPoolSizeGuard is far below high(uint32).

type
  PathId* = distinct uint32
    ## Dense handle for a module path string.
  NodeId* = distinct uint32
    ## Dense handle for a canonical node ID (modulePath::functionName).
  SymbolId* = distinct uint32
    ## Dense handle for an arbitrary symbol string.

func `==`*(x, y: PathId): bool {.borrow.}
func hash*(x: PathId): Hash {.borrow.}
func `==`*(x, y: NodeId): bool {.borrow.}
func hash*(x: NodeId): Hash {.borrow.}
func `==`*(x, y: SymbolId): bool {.borrow.}
func hash*(x: SymbolId): Hash {.borrow.}

func `$`*(id: PathId): string {.inline.} = $uint32(id)
func `$`*(id: NodeId): string {.inline.} = $uint32(id)
func `$`*(id: SymbolId): string {.inline.} = $uint32(id)

type
  InternPool* = object
    ## Bidirectional string ↔ uint32 mapping.
    ## Built once during ingestion, then frozen into an immutable snapshot.
    strToId: Table[string, uint32]
    idToStr: seq[string]

  InternPoolSnapshot* = object
    ## Immutable read-only view of an InternPool.
    ## Workers receive this after ingestion to eliminate lock contention.
    strToId: Table[string, uint32]
    idToStr: seq[string]

## Pool size guard.
func checkSizeGuard(nextId: uint32) {.inline.} =
  if nextId >= InternPoolSizeGuard:
    doAssert(false, "InternPool size guard exceeded: " & $nextId)

## Create an empty intern pool.
func initInternPool*(capacity: int = 0): InternPool =
  result = InternPool(
    strToId: initTable[string, uint32](capacity),
    idToStr: newSeqOfCap[string](capacity)
  )

## Number of interned symbols.
func poolSize*(pool: InternPool): int {.inline.} =
  pool.idToStr.len

## Intern a node ID string and return its dense handle.
func internNode*(pool: var InternPool; raw: string): NodeId {.raises: [].} =
  let key = raw.strip()
  let existing = pool.strToId.getOrDefault(key, IdNotFoundSentinel)
  if existing != IdNotFoundSentinel:
    return NodeId(existing)
  let slot = uint32(pool.idToStr.len)
  checkSizeGuard(slot)
  pool.idToStr.add(key)
  pool.strToId[key] = slot
  NodeId(slot)

## Resolve a node handle back to its canonical string.
func resolveNode*(pool: InternPool; id: NodeId): string {.inline.} =
  let idx = int(uint32(id))
  if idx < pool.idToStr.len:
    return pool.idToStr[idx]
  ""

## Resolve a node handle from an immutable snapshot.
func resolveNode*(pool: InternPoolSnapshot; id: NodeId): string {.inline.} =
  let idx = int(uint32(id))
  if idx < pool.idToStr.len:
    return pool.idToStr[idx]
  ""

## Intern a module path.
func internPath*(pool: var InternPool; raw: string): PathId {.raises: [].} =
  let key = raw.strip()
  let existing = pool.strToId.getOrDefault(key, IdNotFoundSentinel)
  if existing != IdNotFoundSentinel:
    return PathId(existing)
  let slot = uint32(pool.idToStr.len)
  checkSizeGuard(slot)
  pool.idToStr.add(key)
  pool.strToId[key] = slot
  PathId(slot)

## Resolve a path handle.
func resolvePath*(pool: InternPool; id: PathId): string {.inline.} =
  let idx = int(uint32(id))
  if idx < pool.idToStr.len:
    return pool.idToStr[idx]
  ""

## Intern an arbitrary symbol.
func internSymbol*(pool: var InternPool; raw: string): SymbolId {.raises: [].} =
  let key = raw.strip()
  let existing = pool.strToId.getOrDefault(key, IdNotFoundSentinel)
  if existing != IdNotFoundSentinel:
    return SymbolId(existing)
  let slot = uint32(pool.idToStr.len)
  checkSizeGuard(slot)
  pool.idToStr.add(key)
  pool.strToId[key] = slot
  SymbolId(slot)

## Resolve a symbol handle.
func resolveSymbol*(pool: InternPool; id: SymbolId): string {.inline.} =
  let idx = int(uint32(id))
  if idx < pool.idToStr.len:
    return pool.idToStr[idx]
  ""

## Adapter: SorterNodeId (string) → NodeId.
func nodeIdForSorter*(pool: var InternPool; nodeId: SorterNodeId): NodeId {.raises: [].} =
  internNode(pool, sorterNodeIdString(nodeId))

## Adapter: NodeId → SorterNodeId (string).
func sorterNodeIdForNode*(pool: InternPool; id: NodeId): SorterNodeId {.inline.} =
  sorterNodeId(resolveNode(pool, id))

## Adapter: NodeId → SorterNodeId (string) from immutable snapshot.
func sorterNodeIdForNode*(pool: InternPoolSnapshot; id: NodeId): SorterNodeId {.inline.} =
  sorterNodeId(resolveNode(pool, id))

## Freeze a mutable pool into an immutable snapshot.
func freezeInternPool*(pool: InternPool): InternPoolSnapshot {.inline.} =
  InternPoolSnapshot(strToId: pool.strToId, idToStr: pool.idToStr)

## Read-only lookup: canonical string → NodeId, if already interned.
func lookupNodeId*(pool: InternPoolSnapshot; raw: string): Option[NodeId] {.inline.} =
  let key = raw.strip()
  let existing = pool.strToId.getOrDefault(key, IdNotFoundSentinel)
  if existing != IdNotFoundSentinel:
    some(NodeId(existing))
  else:
    none(NodeId)

## Read-only adapter: SorterNodeId → NodeId, if already interned.
func nodeIdForSorter*(pool: InternPoolSnapshot; nodeId: SorterNodeId): Option[NodeId] {.inline.} =
  lookupNodeId(pool, sorterNodeIdString(nodeId))

{.pop.}
