import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}
## Salsa Red-Green MemoDb — Incremental Dependency-Tracked Memoization
##
## Extends the flat MemoDb with Salsa-style Red-Green dependency tracking.
## When a subtree root hash changes (detected by invalidation_trigger.nim),
## all dependent cache entries are transitively marked Red (stale).
## Green entries can be reused without re-running the gate.
##
## Algorithm:
##   1. persist(gateId, subtreeRoot, inputs) — record result + dependency set
##   2. lookupGreen(gateId, subtreeRoot, currentInputs) — return cached if all
##      inputs are Green and unchanged
##   3. markDirty(subtreeRoot) — cascade Red to all dependents
##
## Complexity: O(affected_subtree) per invalidation, O(1) per lookup.

import std/[tables, sets]
import gate/daemon/gate_daemon_types

type
  MemoColor* = enum
    ## Salsa-style node color.
    mcRed = "red"     ## Potentially stale — must re-validate
    mcGreen = "green" ## Verified clean — safe to reuse

  MemoNode* = object
    ## Dependency-tracked cache entry.
    entry*: CacheEntry           ## The cached gate result
    color*: MemoColor            ## Red/Green status
    inputHashes*: HashSet[string] ## subtreeRoot hashes this entry depends on

  SalsaMemoDb* = object
    ## Dependency-tracked memoization database.
    ## Extends MemoDb with Red-Green coloring and cascading invalidation.
    nodes*: Table[string, MemoNode]       ## key = cacheKey(gateId, subtreeRoot)
    dependents*: Table[string, seq[string]] ## input → list of dependent cacheKeys
    revision*: int
    hitCount*: int64
    missCount*: int64
    persistCount*: int64
    cascadeCount*: int64         ## total cascade operations performed

  InvalidationStats* = object
    ## Stats returned from a cascade invalidation.
    dirtiedCount*: int           ## number of entries marked Red
    cascadeDepth*: int           ## max cascade chain length

# ══════════════════════════════════════════════════════════════════════════════
# Construction
# ══════════════════════════════════════════════════════════════════════════════

proc initSalsaMemoDb*(): SalsaMemoDb {.raises: [].} =
  ## Create an empty Salsa MemoDb.
  SalsaMemoDb(
    nodes: initTable[string, MemoNode](),
    dependents: initTable[string, seq[string]](),
    revision: 0, hitCount: 0, missCount: 0, persistCount: 0, cascadeCount: 0
  )

# ══════════════════════════════════════════════════════════════════════════════
# Lookup — O(1) green check
# ══════════════════════════════════════════════════════════════════════════════

proc lookupGreen*(db: var SalsaMemoDb; gateId, subtreeRoot: string;
                  currentInputs: HashSet[string]): CacheEntry {.raises: [].} =
  ## Look up a cache entry and verify it's Green with unchanged inputs.
  ##
  ## Returns the cached entry if:
  ##   1. The entry exists and is Green
  ##   2. All current inputs are present in the entry's input set
  ##   3. No input has been marked Red
  ##
  ## Returns a default (empty) CacheEntry on miss or if any input is Red.
  let key = cacheKey(gateId, subtreeRoot)
  let node = db.nodes.getOrDefault(key)
  if node.entry.gateId.len == 0:
    inc db.missCount
    return CacheEntry()  # Not found

  if node.color == mcRed:
    inc db.missCount
    return CacheEntry()  # Stale — must re-validate

  # Verify all current inputs are still in the dependency set
  for input in currentInputs:
    if input notin node.inputHashes:
      inc db.missCount
      return CacheEntry()  # Input set changed — must re-validate

  # Check if any dependency is Red
  for input in node.inputHashes:
    # Any entry keyed by this input that is Red means the input changed
    for depKey in db.dependents.getOrDefault(input):
      if depKey == key: continue  # skip self
      let depNode = db.nodes.getOrDefault(depKey)
      if depNode.color == mcRed:
        # One of our inputs is dirty — this entry should also be dirty
        # (lazy propagation: mark self Red on detection)
        db.nodes[key] = MemoNode(
          entry: node.entry,
          color: mcRed,
          inputHashes: node.inputHashes
        )
        inc db.missCount
        return CacheEntry()

  inc db.hitCount
  return node.entry

# ══════════════════════════════════════════════════════════════════════════════
# Persist — record a Green result with dependencies
# ══════════════════════════════════════════════════════════════════════════════

proc persist*(db: var SalsaMemoDb; entry: CacheEntry;
              inputHashes: HashSet[string]) {.raises: [].} =
  ## Record a gate result as Green with its dependency set.
  ## Registers reverse dependency edges for cascading invalidation.
  inc db.revision
  inc db.persistCount
  var e = entry
  e.revision = db.revision
  let key = cacheKey(entry.gateId, entry.subtreeRoot)

  db.nodes[key] = MemoNode(
    entry: e,
    color: mcGreen,
    inputHashes: inputHashes
  )

  # Register reverse edges: input → this entry
  for input in inputHashes:
    var deps = db.dependents.getOrDefault(input, @[])
    var found = false
    for existing in deps:
      if existing == key:
        found = true
        break
    if not found:
      deps.add(key)
      db.dependents[input] = deps

# ══════════════════════════════════════════════════════════════════════════════
# Cascade Invalidation — Red propagation
# ══════════════════════════════════════════════════════════════════════════════

proc markDirty*(db: var SalsaMemoDb; subtreeRoot: string): InvalidationStats {.raises: [].} =
  ## Mark all entries that depend on subtreeRoot as Red.
  ## Recursively cascades through the dependency graph.
  ##
  ## Returns stats on how many entries were dirtied and cascade depth.
  var dirtied = 0
  var maxDepth = 0
  var visited = initHashSet[string]()
  var frontier: seq[string]

  # Seed: all entries directly depending on this subtree root
  let dependents = db.dependents.getOrDefault(subtreeRoot)
  for depKey in dependents:
    frontier.add(depKey)

  # BFS cascade
  var depth = 0
  while frontier.len > 0:
    var nextFrontier: seq[string]
    for key in frontier:
      if key in visited:
        continue
      visited.incl(key)

      var node = db.nodes.getOrDefault(key)
      if node.entry.gateId.len == 0:
        continue  # Already deleted
      if node.color == mcRed:
        continue  # Already Red

      # Mark Red
      node.color = mcRed
      db.nodes[key] = node
      inc dirtied

      # Cascade to entries that depend on this entry's subtree root
      let entryKey = cacheKey(node.entry.gateId, node.entry.subtreeRoot)
      let transitiveDeps = db.dependents.getOrDefault(entryKey)
      for td in transitiveDeps:
        if td notin visited:
          nextFrontier.add(td)

    frontier = nextFrontier
    inc depth
    if depth > maxDepth:
      maxDepth = depth

  inc db.cascadeCount
  db.revision += dirtied

  InvalidationStats(dirtiedCount: dirtied, cascadeDepth: maxDepth)

proc invalidate*(db: var SalsaMemoDb; gateId: string): int {.raises: [].} =
  ## Remove all entries for a gate. Returns count of removed entries.
  var toRemove: seq[string]
  for key, node in db.nodes:
    if node.entry.gateId == gateId:
      toRemove.add(key)
  for key in toRemove:
    # Remove from nodes
    db.nodes.del(key)
    # Clean up reverse edges
    var inputsToClean: seq[string]
    for input, deps in db.dependents:
      var newDeps: seq[string]
      for dep in deps:
        if dep != key:
          newDeps.add(dep)
      if newDeps.len == 0:
        inputsToClean.add(input)
      else:
        db.dependents[input] = newDeps
    for input in inputsToClean:
      db.dependents.del(input)
  inc db.revision
  toRemove.len

# ══════════════════════════════════════════════════════════════════════════════
# Query / Diagnostics
# ══════════════════════════════════════════════════════════════════════════════

proc getColor*(db: SalsaMemoDb; gateId, subtreeRoot: string): MemoColor {.raises: [].} =
  ## Get the color of a specific entry. Returns mcRed if not found.
  let key = cacheKey(gateId, subtreeRoot)
  let node = db.nodes.getOrDefault(key)
  if node.entry.gateId.len == 0:
    mcRed  # Not found → treat as dirty
  else:
    node.color

proc countByColor*(db: SalsaMemoDb): tuple[green: int, red: int] {.raises: [].} =
  ## Count entries by color.
  var green = 0
  var red = 0
  for _, node in db.nodes:
    if node.color == mcGreen:
      inc green
    else:
      inc red
  (green, red)

proc stats*(db: SalsaMemoDb): tuple[entries: int, green: int, red: int,
                                    revision: int, hits: int64, misses: int64,
                                    persists: int64, cascades: int64] {.raises: [].} =
  ## Full diagnostic stats.
  let colors = db.countByColor()
  (db.nodes.len, colors.green, colors.red, db.revision,
   db.hitCount, db.missCount, db.persistCount, db.cascadeCount)

proc dependencyCount*(db: SalsaMemoDb; gateId, subtreeRoot: string): int {.raises: [].} =
  ## Get the number of inputs this entry depends on.
  let key = cacheKey(gateId, subtreeRoot)
  let node = db.nodes.getOrDefault(key)
  node.inputHashes.len

{.pop.}

