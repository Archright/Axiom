import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/utils/constants
import core/domain_types
import core/json/std_redirect
import core/reasoning_recorder
import core/telemetry/metrics
import core/types/asi_types
import std/options
import std/os
import std/strutils
import std/syncio
import std/tables
import std/times
import verification/analyzer/analyzer_shared_cert
import verification/certificate_applier
import verification/gate_rule_adapter
import verification/vault_index
import infrastructure/logging_facade
proc buildVerificationTimeline(logPath: string; days: int  = 7): seq[
    VerificationTimelinePoint] =
  let labels = buildLastNDaysUtc(days)
  if labels.len == 0:
    return @[]
  var byDay = initTable[string, int]()
  for label in labels:
    byDay[label] = 0
  if fileExists(logPath):
    for raw in lines(logPath):
      if raw.strip().len == 0:
        continue
      let nodeOpt = parseJsonSafe(raw)
      if nodeOpt.isNone:
        continue
      let node = nodeOpt.get()
      if node.kind != JObject:
        continue
      if not node.hasKey("phase") or node.getOrDefault("phase").kind != JString:
        continue
      if node.getOrDefault("phase").getStr() != "dynamic-proof-search":
        continue
      if not node.hasKey(statusKey) or node.getOrDefault(statusKey).kind != JString:
        continue
      if node.getOrDefault(statusKey).getStr() != "succeeded":
        continue
      if not node.hasKey("ts") or node.getOrDefault("ts").kind != JString:
        continue
      let day = parseDayFromTimestamp(node.getOrDefault("ts").getStr())
      if day.len > 0 and byDay.hasKey(day):
        byDay[day] = byDay[day] + 1
  for label in labels:
    result.add(VerificationTimelinePoint(day: label,
        redToGreenTransitions: byDay[label]))

# @axiom-hint: lean="certificates.size ≥ 0" smt="(assert (and (>= (seq.len certificates) 0)))"
# @axiom-hint: lean="(certificates ≥ 0)" smt="(assert (and (>= certificates 0)))"
func finalizeStatusCounts(summary: var VerificationReportSummary) =
  for cert in summary.certificates:
    case cert.status
    of certGreen:
      inc summary.formalProofFunctions
      inc summary.verifiedFunctions
    of certPending:
      inc summary.pendingFunctions
    of certRed:
      inc summary.redFunctions
    of certStale:
      inc summary.staleFunctions
    of certVerifiedAxiom:
      inc summary.verifiedAxiomFunctions
      inc summary.verifiedFunctions
    of certPseudoVerified:
      inc summary.pseudoVerifiedFunctions
    of certYellow:
      inc summary.yellowFunctions
    of certNoObligation:
      discard  # normal termination, no substantive obligation — neither verified nor incomplete
    of certZ3Verified, certZ3Candidate:
      # P3b: Z3-only = candidate evidence, NOT product VERIFIED. It must not be
      # counted as verified/formal-proof (no Lean kernel acceptance). It is
      # reported as an explicitly separated z3-candidate bucket.
      inc summary.z3CandidateFunctions
    of certLeanVerified:
      inc summary.formalProofFunctions
      inc summary.verifiedFunctions
    of certDualVerified:
      inc summary.formalProofFunctions
      inc summary.verifiedFunctions
    of certTypeLevelVerified:
      inc summary.formalProofFunctions
      inc summary.verifiedFunctions
    of certWellFormed:
      inc summary.pendingFunctions
    of certSafetyVerified:
      inc summary.formalProofFunctions
      inc summary.verifiedFunctions
    of certSoundnessDebt:
      inc summary.pendingFunctions
    of certNotCurrent:
      inc summary.pendingFunctions
  summary.cumulativeDefectsHealed = computeCumulativeDefectsHealed(
      summary.certificates)
  summary.averageRetryCount = computeAverageRetryCount(summary.certificates)
  let universe = AsiUniverse(totalFunctions: summary.totalTrustedFunctions)
  # DEBT#047: Replaced deprecated computeFormalProofIntegrity / computeAxiomaticIntegrity
  # with canonical computeInformationGainWeightedAsi (SSOT formula).
  let igScore = metrics.computeInformationGainWeightedAsi(
    summary.certificates,
    universe,
    summary.averageRetryCount
  )
  summary.formalProofIntegrityIndex = igScore.toFloat
  summary.axiomaticIntegrityIndex = igScore.toFloat
  summary.architectureStabilityIndex = metrics.computeInformationGainWeightedAsi(
    summary.certificates,
    universe,
    summary.averageRetryCount
  ).toFloat
  summary.blockingFailure =
    summary.mismatchedFingerprints > 0 or
    summary.cycleDetected or
    summary.architectureGate.blockingFailures > 0 or
    summary.auditTrailGate.blockingFailures > 0 or
    summary.globalInfluenceGate.blockingFailures > 0 or
    summary.typeIntegrityGate.blockingFailures > 0 or
    summary.symbolicInvariantGate.blockingFailures > 0 or
    summary.semanticIntegrityGate.blockingFailures > 0
# @axiom-hint: lean="vaultDir.length ≥ 0" smt="(assert (and (>= (str.len vaultDir) 0)))"
# @axiom-hint: lean="nodeOpt.isNone = true ∧ (result ≥ 0)" smt="(assert (and (= (option.isNone nodeOpt) true) (>= result 0)))"
proc runFinalize*(result: var VerificationReportSummary; idx: var VaultIndex;
 idxPath: string; repoRoot: string; tStart: float) =
  ## [WAVE_Z:finalize] 13/14 Audit Trail + Finalize + Save + Timeline
  let bundle = applyAuditTrailGate(result.certificates)
  result.auditTrailGate = bundle.gateResult
  applyDirectives(result.certificates, bundle.directives)
  finalizeStatusCounts(result)
  idx.lastVerifiedAt = toUnix(getTime())
  saveVirtualVaultIndex(idxPath, idx)
  let tEnd = epochTime()
  logDebug("stage_08_reporter", "[TIMING] Total verifyCertificates: " & $(tEnd - tStart) & "s")
  result.verificationTimeline = buildVerificationTimeline(joinPath(repoRoot,
      "logs", "thought_trajectory.jsonl"), 7)


## Wave Z Design (pending manual refactoring):
## This 403-line God Function (ACI 165, 14 responsibilities) should be
## decomposed into 4 algebraic pipeline domains:
##   1. runHydrationEngine  — Virtual DB, Symbolic GC, Cert load, Hydration
##   2. runSymbolicManager  — Canonicalization, Vault enrichment, Invariant synthesis
##   3. runGovernanceGate   — Architecture, Influence, ASI, Type gates
##   4. runProofAggregator  — Audit trail, Status counts, Vault save, Timeline
## Target orchestrator: 15 lines, ACI < 20.
## See: docs/history/reports/aci_refactoring_residual_2026_05.md
# @axiom-hint: lean="stepName.length ≥ 0 ∧ result.certificates.size ≥ 0" smt="(assert (and (>= (str.len stepName) 0) (>= (seq.len result.certificates) 0)))"
proc auditVerificationStep*(stepName: string;
    result: VerificationReportSummary) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## [AXIOM v0.6.8] Record orchestration-level reasoning trail for the
  ## verifyCertificates pipeline step. Emits one phase event + one verdict
  ## per certificate that has a non-empty status.
  recordPhase("verifyCertificates", stepName, "orchestration")
  for i in 0 ..< result.certificates.len:
    let cert = result.certificates[i]
    let statusStr = $cert.status
    if statusStr.len > 0:
      recordVerdict(string(cert.modulePath) & "::" & cert.functionName,
          statusStr, stepName)

# @axiom-hint: lean="certDir.length ≥ 0" smt="(assert (>= (str.len certDir) 0))"

{.pop.}
