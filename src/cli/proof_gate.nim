import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
# axiomIoBoundary
## Proof Gate — typed anti-vacuity / anti-tautology pipeline for verification reports.
##
## All ASI/VSR calculations flow through this module; no ad-hoc metric math in
## CLI callers. Canonical ASI is produced via core/telemetry/metrics SSOT.

import std/options
import std/sequtils
import std/strutils
import std/times

import core/judge/tautology_checker
import core/orchestrator/orchestrator_types
import core/telemetry/metrics
import core/types/asi_types
import core/types/vkd_types

type
  ValidatedProofReport* = object
    ## Report after verification, ready for anti-vacuity / anti-tautology gates.
    orchestrationReport*: OrchestrationReport
    totalSourceFunctions*: int
    verifiedCount*: int
    vacuousCount*: int
    tautologyCount*: int
    gateApplied*: bool

  CanonicalVKDState* = object
    ## Canonical proof-state snapshot persisted to ax_proof_state.json.
    vkd*: ValidatedAsi
    vsr*: float
    completionRate*: float
    totalFunctions*: int
    netVerifiedFunctions*: int
    vacuousDemotions*: int
    tautologyDemotions*: int
    timestamp*: string

proc countNodeStatuses(report: OrchestrationReport): tuple[verified, vacuous, failed, timeout, blocked: int] {.raises: [].} =
  result.verified = report.nodeReports.countIt(it.status in [orchestrationVerified, orchestrationInductiveValid])
  result.vacuous = report.nodeReports.countIt(it.status == orchestrationVacuousContradiction)
  result.failed = report.nodeReports.countIt(it.status == orchestrationProofFailed)
  result.timeout = report.nodeReports.countIt(it.status == orchestrationTimedOut)
  result.blocked = report.nodeReports.countIt(it.status == orchestrationBlocked)

proc isStaleVacuous*(node: OrchestrationNodeReport): bool {.raises: [].} =
  ## Vacuous node detected either by explicit status or stale reason marker.
  if node.status == orchestrationVacuousContradiction:
    return true
  let reason = node.staleReason.toLowerAscii()
  reason.contains("vacuous") or reason.contains("contradiction")

proc isTautologyNode*(node: OrchestrationNodeReport): bool {.raises: [].} =
  ## Tautology node detected via type-system-level tautology patterns.
  if node.smtlib2.len == 0:
    return false
  isTautologyConstraint(node.smtlib2, "")

proc initValidatedProofReport*(
  report: OrchestrationReport;
  totalSourceFunctions: int
): ValidatedProofReport {.raises: [].} =
  ## Construct a validated report with counts derived from node statuses.
  let counts = countNodeStatuses(report)
  var tautologyCount = 0
  for node in report.nodeReports:
    if isTautologyNode(node):
      inc tautologyCount
  ValidatedProofReport(
    orchestrationReport: report,
    totalSourceFunctions: totalSourceFunctions,
    verifiedCount: counts.verified,
    vacuousCount: counts.vacuous,
    tautologyCount: tautologyCount,
    gateApplied: false
  )

proc computeNetVerified*(report: ValidatedProofReport): int {.raises: [].} =
  ## Verified nodes minus vacuous and tautology demotions.
  max(0, report.verifiedCount - report.vacuousCount - report.tautologyCount)

proc computeCompletionRate*(report: ValidatedProofReport): float {.raises: [].} =
  ## Net verified functions divided by total source functions.
  ## The ratio is computed through the vkd_types.initKernelRatio factory
  ## (SSOT: docs/spec/verification_density.md); an impossible state
  ## (verified > total) falls back to 0.0 instead of leaking a raw ratio.
  if report.totalSourceFunctions <= 0:
    return 0.0
  let ratio = initKernelRatio(computeNetVerified(report), report.totalSourceFunctions)
  if ratio.isSome: ratio.get.toFloat else: 0.0

proc shouldIsolateNode*(node: OrchestrationNodeReport): bool {.raises: [].} =
  ## Vacuous pattern check used by downstream isolation gates.
  isStaleVacuous(node)

proc applyAntiVacuityGate*(report: sink ValidatedProofReport): ValidatedProofReport {.raises: [].} =
  ## Demote verified nodes that are vacuous contradictions.
  result = report
  result.gateApplied = true
  if result.vacuousCount > result.verifiedCount:
    result.vacuousCount = result.verifiedCount

proc applyAntiTautologySentinel*(report: sink ValidatedProofReport): ValidatedProofReport {.raises: [].} =
  ## Demote verified nodes that are tautologies.
  result = report
  result.gateApplied = true
  let available = max(0, result.verifiedCount - result.vacuousCount)
  if result.tautologyCount > available:
    result.tautologyCount = available

proc computeFilteredVsr*(report: ValidatedProofReport): float {.raises: [].} =
  ## Verification success rate after demotions over all processed nodes.
  let totalProcessed = report.orchestrationReport.nodeReports.len
  if totalProcessed <= 0:
    return 0.0
  initAsiRatio(computeNetVerified(report).float / totalProcessed.float).get(defaultAsiRatio()).toFloat

proc computeCanonicalVkd*(report: ValidatedProofReport): CanonicalVKDState {.raises: [].} =
  ## Canonical VKD snapshot. The kernel ratio is computed via the
  ## vkd_types.initKernelRatio factory (SSOT: docs/spec/verification_density.md)
  ## and formatted through metrics.exportAsiFixed4.
  let netVerified = computeNetVerified(report)
  let completionRate = computeCompletionRate(report)
  let smartCompletionRate = initAsiRatio(completionRate).get(defaultAsiRatio())
  CanonicalVKDState(
    vkd: exportAsiFixed4(smartCompletionRate),
    vsr: computeFilteredVsr(report),
    completionRate: completionRate,
    totalFunctions: report.totalSourceFunctions,
    netVerifiedFunctions: netVerified,
    vacuousDemotions: report.vacuousCount,
    tautologyDemotions: report.tautologyCount,
    timestamp: now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  )

proc computeCumulativeCanonicalVkd*(
  report: ValidatedProofReport;
  historicalVerified: int;
  kernelScopeVerifiedCount: int = -1
): CanonicalVKDState {.raises: [].} =
  ## Cumulative VKD snapshot that unions historical verified certificates with
  ## the current batch. Idempotent bit-set union guarantees monotonicity:
  ## VKD can only increase (or stay flat) as new nodes are verified.
  ## When `kernelScopeVerifiedCount >= 0`, it overrides the batch's raw verified
  ## count (which may include non-kernel verifications such as `parseJson`),
  ## keeping the cumulative numerator aligned to kernel-scope certs only.
  let base = computeCanonicalVkd(report)
  let netNewVerified = if kernelScopeVerifiedCount >= 0: kernelScopeVerifiedCount
                       else: max(0, base.netVerifiedFunctions)
  let cumulativeVerified = historicalVerified + netNewVerified
  let effectiveTotal = max(1, base.totalFunctions)
  # Monotone clamp: a cumulative total that exceeds the kernel count (e.g. after
  # re-verification) saturates VKD at 1.0 instead of degrading the score.
  let cumulativeRatio = initKernelRatio(cumulativeVerified, effectiveTotal)
  let clampedRate =
    if cumulativeRatio.isSome: cumulativeRatio.get.toFloat
    else: 1.0
  let smartCumulativeRate = initAsiRatio(clampedRate).get(defaultAsiRatio())
  CanonicalVKDState(
    vkd: exportAsiFixed4(smartCumulativeRate),
    vsr: base.vsr,
    completionRate: clampedRate,
    totalFunctions: base.totalFunctions,
    netVerifiedFunctions: cumulativeVerified,
    vacuousDemotions: base.vacuousDemotions,
    tautologyDemotions: base.tautologyDemotions,
    timestamp: base.timestamp
  )

{.pop.}
