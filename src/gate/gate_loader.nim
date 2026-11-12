## gate_loader.nim — SSOT-based gate configuration loader and DAG validator.
##
## Architecture pipeline:
##   config/gates.json (runtime config SSOT)
##         ↓
##   topology_spec.nim (dependency topology SSOT)
##         ↓
##   gate_loader.nim (loads, validates DAG, generates registrations)
##         ↓
##   declareGate (registers in global registry)
##         ↓
##   dag_executor.nim (executes in topological order)
##
## Responsibilities:
##   1. Parse config/gates.json → GateConfigEntry catalog
##   2. Derive dependency graph from TopologySpec.after edges
##   3. Validate DAG acyclicity via Kahn's algorithm (compile-time when possible)
##   4. Generate declareGate calls for all enabled gates
##   5. Provide O(1) gate lookup by ID at runtime
##
## Usage:
##   import gate/gate_loader
##   let loader = newGateLoader()
##   loader.loadConfig()
##   loader.validateDag()
##   loader.registerAllGates()

import std/[json, tables, strformat, strutils, os, algorithm, sets]
import core/trusted/layer_declaration
axiomLayer "gate"

import core/trusted/axiom_pragmas
import gate/topology_spec     # TopologySpec, initTopologyEntry, WeightKind
import gate/config_loader     # GateRuntimeConfig, loadGateRuntimeConfigFromRoot
import core/utils/repo_root   # findRepoRoot
import infrastructure/logger  # logger
import gate/framework/topology_types  # WeightKind, TopologyEntry

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  ## GateConfigEntry holds the parsed configuration for a single gate.
  GateConfigEntry* = object
    id*: string
    enabled*: bool

  ## GateHandlerInfo carries the handler reference and dependency metadata
  ## for a single gate after topology analysis.
  GateHandlerInfo* = object
    config*: GateConfigEntry
    dependsOn*: seq[string]    ## Derived from TopologySpec[].after
    entry*: string             ## Source path from TopologySpec[].entry
    tier*: int                 ## Execution tier from TopologySpec
    weight*: string            ## "light" | "medium" | "heavy"

  ## GateLoader is the central loader that combines runtime config with
  ## compile-time topology to produce a validated, ready-to-register gate map.
  GateLoader* = ref object
    configMap*: Table[string, GateConfigEntry]
    handlerMap*: Table[string, GateHandlerInfo]
    sortedIds*: seq[string]    ## Topologically sorted gate IDs
    validationErrors*: seq[string]

# ---------------------------------------------------------------------------
# Config Parsing (from gates.json)
# ---------------------------------------------------------------------------

func newGateLoader*(): GateLoader =
  ## Create a fresh GateLoader instance.
  result = GateLoader()
  result.configMap = initTable[string, GateConfigEntry]()
  result.handlerMap = initTable[string, GateHandlerInfo]()
  result.sortedIds = @[]
  result.validationErrors = @[]

func isEmpty*(loader: GateLoader): bool =
  ## True when no configuration has been loaded yet.
  loader.configMap.len == 0

# ---------------------------------------------------------------------------
# Gates.json Loading
# ---------------------------------------------------------------------------

proc loadConfig*(loader: var GateLoader, root: string) {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load config/gates.json and populate loader.configMap.
  ## Reuses config_loader.nim's GateRuntimeConfig internally and
  ## translates it into GateConfigEntry entries.
  let catalog = loadGateRuntimeConfigFromRoot(root)

  for key, rcfg in catalog.data:
    loader.configMap[key] = GateConfigEntry(
      id: key,
      enabled: rcfg.enabled
    )

  if loader.configMap.len > 0:
    logger.info(&"[gate-loader] Loaded {loader.configMap.len} gate(s) from config/gates.json")
  else:
    logger.warn("[gate-loader] No gates found in config/gates.json, using empty catalog")

proc loadConfig*(loader: var GateLoader) {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Convenience overload: auto-detect repo root.
  let root = findRepoRoot()
  loader.loadConfig(root)

# ---------------------------------------------------------------------------
# Topology Analysis — derive dependsOn from TopologySpec.after edges
# ---------------------------------------------------------------------------

proc buildDependencyGraph*(loader: var GateLoader) =
  ## Walk TopologySpec and populate handlerMap with dependency info.
  ## This connects the compile-time topology to runtime config.

  for spec in TopologySpec:
    let gid = spec.id

    # Skip if already processed
    if gid in loader.handlerMap:
      continue

    # Get config from loader.configMap (or use defaults)
    let configEntry = loader.configMap.getOrDefault(gid, GateConfigEntry(
      id: gid,
      enabled: true  # Default to enabled if not in config
    ))

    # Create handler info from topology spec
    let info = GateHandlerInfo(
      config: configEntry,
      dependsOn: spec.after,  # Direct mapping from topology
      entry: spec.entry,
      tier: spec.tier,
      weight: $spec.weight  # Convert WeightKind to string
    )

    loader.handlerMap[gid] = info

  logger.info(&"[gate-loader] Mapped {loader.handlerMap.len} gate(s) to topology entries")

# ---------------------------------------------------------------------------
# DAG Cycle Detection (Kahn's algorithm)
# ---------------------------------------------------------------------------

func detectCycles*(loader: var GateLoader): seq[string] =
  ## Detect circular dependencies using Kahn's algorithm.
  ## Returns list of gates involved in cycles (empty = no cycles).

  var inDegree = initTable[string, int]()
  var adjList = initTable[string, seq[string]]()
  var zeroDegree = initHashSet[string]()

  # Initialize
  for gid, info in loader.handlerMap:
    inDegree[gid] = 0
    adjList[gid] = @[]

  # Build adjacency list and compute in-degree
  for gid, info in loader.handlerMap:
    for dep in info.dependsOn:
      if dep in loader.handlerMap:
        adjList[dep].add(gid)
        inDegree[gid] = inDegree[gid] + 1

  # Find initial zero-degree nodes
  for gid, deg in inDegree:
    if deg == 0:
      zeroDegree.incl(gid)

  # Kahn's algorithm
  var topoOrder: seq[string] = @[]
  var visited = initHashSet[string]()

  while zeroDegree.len > 0:
    let node = zeroDegree.pop()
    topoOrder.add(node)
    visited.incl(node)

    for neighbor in adjList[node]:
      inDegree[neighbor] = inDegree[neighbor] - 1
      if inDegree[neighbor] == 0:
        zeroDegree.incl(neighbor)

  # Check for cycles
  if topoOrder.len < loader.handlerMap.len:
    # Cycles detected — find nodes not in topoOrder
    for gid in loader.handlerMap.keys:
      if gid notin visited:
        result.add(gid)

  loader.sortedIds = topoOrder

proc validateDag*(loader: var GateLoader): bool =
  ## Validate DAG and populate validationErrors.
  ## Returns true if DAG is valid (no cycles).

  loader.validationErrors = @[]
  let cycleNodes = detectCycles(loader)

  if cycleNodes.len > 0:
    loader.validationErrors.add(&"Circular dependency detected involving: {cycleNodes}")
    logger.error(&"[gate-loader] DAG validation FAILED: cycles detected")
    return false

  logger.info(&"[gate-loader] DAG validation PASSED: {loader.sortedIds.len} gates topologically sorted")
  return true



# ---------------------------------------------------------------------------
# Full Pipeline
# ---------------------------------------------------------------------------

proc fullLoad*(loader: var GateLoader, root: string) {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute full loading pipeline: config → topology → validation → sort.
  loader.loadConfig(root)
  loader.buildDependencyGraph()
  discard loader.validateDag()

proc fullLoad*(loader: var GateLoader) {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Convenience overload: auto-detect repo root.
  let root = findRepoRoot()
  loader.fullLoad(root)

# ---------------------------------------------------------------------------
# Debug/Introspection
# ---------------------------------------------------------------------------

func describe*(loader: GateLoader): string =
  ## Return human-readable summary of loader state.
  result = ""
  result.add(&"Total gates in topology: {TopologySpec.len}\n")
  result.add(&"Loaded from config: {loader.configMap.len}\n")
  result.add(&"Mapped to handlers: {loader.handlerMap.len}\n")
  result.add(&"Topologically sorted: {loader.sortedIds.len}\n")

  if loader.validationErrors.len > 0:
    result.add(&"VALIDATION ERRORS:\n")
    for err in loader.validationErrors:
      result.add(&"  - {err}\n")
  else:
    result.add("No validation errors\n")

  result.add("\nTopological order:\n")
  for i, gid in loader.sortedIds:
    let marker = if gid in loader.handlerMap and loader.handlerMap[gid].config.enabled: "✓" else: "✗"
    result.add(&"{marker} {i+1}. {gid}\n")

# ---------------------------------------------------------------------------
# Module Initialization
# ---------------------------------------------------------------------------

when isMainModule:
  ## Test harness for gate_loader.nim
  var loader = newGateLoader()
  loader.fullLoad()
  echo loader.describe()
