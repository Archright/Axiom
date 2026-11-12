
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push, raises: [CatchableError].}
import core/axiom_pragmas
# axiomIoBoundary
## Stage 04: Gate Check
## Architecture, type, symbolic, and semantic integrity gates.
## Thin orchestration delegating to src/gate/ rule-guard functions.
import
  std / algorithm

import
  std / os

import
  std / sequtils

import
  std / sets

import
  std / strutils

import
  core / types / domain_types

import
  verification / gate_rule_adapter

import
  verification / certificate_manager

import
  verification / certificate_applier

import
  verification / dependency_analyzer

import
  verification / analyzer / stage_02_fingerprint

import
  verification / state_manager

import
  verification / proof_linkage

proc runTypeGate*(result: var VerificationReportSummary; repoRoot: string) =
  let bundle = applyTypeIntegrityGate(result.certificates)
  result.typeIntegrityGate = bundle.gateResult
  applyDirectives(result.certificates, bundle.directives)
  let auditPath = joinPath(repoRoot, "logs", "audit", "stream.jsonl")
  for violation in result.typeIntegrityGate.violations:
    discard appendGlobalInfluenceEvent(auditPath, influencer = "",
                                       affectedNodes = violation.affectedNodes,
                                       demotionKind = "certRed",
                                       reason = violation.ruleId &
        ":" &
        violation.message, astDiffCount = 0)

proc runSymbolicAudit*(result: var VerificationReportSummary;
    repoRoot: string) =
  let auditPath = joinPath(repoRoot, "logs", "audit", "stream.jsonl")
  for violation in result.symbolicInvariantGate.violations:
    discard appendGlobalInfluenceEvent(auditPath, influencer = "",
                                       affectedNodes = violation.affectedNodes, demotionKind =
      if violation.ruleId == "symbolic-unsupported":
        "certPending"
      else:
        "certRed"
    , reason = violation.ruleId & ":" & violation.message, astDiffCount = 0)

proc runSemanticAudit*(result: var VerificationReportSummary;
    repoRoot: string) =
  let auditPath = joinPath(repoRoot, "logs", "audit", "stream.jsonl")
  for violation in result.semanticIntegrityGate.violations:
    let demotion = if violation.severity == agBlocking:
      "certRed"
    else:
      "warning"
    discard appendGlobalInfluenceEvent(auditPath, influencer = "",
                                       affectedNodes = violation.affectedNodes,
                                       demotionKind = demotion,
                                       reason = violation.ruleId &
        ":" &
        violation.message, astDiffCount = 0)

func applyCycleResults(summary: var VerificationReportSummary;
                       cyclicFunctions: HashSet[string]) =
  if cyclicFunctions.len == 0:
    return
  summary.cycleDetected = true
  summary.cyclicFunctions = cyclicFunctions.toSeq().sorted()
  for i in 0 ..< summary.certificates.len:
    if summary.certificates[i].functionName in cyclicFunctions:
      markCertificateInvalid(summary.certificates[i], "architecture-cycle")

proc runCanonicalizeAndArchGate*(result: var VerificationReportSummary) {.axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect, TimeEffect].} =
  ## [WAVE_Z:canonicalize] 5/14 Canonicalization + Architecture Gate
  canonicalizeCallsAcrossModules(result.certificates)
  applyCycleResults(result,
                    detectArchitecturalCyclicFunctions(result.certificates))
  invalidateDependents(result.certificates, proc (cert: var FunctionCertificate;
      dependency: string) {.raises: [].} =
    if cert.status != certStale:
      try:
        markCertificatePendingByDependency(cert, dependency)
      except CatchableError:
        discard)  # axiom:best-effort(ioboundary catch)
  let archBundle = applyArchitecturePrinciplesGate(result.certificates)
  result.architectureGate = archBundle.gateResult
  applyDirectives(result.certificates, archBundle.directives)
  let linkageBundle = applyAxiomLinkageGate(result.certificates,
      verifyAxiomLinkage)
  result.architectureGate = mergeArchitecturePrinciplesGate(
      result.architectureGate, linkageBundle.gateResult)
  applyDirectives(result.certificates, linkageBundle.directives)
  if linkageBundle.gateResult.blockingFailures > 0:
    for cert in result.certificates:
      if cert.status == certStale and
          cert.reason.startsWith("Rule 10 (Axiom Linkage):"):
        persistCertificateGateStatus(cert)

{.pop.}
