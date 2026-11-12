import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/options
import std/os
import std/strutils
import core/json/json_utils
import verification/reporter
import core/json/std_redirect
import ../core/trusted/axiom_pragmas
# axiomIoBoundary

type
  ThoughtDashboardSummary* = object
    totalAttempts*: int
    successCount*: int
    proofSuccessRate*: float
    averageAttemptsPerSuccess*: float
    cumulativeDefectsHealed*: int
    architectureStabilityIndex*: float
    averageRetryCount*: float
    verificationTimeline*: seq[VerificationTimelinePoint]

## Summarize Thought Trajectory.
proc summarizeThoughtTrajectory*(
 logPath: string = joinPath("logs", "ax_prove_trajectory.jsonl");
  certDir: string = joinPath(getCurrentDir(), ".axiom", "vault")
): ThoughtDashboardSummary {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (>= (str.len logPath) 0) (>= (str.len certDir) 0) (= (option.isNone nodeOpt) true) (= attemptCount 0) (= successCount 0)))
  ## axiom-lean: logPath.length ≥ 0 ∧ certDir.length ≥ 0 ∧ nodeOpt.isNone = true ∧ attemptCount = 0 ∧ successCount = 0
  if not fileExists(logPath):
    var fallback = verifyCertificates(certDir)
    return ThoughtDashboardSummary(
      totalAttempts: 0,
      successCount: 0,
      proofSuccessRate: 0.0,
      averageAttemptsPerSuccess: 0.0,
      cumulativeDefectsHealed: fallback.cumulativeDefectsHealed,
      architectureStabilityIndex: fallback.architectureStabilityIndex,
      averageRetryCount: fallback.averageRetryCount,
      verificationTimeline: fallback.verificationTimeline
    )

  var attemptCount = 0
  var successCount = 0
  var attemptSumForSuccess = 0
  for raw in lines(logPath):
    if raw.strip().len == 0:
      continue
    let nodeOpt = parseJsonOpt(raw)
    if nodeOpt.isNone:
      continue
    let node = nodeOpt.get()
    if node.kind != JObject:
      continue
    if node.hasKey("phase") and node["phase"].kind == JString and
       node["phase"].getStr() in ["dynamic-proof-search", "skScribe", "skSwat", "skJudge", "skCegar", "skLegislator"]:
      let attemptNode =
        if node.hasKey("attempt"): node["attempt"]
        elif node.hasKey("extra") and node["extra"].kind == JObject and node["extra"].hasKey("attempt"): node["extra"]["attempt"]
        else: nil
      if attemptNode != nil and attemptNode.kind in {JInt, JFloat}:
        inc attemptCount
      if node.hasKey("status") and node["status"].kind == JString and node["status"].getStr() in ["succeeded", "ssSucceeded"]:
        inc successCount
        if attemptNode != nil and attemptNode.kind in {JInt, JFloat}:
          attemptSumForSuccess += attemptNode.getInt()

  let successRate =
    if attemptCount == 0: 0.0
    else: (successCount.float * 100.0) / attemptCount.float
  let averageAttempts =
    if successCount == 0: 0.0
    else: attemptSumForSuccess.float / successCount.float
  let certSummary = verifyCertificates(certDir)

  ThoughtDashboardSummary(
    totalAttempts: attemptCount,
    successCount: successCount,
    proofSuccessRate: successRate,
    averageAttemptsPerSuccess: averageAttempts,
    cumulativeDefectsHealed: certSummary.cumulativeDefectsHealed,
    architectureStabilityIndex: certSummary.architectureStabilityIndex,
    averageRetryCount: certSummary.averageRetryCount,
    verificationTimeline: certSummary.verificationTimeline
  )

func summaryJson*(summary: ThoughtDashboardSummary): JsonNode =
  %*{
    "totalAttempts": summary.totalAttempts,
    "successCount": summary.successCount,
    "proofSuccessRate": summary.proofSuccessRate,
    "averageAttemptsPerSuccess": summary.averageAttemptsPerSuccess,
    "cumulativeDefectsHealed": summary.cumulativeDefectsHealed,
    "architectureStabilityIndex": summary.architectureStabilityIndex,
    "averageRetryCount": summary.averageRetryCount
  }

func renderThoughtDashboard*(summary: ThoughtDashboardSummary): string =
  "Thought Dashboard\n" &
  "  Total Attempts: " & $summary.totalAttempts & "\n" &
  "  Success Count: " & $summary.successCount & "\n" &
  "  Proof Success Rate: " & $summary.proofSuccessRate & "%\n" &
  "  Avg Attempts/Success: " & $summary.averageAttemptsPerSuccess & "\n" &
  "  Cumulative Defects Healed: " & $summary.cumulativeDefectsHealed & "\n" &
  "  ASI: " & $summary.architectureStabilityIndex
{.pop.}
