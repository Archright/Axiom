import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
import core/utils/constants
import core/contracts/universal_pipeline_contract
import core/json/std_redirect
import core/lean_util as leanUtil
import core/pipeline_core_types as pipelineCoreTypes
import core/remediation_types
import core/translator/universal_mapper
import core/utils/text_utils
import core/workflow_state
import std/options
import std/os
import std/sequtils
import std/strutils
# @axiom-hint: lean="report_vulnerabilityKind.length ≥ 0 ∧ report_violatedProperty.length ≥ 0 ∧ report_branchPoints.size ≥ 0 ∧ report_pathSignature.length ≥ 0 ∧ report_counterExampleSummary.length ≥ 0 ∧ report_traceRef.length ≥ 0 ∧ report_traceUrl.length ≥ 0 ∧ report_evolutionReasoning.length ≥ 0" smt="(assert (and (>= (str.len report_vulnerabilityKind) 0) (>= (str.len report_violatedProperty) 0) (>= (seq.len report_branchPoints) 0) (>= (str.len report_pathSignature) 0) (>= (str.len report_counterExampleSummary) 0) (>= (str.len report_traceRef) 0) (>= (str.len report_traceUrl) 0) (>= (str.len report_evolutionReasoning) 0)))"
func traceReportIdentity(report: TraceReport): string {.raises: [], noSideEffect.} =
  if report.pathSignature.len > 0:
    return report.pathSignature
  if report.vulnerabilityKind.len > 0:
    return report.vulnerabilityKind
  "summary"
## Build Trace Ref.
# @axiom-hint: lean="modulePath.length ≥ 0 ∧ functionName.length ≥ 0 ∧ report_vulnerabilityKind.length ≥ 0 ∧ report_violatedProperty.length ≥ 0 ∧ report_branchPoints.size ≥ 0 ∧ report_pathSignature.length ≥ 0 ∧ report_counterExampleSummary.length ≥ 0 ∧ report_traceRef.length ≥ 0 ∧ report_traceUrl.length ≥ 0 ∧ report_evolutionReasoning.length ≥ 0" smt="(assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0) (>= (str.len report_vulnerabilityKind) 0) (>= (str.len report_violatedProperty) 0) (>= (seq.len report_branchPoints) 0) (>= (str.len report_pathSignature) 0) (>= (str.len report_counterExampleSummary) 0) (>= (str.len report_traceRef) 0) (>= (str.len report_traceUrl) 0) (>= (str.len report_evolutionReasoning) 0)))"
func buildTraceRef*(
  modulePath: string;
  functionName: string;
  report: TraceReport
): string {.raises: [], noSideEffect.} =
  "trace://uap/" &
    sanitizeToken(extractFilename(modulePath)) & "/" &
    sanitizeToken(functionName) & "/" &
    sanitizeToken(traceReportIdentity(report))

## Build Trace Url.
# @axiom-hint: lean="traceRef.length ≥ 0" smt="(assert (and (>= (str.len traceRef) 0)))"
func buildTraceUrl*(traceRef: string): string {.raises: [], noSideEffect.} =
  "http://localhost:12345/trace/" & sanitizeToken(traceRef)

## Normalize Trace Report.
# @axiom-hint: lean="result = report ∧ (result ≥ 0)" smt="(assert (and (= result report) (>= result 0)))"
func normalizeTraceReport*(
  report: TraceReport;
  modulePath: string;
  functionName: string;
  evolutionReasoning: string
): TraceReport {.raises: [], noSideEffect.} =
  result = report
  result.evolutionReasoning =
    if evolutionReasoning.strip().len > 0:
      evolutionReasoning
    elif report.counterExampleSummary.strip().len > 0:
      report.counterExampleSummary
    else:
      "no negative invariant violation detected; trace normalized without refinement"
  if result.traceRef.len == 0:
    result.traceRef = buildTraceRef(modulePath, functionName, result)
  if result.traceUrl.len == 0:
    result.traceUrl = buildTraceUrl(result.traceRef)

## Json From Proof Provenance.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func jsonFromProofProvenance*(provenance: ProofProvenance): JsonNode {.raises: [].} =
  result = newJObject()
  result["engine"] = newJString(verificationEngineString(provenance.engine))
  result[strategyKey] = newJString(provenance.strategy)
  result["artifactPath"] = newJString(provenance.artifactPath)

## Json From Dependency Context.
# @axiom-hint: lean="context_symbolChecksums.size ≥ 0" smt="(assert (and (>= (seq.len context_symbolChecksums) 0)))"
# @axiom-hint: lean="(checksumNode ≥ 0) ∧ (result ≥ 0)" smt="(assert (and (>= checksumNode 0) (>= result 0)))"
func jsonFromDependencyContext*(context: DependencyContext): JsonNode {.raises: [].} =
  result = newJObject()
  let checksums = newJArray()
  for item in context.symbolChecksums:
    var checksumNode = newJObject()
    checksumNode["symbol"] = newJString(item.symbol)
    checksumNode["checksum"] = newJString(item.checksum)
    checksums.add(checksumNode)
  result["symbolChecksums"] = checksums

## Json From Universal Smt Track.
# @axiom-hint: lean="track_modulePath.length ≥ 0 ∧ track_functionName.length ≥ 0 ∧ track_enumTypeName.length ≥ 0 ∧ track_proofGoal.length ≥ 0 ∧ track_semanticRule.length ≥ 0 ∧ track_enumValues.size ≥ 0 ∧ track_solverStatus.length ≥ 0 ∧ track_verified = true ∨ track_verified = false ∧ track_smt2.length ≥ 0 ∧ track_provenance_strategy.length ≥ 0 ∧ track_provenance_artifactPath.length ≥ 0" smt="(assert (and (>= (str.len track_modulePath) 0) (>= (str.len track_functionName) 0) (>= (str.len track_enumTypeName) 0) (>= (str.len track_proofGoal) 0) (>= (str.len track_semanticRule) 0) (>= (seq.len track_enumValues) 0) (>= (str.len track_solverStatus) 0) (or (= track_verified true) (= track_verified false)) (>= (str.len track_smt2) 0) (>= (str.len track_provenance_strategy) 0) (>= (str.len track_provenance_artifactPath) 0)))"
# @axiom-hint: lean="(result ≥ 0) ∧ track_verified = true ∨ track_verified = false" smt="(assert (and (>= result 0) (or (= track_verified true) (= track_verified false))))"
func jsonFromUniversalSmtTrack*(track: UniversalSmtTrack): JsonNode {.raises: [].} =
  result = newJObject()
  result[modulePathKey] = newJString(track.modulePath)
  result[functionNameKey] = newJString(track.functionName)
  result["enumTypeName"] = newJString(track.enumTypeName)
  result["proofGoal"] = newJString(track.proofGoal)
  result["semanticRule"] = newJString(track.semanticRule)
  let enumValuesNode = newJArray()
  for value in track.enumValues:
    enumValuesNode.add(newJString(value))
  result["enumValues"] = enumValuesNode
  result["solverStatus"] = newJString(track.solverStatus)
  result[verifiedKey] = newJBool(track.verified)
  result["smt2"] = newJString(track.smt2)
  result["provenance"] = jsonFromProofProvenance(track.provenance)

## Json From Universal Lean Track.
# @axiom-hint: lean="track_theoremName.length ≥ 0 ∧ track_theoremSource.length ≥ 0 ∧ track_verified = true ∨ track_verified = false ∧ track_premiseSatisfied = true ∨ track_premiseSatisfied = false ∧ track_premises.size ≥ 0 ∧ track_provenance_strategy.length ≥ 0 ∧ track_provenance_artifactPath.length ≥ 0" smt="(assert (and (>= (str.len track_theoremName) 0) (>= (str.len track_theoremSource) 0) (or (= track_verified true) (= track_verified false)) (or (= track_premiseSatisfied true) (= track_premiseSatisfied false)) (>= (seq.len track_premises) 0) (>= (str.len track_provenance_strategy) 0) (>= (str.len track_provenance_artifactPath) 0)))"
# @axiom-hint: lean="(premiseNode ≥ 0) ∧ (result ≥ 0) ∧ track_verified = true ∨ track_verified = false ∧ track_premiseSatisfied = true ∨ track_premiseSatisfied = false" smt="(assert (and (>= premiseNode 0) (>= result 0) (or (= track_verified true) (= track_verified false)) (or (= track_premiseSatisfied true) (= track_premiseSatisfied false))))"
func jsonFromUniversalLeanTrack*(track: UniversalLeanTrack): JsonNode {.raises: [].} =
  result = newJObject()
  result["theoremName"] = newJString(track.theoremName)
  result["theoremSource"] = newJString(track.theoremSource)
  result[verifiedKey] = newJBool(track.verified)
  result["premiseSatisfied"] = newJBool(track.premiseSatisfied)
  let premisesNode = newJArray()
  for premise in track.premises:
    var premiseNode = newJObject()
    premiseNode["premisePath"] = newJString(premise.premisePath)
    premiseNode["expectedValue"] = newJString(premise.expectedValue)
    premiseNode["theoremBinding"] = newJString(premise.theoremBinding)
    premisesNode.add(premiseNode)
  result["premises"] = premisesNode
  result["negativeMutationPass"] = newJBool(track.negativeMutationPass)
  result["provenance"] = jsonFromProofProvenance(track.provenance)

## Json From Verification Verdict Report.
# @axiom-hint: lean="report_status.length ≥ 0 ∧ report_category.length ≥ 0 ∧ report_failureOrigin.length ≥ 0 ∧ report_finalVerdict.length ≥ 0 ∧ report_counterExampleProperty.length ≥ 0 ∧ report_counterExampleBindings.size ≥ 0 ∧ report_counterExampleSummary.length ≥ 0 ∧ report_nearestLeanDiagnostic.length ≥ 0 ∧ report_failedReplayAttempts ≥ -9223372036854775808 ∧ report_failedReplayAttempts ≤ 9223372036854775807" smt="(assert (and (>= (str.len report_status) 0) (>= (str.len report_category) 0) (>= (str.len report_failureOrigin) 0) (>= (str.len report_finalVerdict) 0) (>= (str.len report_counterExampleProperty) 0) (>= (seq.len report_counterExampleBindings) 0) (>= (str.len report_counterExampleSummary) 0) (>= (str.len report_nearestLeanDiagnostic) 0) (and (>= report_failedReplayAttempts -9223372036854775808) (<= report_failedReplayAttempts 9223372036854775807))))"
func jsonFromVerificationVerdictReport*(report: VerificationVerdictReport): JsonNode {.raises: [].} =
  %*{
    "status": report.status,
    "category": report.category,
    "failureOrigin": report.failureOrigin,
    "finalVerdict": report.finalVerdict,
    "counterExampleProperty": report.counterExampleProperty,
    "counterExampleBindings": report.counterExampleBindings.mapIt(%*{
      "symbol": it.name,
      "value": it.value
    }),
    "counterExampleSummary": report.counterExampleSummary,
    "nearestLeanDiagnostic": report.nearestLeanDiagnostic,
    "failedReplayAttempts": report.failedReplayAttempts,
    "provenLayer": $report.provenLayer
  }

## Json From Trace Report.
# @axiom-hint: lean="report_vulnerabilityKind.length ≥ 0 ∧ report_violatedProperty.length ≥ 0 ∧ report_branchPoints.size ≥ 0 ∧ report_pathSignature.length ≥ 0 ∧ report_counterExampleSummary.length ≥ 0 ∧ report_traceRef.length ≥ 0 ∧ report_traceUrl.length ≥ 0 ∧ report_evolutionReasoning.length ≥ 0" smt="(assert (and (>= (str.len report_vulnerabilityKind) 0) (>= (str.len report_violatedProperty) 0) (>= (seq.len report_branchPoints) 0) (>= (str.len report_pathSignature) 0) (>= (str.len report_counterExampleSummary) 0) (>= (str.len report_traceRef) 0) (>= (str.len report_traceUrl) 0) (>= (str.len report_evolutionReasoning) 0)))"
func jsonFromTraceReport*(report: TraceReport): JsonNode {.raises: [].} =
  %*{
    "vulnerabilityKind": report.vulnerabilityKind,
    "violatedProperty": report.violatedProperty,
    "branchPoints": report.branchPoints,
    "pathSignature": report.pathSignature,
    "counterExampleSummary": report.counterExampleSummary,
    "traceRef": report.traceRef,
    "traceUrl": report.traceUrl,
    "evolutionReasoning": report.evolutionReasoning
  }
func jsonFromMathematicalDiscontinuity*(disc: MathematicalDiscontinuity): JsonNode {.raises: [].} =
  result = newJObject()
  result["filePath"] = newJString(disc.filePath)
  result["lineNumber"] = newJInt(disc.lineNumber)
  var varsNode = newJArray()
  for v in disc.smtUnsatCoreVars:
    varsNode.add(newJString(v))
  result["smtUnsatCoreVars"] = varsNode
  result["discontinuityKind"] = newJString($disc.discontinuityKind)
  result["description"] = newJString(disc.description)
func jsonFromStructuredRemediationPayload*(payload: StructuredRemediationPayload): JsonNode {.raises: [].} =
  result = newJObject()
  var discArr = newJArray()
  for disc in payload.discontinuities:
    discArr.add(jsonFromMathematicalDiscontinuity(disc))
  result["discontinuities"] = discArr
  var patternsArr = newJArray()
  for pattern in payload.suggestedPatterns:
    var pNode = newJObject()
    pNode["patternName"] = newJString(pattern.patternName)
    pNode["patternDescription"] = newJString(pattern.patternDescription)
    pNode["nimCodeTemplate"] = newJString(pattern.nimCodeTemplate)
    var appNode = newJArray()
    for kind in pattern.applicableTo:
      appNode.add(newJString($kind))
    pNode["applicableTo"] = appNode
    patternsArr.add(pNode)
  result["suggestedPatterns"] = patternsArr
  var templatesArr = newJArray()
  for tmpl in payload.refactoringTemplates:
    var tNode = newJObject()
    tNode["signal"] = newJString($tmpl.signal)
    tNode["pattern"] = newJString($tmpl.pattern)
    tNode["description"] = newJString(tmpl.description)
    tNode["nimHint"] = newJString(tmpl.nimHint)
    tNode["priority"] = newJInt(tmpl.priority)
    templatesArr.add(tNode)
  result["refactoringTemplates"] = templatesArr

## Json From Universal Pipeline Result.
# @axiom-hint: lean="keyIdx ≥ 0 ∧ colonIdx ≥ 0 ∧ (pathSignature ≥ 0) ∧ (inferredNode ≥ 0) ∧ (result ≥ 0) ∧ pipeline_inferredSpec_refinementProven = true ∨ pipeline_inferredSpec_refinementProven = false ∧ pipeline_smtTrack_verified = true ∨ pipeline_smtTrack_verified = false ∧ pipeline_leanTrack_verified = true ∨ pipeline_leanTrack_verified = false ∧ pipeline_leanTrack_premiseSatisfied = true ∨ pipeline_leanTrack_premiseSatisfied = false ∧ pipeline_initialScan_hasVulnerability = true ∨ pipeline_initialScan_hasVulnerability = false ∧ pipeline_initialScan_logicModelConflicted = true ∨ pipeline_initialScan_logicModelConflicted = false ∧ pipeline_finalScan_hasVulnerability = true ∨ pipeline_finalScan_hasVulnerability = false ∧ pipeline_finalScan_logicModelConflicted = true ∨ pipeline_finalScan_logicModelConflicted = false ∧ pipeline_evolutionHit_sat = true ∨ pipeline_evolutionHit_sat = false" smt="(assert (and (>= keyIdx 0) (>= colonIdx 0) (>= pathSignature 0) (>= inferredNode 0) (>= result 0) (or (= pipeline_inferredSpec_refinementProven true) (= pipeline_inferredSpec_refinementProven false)) (or (= pipeline_smtTrack_verified true) (= pipeline_smtTrack_verified false)) (or (= pipeline_leanTrack_verified true) (= pipeline_leanTrack_verified false)) (or (= pipeline_leanTrack_premiseSatisfied true) (= pipeline_leanTrack_premiseSatisfied false)) (or (= pipeline_initialScan_hasVulnerability true) (= pipeline_initialScan_hasVulnerability false)) (or (= pipeline_initialScan_logicModelConflicted true) (= pipeline_initialScan_logicModelConflicted false)) (or (= pipeline_finalScan_hasVulnerability true) (= pipeline_finalScan_hasVulnerability false)) (or (= pipeline_finalScan_logicModelConflicted true) (= pipeline_finalScan_logicModelConflicted false)) (or (= pipeline_evolutionHit_sat true) (= pipeline_evolutionHit_sat false))))"
func jsonFromUniversalPipelineResult*(pipeline: UniversalPipelineResult): JsonNode {.raises: [].} =
  result = newJObject()
  result[translationKey] = universalTranslationToJson(pipeline.translation)
  var inferredNode = newJObject()
  inferredNode["theoremName"] = newJString(pipeline.inferredSpec.theoremName)
  inferredNode["theoremSource"] = newJString(pipeline.inferredSpec.theoremSource)
  inferredNode["guaranteedRange"] = newJString(pipeline.inferredSpec.guaranteedRange)
  let assumptionsNode = newJArray()
  for assumption in pipeline.inferredSpec.assumptions:
    assumptionsNode.add(newJString(assumption))
  inferredNode["assumptions"] = assumptionsNode
  inferredNode["proofReplay"] = pipeline.inferredSpec.proofReplay.toJson()
  result[inferredSpecKey] = inferredNode
  result["provenance"] = jsonFromProofProvenance(pipeline.provenance)
  result["dependencyContext"] = jsonFromDependencyContext(pipeline.dependencyContext)
  var fpNode = newJObject()
  fpNode["smt"] = newJString(pipeline.fingerprints.smt)
  fpNode["lean"] = newJString(pipeline.fingerprints.lean)
  fpNode["cert"] = newJString(pipeline.fingerprints.cert)
  fpNode["unified"] = newJString(pipeline.fingerprints.unified)
  result[fingerprintsKey] = fpNode
  result["smtTrack"] = jsonFromUniversalSmtTrack(pipeline.smtTrack)
  result["leanTrack"] = jsonFromUniversalLeanTrack(pipeline.leanTrack)
  let proofReplay = pipeline.inferredSpec.proofReplay
  var prNode = newJObject()
  prNode["solver"] = newJString(DefaultSolverCommand)
  prNode["artifactStatus"] = newJString(if pipeline.verificationVerdict == "refuted_by_counterexample": "sat" else: "unsat")
  prNode["method"] = newJString(proofReplay.replayMethod)
  prNode["verified"] = newJBool(proofReplay.verified)
  prNode["leanKernelVerified"] = newJBool(proofReplay.leanKernelVerified)
  prNode["soundnessNote"] = newJString(proofReplay.soundnessNote)
  var tacticsArr = newJArray()
  for t in proofReplay.tactics:
    tacticsArr.add(newJString(t.name))
  prNode["tactics"] = tacticsArr
  var mpArr = newJArray()
  for p in proofReplay.minimalProofPath:
    mpArr.add(newJString(p))
  prNode["minimalProofPath"] = mpArr
  prNode["kernelTheorem"] = newJString("solver_to_proof_replay")
  result[proofReplayKey] = prNode
  var osNode = newJObject()
  osNode["stateTypeName"] = newJString(pipeline.inferredSpec.stateTypeName)
  var scArr = newJArray()
  for s in pipeline.inferredSpec.stepConstructors:
    scArr.add(newJString(s))
  osNode["stepConstructors"] = scArr
  var eiArr = newJArray()
  for s in pipeline.inferredSpec.environmentInputs:
    eiArr.add(newJString(s))
  osNode["environmentInputs"] = eiArr
  var siArr = newJArray()
  for s in pipeline.inferredSpec.stateInvariants:
    siArr.add(newJString(s))
  osNode["stateInvariants"] = siArr
  var nscArr = newJArray()
  for s in pipeline.translation.stepFunctionCases:
    nscArr.add(newJString(s))
  osNode["nextStateCases"] = nscArr
  result[operationalSemanticsKey] = osNode
  var refNode = newJObject()
  refNode["theorem"] = newJString(pipeline.inferredSpec.refinementTheorem)
  refNode["proven"] = newJBool(pipeline.inferredSpec.refinementProven)
  refNode["counterexampleRequired"] = newJBool(not pipeline.inferredSpec.refinementProven)
  var sswArr = newJArray()
  for w in proofReplay.strictSpecWarnings:
    sswArr.add(newJString(w))
  refNode["strictSpecWarnings"] = sswArr
  refNode["soundnessNote"] = newJString(proofReplay.soundnessNote)
  result[refinementKey] = refNode
  var termNode = newJObject()
  termNode["argument"] = newJString(pipeline.inferredSpec.terminationArgument)
  var theoremsArr = newJArray()
  theoremsArr.add(newJString("rank_decreases"))
  theoremsArr.add(newJString("termination_argument"))
  theoremsArr.add(newJString("no_deadlock_without_terminal"))
  termNode["theorems"] = theoremsArr
  var lcvArr = newJArray()
  for v in pipeline.inferredSpec.loopControlVariables:
    lcvArr.add(newJString(v))
  termNode["loopControlVariables"] = lcvArr
  var rvArr = newJArray()
  for v in pipeline.inferredSpec.rankVariables:
    rvArr.add(newJString(v))
  termNode["rankVariables"] = rvArr
  result[terminationKey] = termNode
  var isNode = newJObject()
  isNode["hasVulnerability"] = newJBool(pipeline.initialScan.hasVulnerability)
  var isHitsArr = newJArray()
  for h in pipeline.initialScan.hits:
    isHitsArr.add(h.toJson())
  isNode["hits"] = isHitsArr
  result[initialScanKey] = isNode
  var fsNode = newJObject()
  fsNode["hasVulnerability"] = newJBool(pipeline.finalScan.hasVulnerability)
  var fsHitsArr = newJArray()
  for h in pipeline.finalScan.hits:
    fsHitsArr.add(h.toJson())
  fsNode["hits"] = fsHitsArr
  result[finalScanKey] = fsNode
  let roundsNode = newJArray()
  for item in pipeline.rounds:
    var rNode = newJObject()
    rNode["round"] = newJInt(item.round)
    rNode["phase"] = newJString(item.phase)
    var fkArr = newJArray()
    for k in item.fixedKinds:
      fkArr.add(newJString(k))
    rNode["fixedKinds"] = fkArr
    rNode["remainingVulnerabilities"] = newJInt(item.remainingVulnerabilities)
    rNode["feedbackSummary"] = newJString(item.feedbackSummary)
    rNode["suggestedTactic"] = newJString(item.suggestedTactic)
    rNode["diagnosticCount"] = newJInt(item.diagnosticCount)
    roundsNode.add(rNode)
  result[healingRoundsKey] = roundsNode
  result["healedSource"] = newJString(pipeline.healedSource)
  result[vkdFixed4Key] = newJString(pipeline.vkdFixed4)
  result["refinedInvariant"] = newJString(pipeline.refinedInvariant)
  result[evolutionReasoningKey] = newJString(pipeline.evolutionReasoning)
  if pipeline.evolutionHit.isSome:
    var pathSignature = ""
    let eh = pipeline.evolutionHit.get()
    let input = eh.counterExampleInput
    let keyIdx = input.find("\"pathSignature\"")
    if keyIdx >= 0:
      let colonIdx = input.find(':', keyIdx)
      if colonIdx >= 0:
        var start = colonIdx + 1
        while start < input.len and input[start] in {' ', '\t', '\n', '\r'}:
          inc start
        if start < input.len and input[start] == '"':
          inc start
          var endIdx = start
          while endIdx < input.len and input[endIdx] != '"':
            inc endIdx
          pathSignature = input[start ..< endIdx]
    result["evolution"] = %*{
      "kind": $eh.hit.kind,
      "trace": {
        "pathSignature": pathSignature
      },
      "refinedInvariant": pipeline.refinedInvariant,
      "proofReplayVerdict": pipeline.verificationVerdict
    }
  result[pocSnippetKey] = newJString(pipeline.pocSnippet)
  result["activeInvariant"] = newJString(pipeline.activeInvariant)
  result[verificationVerdictKey] = newJString(pipeline.verificationVerdict)
  result["verificationVerdictReport"] = jsonFromVerificationVerdictReport(pipeline.verificationVerdictReport)
  result[traceReportKey] = jsonFromTraceReport(pipeline.traceReport)
  result["personaLogs"] = %*pipeline.personaLogs
  result["proofArtifactPath"] = newJString(pipeline.proofArtifactPath)
  result["proofSummaryPath"] = newJString(pipeline.proofSummaryPath)
  result["bddFeaturePath"] = newJString(pipeline.bddFeaturePath)
  result["reproductionPath"] = newJString(pipeline.reproductionPath)
  result["promotionSnapshotPath"] = newJString(pipeline.promotionSnapshotPath)
  result["provenLayer"] = newJString($pipeline.provenLayer)
  var smNode = newJObject()
  smNode["f_factor"] = newJFloat(pipeline.synergyMetrics.fFactor)
  smNode["g_factor"] = newJFloat(pipeline.synergyMetrics.gFactor)
  smNode["h_factor"] = newJFloat(pipeline.synergyMetrics.hFactor)
  smNode["geometricMean"] = newJFloat(pipeline.synergyMetrics.geometricMean)
  result["synergyMetrics"] = smNode
  var ndNode = newJArray()
  for disc in pipeline.nearestDiscontinuities:
    ndNode.add(jsonFromMathematicalDiscontinuity(disc))
  result["nearestDiscontinuities"] = ndNode
  result["remediation"] = jsonFromStructuredRemediationPayload(pipeline.structuredRemediation)
{.pop.}

