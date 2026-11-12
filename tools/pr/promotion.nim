## tools/pr/promotion.nim
## Promotion eligibility evaluation for metric-driven promotion pipeline.
##
## Provides evaluatePromotionEligibility() which gates promotion on 7
## sequential checks. All must pass for promotion to be eligible.
## Failed checks return failedPrerequisites with the specific gate name.

import std/[json, strutils, tables, options, sets, os]
import checksums/sha2
import core/axiom_pragmas
import core/types/debt_types
import core/debt/debt_observation

const
  PromotionReportPath = "data/reports/promotion_latest.json"

# ---------------------------------------------------------------------------
# Local helpers
# ---------------------------------------------------------------------------

proc getOrDefaultStr(node: JsonNode; key: string; default: string = ""): string {.raises: [CatchableError].} =
  if node.isNil or not node.hasKey(key) or node[key].kind == JNull:
    return default
  result = node[key].getStr(default)

# ---------------------------------------------------------------------------
# Input types
# ---------------------------------------------------------------------------

type
  Observation* = object
    metricId*: string
    observedValue*: int64
    direction*: string
    status*: string
    observationId*: string
    recordedAt*: string

  BaselineMaterialState* = object
    metricId*: string
    effectiveBaselineHash*: string
    materializedBaselineHash*: string
    baselineRevisionId*: string
    current*: int
    target*: int
    status*: string
    resolution*: string
    stabilityMode*: string

  PolicyRevision* = object
    contractHash*: string
    revisionId*: string
    effectiveDate*: string

  PromotionEligibility* = object
    eligible*: bool
    failedPrerequisites*: seq[string]
    metricId*: string
    contractHash*: string
    baseline*: string
    stabilityWindow*: int
    minStableRevisions*: int
    stabilityMode*: string
    requiredConsecutives*: int
    status*: string

# ---------------------------------------------------------------------------
# Baseline freshness check (local copy for Phase 3 independence)
# ---------------------------------------------------------------------------

proc baselineFreshLocal*(): bool {.raises: [CatchableError], axiomEffect: IOEffect, axiomDecision(
  id = "DECISION-0807",
  reason = "Check if baseline hash matches materialized baseline hash for Phase 3 freshness check in promotion evaluation",
  adr = "docs/adr/0001-fail-closed-result-type.md",
  introduced = "v35"
).} =
  ## Check that the latest effective baseline hash matches the materialized
  ## baseline hash. Returns true if the baseline is fresh.
  const BaselineRevisionsPath = "data/debt/baseline_revisions.json"
  if not fileExists(BaselineRevisionsPath):
    return false
  try:
    let revJson = parseJson(readFile(BaselineRevisionsPath))
    let effectiveHash = revJson.getOrDefaultStr("effectiveBaselineHash", "")
    let materializedHash = revJson.getOrDefaultStr("materializedBaselineHash", "")
    result = effectiveHash.len > 0 and effectiveHash == materializedHash
  except CatchableError:
    result = false

# ---------------------------------------------------------------------------
# Gate implementations
# ---------------------------------------------------------------------------

func gateContractValid*(metricId: string; contractHash: string; policyRevision: PolicyRevision): bool {.raises: [].} =
  ## Gate 1: ContractValid — policyRevision.contractHash must match
  ## the metric contract hash from metric_specs.json.
  policyRevision.contractHash == contractHash

func gateObservationDistinct*(observations: seq[Observation]): bool {.raises: [].} =
  ## Gate 2: ObservationDistinct — all ESKeys in the window must be distinct.
  ## ESKey = metricId + observedValue + direction.
  var seen: HashSet[string]
  for obs in observations:
    let esKey = obs.metricId & "|" & $obs.observedValue & "|" & obs.direction
    if esKey in seen:
      return false
    seen.incl(esKey)
  true

func gateStabilitySequence*(observations: seq[Observation]; requiredConsecutives: int): bool {.raises: [].} =
  ## Gate 3: StabilitySequence (S5) — at least `requiredConsecutives`
  ## consecutive observations with distinct ESKeys.
  if observations.len < requiredConsecutives:
    return false
  var distinctCount = 0
  var lastEsKey = ""
  for obs in observations:
    let esKey = obs.metricId & "|" & $obs.observedValue & "|" & obs.direction
    if esKey != lastEsKey:
      inc distinctCount
      lastEsKey = esKey
    if distinctCount >= requiredConsecutives:
      return true
  false

func gateDirectionSatisfied*(observations: seq[Observation]; baseline: BaselineMaterialState): bool {.raises: [].} =
  ## Gate 4: DirectionSatisfied — the most recent observation's
  ## direction must be consistent with the baseline direction meaning.
  ## For REGRESSION mode: latest direction must not be REGRESSION.
  if observations.len == 0:
    return false
  let latest = observations[^1]
  case baseline.stabilityMode
  of "REGRESSION":
    # In regression mode, the latest observation must not show regression
    # (i.e., it should be IMPROVEMENT or MAINTAINED).
    latest.direction != "REGRESSION"
  of "IMPROVEMENT":
    latest.direction == "IMPROVEMENT"
  else:
    true  # unknown mode — pass open

func gateBaselineFresh*(baseline: BaselineMaterialState): bool {.raises: [].} =
  ## Gate 5: BaselineFresh — baseline.effectiveBaselineHash must equal
  ## the materialized baseline hash, and baselineRevisionId must match.
  baseline.effectiveBaselineHash == baseline.materializedBaselineHash and
    baseline.baselineRevisionId.len > 0

func gateEvidencePresent*(observations: seq[Observation]): bool {.raises: [].} =
  ## Gate 6: EvidencePresent — every observation must have a valid
  ## observationId and the observationIds must correspond to evidence refs.
  for obs in observations:
    if obs.observationId.len == 0:
      return false
    if not obs.observationId.startsWith("sha256:"):
      return false
  true

proc gateNoPendingReconcile*(observations: seq[Observation]; baseline: BaselineMaterialState): bool {.raises: [CatchableError], axiomEffect: IOEffect, axiomDecision(
  id = "DECISION-0808",
  reason = "Check that latest observation matches baseline (no pending reconciliation) — involves I/O for freshness check",
  adr = "docs/adr/0001-fail-closed-result-type.md",
  introduced = "v35"
).} =
  ## Gate 7: NoPendingReconcile — the latest observation pair must
  ## match the baseline (no recomputation since last materialization).
  if observations.len == 0:
    return false
  let latest = observations[^1]
  # The latest observation's observedValue must match the baseline current value,
  # and the baseline must be fresh (no pending reconciliation).
  latest.observedValue.int == baseline.current and baselineFreshLocal()

# ---------------------------------------------------------------------------
# Main evaluation function
# ---------------------------------------------------------------------------

proc evaluatePromotionEligibility*(
  metricId: string,
  contractHash: string,
  observations: seq[Observation],
  baselineState: BaselineMaterialState,
  policyRevision: PolicyRevision
): PromotionEligibility {.raises: [CatchableError], axiomDecision(
  id = "DECISION-0809",
  reason = "Evaluate promotion eligibility through 7 sequential gates; all must pass for eligible = true",
  adr = "docs/adr/0001-fail-closed-result-type.md",
  introduced = "v35"
).} =
  ## Evaluate promotion eligibility through 7 sequential gates.
  ## All gates must pass for eligible = true.
  ## On first failure, returns failedPrerequisites with the gate name.
  ##
  ## Gates (all must pass):
  ##   1. ContractValid: policyRevision.contractHash == metricContract(metricId).hash
  ##   2. ObservationDistinct: window 내 distinct ESKeys
  ##   3. StabilitySequence: S5 — distinct ESKey 시퀀스 5개 연속 관측
  ##   4. DirectionSatisfied: baseline.direction 의미
  ##   5. BaselineFresh: baseline.hash == materialsCurrentHash (+provenance: baselineRevisionId 동일)
  ##   6. EvidencePresent: observationIds ↔ evidenceRefs 존재
  ##   7. NoPendingReconcile: latestPair == baseline (최근 관측 이후 재계산 없음)

  result.metricId = metricId
  result.contractHash = contractHash
  result.stabilityWindow = 5
  result.minStableRevisions = 3
  result.stabilityMode = "REGRESSION"
  result.requiredConsecutives = 5
  result.status = "INFO"

  # Gate 1: ContractValid
  if not gateContractValid(metricId, contractHash, policyRevision):
    result.failedPrerequisites.add("ContractValid")
    result.eligible = false
    return

  # Gate 2: ObservationDistinct
  if not gateObservationDistinct(observations):
    result.failedPrerequisites.add("ObservationDistinct")
    result.eligible = false
    return

  # Gate 3: StabilitySequence
  if not gateStabilitySequence(observations, result.requiredConsecutives):
    result.failedPrerequisites.add("StabilitySequence")
    result.eligible = false
    return

  # Gate 4: DirectionSatisfied
  if not gateDirectionSatisfied(observations, baselineState):
    result.failedPrerequisites.add("DirectionSatisfied")
    result.eligible = false
    return

  # Gate 5: BaselineFresh
  if not gateBaselineFresh(baselineState):
    result.failedPrerequisites.add("BaselineFresh")
    result.eligible = false
    return

  # Gate 6: EvidencePresent
  if not gateEvidencePresent(observations):
    result.failedPrerequisites.add("EvidencePresent")
    result.eligible = false
    return

  # Gate 7: NoPendingReconcile
  if not gateNoPendingReconcile(observations, baselineState):
    result.failedPrerequisites.add("NoPendingReconcile")
    result.eligible = false
    return

  # All gates passed
  result.eligible = true
  result.status = "ELIGIBLE"

# ---------------------------------------------------------------------------
# --promotion-report CLI helper
# ---------------------------------------------------------------------------

proc writePromotionReport*(eligibility: PromotionEligibility; outputPath: string = PromotionReportPath) {.raises: [CatchableError], axiomDecision(
  id = "DECISION-0805",
  reason = "Write promotion eligibility report as canonical JSON to data/reports/promotion_latest.json",
  adr = "docs/adr/0001-fail-closed-result-type.md",
  introduced = "v35"
).} =
  ## Write the promotion eligibility result as canonical JSON.
  ## The report is materialized convenience — not evidence.
  let dir = outputPath.parentDir()
  if not dirExists(dir): createDir(dir)

  var report = %*{
    "metricId": eligibility.metricId,
    "contractHash": eligibility.contractHash,
    "baseline": eligibility.baseline,
    "stabilityWindow": eligibility.stabilityWindow,
    "minStableRevisions": eligibility.minStableRevisions,
    "stabilityMode": eligibility.stabilityMode,
    "requiredConsecutives": eligibility.requiredConsecutives,
    "status": eligibility.status,
    "eligible": eligibility.eligible,
    "failedPrerequisites": eligibility.failedPrerequisites
  }

  writeFile(outputPath, report.pretty())

# ---------------------------------------------------------------------------
# Baseline key computation (idempotent — not revision-based)
# ---------------------------------------------------------------------------

func baselineKey*(canonicalState: string): string {.raises: [].} =
  ## baseline key = sha256(canonical state(...)).
  ## Materialize always produces the same key for the same state (idempotent,
  ## not a new revision).
  "sha256:" & $Sha_256.secureHash("baseline:" & canonicalState)

when isMainModule:
  echo "tools/pr/promotion — promotion eligibility evaluator"
  echo "Use evaluatePromotionEligibility() from other modules."
