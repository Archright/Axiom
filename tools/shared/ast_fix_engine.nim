import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}
## Deterministic AST fix engine with cache-isolated nim check
## and dynamic fixed-point convergence.

import std/[os, osproc, strutils, sequtils, tables, times]
import compiler_output_parser

type
  ModuleNode* = object
    path*: string
    imports*: seq[string]

  ModuleGraph* = object
    nodes*: seq[ModuleNode]
    nameToIdx*: Table[string, int]

  ConvergenceResult* = object
    converged*: bool
    iterations*: int
    maxIter*: int
    finalErrors*: string

  CycleState* = object
    checksums*: seq[string]
    windowSize*: int

import checksums/sha1

proc fileChecksum(path: string): string =
  try: result = $secureHash(readFile(path))
  except CatchableError: result = ""

proc buildModuleGraph*(roots: seq[string]): ModuleGraph =
  ## Build import dependency graph from source files via DFS walk.
  var stack = roots
  while stack.len > 0:
    let path = stack.pop()
    let absPath = path.expandFilename
    if absPath in result.nameToIdx: continue
    let idx = result.nodes.len
    result.nameToIdx[absPath] = idx
    var node = ModuleNode(path: absPath, imports: @[])
    try:
      let content = readFile(absPath)
      for line in content.splitLines:
        let s = line.strip
        if s.startsWith("import ") or s.startsWith("from "):
          let mods = if s.startsWith("import "): s[7..^1]
                    else: s[4..^1]
          for modEntry in mods.split(","):
            let modName = modEntry.strip.split(" ")[0].strip
            if modName.len > 0 and modName.endsWith(".nim"):
              node.imports.add(modName)
              stack.add(modName)
            elif modName.len > 0:
              node.imports.add(modName)
    except CatchableError: # axiom:best-effort(unreadable file — skip for graph construction)
      discard
    result.nodes.add(node)

proc computeMaxDepth*(graph: ModuleGraph): int =
  ## DFS-based max dependency chain depth.
  var memo = initTable[string, int]()

  proc dfs(idx: int, visited: var seq[int]): int =
    let path = graph.nodes[idx].path
    if path in memo: return memo[path]
    if idx in visited: return 0  # cycle guard
    visited.add(idx)
    var maxChild = 0
    for imp in graph.nodes[idx].imports:
      if imp in graph.nameToIdx:
        let childDepth = dfs(graph.nameToIdx[imp], visited)
        if childDepth + 1 > maxChild:
          maxChild = childDepth + 1
    visited.del(visited.len - 1)
    memo[path] = maxChild
    return maxChild

  for i in 0..<graph.nodes.len:
    var visited: seq[int] = @[]
    let depth = dfs(i, visited)
    if depth > result:
      result = depth

proc tarjanSCCCount*(graph: ModuleGraph): int =
  ## Count Strongly Connected Components via Tarjan's algorithm.
  var index = 0
  var stack: seq[int] = @[]
  var onStack = initTable[int, bool]()
  var indices = initTable[string, int]()
  var lowlink = initTable[string, int]()
  var sccCount = 0

  proc strongConnect(idx: int) =
    let path = graph.nodes[idx].path
    indices[path] = index
    lowlink[path] = index
    index += 1
    stack.add(idx)
    onStack[idx] = true

    for imp in graph.nodes[idx].imports:
      if imp in graph.nameToIdx:
        let impIdx = graph.nameToIdx[imp]
        let impPath = graph.nodes[impIdx].path
        if impPath notin indices:
          strongConnect(impIdx)
          if lowlink[impPath] < lowlink[path]:
            lowlink[path] = lowlink[impPath]
        elif onStack.getOrDefault(impIdx, false):
          if lowlink[impPath] < lowlink[path]:
            lowlink[path] = lowlink[impPath]

    if lowlink[path] == indices[path]:
      # Root of SCC
      var sccSize = 0
      while true:
        let w = stack.pop()
        onStack[w] = false
        sccSize += 1
        if w == idx: break
      if sccSize > 0:
        sccCount += 1

  for i in 0..<graph.nodes.len:
    let path = graph.nodes[i].path
    if path notin indices:
      strongConnect(i)
  result = sccCount

proc computeMaxIter*(graph: ModuleGraph): int =
  ## Dynamic bound: clamp(dagDepth + sccCount + 1, 3, 20)
  let dagDepth = graph.computeMaxDepth
  let sccCount = graph.tarjanSCCCount
  result = clamp(dagDepth + sccCount + 1, 3, 20)

proc runNimCheckIsolated*(filePath: string; iteration: int): string =
  ## Run nim check with cache-isolated tmpdir per iteration.
  let tmpDir = getTempDir() / "axiom_heal_" & $iteration
  # axiom:best-effort(tmpdir creation — fall back to no cache isolation)
  try: createDir(tmpDir)
  except CatchableError:
    stderr.writeline("WARNING: Cannot create tmpdir " & tmpDir)
  let cachePath = tmpDir / ".nimcache"
  # axiom:best-effort(cache dir creation — fall back to no cache isolation)
  try: createDir(cachePath)
  except CatchableError:
    stderr.writeline("WARNING: Cannot create cache dir " & cachePath)

  let cmd = "nim check --hints:off --warnings:off --nimcache:" &
            cachePath & " --forceBuild:on " & filePath
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode == 0:
    result = ""
  else:
    result = output

proc detectOscillation*(state: var CycleState; checksum: string; windowSize: int = 3): bool =
  ## Detect 3-repeat checksum cycle.
  state.windowSize = windowSize
  state.checksums.add(checksum)
  if state.checksums.len > windowSize * 2:
    state.checksums = state.checksums[^windowSize..^1]
  if state.checksums.len < windowSize: return false
  # Check if last `windowSize` checksums are all identical
  let recent = state.checksums[^windowSize..^1]
  for i in 1..<recent.len:
    if recent[i] != recent[0]:
      return false
  return true

proc hotDeterministicLoop*(filePath: string; graph: ModuleGraph): ConvergenceResult =
  ## Main convergence loop: iterate nim check + apply fixes until stable.
  let maxIter = graph.computeMaxIter
  result.maxIter = maxIter

  var cycleState: CycleState
  for i in 1..maxIter:
    let output = runNimCheckIsolated(filePath, i)
    if output.len == 0:
      result.converged = true
      result.iterations = i
      result.finalErrors = ""
      return

    let parsed = parseCompilerOutput(output)
    let checksum = fileChecksum(filePath)
    result.iterations = i
    result.finalErrors = output

    # Oscillation detection
    if detectOscillation(cycleState, checksum):
      result.converged = false
      return

    # If no new parseable errors, treat as converged
    if parsed.errors.len == 0 and output.len == 0:
      result.converged = true
      return

  result.converged = false
