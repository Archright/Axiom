## Measurement Materializer — post-execution measurement projection (MEAS).
##
## B3 / MEAS-1..3b: The canonical product execution path (`ax prove`) NEVER writes
## tracked measurement state. This module is the **internal post-execution
## projection stage** that materializes `data/metrics/obligation_metrics.json`
## from a completed, canonical verification-result snapshot.
##
## Contract (Measurement Projection Boundary):
##   MEAS-1  CanonicalVerificationResult → MeasurementProjection → data/metrics/*
##           The ONLY permitted input is a completed report snapshot that already
##           carries the final OGR/PAR execution stats (`logs/ax_proof_state.json`
##           after a successful prove re-persists the full report). The projection
##           SHALL never consume a partially-written report.
##   MEAS-2  Measurement_{t+1} = M(CanonicalResult_t, ExecutionContract_t)  — derived
##           from the current execution's counts, never from previous measurement state.
##   MEAS-3  Measurement state ↛ CanonicalVerificationResult. This stage runs strictly
##           after the product-execution boundary closes, and its outcome cannot feed
##           back into proof correctness.
##   MEAS-3b Projection failure or absence does NOT change, invalidate, or retroactively
##           modify CanonicalVerificationResult. Every I/O and parse here is fail-open.
##
## This module is internal tooling, not a public product surface.

import std/[json, os]
import core/trusted/axiom_pragmas
import core/types/results
import core/utils/io_utils
import verification/obligation/metrics  ## computeOgrPar
import verification/obligation/metrics_io  ## ObligationMetrics, metricsFromCounts, writeObligationMetrics

## MEAS-3b: materialization is best-effort by construction. Callers MUST NOT
## propagate materializer failure into the product execution exit semantics.

func extractExecutionStatsCounts*(
  reportNode: JsonNode
): tuple[eligibleTargets, targetsWithObligations, obligationGeneratedCount, obligationAttemptedCount: int] {.raises: [].} =
  ## Pure projection: reads the four OGR/PAR counters from a canonical report's
  ## `executionStats` node. Missing or malformed nodes project to all-zero counts
  ## (fail-open — absence of measurement must not alter correctness).
  if reportNode.isNil or reportNode.kind != JObject:
    return
  let node = reportNode{"executionStats"}
  if node.isNil or node.kind != JObject:
    return
  result.eligibleTargets = node{"eligibleTargets"}.getInt(0)
  result.targetsWithObligations = node{"targetsWithObligations"}.getInt(0)
  result.obligationGeneratedCount = node{"obligationGeneratedCount"}.getInt(0)
  result.obligationAttemptedCount = node{"obligationAttemptedCount"}.getInt(0)

proc materializeObligationMetricsFromReport*(
  reportPath: string
): Result[void, string] {.axiomDecision, axiomEffect: IoEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Reads a completed canonical report snapshot and (re)materializes the
  ## obligation metrics file from its execution stats.
  ##
  ## Fail-open semantics (MEAS-3b): missing file, unparseable JSON, or absent
  ## counters all yield `ok()` (no-op) rather than an error — projection must
  ## never disturb product execution. Only an explicit write failure is surfaced
  ## (and callers must still ignore it for product-exit purposes).
  if reportPath.len == 0 or not fileExists(reportPath):
    return Result[void, string](ok: true)
  var reportNode: JsonNode
  try:
    reportNode = parseJson(readFile(reportPath))
  except CatchableError as e:
    # Fail-open: an unreadable/unparseable report snapshot has no measurements to project.
    return err("materializeObligationMetricsFromReport: unreadable report snapshot: " & e.msg)
  if reportNode.isNil or reportNode.kind != JObject:
    return Result[void, string](ok: true)  # no semantic executionStats payload to project
  let (eligible, targets, generated, attempted) =
    extractExecutionStatsCounts(reportNode)
  # MEAS-2: derive from this execution's counts only.
  let metrics = metricsFromCounts(eligible, targets, generated, attempted)
  return writeObligationMetrics(metrics)

proc materializeObligationMetrics*(): Result[void, string] {.axiomDecision, axiomEffect: IoEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Convenience binding: materializes from the default repo report snapshot
  ## (`logs/ax_proof_state.json` relative to the working directory).
  return materializeObligationMetricsFromReport(joinPath("logs", "ax_proof_state.json"))

when isMainModule:
  ## Executable entry point for the terminal measurement projection.
  ##
  ## Used by readiness_start_gate as a subprocess (the gate layer must not
  ## import verification/* directly — it shells out to this I/O-boundary tool).
  ## Exit codes follow MEAS-3b fail-open semantics: any projection failure is a
  ## non-zero exit but NEVER disturbs the caller's product verdict.
  import std/[osproc, strutils]
  # axiomIoBoundary
  var reportPath = joinPath("logs", "ax_proof_state.json")
  if paramCount() >= 1:
    reportPath = paramStr(1)
  let r = materializeObligationMetricsFromReport(reportPath)
  if r.isErr:
    quit(1)
  quit(0)
