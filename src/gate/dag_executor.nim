import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

# axiom:parallel-execution
## Runtime topological sort, fail-closed propagation, and parallel layer execution.
##
## Layer grouping uses Kahn's algorithm to partition gates into dependency layers.
## Each layer executes in parallel via malebolgia master.spawn.
## If any gate fails, downstream layers are skipped (fail-closed).

import std/[tables, strutils, sets, sequtils, times, monotimes]
import malebolgia
# axiom:integration-fix — removed unused imports (algorithm, strformat, gate_types)
import gate/gate_registry  # GateSpec, GateContext, GateRunner
# axiom:cache-integration
import gate/gate_cache  # computeCacheKey, getCachedResult, saveCacheEntry, logCacheStats

# ── Profiling Infrastructure (axiom:profiling) ──────────────────────────────

type
  ProfileEntry* = object
    id*: string
    durationMs*: float

var profileEnabled* = false
var profileResults* = @[]

proc checkProfileFlag() {.gcsafe.} =
  ## Check for --profile flag in command line arguments
  if profileEnabled:
    return
  for i in 0 .. paramCount() - 1:
    if paramStr(i) == "--profile":
      profileEnabled = true
      break

proc profileRecord*(gateId: string; durationMs: float) {.gcsafe.} =
  ## Record a gate execution duration for profiling
  if profileEnabled:
    profileResults.add(ProfileEntry(id: gateId, durationMs: durationMs))

proc printProfileSummary() {.gcsafe.} =
  ## Print profiling summary sorted by duration (slowest first)
  if not profileEnabled or profileResults.len == 0:
    return
  
  echo ""
  echo "[PROFILE] Gate Execution Summary"
  echo "[PROFILE] ======================"
  
  var sorted = profileResults.sortedByIt(-it.durationMs)
  
  for entry in sorted:
    echo "[PROFILE] Gate ", entry.id, ": ", entry.durationMs, "ms"
  
  echo "[PROFILE] Total gates profiled: ", sorted.len
  echo ""

# ── Topological Sort (Kahn's Algorithm) ─────────────────────────────────────

proc topologicalSort*(registry: openArray[GateSpec]): seq[GateSpec] {.raises: [CatchableError].} =
  ## Return gates in dependency-respecting order using Kahn's algorithm.
  ## Raises CatchableError on cycle detection.
  
  var inDegree = initTable[string, int]()
  var adj = initTable[string, seq[string]]()
  var gateMap = initTable[string, GateSpec]()
  
  # Initialize
  for g in registry:
    inDegree[g.id] = 0
    adj[g.id] = @[]
    gateMap[g.id] = g
  
  # Build adjacency list from dependsOn
  for g in registry:
    for dep in g.dependsOn:
      if dep in adj:
        adj[dep].add(g.id)
        inDegree[g.id] = inDegree[g.id] + 1
  
  # Kahn's algorithm
  var queue: seq[string] = @[]
  for g in registry:
    if inDegree[g.id] == 0:
      queue.add(g.id)
  
  var sorted: seq[GateSpec] = @[]
  
  while queue.len > 0:
    let current = queue[0]
    queue.delete(0)
    sorted.add(gateMap[current])
    
    for neighbor in adj[current]:
      inDegree[neighbor] = inDegree[neighbor] - 1
      if inDegree[neighbor] == 0:
        queue.add(neighbor)
  
  # Check for cycles
  if sorted.len != registry.len:
    var unresolved: seq[string] = @[]
    var sortedIds: seq[string] = @[]
    for s in sorted:
      sortedIds.add(s.id)
    
    for g in registry:
      if g.id notin sortedIds:
        unresolved.add(g.id)
    
    raise newException(CatchableError,
      "DAG cycle detected. Unresolved gates: " & unresolved.join(", "))
  
  return sorted

# ── Levelized Layer Grouping (Kahn's Algorithm) ─────────────────────────────

proc groupLayers*(registry: openArray[GateSpec]): seq[seq[GateSpec]] {.raises: [CatchableError].} =
  ## Partition gates into dependency layers using Kahn's algorithm.
  ## Layer 0: gates with no dependencies.
  ## Layer N: gates whose only dependencies are in layers < N.
  ## All gates within a layer can execute in parallel.
  
  var inDegree = initTable[string, int]()
  var adj = initTable[string, seq[string]]()
  var gateMap = initTable[string, GateSpec]()
  
  # Initialize
  for g in registry:
    inDegree[g.id] = 0
    adj[g.id] = @[]
    gateMap[g.id] = g
  
  # Build adjacency list from dependsOn
  for g in registry:
    for dep in g.dependsOn:
      if dep in adj:
        adj[dep].add(g.id)
        inDegree[g.id] = inDegree[g.id] + 1
  
  # BFS-level-by-level using Kahn's algorithm
  var layers: seq[seq[GateSpec]] = @[]
  var currentLevel: seq[string] = @[]
  
  for g in registry:
    if inDegree[g.id] == 0:
      currentLevel.add(g.id)
  
  while currentLevel.len > 0:
    var nextLevel: seq[string] = @[]
    var layerGates: seq[GateSpec] = @[]
    
    for nodeId in currentLevel:
      layerGates.add(gateMap[nodeId])
      
      for neighbor in adj[nodeId]:
        inDegree[neighbor] = inDegree[neighbor] - 1
        if inDegree[neighbor] == 0:
          nextLevel.add(neighbor)
    
    layers.add(layerGates)
    currentLevel = nextLevel
  
  # Check for cycles: all gates must be assigned to a layer
  var totalAssigned = 0
  for l in layers:
    totalAssigned += l.len
  
  if totalAssigned != registry.len:
    var unresolved: seq[string] = @[]
    var assignedIds: HashSet[string] = initHashSet[string]()
    for l in layers:
      for g in l:
        assignedIds.incl(g.id)
    for g in registry:
      if g.id notin assignedIds:
        unresolved.add(g.id)
    raise newException(CatchableError,
      "DAG cycle detected. Unresolved gates: " & unresolved.join(", "))
  
  result = layers

# ── Parallel Gate Execution with Fail-Closed Propagation ────────────────────

type
  GateResult* = object
    id*: string
    success*: bool
    error*: string
    durationMs*: float

## Gcsafe wrapper for malebolgia spawn — executes a single gate.
proc runSingleGate(gateId: string; runner: GateRunner; ctx: GateContext): GateResult
    {.gcsafe, used.} =
  let start = getMonoTime()
  try:
    let passed = runner(ctx)
    let elapsed = (getMonoTime() - start).inMilliseconds()
    if passed:
      echo "[DAG-Parallel] Gate ", gateId, " passed"
      result = GateResult(id: gateId, success: true, error: "", durationMs: elapsed)
    else:
      echo "[DAG-Parallel] Gate ", gateId, " failed"
      result = GateResult(id: gateId, success: false, error: "gate returned false", durationMs: elapsed)
  except CatchableError as e:
    let elapsed = (getMonoTime() - start).inMilliseconds()
    echo "[DAG-Parallel] Gate ", gateId, " raised error: ", e.msg
    result = GateResult(id: gateId, success: false, error: e.msg, durationMs: elapsed)

proc runGatesParallel*(registry: openArray[GateSpec], ctx: GateContext): bool {.gcsafe, raises: [CatchableError].} =
  ## Execute gates in parallel by dependency layers.
  ## Returns false if any gate fails (fail-closed).
  ## Skips dependent layers if a dependency fails.
  
  checkProfileFlag()
  let layers = groupLayers(registry)
  
  if layers.len == 0:
    echo "[DAG-Parallel] No gates to execute"
    return true
  
  echo "[DAG-Parallel] Executing ", layers.len, " layer(s) across ", registry.len, " gate(s)"
  
  # Track results for fail-closed propagation
  var failedGates: HashSet[string] = initHashSet[string]()
  
  for layerIdx, layer in layers:
    echo "[DAG-Parallel] Layer ", layerIdx, ": ", layer.mapIt(it.id).join(", ")
    
    # Check if this layer has any unmet dependencies (dependency failed in earlier layer)
    var shouldRun = true
    for gate in layer:
      for dep in gate.dependsOn:
        if dep in failedGates:
          shouldRun = false
          echo "[DAG-Parallel] Skipping layer ", layerIdx, " gate ", gate.id, 
               " (dependency ", dep, " failed)"
          break
      if not shouldRun:
        break
    
    if not shouldRun:
      continue
    
    # Execute all gates in this layer in parallel via malebolgia
    var results: seq[GateResult] = newSeq[GateResult](layer.len)
    
    block parallelExecution:
      var master = createMaster()
      master.awaitAll:
        for i in 0 ..< layer.len:
          let gate = layer[i]
          
          # axiom:cache-integration — check cache before spawning
          let cacheKey = computeCacheKey(gate.id, ctx.repoRoot, ctx.stagedFiles)
          let cachedOpt = getCachedResult(cacheKey)
          if cachedOpt.isSome():
            let cached = cachedOpt.get()
            echo "[DAG-Cache] Hit: ", gate.id, " (cached)"
            recordHit()
            results[i] = GateResult(id: gate.id, success: cached.result, error: cached.error)
          else:
            recordMiss()
            master.spawn runSingleGate(gate.id, gate.runner, ctx) -> results[i]
    
    # Results collected in results[] during awaitAll — fail-closed check
    for res in results:
      # axiom:profiling — record duration for profiled gates
      profileRecord(res.id, res.durationMs)
      
      # axiom:cache-integration — save result to cache on miss
      if res.success or res.error.len > 0:
        let cacheKey = computeCacheKey(res.id, ctx.repoRoot, ctx.stagedFiles)
        let entry = CacheEntry(result: res.success, error: res.error, timestamp: epochTime().float)
        try:
          saveCacheEntry(cacheKey, entry)
        except CatchableError:
          recordError()
      
      if not res.success:
        echo "[DAG-Parallel] FAIL-CLOSED: Gate ", res.id, " failed (error: ", res.error, ")"
        failedGates.incl(res.id)
        return false
    
    # axiom:cache-integration — log stats at end of each layer
    let stats = getCacheStats()
    if stats.hits + stats.misses + stats.errors > 0:
      logCacheStats()
  
  printProfileSummary()
  echo "[DAG-Parallel] All layers passed successfully"
  return true

# ── Sequential Fallback ─────────────────────────────────────────────────────

proc runGates*(registry: openArray[GateSpec], ctx: GateContext): bool {.gcsafe, raises: [CatchableError].} =
  ## Execute gates in topological order (sequential).
  ## Returns false if any gate fails (fail-closed).
  ## Skips dependent gates if a dependency fails.
  ##
  ## This is the original sequential executor, preserved for compatibility.
  ## For parallel execution, use runGatesParallel instead.
  
  checkProfileFlag()
  let sorted = topologicalSort(registry)
  var failedGates: seq[string] = @[]
  
  for gate in sorted:
    # Check if any dependency failed
    for dep in gate.dependsOn:
      if dep in failedGates:
        echo "[DAG] Skipping ", gate.id, " (dependency ", dep, " failed)"
        return false
    
    # axiom:cache-integration — check cache before execution
    let cacheKey = computeCacheKey(gate.id, ctx.repoRoot, ctx.stagedFiles)
    let cachedOpt = getCachedResult(cacheKey)
    if cachedOpt.isSome():
      let cached = cachedOpt.get()
      echo "[DAG-Cache] Hit: ", gate.id, " (cached)"
      recordHit()
      if not cached.result:
        echo "[DAG] Gate ", gate.id, " failed (cached: ", cached.error, ")"
        failedGates.add(gate.id)
        return false
      echo "[DAG] Gate ", gate.id, " passed (cached)"
      continue
    
    recordMiss()
    
    # Execute gate
    let start = getMonoTime()
    var success = false
    try:
      success = gate.runner(ctx)
    except CatchableError:
      let elapsed = (getMonoTime() - start).inMilliseconds()
      echo "[DAG] Gate ", gate.id, " raised error: ", getCurrentExceptionMsg()
      failedGates.add(gate.id)
      
      # axiom:profiling — record duration for profiled gates
      profileRecord(gate.id, elapsed)
      
      # axiom:cache-integration — save failure to cache
      let entry = CacheEntry(result: false, error: getCurrentExceptionMsg(), timestamp: epochTime().float)
      try:
        saveCacheEntry(cacheKey, entry)
      except CatchableError:
        recordError()
      return false
    
    # axiom:cache-integration — save result to cache
    let elapsed = (getMonoTime() - start).inMilliseconds()
    let entry = CacheEntry(result: success, error: "", timestamp: epochTime().float)
    try:
      saveCacheEntry(cacheKey, entry)
    except CatchableError:
      recordError()
    
    # axiom:profiling — record duration for profiled gates
    profileRecord(gate.id, elapsed)
    
    if not success:
      echo "[DAG] Gate ", gate.id, " failed"
      failedGates.add(gate.id)
      return false
    else:
      echo "[DAG] Gate ", gate.id, " passed"
  
  # axiom:profiling — print summary if enabled
  printProfileSummary()
  
  # axiom:cache-integration — log final cache stats
  let stats = getCacheStats()
  if stats.hits + stats.misses + stats.errors > 0:
    logCacheStats()
  
  return true

# ── Utility Functions ────────────────────────────────────────────────────────

proc detectCyclePath*(registry: openArray[GateSpec]): seq[string] =
  ## Attempt to trace a cycle path for debugging.
  ## Returns empty seq if no cycle.
  
  # Simple DFS to find cycle
  var visited = initTable[string, bool]()
  var recStack = initTable[string, bool]()
  
  proc dfs(current: string, registry: openArray[GateSpec]): seq[string] =
    visited[current] = true
    recStack[current] = true
    
    for g in registry:
      if g.id == current:
        for dep in g.dependsOn:
          if dep notin visited:
            let path = dfs(dep, registry)
            if path.len > 0:
              return @[current] & path
          elif recStack[dep]:
            return @[current, dep]
    
    recStack[current] = false
    return @[]
  
  for g in registry:
    if g.id notin visited:
      let cycle = dfs(g.id, registry)
      if cycle.len > 0:
        return cycle
  
  return @[]
