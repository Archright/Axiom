import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [Exception].}

## Module dependency topology sort with Tarjan SCC integration.
##
## Full pipeline: extract imports → build graph → detect cycles → topological sort
## → layered CI job generation.  Uses ``tarjan_scc`` for circular dependency
## detection and Kahn's algorithm for the ordering itself.

import std/[os, strutils, algorithm, tables, sequtils]
import tarjan_scc

# ---------------------------------------------------------------------------
# Import extraction
# ---------------------------------------------------------------------------

func isStdModule(name: string): bool =
  ## True if *name* refers to a standard-library or third-party package
  ## (prefix ``std/`` or contains ``/`` but is not a bare identifier).
  name.startsWith("std/") or '/' in name

proc extractImports*(filePath: string): seq[string] =
  ## Parse a ``.nim`` file and extract all ``import`` / ``from`` statements.
  ## Returns module names (not file paths).  Standard-library modules
  ## (``std/…``) are included so the caller can filter them later.
  let content = readFile(filePath)
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("#"):
      continue
    if trimmed.startsWith("import ") or trimmed.startsWith("from "):
      let isFrom = trimmed.startsWith("from ")
      var body = trimmed
      if isFrom:
        # "from foo import bar, baz" → we want "foo"
        body = body[4..^1]  # drop "from"
      else:
        body = body[7..^1]  # drop "import"

      # Strip trailing "import …" clause for from-imports.
      if isFrom:
        let impIdx = body.find(" import ")
        if impIdx >= 0:
          body = body[0 ..< impIdx]

      # Handle bracket imports: std/[os, strutils] → std/os, std/strutils
      let bracketStart = body.find('[')
      if bracketStart >= 0:
        let bracketEnd = body.find(']')
        if bracketEnd > bracketStart:
          let prefix = body[0 ..< bracketStart].strip()
          let inner = body[bracketStart + 1 ..< bracketEnd]
          for item in inner.split(','):
            let modName = item.strip()
            if modName.len > 0:
              if prefix.len > 0:
                result.add(prefix & "/" & modName)
              else:
                result.add(modName)
          continue

      # Plain comma-separated or single import.
      for item in body.split(','):
        let modName = item.strip()
        if modName.len > 0:
          result.add(modName)

# ---------------------------------------------------------------------------
# Topology sort (Kahn's algorithm)
# ---------------------------------------------------------------------------

proc topologicalSort*(graph: ModuleGraph): seq[seq[string]] =
  ## Kahn's algorithm — returns modules grouped by dependency layer.
  ##
  ## * Layer 0 = no dependencies (roots).
  ## * Layer 1 = depends only on Layer 0, etc.
  ##
  ## Uses ``tarjan_scc.detectCycles``; if cycles exist the procedure
  ## prints a fatal report and calls ``quit(1)``.
  let cycles = detectCycles(graph)
  if cycles.len > 0:
    echo formatCycles(cycles)
    quit(1)

  # Compute in-degree for every node.
  var inDegree: Table[string, int]
  for node in graph.nodes:
    if node notin inDegree:
      inDegree[node] = 0
  for node, neighbors in graph.adjList:
    for nb in neighbors:
      discard inDegree.hasKeyOrPut(nb, 0)
      inc inDegree[nb]

  # Seed layer 0 with zero-in-degree nodes.
  var currentLayer: seq[string]
  for node in graph.nodes:
    if inDegree.getOrDefault(node, 0) == 0:
      currentLayer.add(node)
  currentLayer.sort(proc(a, b: string): int = cmp(a, b))

  var remaining = inDegree
  while currentLayer.len > 0:
    result.add(currentLayer)
    var nextLayer: seq[string]
    for node in currentLayer:
      for nb in graph.adjList.getOrDefault(node, @[]):
        dec remaining[nb]
        if remaining[nb] == 0:
          nextLayer.add(nb)
    nextLayer.sort(proc(a, b: string): int = cmp(a, b))
    currentLayer = nextLayer

# ---------------------------------------------------------------------------
# Layer building
# ---------------------------------------------------------------------------

proc buildLayers*(modules: seq[string],
                  getImports: proc(module: string): seq[string]): seq[seq[string]] =
  ## Build dependency layers for parallel CI.
  ##
  ## Constructs a ``ModuleGraph`` from *modules* and *getImports*, runs
  ## cycle detection via ``tarjan_scc``, then produces the layered
  ## ordering via ``topologicalSort``.
  let graph = buildGraph(modules, getImports)
  result = topologicalSort(graph)

# ---------------------------------------------------------------------------
# CI job generation
# ---------------------------------------------------------------------------

proc generateCIJobs*(layers: seq[seq[string]]): string =
  ## Generate CircleCI YAML job definitions for layered parallel execution.
  ##
  ## Each layer becomes a ``layer_N`` job that runs its modules in
  ## parallel.  Layers are serialized via ``requires`` so layer *N+1*
  ## only starts after layer *N* succeeds.
  result = "# Auto-generated by tools/module_topology.nim\n"
  result.add("# Layered CI jobs — each layer runs its modules in parallel.\n\n")
  result.add("jobs:\n")

  for i, layer in layers:
    let layerId = "layer_" & $i
    result.add("  " & layerId & ":\n")
    result.add("    docker:\n")
    result.add("      - image: nimlang/nim:2.2.10\n")
    result.add("    steps:\n")
    result.add("      - checkout\n")
    for moduleName in layer:
      result.add("      - run:\n")
      result.add("          name: test " & moduleName & "\n")
      result.add("          command: nim c --hints:off -r " & moduleName & "\n")

  # Workflow wiring.
  result.add("\nworkflows:\n")
  result.add("  layered_test:\n")
  result.add("    jobs:\n")
  for i, _ in layers:
    let layerId = "layer_" & $i
    if i == 0:
      result.add("      - " & layerId & "\n")
    else:
      result.add("      - " & layerId & ":\n")
      result.add("          requires:\n")
      result.add("            - layer_" & $(i - 1) & "\n")

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

proc run*(modules: seq[string]): int =
  ## Full pipeline: extract imports → build graph → topological sort → report.
  ##
  ## Returns 0 on success, 1 on cycle detection or other error.
  if modules.len == 0:
    echo "module_topology: no modules provided"
    return 1

  # Build the graph via the import extraction callback.
  let getImports = proc (module: string): seq[string] =
    ## Callback that reads *module* as a file path and returns its imports,
    ## filtering out standard-library modules (``std/…``).
    let path =
      if fileExists(module): module
      else: module & ".nim"
    if not fileExists(path):
      return @[]
    extractImports(path).filterIt(not isStdModule(it))

  let graph = buildGraph(modules, getImports)

  # Detect cycles first.
  let cycles = detectCycles(graph)
  if cycles.len > 0:
    echo formatCycles(cycles)
    return 1

  # Topological sort.
  let layers = topologicalSort(graph)

  # Report.
  echo "Module topology (" & $modules.len & " modules, " &
       $layers.len & " layers):"
  for i, layer in layers:
    echo "  Layer " & $i & ": " & layer.join(", ")
  echo ""

  # CI job output.
  echo generateCIJobs(layers)
  return 0

{.pop.}
