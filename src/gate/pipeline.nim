import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## pipeline.nim — DAG-based gate scheduler
##
## Pure state machine: Gate Configs → Kahn's DAG build → Layer-by-layer
## parallel execution via malebolgia → ResultTable.
##
## Each layer executes independent gates in parallel.
## PipelineContext is a value type — each gate receives its own immutable copy.
## The gateRunner callback allows the orchestrator to inject gate execution
## logic without tight coupling to the pipeline engine.
##
## Malebolgia integration pattern (from loop_driver.nim):
## - Heap-allocate shared context via `create()`, pass as `pointer`
## - Gcsafe wrapper takes only gcsafe args (string, pointer)
## - `{.cast(gcsafe).}` inside wrapper for non-gcsafe body

import std/[monotimes, tables]
import core/observer
import gate/gate_types
import malebolgia

# ─── Result Types ──────────────────────────────────────────────────────────

type
  LayerResult* = object
    ## Result of executing a single gate within a parallel layer.
    gateId*: string
    passed*: bool
    output*: string
    durationMs*: float

  DAGResult* = object
    ## Full result of DAG execution — all layers, all gates.
    layers*: seq[seq[LayerResult]]
    allPassed*: bool
    totalDurationMs*: float

  ## Heap-allocated context shared across parallel gate workers.
  ## All workers receive a `pointer` to this — read-only access.
  GateWorkerContext = object
    ctx: PipelineContext
    runner: proc(gateId: string; ctx: PipelineContext): bool {.nimcall, raises: [].}

# ─── Kahn's Algorithm: Topological Sort ────────────────────────────────────

func buildDAG*(configs: seq[GateConfig]): seq[seq[GateConfig]] {.raises: [].} =
  ## Topological sort using Kahn's algorithm.
  ##
  ## Builds a DAG from the ``after`` dependency field of each GateConfig.
  ## Returns gates grouped by depth — each inner seq is one layer of
  ## independent gates that may execute in parallel.
  ##
  ## Returns an empty seq if a cycle is detected (caller handles).
  if configs.len == 0:
    return @[]

  # Build id → index lookup
  var idToIdx: Table[string, int]
  for i, cfg in configs:
    idToIdx[cfg.id] = i

  # Compute in-degrees and dependent lists
  var inDegree = newSeq[int](configs.len)
  var dependents = newSeq[seq[int]](configs.len)

  for i, cfg in configs:
    for depId in cfg.after:
      let depIdx = idToIdx.getOrDefault(depId, -1)
      if depIdx >= 0:
        dependents[depIdx].add(i)
        inc inDegree[i]

  # Kahn's algorithm: process zero-degree nodes level by level
  var layers: seq[seq[GateConfig]]
  var processed = 0
  var frontier: seq[int]

  for i in 0..<configs.len:
    if inDegree[i] == 0:
      frontier.add(i)

  while frontier.len > 0:
    var currentLayer: seq[GateConfig]
    var nextFrontier: seq[int]

    for idx in frontier:
      currentLayer.add(configs[idx])
      inc processed

      for depIdx in dependents[idx]:
        dec inDegree[depIdx]
        if inDegree[depIdx] == 0:
          nextFrontier.add(depIdx)

    layers.add(currentLayer)
    frontier = nextFrontier

  # Cycle detection: if not all nodes processed, a cycle exists
  if processed != configs.len:
    return @[]

  layers

# ─── Gate Runner Wrapper (for malebolgia) ─────────────────────────────────

## Gcsafe wrapper for malebolgia spawn.
## Pattern from loop_driver.nim: take only gcsafe args (string, pointer),
## cast internally with {.cast(gcsafe).}.
proc runGateWorker(gateId: string; workerCtx: pointer): LayerResult
    {.gcsafe, used.} =
  let wc = cast[ptr GateWorkerContext](workerCtx)
  {.cast(gcsafe).}:
    let start = getMonoTime()
    let passed = wc.runner(gateId, wc.ctx)
    let elapsedNs = getMonoTime().ticks - start.ticks
    let elapsedMs = elapsedNs.float / 1_000_000.0
    LayerResult(
      gateId: gateId,
      passed: passed,
      durationMs: elapsedMs
    )

# ─── Parallel Layer Execution ──────────────────────────────────────────────

proc executeLayer*(layer: seq[GateConfig]; ctx: PipelineContext;
                   gateRunner: proc(gateId: string; ctx: PipelineContext): bool
                       {.nimcall, raises: [].};
 maxJobs: int): seq[LayerResult] =
  ## Execute all gates in a layer in parallel via malebolgia.
  ##
  ## Each gate receives its own value copy of ``ctx`` — no shared mutable state.
  ## The ``gateRunner`` callback is injected by the orchestrator for loose coupling.
  ## ``maxJobs`` bounds concurrent execution (malebolgia thread pool handles scheduling).
  result = newSeq[LayerResult](layer.len)
  if layer.len == 0:
    return

  # Allocate shared context on heap (workers access read-only)
  let workerCtx = create(GateWorkerContext)
  workerCtx[] = GateWorkerContext(ctx: ctx, runner: gateRunner)

  block parallelExecution:
    var master = createMaster()
    master.awaitAll:
      for i in 0..<layer.len:
        master.spawn runGateWorker(layer[i].id, workerCtx) -> result[i]

  dealloc(workerCtx)

# ─── Full DAG Execution ────────────────────────────────────────────────────

proc executeDAG*(dag: seq[seq[GateConfig]]; ctx: PipelineContext;
                 gateRunner: proc(gateId: string; ctx: PipelineContext): bool
                     {.nimcall, raises: [].};
 maxJobs: int; failFast: bool = true): DAGResult =
  ## Execute the full DAG layer-by-layer.
  ##
  ## Layers execute sequentially (Layer 0, then Layer 1, etc.).
  ## Within each layer, gates execute in parallel via malebolgia.
  ##
  ## If ``failFast`` is true and any gate in a layer fails, execution stops
  ## immediately — subsequent layers are not executed.
  let totalStart = getMonoTime()
  result.layers = @[]
  result.allPassed = true

  for layerIdx in 0..<dag.len:
    let layerStart = getMonoTime()
    let layerResults = executeLayer(dag[layerIdx], ctx, gateRunner, maxJobs)
    let layerElapsedNs = getMonoTime().ticks - layerStart.ticks
    discard layerElapsedNs  # available for logging

    result.layers.add(layerResults)

    # Check for failures in this layer
    var layerFailed = false
    for lr in layerResults:
      if not lr.passed:
        result.allPassed = false
        layerFailed = true

    if failFast and layerFailed:
      break

  let totalElapsedNs = getMonoTime().ticks - totalStart.ticks
  result.totalDurationMs = totalElapsedNs.float / 1_000_000.0

# ─── Stage Filter ──────────────────────────────────────────────────────────

func findGateConfigs*(allGates: seq[GateConfig]; stage: GateStage): seq[GateConfig] {.raises: [].} =
  ## Filter gate configurations by execution stage.
  ## Returns only gates whose ``stages`` set contains the given stage.
  result = @[]
  for cfg in allGates:
    if stage in cfg.stages:
      result.add(cfg)

{.pop.}
