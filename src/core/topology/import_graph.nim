import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## import_graph.nim — Shared module dependency graph builder
##
## Extracted from dag_enforcement_gate.nim for DRY reuse across
## gate and discovery tools (AGENTS.md §1.3 DRY).
##
## Context7-verified: Nim module graphs are DAGs by design
## (Nim compiler modulegraphs.html).

import std/[os, strutils, sets, tables]
import core/axiom_pragmas
import core/macros/best_effort

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  ModuleEdge* = tuple[fromModule, toModule: string]

const CoreDir* = "src/core"

# ---------------------------------------------------------------------------
# Internal: resolve import expressions
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveModuleName(currentDir, importExpr: string): string {.raises: [OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Resolve a Nim import expression relative to current file location.
  ## Returns empty string if not a core/ module.
  var expr = importExpr.strip()
  # Remove 'as', 'except' clauses
  if " as " in expr:
    expr = expr.split(" as ")[0].strip()
  if " except " in expr:
    expr = expr.split(" except ")[0].strip()

  if expr.startsWith("std/") or expr.startsWith("vendor/"):
    return ""

  if expr.startsWith("core/"):
    result = expr[5..^1]
  elif expr.startsWith("./") or expr.startsWith("../"):
    var base = currentDir
    var remaining = expr
    while remaining.startsWith("../"):
      base = parentDir(base)
      remaining = remaining[3..^1]
    if remaining.startsWith("./"):
      remaining = remaining[2..^1]
    result = base / remaining
    result = result.replace("\\", "/")
    if result.startsWith("src/core/"):
      result = result[9..^1]
    elif result.startsWith("core/"):
      result = result[5..^1]
  else:
    let localPath = currentDir / expr
    if fileExists(localPath & ".nim"):
      result = localPath.replace("\\", "/")
      if result.startsWith("src/core/"):
        result = result[9..^1]
      elif result.startsWith("core/"):
        result = result[5..^1]
    else:
      let corePath = CoreDir / expr
      if fileExists(corePath & ".nim"):
        result = expr
      else:
        for kind, path in walkDir(CoreDir):
          if kind == pcDir:
            let subPath = path / expr
            if fileExists(subPath & ".nim"):
              result = expr
              return
        result = ""

# ---------------------------------------------------------------------------
# Public API: graph construction
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractCoreImports*(filePath: string): seq[string] {.raises: [OSError, ValueError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""file read — empty content on failure""").} =
  ## Extract all imports that resolve to core/ modules.
  result = @[]
  let content = try: readFile(filePath) except CatchableError: ""
  if content.len == 0:
    return

  let currentDir = parentDir(absolutePath(filePath))
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if not (line.startsWith("import ") or line.startsWith("from ")):
      continue
    let prefix = if line.startsWith("import "): "import " else: "from "
    let after = line[prefix.len..^1]
    for part in after.split(','):
      let modName = resolveModuleName(currentDir, part)
      if modName.len > 0 and modName notin result:
        result.add(modName)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc buildImportGraph*(coreDir: string): Table[string, seq[string]] {.raises: [OSError, ValueError].} =
  ## Build a dependency graph of all modules under coreDir.
  ## Keys are relative module paths (e.g., "types/domain_types").
  ## Values are lists of imported core module paths.
  result = initTable[string, seq[string]]()
  for path in walkDirRec(coreDir, {pcFile}):
    if not path.endsWith(".nim"):
      continue
    let relPath = path[coreDir.len+1..^5]  # strip "src/core/" and ".nim"
    let imports = extractCoreImports(path)
    if imports.len > 0:
      result[relPath] = imports

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc countCoreModules*(coreDir: string): int {.raises: [OSError].} =
  ## Count all .nim files under coreDir.
  result = 0
  for path in walkDirRec(coreDir, {pcFile}):
    if path.endsWith(".nim"):
      result.inc

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func countCoreModulesFromGraph*(graph: Table[string, seq[string]]): int {.raises: [].} =
  ## Count modules from an already-built import graph (avoids re-walking the directory).
  result = graph.len

# ---------------------------------------------------------------------------
# Public API: graph analysis (pure, func)
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func findCycles*(graph: Table[string, seq[string]]): seq[seq[string]] {.raises: [].} =
  ## Detect all cycles in the dependency graph using iterative DFS.
  var cycles: seq[seq[string]] = @[]
  var visited = initHashSet[string]()

  for startNode in graph.keys:
    if startNode in visited:
      continue
    var stack: seq[tuple[node: string, path: seq[string], pathSet: HashSet[string]]] = @[]
    stack.add((node: startNode, path: @[startNode], pathSet: toHashSet([startNode])))
    while stack.len > 0:
      let current = stack.pop()
      visited.incl(current.node)
      for neighbor in graph.getOrDefault(current.node):
        if neighbor in current.pathSet:
          var cycle: seq[string] = @[]
          var started = false
          for n in current.path:
            if n == neighbor:
              started = true
            if started:
              cycle.add(n)
          if cycle.len > 0 and cycle notin cycles:
            cycles.add(cycle)
        elif neighbor notin visited:
          var newPath = current.path
          newPath.add(neighbor)
          var newSet = current.pathSet
          newSet.incl(neighbor)
          stack.add((node: neighbor, path: newPath, pathSet: newSet))
  result = cycles

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeTopologicalLayers*(graph: Table[string, seq[string]]): seq[seq[string]] {.raises: [].} =
  ## Compute topological layers using Kahn's algorithm.
  ## Layer 0 = leaf nodes (no incoming edges from other core modules).
  ## Layer N+1 = nodes whose dependencies are all in layers ≤ N.
  var indegree = initTable[string, int]()
  for node in graph.keys:
    if node notin indegree:
      indegree[node] = 0
    for neighbor in graph.getOrDefault(node, @[]):
      indegree[neighbor] = indegree.getOrDefault(neighbor, 0) + 1

  var remaining = indegree
  while remaining.len > 0:
    var layer: seq[string] = @[]
    for node, deg in remaining:
      if deg == 0:
        layer.add(node)
    if layer.len == 0:
      # Cycle detected — should not happen for a DAG
      break
    result.add(layer)
    for node in layer:
      remaining.del(node)
      for neighbor in graph.getOrDefault(node, @[]):
        if neighbor in remaining:
          remaining[neighbor] = remaining.getOrDefault(neighbor, 0) - 1

# ---------------------------------------------------------------------------
# Public API: reverse dependency graph (Phase 5.3 — Import Tree transitive dependents)
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildReverseGraph*(graph: Table[string, seq[string]]): Table[string, seq[string]] {.raises: [].} =
  ## Build reverse dependency graph: for each module, list modules that depend on it.
  ## If module A imports B, then reverseGraph[B] contains A.
  ## Used for transitive dependent analysis (Phase 5.3).
  result = initTable[string, seq[string]]()
  for src, deps in graph:
    for dep in deps:
      result.mgetOrPut(dep, @[]).add(src)
  # Ensure all modules appear as keys even if nothing depends on them
  for src in graph.keys:
    if src notin result:
      result[src] = @[]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func transitiveDependents*(reverseGraph: Table[string, seq[string]],
                           changedModules: HashSet[string]): HashSet[string] {.raises: [].} =
  ## BFS through reverse edges from changedModules to find all transitively
  ## affected modules. Returns changedModules ∪ all modules that (directly
  ## or transitively) import any module in changedModules.
  result = changedModules
  var queue: seq[string]
  for m in changedModules:
    queue.add(m)
  while queue.len > 0:
    let current = queue[^1]
    queue.setLen(queue.len - 1)
    for dependent in reverseGraph.getOrDefault(current):
      if dependent notin result:
        result.incl(dependent)
        queue.add(dependent)

{.pop.}
