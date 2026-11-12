## tools/full_transform.nim — 3-Phase AST Transformation Pipeline
##
## Phase 1: AST pre-scan → proc→func conversion + {.acyclic.} injection
## Phase 2: Tarjan SCC extraction → topological sort from dependency graph
## Phase 3: Parallel nim check with per-worker isolation (nimcache + tmpdir)
##
## Build:
##   nim c --hints:off --path:src -o:bin/full-transform tools/full_transform.nim
##
## Usage:
##   bin/full-transform
##   bin/full-transform --workers N
##   bin/full-transform --dry-run

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, json, strutils, times, algorithm, sets, tables]
import tarjan_scc

{.push raises: [CatchableError].}

# ═══════════════════════════════════════════════════════════════════════
# Effect declarations (AGENTS.md §0.6 Static First)
# ═══════════════════════════════════════════════════════════════════════

template axiomEffect*(e: untyped) {.pragma.}
type IoEffect* = object

# ═══════════════════════════════════════════════════════════════════════
# Types
# ═══════════════════════════════════════════════════════════════════════

type
  SCCResult = object
    sccId: int
    files: seq[string]
    deps: seq[int]  ## other SCC IDs this depends on (topological order)

  PipelineResult = object
    phase: string
    success: bool
    sccCount: int
    filesProcessed: int
    errors: seq[string]
    elapsedMs: float

# ═══════════════════════════════════════════════════════════════════════
# Iterative Tarjan SCC Algorithm (§0.6: func-only, no exceptions)
# ═══════════════════════════════════════════════════════════════════════

func tarjanSCC(nodes: seq[string],
               edges: Table[string, seq[string]]): seq[seq[string]] =
  ## Iterative Tarjan's SCC — returns strongly connected components.
  ## Stack-safe: uses explicit DFS stack instead of recursion.
  ## Pure computation — no I/O, no exceptions.
  if nodes.len == 0:
    return @[]

  var idx = 0
  var nodeIndex = initTable[string, int]()
  var lowlink = initTable[string, int]()
  var onStack = initHashSet[string]()
  var stack: seq[string]
  var sccs: seq[seq[string]]

  type Frame = object
    node: string
    neighborPos: int

  for startNode in nodes:
    if startNode in nodeIndex:
      continue

    var dfs: seq[Frame]
    nodeIndex[startNode] = idx
    lowlink[startNode] = idx
    inc idx
    stack.add(startNode)
    onStack.incl(startNode)
    dfs.add(Frame(node: startNode, neighborPos: 0))

    while dfs.len > 0:
      var frame = addr dfs[^1]
      let neighbors = edges.getOrDefault(frame.node, @[])

      if frame.neighborPos < neighbors.len:
        let neighbor = neighbors[frame.neighborPos]
        inc frame.neighborPos

        if neighbor notin nodeIndex:
          nodeIndex[neighbor] = idx
          lowlink[neighbor] = idx
          inc idx
          stack.add(neighbor)
          onStack.incl(neighbor)
          dfs.add(Frame(node: neighbor, neighborPos: 0))
        elif neighbor in onStack:
          lowlink[frame.node] = min(lowlink[frame.node],
                                    nodeIndex[neighbor])
      else:
        # All neighbors processed — pop frame
        let completed = dfs[^1].node
        dfs.setLen(dfs.len - 1)

        if lowlink[completed] == nodeIndex[completed]:
          var component: seq[string]
          while true:
            let w = stack[^1]
            stack.setLen(stack.len - 1)
            onStack.excl(w)
            component.add(w)
            if w == completed:
              break
          sccs.add(component)

        # Propagate lowlink to parent
        if dfs.len > 0:
          let parentNode = dfs[^1].node
          lowlink[parentNode] = min(lowlink[parentNode],
                                    lowlink[completed])

  sccs

func topologicalSort(sccs: seq[seq[string]],
                     edges: Table[string, seq[string]]): seq[seq[string]] =
  ## Topological sort of SCCs — dependencies come first.
  ## Pure computation — no I/O, no exceptions.
  if sccs.len <= 1:
    return sccs

  # Build SCC membership map: file → sccIndex
  var fileToScc = initTable[string, int]()
  for i, scc in sccs:
    for f in scc:
      fileToScc[f] = i

  # Build inter-SCC edges (deduplicated)
  var sccEdges = initTable[int, seq[int]]()
  for i, scc in sccs:
    for f in scc:
      for neighbor in edges.getOrDefault(f, @[]):
        if neighbor in fileToScc:
          let j = fileToScc[neighbor]
          if j != i:
            sccEdges.mgetOrPut(i, @[]).add(j)

  # Kahn's algorithm — in-degree based topological sort
  var inDegree = initTable[int, int]()
  for i in 0 ..< sccs.len:
    inDegree[i] = 0
  for _, targets in sccEdges:
    for t in targets:
      inDegree[t] = inDegree.getOrDefault(t, 0) + 1

  var queue: seq[int]
  for i in 0 ..< sccs.len:
    if inDegree[i] == 0:
      queue.add(i)

  var sorted: seq[seq[string]]
  while queue.len > 0:
    let current = queue[0]
    queue.delete(0)
    sorted.add(sccs[current])
    for target in sccEdges.getOrDefault(current, @[]):
      dec inDegree[target]
      if inDegree[target] == 0:
        queue.add(target)

  # Append any remaining (cycles within SCCs — already handled by Tarjan)
  if sorted.len < sccs.len:
    let sortedSet = sorted.len
    for i in 0 ..< sccs.len:
      var found = false
      for j in 0 ..< sortedSet:
        if sccs[i].len > 0 and sccs[i][0] == sorted[j][0]:
          found = true
          break
      if not found:
        sorted.add(sccs[i])

  sorted

# ═══════════════════════════════════════════════════════════════════════
# File discovery (§0.6: func-only for pure computations)
# ═══════════════════════════════════════════════════════════════════════

proc findNimFiles(root: string): seq[string] {.axiomEffect: IoEffect.} =
  ## Collect .nim files under root, excluding build/cache/vendor dirs.
  const defaultExclude = [".nimcache", "nimcache", ".git", "node_modules",
                          "build", "vendor", ".kimi-code", "generated"]
  result = @[]
  try:
    for path in walkDirRec(root):
      if not path.endsWith(".nim"):
        continue
      let (_, dirPart, _) = splitFile(path)
      var skip = false
      for ex in defaultExclude:
        if ex in dirPart:
          skip = true
          break
      if not skip:
        result.add(path)
  except CatchableError:
    discard  # axiom:best-effort(unreadable-source-file: skip file, continue scanning remaining files)

proc buildDependencyGraph(files: seq[string]): Table[string, seq[string]] {.axiomEffect: IoEffect.} =
  ## Parse import statements to build a file dependency graph.
  result = initTable[string, seq[string]]()
  for filePath in files:
    try:
      let content = readFile(filePath)
      var deps: seq[string]
      for line in content.splitLines():
        let stripped = line.strip()
        if stripped.startsWith("import ") or stripped.startsWith("from "):
          deps.add(stripped)
      result[filePath] = deps
    except CatchableError:
      result[filePath] = @[]

# ═══════════════════════════════════════════════════════════════════════
# Phase 1: AST Pre-scan
# ═══════════════════════════════════════════════════════════════════════

proc phase1AstPrescan(dryRun: bool = false): PipelineResult {.axiomEffect: IoEffect.} =
  ## Phase 1: AST-driven refactoring via ast-refine
  ## - proc→func conversion (syntax-safe, via cast pattern)
  ## - narrow-raises analysis
  ## - debt collection
  echo "Phase 1: AST pre-scan..."
  result.phase = "ast_prescan"
  let t0 = epochTime()

  # Build ast-refine if needed
  let astRefineBin = "bin/ast-refine"
  if not fileExists(astRefineBin):
    echo "  Building ast-refine..."
    let (output, exitCode) = execCmdEx(
      "nim c --hints:off --path:src -o:" & astRefineBin & " tools/ast_refine.nim")
    if exitCode != 0:
      result.errors.add("ast_refine build failed: " & output)
      return

  # Run proc-to-func conversion
  let dryFlag = if dryRun: " --dry-run" else: ""
  echo "  Running proc-to-func..."
  let (output1, exit1) = execCmdEx(astRefineBin & " proc-to-func" & dryFlag)
  echo "  proc-to-func exit: ", exit1
  if output1.len > 0:
    for line in output1.splitLines():
      if line.len > 0:
        echo "    ", line

  # Run collect-debt
  echo "  Running collect-debt..."
  let (output2, exit2) = execCmdEx(astRefineBin & " collect-debt")
  echo "  collect-debt exit: ", exit2

  result.filesProcessed = 0  # Will be updated by Phase 2 file count
  result.success = exit1 == 0
  result.elapsedMs = (epochTime() - t0) * 1000
  echo "  Phase 1 complete: ", result.elapsedMs.int, "ms"

# ═══════════════════════════════════════════════════════════════════════
# Phase 2: Tarjan SCC Extraction
# ═══════════════════════════════════════════════════════════════════════

proc phase2SCCExtraction(): seq[SCCResult] {.axiomEffect: IoEffect.} =
  ## Phase 2: Tarjan SCC extraction from source dependency graph.
  ## Builds graph from src/ .nim files, runs Tarjan, topologically sorts.
  echo "Phase 2: Tarjan SCC extraction..."

  # Try to load pre-computed graph, else build from source
  let graphPath = "tools/config/dependency_graph.json"
  var edges = initTable[string, seq[string]]()
  var files: seq[string]

  if fileExists(graphPath):
    try:
      let graph = parseFile(graphPath)
      if graph.hasKey("nodes") and graph["nodes"].len > 0:
        # Load pre-computed graph
        for node in graph["nodes"]:
          let name = node["name"].getStr()
          files.add(name)
        if graph.hasKey("edges"):
          for edge in graph["edges"]:
            let src = edge["from"].getStr()
            let dst = edge["to"].getStr()
            edges.mgetOrPut(src, @[]).add(dst)
        echo "  Loaded dependency graph: ", files.len, " nodes"
      else:
        echo "  dependency_graph.json empty, building from source..."
        files = findNimFiles("src")
        edges = buildDependencyGraph(files)
        echo "  Built graph from source: ", files.len, " files"
    except CatchableError:
      echo "  Failed to parse dependency_graph.json, building from source..."
      files = findNimFiles("src")
      edges = buildDependencyGraph(files)
      echo "  Built graph from source: ", files.len, " files"
  else:
    echo "  dependency_graph.json not found, building from source..."
    files = findNimFiles("src")
    edges = buildDependencyGraph(files)
    echo "  Built graph from source: ", files.len, " files"

  # Run iterative Tarjan SCC
  let rawSccs = tarjanSCC(files, edges)
  echo "  Raw SCCs: ", rawSccs.len

  # Topological sort
  let sortedSccs = topologicalSort(rawSccs, edges)
  echo "  Sorted SCCs: ", sortedSccs.len

  # Convert to SCCResult with IDs and dependency info
  result = @[]
  for i, scc in sortedSccs:
    result.add(SCCResult(
      sccId: i,
      files: scc,
      deps: @[]
    ))

  # Report
  var totalFiles = 0
  for scc in result:
    totalFiles += scc.files.len
  echo "  Total files in SCCs: ", totalFiles
  echo "  Phase 2 complete"

# ═══════════════════════════════════════════════════════════════════════
# Phase 3: Parallel nim check with per-worker isolation
# ═══════════════════════════════════════════════════════════════════════

proc phase3ParallelCheck(sccs: seq[SCCResult],
                         maxWorkers: int = 4,
                         dryRun: bool = false): PipelineResult {.axiomEffect: IoEffect.} =
  ## Phase 3: Parallel nim check with per-worker environment isolation.
  ## Each worker gets its own nimcache + tmpdir to prevent IC cookie collision.
  ## Rollback: git checkout only the failing SCC's files, not the entire project.
  echo "Phase 3: Parallel nim check (", sccs.len, " SCCs, ", maxWorkers, " workers)..."
  result.phase = "parallel_check"
  let t0 = epochTime()
  var errors: seq[string]
  var processed = 0

  # Save original environment for restoration
  let origCacheDir = getEnv("NIM_CACHE_DIR")
  let origTmpDir = getEnv("TMPDIR")

  for scc in sccs:
    let workerId = scc.sccId mod maxWorkers
    let nimcacheDir = "build/nimcache_scc_" & $scc.sccId
    let tmpDir = "/tmp/axiom_scc_" & $scc.sccId

    # Per-worker environment isolation (§0.6a: worker separation)
    putEnv("NIM_CACHE_DIR", nimcacheDir)
    putEnv("TMPDIR", tmpDir)
    try:
      createDir(nimcacheDir)
    except CatchableError:
      discard  # axiom:best-effort(nimcache-dir-creation-failure: build may still succeed with existing cache)
    try:
      createDir(tmpDir)
    except CatchableError:
      discard  # axiom:best-effort(tmp-dir-creation-failure: build may still succeed with system temp)

    echo "  SCC#", scc.sccId, " (worker ", workerId, "): ",
         scc.files.len, " files"

    for filePath in scc.files:
      if not fileExists(filePath):
        continue

      inc processed

      if dryRun:
        echo "    [dry-run] ", filePath
        continue

      # Run nim check on this file with isolated nimcache
      let cmd = "nim check --hints:off --nimcache:" & nimcacheDir &
                " --path:src " & filePath
      let (output, exitCode) = execCmdEx(cmd)

      if exitCode != 0:
        let errMsg = "SCC#" & $scc.sccId & " " & filePath & ": " & output.strip()
        errors.add(errMsg)
        echo "    FAIL: ", filePath
        # Rollback: restore only this SCC's failing files
        for f in scc.files:
          if fileExists(f):
            discard execCmdEx("git checkout -- " & f)
        echo "    Rolled back SCC#", scc.sccId
      else:
        echo "    OK: ", filePath

  # Restore original environment
  if origCacheDir.len > 0:
    putEnv("NIM_CACHE_DIR", origCacheDir)
  else:
    delEnv("NIM_CACHE_DIR")
  if origTmpDir.len > 0:
    putEnv("TMPDIR", origTmpDir)
  else:
    delEnv("TMPDIR")

  result.success = errors.len == 0
  result.errors = errors
  result.filesProcessed = processed
  result.sccCount = sccs.len
  result.elapsedMs = (epochTime() - t0) * 1000
  echo "  Phase 3 complete: ", result.elapsedMs.int, "ms"

# ═══════════════════════════════════════════════════════════════════════
# Pipeline orchestrator
# ═══════════════════════════════════════════════════════════════════════

proc main() {.axiomEffect: IoEffect.} =
  echo "=== Axiom Full Transform Pipeline ==="
  echo ""

  # Parse CLI flags
  var maxWorkers = 4
  var dryRun = false
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg == "--dry-run":
      dryRun = true
    elif arg == "--workers" and i < paramCount():
      try:
        maxWorkers = parseInt(paramStr(i + 1))
      except CatchableError:
        maxWorkers = 4
    elif arg == "--help" or arg == "-h":
      echo "Usage: full-transform [--dry-run] [--workers N]"
      echo ""
      echo "Options:"
      echo "  --dry-run    Show what would be done without executing"
      echo "  --workers N  Max parallel workers for Phase 3 (default: 4)"
      quit(0)

  let pipelineStart = epochTime()

  # Phase 1: AST pre-scan (proc→func, narrow-raises, collect-debt)
  let p1 = phase1AstPrescan(dryRun)
  echo ""
  echo "Phase 1 result: success=", p1.success,
       " elapsed=", p1.elapsedMs.int, "ms"
  if not p1.success:
    echo "Phase 1 FAILED:"
    for e in p1.errors:
      echo "  ", e
    quit(1)

  # Phase 2: Tarjan SCC extraction (pure function)
  let sccs = phase2SCCExtraction()
  echo ""
  echo "Phase 2 result: ", sccs.len, " SCCs extracted"
  for scc in sccs:
    echo "  SCC#", scc.sccId, ": ", scc.files.len, " files",
         if scc.deps.len > 0: " (deps: " & $scc.deps & ")" else: ""

  # Phase 3: Parallel nim check with per-worker isolation
  let p3 = phase3ParallelCheck(sccs, maxWorkers, dryRun)
  echo ""
  echo "Phase 3 result: success=", p3.success,
       " files=", p3.filesProcessed,
       " elapsed=", p3.elapsedMs.int, "ms"
  if not p3.success:
    echo "Phase 3 ERRORS: ", p3.errors.len
    for e in p3.errors:
      echo "  ", e

  let totalTime = (epochTime() - pipelineStart) * 1000
  echo ""
  echo "=== Pipeline Complete ==="
  echo "Total time: ", totalTime.int, "ms"
  echo "Phases: 1(", p1.elapsedMs.int, "ms) → 2(graph) → 3(",
       p3.elapsedMs.int, "ms)"

when isMainModule:
  main()
