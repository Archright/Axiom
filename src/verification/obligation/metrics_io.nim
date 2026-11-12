## Obligation Metrics I/O — canonical metrics file persistence.
##
## Reads/writes `data/metrics/obligation_metrics.json` which stores the
## post-run obligation counters (OGR/PAR raw counts and derived rates).
##
## Schema (additive, backward-compatible):
##   { "schemaVersion": 1,
##     "eligibleTargets": N,
##     "targetsWithObligations": N,
##     "obligationGeneratedCount": N,
##     "obligationAttemptedCount": N,
##     "ogr": F,
##     "par": F }
##
## Determinism: no wall-clock timestamp; only epoch-derived identifiers
## if needed (none used here). Pure serialization functions carry {.raises: [].}

import std/[json, os]
import core/trusted/axiom_pragmas
import core/types/results
import core/utils/io_utils
import verification/obligation/metrics  ## computeOgrPar

proc stateJoin(parts: varargs[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## AXIOM_STATE_DIR 설정 시 <state>/<parts...>, 미설정 시 기존 CWD 상대 경로 그대로(zero-diff).
  let base = block:
    let v = getEnv("AXIOM_STATE_DIR")
    if v.len > 0: v else: getCurrentDir()
  result = base
  for p in parts: result = joinPath(result, p)

{.push raises: [].}

const
  MetricsDir* = "data/metrics"
  ObligationMetricsFile* = "obligation_metrics.json"

type
  ObligationMetrics* = object
    schemaVersion*: int
    eligibleTargets*: int
    targetsWithObligations*: int
    obligationGeneratedCount*: int
    obligationAttemptedCount*: int
    ogr*: float
    par*: float

func defaultObligationMetrics*: ObligationMetrics =
  ## Returns zero-initialized metrics (all fields 0).
  ObligationMetrics(
    schemaVersion: 1,
    eligibleTargets: 0,
    targetsWithObligations: 0,
    obligationGeneratedCount: 0,
    obligationAttemptedCount: 0,
    ogr: 0.0,
    par: 0.0
  )

func metricsFromCounts*(
  eligibleTargets: int;
  targetsWithObligations: int;
  generated: int;
  attempted: int
): ObligationMetrics {.raises: [].} =
  ## Builds ObligationMetrics from raw runtime counters.
  ## Computes OGR/PAR via computeOgrPar for consistency.
  let ogrPar = computeOgrPar(eligibleTargets, targetsWithObligations, generated, attempted)
  ObligationMetrics(
    schemaVersion: 1,
    eligibleTargets: eligibleTargets,
    targetsWithObligations: targetsWithObligations,
    obligationGeneratedCount: generated,
    obligationAttemptedCount: attempted,
    ogr: ogrPar.ogr,
    par: ogrPar.par
  )

func metricsToJson*(m: ObligationMetrics): JsonNode {.raises: [].} =
  ## Serializes ObligationMetrics to a JSON object node.
  result = newJObject()
  result["schemaVersion"] = %m.schemaVersion
  result["eligibleTargets"] = %m.eligibleTargets
  result["targetsWithObligations"] = %m.targetsWithObligations
  result["obligationGeneratedCount"] = %m.obligationGeneratedCount
  result["obligationAttemptedCount"] = %m.obligationAttemptedCount
  result["ogr"] = %m.ogr
  result["par"] = %m.par

func metricsFromJson*(node: JsonNode): ObligationMetrics {.raises: [].} =
  ## Deserializes a JSON object node to ObligationMetrics.
  ## Missing fields fall back to defaults (backward-compatible).
  result = defaultObligationMetrics()
  result.schemaVersion = node{"schemaVersion"}.getInt(1)
  result.eligibleTargets = node{"eligibleTargets"}.getInt(0)
  result.targetsWithObligations = node{"targetsWithObligations"}.getInt(0)
  result.obligationGeneratedCount = node{"obligationGeneratedCount"}.getInt(0)
  result.obligationAttemptedCount = node{"obligationAttemptedCount"}.getInt(0)
  result.ogr = node{"ogr"}.getFloat(0.0)
  result.par = node{"par"}.getFloat(0.0)

{.pop.}

proc writeObligationMetrics*(metrics: ObligationMetrics): Result[void, string] {.axiomDecision.} =
  ## Writes ObligationMetrics to data/metrics/obligation_metrics.json atomically.
  ## Creates the directory if missing. Uses writeFileAtomic for crash safety.
  try:
    let dir = stateJoin("data", "metrics")
    if not dirExists(dir):
      createDir(dir)
    let path = joinPath(dir, ObligationMetricsFile)
    let jsonOut = metricsToJson(metrics).pretty() & "\n"
    writeFileAtomic(path, jsonOut)
  except CatchableError as e:
    return err("writeObligationMetrics: " & e.msg)

proc readObligationMetrics*(): ObligationMetrics {.raises: [].} =
  ## Reads ObligationMetrics from disk. Returns default on missing/error.
  try:
    let path = joinPath(stateJoin("data", "metrics"), ObligationMetricsFile)
    if fileExists(path):
      let node = parseJson(readFile(path))
      if node.kind == JObject:
        return metricsFromJson(node)
  except CatchableError:
    discard
  defaultObligationMetrics()
