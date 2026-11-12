import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

import core/interfaces/file_io_executor
import core/interfaces/logging_hub as logging_hub
import std/[times, json, sequtils]
import core/trusted/axiom_pragmas
# axiomIoBoundary

let fileIo* = SystemFileIoExecutor()
type
  GateMetric* = object
    gateId*: string
    passed*: bool
    durationMs*: int64
    timestamp*: int64       ## Unix epoch seconds
    epoch*: int

  GateHealth* = enum
    ghHealthy    ## passRate >= expected
    ghWarning    ## passRate between 50% and expected threshold
    ghDegraded   ## passRate < 50% of expected
    ghCritical   ## passRate == 0.0 (all failures)

  GateHealthReport* = object
    gateId*: string
    health*: GateHealth
    passRate*: float          ## 0.0..1.0
    avgDurationMs*: float
    sampleCount*: int
    consecutiveFailures*: int
const
  TelemetryPath* = "logs/gate_telemetry.jsonl"
  RollingWindowSize* = 100  ## Number of recent executions to consider

# ---------------------------------------------------------------------------
# Pure computations (func, no I/O)
# ---------------------------------------------------------------------------
func computePassRate*(metrics: seq[GateMetric]): float {.raises: [].} =
  if metrics.len == 0: return 1.0
  let passed = metrics.countIt(it.passed)
  passed.float / metrics.len.float
func computeAvgDuration*(metrics: seq[GateMetric]): float {.raises: [].} =
  if metrics.len == 0: return 0.0
  var total = 0.0
  for m in metrics:
    total += m.durationMs.float
  total / metrics.len.float
func countConsecutiveFailures*(metrics: seq[GateMetric]): int {.raises: [].} =
  ## Count failures from the most recent execution backwards
  result = 0
  for i in countdown(metrics.len - 1, 0):
    if not metrics[i].passed:
      inc result
    else:
      break
func classifyHealth*(passRate, expectedPassRate: float): GateHealth {.raises: [], noSideEffect.} =
  if passRate == 0.0: ghCritical
  elif passRate < expectedPassRate * 0.5: ghDegraded
  elif passRate < expectedPassRate: ghWarning
  else: ghHealthy
# ---------------------------------------------------------------------------
# I/O boundary — metric persistence (proc, side-effect permitted)
# ---------------------------------------------------------------------------
proc recordMetric*(gateId: string; passed: bool; durationMs: int64;
                   epoch: int  = 0) =
  ## Append a gate execution metric to the JSONL log.
  ## Accepts raw data to avoid importing gate/gate_types from core/.
  let metric = GateMetric(
    gateId: gateId,
    passed: passed,
    durationMs: durationMs,
    timestamp: toUnix(getTime()),
    epoch: epoch
  )
  discard fileIo.appendLine(TelemetryPath, $(%*metric))
proc loadMetrics*(gateId: string; limit: int = RollingWindowSize):
    seq[GateMetric] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load recent metrics for a specific gate from the JSONL log.
  if not fileIo.fileExists(TelemetryPath): return @[]
  let fileLines = fileIo.readLines(TelemetryPath)
  var all: seq[GateMetric]
  for line in fileLines:
    if line.len == 0: continue
    try:
      let j = parseJson(line)
      if j["gateId"].getStr() == gateId:
        all.add(GateMetric(
          gateId: j["gateId"].getStr(),
          passed: j["passed"].getBool(),
          durationMs: j["durationMs"].getInt(),
          timestamp: j["timestamp"].getInt(),
          epoch: j["epoch"].getInt()
        ))
    except CatchableError:
      continue
  # Return last N entries
  if all.len > limit:
    result = all[all.len - limit .. ^1]
  else:
    result = all
proc loadAllMetrics*(limit: int = RollingWindowSize):
    seq[GateMetric] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load recent metrics for all gates from the JSONL log.
  if not fileIo.fileExists(TelemetryPath): return @[]
  let fileLines = fileIo.readLines(TelemetryPath)
  var all: seq[GateMetric]
  for line in fileLines:
    if line.len == 0: continue
    try:
      let j = parseJson(line)
      all.add(GateMetric(
        gateId: j["gateId"].getStr(),
        passed: j["passed"].getBool(),
        durationMs: j["durationMs"].getInt(),
        timestamp: j["timestamp"].getInt(),
        epoch: j["epoch"].getInt()
      ))
    except CatchableError:
      continue
  if all.len > limit:
    result = all[all.len - limit .. ^1]
  else:
    result = all
proc assessHealth*(gateId: string; expectedPassRate: float;
                   maxDurationMs: int): GateHealthReport  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Assess gate health from telemetry data.
  let metrics = loadMetrics(gateId)
  let passRate = computePassRate(metrics)
  let avgDuration = computeAvgDuration(metrics)
  let failures = countConsecutiveFailures(metrics)
  let health = classifyHealth(passRate, expectedPassRate)

  GateHealthReport(
    gateId: gateId,
    health: health,
    passRate: passRate,
    avgDurationMs: avgDuration,
    sampleCount: metrics.len,
    consecutiveFailures: failures
  )
proc readJsonFile*(path: string): JsonNode  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read and parse a JSON file via FileIoExecutor.
  result = newJNull()
  if not fileIo.fileExists(path): return
  let content = fileIo.readFile(path)
  if content.len == 0: return
  try:
    result = parseJson(content)
  except CatchableError:
    logging_hub.logInfo("Failed to parse JSON: " & path)
proc generateHealthSummary*(): JsonNode =
  ## Generate a JSON summary of all gate health statuses.
  ## Reads baseline from data/gate_performance_baseline.json
  result = %*{"gates": [], "timestamp": toUnix(getTime())}
  const baselinePath = "data/gate_performance_baseline.json"
  let baseline = readJsonFile(baselinePath)
  if baseline.kind == JNull:
    logging_hub.logInfo("No gate performance baseline found at " & baselinePath)
    return

  for gateId, spec in baseline:
    let expectedRate = spec{"expectedPassRate"}.getFloat(0.9)
    let maxDur = spec{"maxDurationMs"}.getInt(5000)
    let report = assessHealth(gateId, expectedRate, maxDur)
    result["gates"].add(%*{
      "gateId": report.gateId,
      "health": $report.health,
      "passRate": report.passRate,
      "avgDurationMs": report.avgDurationMs,
      "sampleCount": report.sampleCount,
      "consecutiveFailures": report.consecutiveFailures
    })

{.pop.}
