import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## UnitResult / GlobalResult — result normalization per contract sentence 4.
##
## projectToSelected implements: Project(FullResult, Selected) == PrunedResult
## — the selection-invariant semantic projection.

import std/[algorithm, json, sequtils, sets, strutils, tables]
import core/types/proof_status

# ---------------------------------------------------------------------------
# UnitResult
# ---------------------------------------------------------------------------

type
  UnitResult* = object
    unitId*: string
    proofStatus*: ProofStatus
    failureClassification*: string
    vacuityClassification*: string
    certificateIdentityDigest*: string
    resultDigest*: string

func toCanonicalJson*(ur: UnitResult): JsonNode {.raises: [].} =
  %*{
    "unitId": ur.unitId,
    "proofStatus": $ur.proofStatus,
    "failureClassification": ur.failureClassification,
    "vacuityClassification": ur.vacuityClassification,
    "certificateIdentityDigest": ur.certificateIdentityDigest,
    "resultDigest": ur.resultDigest}

# ---------------------------------------------------------------------------
# GlobalResult — full run result set with selection-scoped projection
# ---------------------------------------------------------------------------

type
  GlobalResult* = object
    unitResults*: seq[UnitResult]
    selectedUniverseRatio*: float
    selectionInvariantProjection*: seq[UnitResult]
    selectionScopedReport*: JsonNode

func toCanonicalJson*(gr: GlobalResult): JsonNode {.raises: [].} =
  let sortedUnits = gr.unitResults.sorted(proc(a, b: UnitResult): int =
    cmp(a.unitId, b.unitId))
  %*{
    "unitResults": sortedUnits.mapIt(it.toCanonicalJson),
    "selectedUniverseRatio": %gr.selectedUniverseRatio,
    "selectionInvariantProjection": gr.selectionInvariantProjection.mapIt(it.toCanonicalJson),
    "selectionScopedReport": gr.selectionScopedReport}

# ---------------------------------------------------------------------------
# projectToSelected — contract sentence 4 implementation
# ---------------------------------------------------------------------------

func projectToSelected*(fullResult: GlobalResult; selectedIds: seq[string]): GlobalResult {.raises: [].} =
  ## Projection of FullResult onto Selected units: keeps only units in selectedIds,
  ## preserving exact per-unit fields. Computes the S/U ratio as selection-scoped
  ## reporting (not invariant).
  let selectedSet = selectedIds.toHashSet
  let projected = fullResult.unitResults.filterIt(it.unitId in selectedSet)
  let totalCount = fullResult.unitResults.len.float
  let selectedCount = selectedSet.len.float
  let ratio = if totalCount > 0: selectedCount / totalCount else: 0.0

  # Selection-invariant components: per-unit fields only (no aggregate ratios)
  let invariantProjection = projected  ## unit-level fields are invariant

  # Selection-scoped report: includes S/U ratio and aggregate counts
  let passCount = projected.countIt(it.proofStatus in [psPass, psNoObligation])
  let failCount = projected.countIt(it.proofStatus == psFail)
  let timeoutCount = projected.countIt(it.proofStatus == psTimeout)
  let skipCount = projected.countIt(it.proofStatus == psSkip)
  let errorCount = projected.countIt(it.proofStatus == psError)
  let vacuousCount = projected.countIt(it.proofStatus in [psVacuousTrivial, psVacuousCounter])

  let report = %*{
    "totalUnits": fullResult.unitResults.len,
    "selectedUnits": projected.len,
    "selectedUniverseRatio": ratio,
    "passCount": passCount,
    "failCount": failCount,
    "timeoutCount": timeoutCount,
    "skipCount": skipCount,
    "errorCount": errorCount,
    "vacuousCount": vacuousCount}

  GlobalResult(
    unitResults: projected,
    selectedUniverseRatio: ratio,
    selectionInvariantProjection: invariantProjection,
    selectionScopedReport: report)

{.pop.}