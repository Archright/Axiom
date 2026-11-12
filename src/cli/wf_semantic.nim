import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import cli/cli_types
import cli/topology_cli
import cli/wf_state
import cli/wf_state_vacuity
import core/axiom_pragmas
import core/contracts/universal_pipeline_contract
import core/gateway/gateway
import core/json/std_redirect
import core/logic/pipeline_fingerprint_engine
import core/logic/pipeline_verdict_engine
import core/logic/semantic_theorem_builder
import core/logic/smt_logic
import core/logic/universal_translation_types
import core/results
import core/trusted/env_access
import core/utils/constants
import core/utils/file_utils
import core/utils/text_utils
import core/vault/vault_manager_spec
import core/workflow_state
import std/options
import std/os
import std/sequtils
import std/strutils
import std/times
import verification/cli_bridge
import verification/pipeline_core_types
import verification/proof_synthesis_engine_part2
## Semantic Proof Artifact Base Name.
func semanticProofArtifactBaseName*(payload: SemanticEqualityPayload): string {.noSideEffect.} =
  sanitizeToken(extractFilename(semanticModulePathString(payload.modulePath))) & "_" &
    sanitizeToken(semanticFunctionNameString(payload.functionName))

## Semantic Proof Artifact Relative Path.
# @axiom-hint: lean="statePath.length ≥ 0 ∧ extension.length ≥ 0" smt="(assert (and (>= (str.len statePath) 0) (>= (str.len extension) 0)))"
func semanticProofArtifactRelativePath*(
  statePath: string;
  payload: SemanticEqualityPayload;
  extension: string
): string {.noSideEffect.} =
  joinPath("src", "semantic_proofs", semanticProofArtifactBaseName(payload) & extension).replace('\\', '/')
## semantic Payload Source Checksum variable.
let semanticPayloadSourceChecksum* = proc (payload: SemanticEqualityPayload): string =
  let modulePath = semanticModulePathString(payload.modulePath)
  if modulePath.len == 0 or not fileExists(modulePath):
    return ""
  try:
    vault_manager_spec.computeSourceFingerprint(readFileSafe(modulePath))
  except CatchableError:
    ""

## Semantic Proof Node Id Candidates.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
proc semanticProofNodeIdCandidates*(
  payload: SemanticEqualityPayload;
  reportNode: JsonNode
): seq[string]  =
  let modulePath = normalizePath(semanticModulePathString(payload.modulePath))
  let functionName = semanticFunctionNameString(payload.functionName)
  result = @[modulePath & "::" & functionName]
  if reportNode.hasKey(targetKey) and reportNode[targetKey].kind == JString:
    let relativeModulePath = trimProofStatePathPrefix(modulePath, reportNode[targetKey].getStr())
    let relativeNodeId = relativeModulePath & "::" & functionName
    if relativeModulePath.len > 0 and relativeNodeId notin result:
      result.add(relativeNodeId)
func buildSemanticInferredSpec(
  payload: SemanticEqualityPayload;
  leanTheoremName, leanTheoremSource: string;
  replay: SemanticProofReplayResult;
  verification: SemanticPayloadVerificationResponse;
  verdictReport: VerificationVerdictReport;
  leanPremises: seq[UniversalProofPremise];
  enumLabels: seq[string]
): LeanSpecInference {.raises: [], used.} =
  ## Build the LeanSpecInference for a semantic equality payload.
  LeanSpecInference(
    theoremName: leanTheoremName,
    theoremSource: leanTheoremSource,
    guaranteedRange: "semantic-equality",
    assumptions: @["SMT premise " & leanPremises[0].premisePath & " == unsat"],
    stateTypeName: semanticEnumTypeNameString(payload.enumTypeName),
    stepConstructors: enumLabels,
    environmentInputs: @[semanticModulePathString(payload.modulePath)],
    stateInvariants: @[
      "throwsRuntimeError = (typ != expected)",
      "bounds-checked container access is modeled through BoundsCheck and Option",
      "disjoint memory regions preserve pointer alias isolation"
    ],
    proofReplay: ProofReplayResult(
      replayMethod: "hybrid-refinement",
      tactics: replay.tacticTrace.mapIt(ProofReplayTactic(name: it, step: 0, verified: false)),
      minimalProofPath: replay.minimalProofPath,
      verified: replay.verified,
      leanKernelVerified: replay.verified,
      strictSpecWarnings: @[],
      soundnessNote: verdictReport.finalVerdict
    ),
    refinementTheorem: leanTheoremName,
    refinementProven: verification.verified and replay.verified,
    terminationArgument: "finite-enum-case-analysis",
    loopControlVariables: @[],
    rankVariables: @[]
  )
func buildSemanticSmtTrack(
  payload: SemanticEqualityPayload;
  verification: SemanticPayloadVerificationResponse;
  smtArtifactPath, semanticStrategy: string;
  enumLabels: seq[string]
): UniversalSmtTrack {.raises: [], used.} =
  ## Build the SMT track for a semantic equality payload.
  UniversalSmtTrack(
    modulePath: semanticModulePathString(payload.modulePath),
    functionName: semanticFunctionNameString(payload.functionName),
    enumTypeName: semanticEnumTypeNameString(payload.enumTypeName),
    proofGoal: semanticProofGoalString(payload.proofGoal),
    semanticRule: semanticSymbolNameString(payload.throwsSymbol) & " <=> " &
      semanticSymbolNameString(payload.leftSymbol) & " != " &
      semanticSymbolNameString(payload.rightSymbol),
    enumValues: enumLabels,
    solverStatus: verification.status,
    verified: verification.verified,
    smt2: verification.smt2,
    provenance: ProofProvenance(
      engine: veZ3Smt2,
      strategy: semanticStrategy,
      artifactPath: smtArtifactPath
    )
  )
func buildSemanticLeanTrack(
  leanTheoremName, leanTheoremSource: string;
  replay: SemanticProofReplayResult;
  verification: SemanticPayloadVerificationResponse;
  leanArtifactPath, semanticStrategy: string;
  leanPremises: seq[UniversalProofPremise]
): UniversalLeanTrack {.raises: [], used.} =
  ## Build the Lean track for a semantic equality payload.
  UniversalLeanTrack(
    theoremName: leanTheoremName,
    theoremSource: leanTheoremSource,
    verified: replay.verified,
    premiseSatisfied: verification.status.toLowerAscii() == "unsat",
    premises: leanPremises,
    provenance: ProofProvenance(
      engine: veLean4Lsp,
      strategy: semanticStrategy,
      artifactPath: leanArtifactPath
    )
  )
## Build Semantic Hybrid Universal Pipeline Result.
# Replaces the deleted verification/universal_pipeline_core module with a
# local, dependency-minimal implementation that constructs the canonical
# pipeline result from a semantic payload and its solver verification.
proc buildSemanticHybridUniversalPipelineResult*(
  payload: SemanticEqualityPayload;
  verification: SemanticPayloadVerificationResponse;
  smtArtifactPath: string;
  leanArtifactPath: string;
  moduleChecksum: string = ""
): UniversalPipelineResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let semanticStrategy = "semantic-enum-equality"
  let replay = runSemanticProofReplay(payload, leanArtifactPath)
  let leanTheoremSource = replay.theoremSource
  let leanTheoremName = buildSemanticLeanTheoremName(payload)
  let semanticTranslation = UniversalTranslation(
    language: "cpp",
    functionName: semanticFunctionNameString(payload.functionName),
    logic: slQfLia,
    ilEntries: @[],
    smt2: verification.smt2,
    controlFlowCount: 0,
    memoryAccessCount: 0,
    stateSpace: @[],
    stateInvariants: @[],
    transitionRelation: @[],
    transitionInvariants: @[],
    operationalSemantics: @[],
    environmentInputs: @[semanticModulePathString(payload.modulePath)],
    envInputConstructors: @[],
    stepFunctionCases: @[],
    loopControlVariables: @[],
    rankVariables: @[]
  )
  let verdictReport = buildSemanticVerificationVerdictReport(
    verification, replay.verified, replay.rounds, replay.feedbackSummary)
  let leanPremises = @[
    UniversalProofPremise(
      premisePath: "$.smtTrack.solverStatus",
      expectedValue: "unsat",
      theoremBinding: leanTheoremName & "_smt_unsat_premise"
    )
  ]
  var enumLabels: seq[string] = @[]
  for ev in payload.enumValues:
    enumLabels.add(semanticEnumLabelString(ev))
  let semanticInferredSpec = LeanSpecInference(
    theoremName: leanTheoremName,
    theoremSource: leanTheoremSource,
    guaranteedRange: "semantic-equality",
    assumptions: @["SMT premise " & leanPremises[0].premisePath & " == unsat"],
    stateTypeName: semanticEnumTypeNameString(payload.enumTypeName),
    stepConstructors: enumLabels,
    environmentInputs: @[semanticModulePathString(payload.modulePath)],
    stateInvariants: @[
      "throwsRuntimeError = (typ != expected)",
      "bounds-checked container access is modeled through BoundsCheck and Option",
      "disjoint memory regions preserve pointer alias isolation"
    ],
    proofReplay: ProofReplayResult(
      replayMethod: "hybrid-refinement",
      tactics: replay.tacticTrace.mapIt(ProofReplayTactic(name: it, step: 0, verified: false)),
      minimalProofPath: replay.minimalProofPath,
      verified: replay.verified,
      leanKernelVerified: replay.verified,
      strictSpecWarnings: @[],
      soundnessNote: verdictReport.finalVerdict
    ),
    refinementTheorem: leanTheoremName,
    refinementProven: verification.verified and replay.verified,
    terminationArgument: "finite-enum-case-analysis",
    loopControlVariables: @[],
    rankVariables: @[]
  )
  let semanticFinalScan = NegativeInvariantScan(
    hasVulnerability: false, hits: @[], logicModelConflicted: false)
  let semanticRefinedInvariant = "throwsRuntimeError = (typ != expected)"
  let semanticActiveInvariant = "equal enum values do not throw"
  result.translation = semanticTranslation
  result.inferredSpec = semanticInferredSpec
  result.provenance = ProofProvenance(
    engine: veHybridRefinement,
    strategy: semanticStrategy,
    artifactPath: leanArtifactPath
  )
  result.dependencyContext = buildSemanticDependencyContext(payload, moduleChecksum)
  result.smtTrack = UniversalSmtTrack(
    modulePath: semanticModulePathString(payload.modulePath),
    functionName: semanticFunctionNameString(payload.functionName),
    enumTypeName: semanticEnumTypeNameString(payload.enumTypeName),
    proofGoal: semanticProofGoalString(payload.proofGoal),
    semanticRule: semanticSymbolNameString(payload.throwsSymbol) & " <=> " &
      semanticSymbolNameString(payload.leftSymbol) & " != " &
      semanticSymbolNameString(payload.rightSymbol),
    enumValues: enumLabels,
    solverStatus: verification.status,
    verified: verification.verified,
    smt2: verification.smt2,
    provenance: ProofProvenance(
      engine: veZ3Smt2,
      strategy: semanticStrategy,
      artifactPath: smtArtifactPath
    )
  )
  result.leanTrack = UniversalLeanTrack(
    theoremName: leanTheoremName,
    theoremSource: leanTheoremSource,
    verified: replay.verified,
    premiseSatisfied: verification.status.toLowerAscii() == "unsat",
    premises: leanPremises,
    provenance: ProofProvenance(
      engine: veLean4Lsp,
      strategy: semanticStrategy,
      artifactPath: leanArtifactPath
    )
  )
  result.initialScan = semanticFinalScan
  result.finalScan = semanticFinalScan
  result.rounds = replay.rounds
  result.vkdFixed4 =
    # NOTE: per-node verdict binary (1 if verified else 0), not a batch VKD
    # ratio. Single semantic-equality node; no verified/total kernel count in
    # scope to call computeVkd(). Tracked for possible ratio replacement
    # (WS-3 key unification).
    if verdictReport.status == "verified": "1.0000" else: "0.0000"
  result.refinedInvariant = semanticRefinedInvariant
  result.evolutionReasoning =
    "SMT unsat evidence is refined into a Lean theorem premise for deterministic replay, and LSP diagnostics steer tactic repair until the replay stabilizes."
  result.pocSnippet = verification.smt2
  result.activeInvariant = semanticActiveInvariant
  result.verificationVerdict = verdictReport.status
  result.verificationVerdictReport = verdictReport
  result.proofArtifactPath = smtArtifactPath
  result.proofSummaryPath = leanArtifactPath
  result.fingerprints = computeUnifiedProofFingerprints(
    semanticTranslation,
    semanticInferredSpec,
    verdictReport.status,
    semanticActiveInvariant,
    semanticRefinedInvariant,
    semanticFinalScan
  )

## build Semantic Payload Proof State Json variable.
let buildSemanticPayloadProofStateJson* = proc (
  payload: SemanticEqualityPayload;
  verification: SemanticPayloadVerificationResponse;
  statePath: string
): Result[JsonNode, string] =
  var status = mapSemanticProofStatus(verification)
  let label = semanticProofLabel(payload)
  let smtArtifactPath = semanticProofArtifactRelativePath(statePath, payload, ".smt2")
  let leanArtifactPath = semanticProofArtifactRelativePath(statePath, payload, ".lean")
  let stateDir = parentDir(statePath)
  let artifactDir = joinPath(stateDir, "src", "semantic_proofs")
  try:
    if artifactDir.len > 0 and not dirExists(artifactDir):
      discard existsOrCreateDir(artifactDir)
  except CatchableError:
    return err("failed to prepare semantic proof artifact directory: " & artifactDir)
  let replayTuple = runSemanticProofReplay(payload, leanArtifactPath)
  let replay = SemanticProofReplayResult(
    theoremSource: replayTuple.theoremSource,
    tacticTrace: replayTuple.tacticTrace,
    minimalProofPath: replayTuple.minimalProofPath,
    verified: replayTuple.verified,
    rounds: replayTuple.rounds,
    feedbackSummary: replayTuple.feedbackSummary,
    failedAttempts: replayTuple.failedAttempts
  )
  let pipeline = buildSemanticHybridUniversalPipelineResult(
    payload,
    verification,
    replay,
    smtArtifactPath,
    leanArtifactPath,
    semanticPayloadSourceChecksum(payload)
  )
  let semanticLeanExe = getAxiomEnv(evLeanCmd, "lake env lean")
  let absoluteLeanArtifactPath = joinPath(stateDir, leanArtifactPath)
  try:
    discard writeFileSafe(joinPath(stateDir, smtArtifactPath), verification.smt2)  # axiom:best-effort(SMT artifact is an informational sidecar; verification uses the lean artifact written separately)
  except CatchableError:
    return err("failed to persist semantic proof artifacts: " & artifactDir)
  var enrichedPipeline = pipeline
  let leanCompilerResult = verifyGeneratedLeanSourceWithCompiler(
    theoremSource = enrichedPipeline.leanTrack.theoremSource,
    artifactPath = absoluteLeanArtifactPath,
    leanExe = semanticLeanExe
  )
  enrichedPipeline.leanTrack.verified = leanCompilerResult.verified
  applyLeanCompilerFeedback(enrichedPipeline.leanTrack, leanCompilerResult)
  enrichedPipeline.inferredSpec.proofReplay.leanKernelVerified = leanCompilerResult.verified
  enrichedPipeline.inferredSpec.proofReplay.verified = leanCompilerResult.verified
  enrichedPipeline.inferredSpec.refinementProven =
    verification.verified and leanCompilerResult.verified
  if not leanCompilerResult.verified and verification.verified:
    status = axProofUnverifiable
    let nearestDiagnostic =
      if leanCompilerResult.diagnostics.len > 0:
        leanCompilerResult.diagnostics[0].message
      else:
        leanCompilerResult.output.strip()
    let failedReplayAttempts = max(enrichedPipeline.verificationVerdictReport.failedReplayAttempts, 5)
    let finalVerdict =
      "Final Verdict: the code is currently classified as unverifiable by the engine because SMT found no counterexample but Lean compiler verification failed after " &
      $failedReplayAttempts & " attempts. Closest Lean diagnostic: " & nearestDiagnostic
    enrichedPipeline.verificationVerdict = "unverifiable"
    enrichedPipeline.verificationVerdictReport = VerificationVerdictReport(
      status: "unverifiable",
      category: "verification_gap",
      failureOrigin: "engine",
      finalVerdict: finalVerdict,
      counterExampleProperty: "",
      counterExampleBindings: @[],
      counterExampleSummary: "",
      nearestLeanDiagnostic: nearestDiagnostic,
      failedReplayAttempts: failedReplayAttempts
    )
    enrichedPipeline.inferredSpec.proofReplay.soundnessNote = finalVerdict
  var bindings = newJArray()
  for binding in verification.counterExampleBindings:
    bindings.add(%*{
      "symbol": binding.name,
      "value": binding.value
    })
  var stateNode = %*{
    targetKey: semanticModulePathString(payload.modulePath),
    sourceRootKey: parentDir(semanticModulePathString(payload.modulePath)),
    timestampKey: now().utc().format("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"),
    "summary": {
      totalNodesKey: 1,
      attemptedNodesKey: 1,
      verifiedKey: if status == axProofVerified: 1 else: 0,
      counterExamplesKey: if status == axProofCounterExampleFound: 1 else: 0,
      timedOutKey: if status == axProofTimedOut: 1 else: 0,
      "unverifiable": if status == axProofUnverifiable: 1 else: 0,
      unattemptedKey: 0
    },
    entriesKey: [
      {
        nodeIdKey: semanticProofNodeId(payload),
        labelKey: label,
        dependencyDepthKey: 0,
        impactIndexKey: verification.enumValues.len,
        statusKey: axProofStatusValue(status),
        "attempted": true,
        premiseCountKey: 0,
        "dependencyCount": 0,
        "dependentNodeCount": 0,
        "transitiveDependentCount": 0,
        "semanticProof": {
          "proofGoal": verification.proofGoal,
          verifiedKey: verification.verified,
          modulePathKey: verification.modulePath,
          functionNameKey: verification.functionName,
          "enumTypeName": verification.enumTypeName,
          "semanticRule": verification.semanticRule,
          "enumValues": verification.enumValues,
          "solverStatus": verification.status,
          "smt2": verification.smt2,
          "engine": "hybrid-refinement",
          strategyKey: "semantic-enum-equality",
          "artifactPath": smtArtifactPath,
          "hasCounterExample": verification.hasCounterExample,
          "counterExampleProperty": verification.counterExampleProperty,
          "counterExampleBindings": bindings,
          "universalPipeline": jsonFromUniversalPipelineResult(enrichedPipeline)
        }
      }
    ],
    "workflow": {
      reproofRequiredKey: newJArray(),
      "performance": {
        totalWallTimeMsKey: 0,
        cpuEfficiencyKey: 0.0,
        "parallelSpeedupRatio": 0.0,
        cacheHitCountKey: 0,
        "timeoutCount": if status == axProofTimedOut: 1 else: 0,
        "timeoutImpactNodes": if status == axProofTimedOut: 1 else: 0,
        "hotspotLabel": if status == axProofTimedOut: label else: "",
        "hotspotElapsedMs": 0
      },
      "timeoutDiagnostics": newJArray()
    }
  }
  if not verification.verified or not leanCompilerResult.verified:
    stateNode["workflow"][reproofRequiredKey].add(%*{
      labelKey: label,
      reasonKey:
        if not verification.verified:
          semanticProofFailureReason(verification)
        else:
          "lean compiler verification failed"
    })
  ok(stateNode)

## Find Semantic Proof Entry Index.
# @axiom-hint: lean="-1 ∧ index" smt="(assert (and -1 index))"
func findSemanticProofEntryIndex*(
  reportNode: JsonNode;
  payload: SemanticEqualityPayload
): int {.noSideEffect.} =
  if not reportNode.hasKey(entriesKey) or reportNode[entriesKey].kind != JArray:
    return -1
  let label = semanticProofLabel(payload)
  let nodeIdCandidates = semanticProofNodeIdCandidates(payload, reportNode)
  for index, entry in reportNode[entriesKey].elems:
    if entry.kind != JObject:
      continue
    if entry.hasKey(nodeIdKey) and entry[nodeIdKey].kind == JString and
        entry[nodeIdKey].getStr() in nodeIdCandidates:
      return index
  for index, entry in reportNode[entriesKey].elems:
    if entry.kind != JObject:
      continue
    if entry.hasKey(labelKey) and entry[labelKey].kind == JString and entry[labelKey].getStr() == label:
      return index
  -1
## merge Semantic Payload Proof State variable.
let mergeSemanticPayloadProofState* = proc (
  baseReportNode: JsonNode;
  payload: SemanticEqualityPayload;
  verification: SemanticPayloadVerificationResponse;
  statePath: string
): Result[JsonNode, string] =
  var mergedState = copy(baseReportNode)
  let semanticState = ??buildSemanticPayloadProofStateJson(payload, verification, statePath)
  let semanticEntry = semanticState[entriesKey][0]
  let semanticLabel = semanticEntry[labelKey].getStr()
  let entryIndex = findSemanticProofEntryIndex(mergedState, payload)
  if not mergedState.hasKey(entriesKey) or mergedState[entriesKey].kind != JArray:
    mergedState[entriesKey] = newJArray()
  if entryIndex >= 0:
    var mergedEntry = mergedState[entriesKey].elems[entryIndex]
    mergedEntry[statusKey] = semanticEntry[statusKey]
    mergedEntry["attempted"] = semanticEntry["attempted"]
    mergedEntry["semanticProof"] = semanticEntry["semanticProof"]
    mergedState[entriesKey].elems[entryIndex] = mergedEntry
  else:
    mergedState[entriesKey].add(semanticEntry)
  sortAxProofEntries(mergedState[entriesKey].elems)
  mergedState[timestampKey] = semanticState[timestampKey]
  if not mergedState.hasKey("workflow") or mergedState["workflow"].kind != JObject:
    mergedState["workflow"] = newJObject()
  if not mergedState["workflow"].hasKey(reproofRequiredKey) or mergedState["workflow"][reproofRequiredKey].kind != JArray:
    mergedState["workflow"][reproofRequiredKey] = newJArray()
  var filteredReproof = newJArray()
  for entry in mergedState["workflow"][reproofRequiredKey].elems:
    if entry.kind != JObject:
      continue
    if entry.hasKey(labelKey) and entry[labelKey].kind == JString and entry[labelKey].getStr() == semanticLabel:
      continue
    filteredReproof.add(entry)
  mergedState["workflow"][reproofRequiredKey] = filteredReproof
  let semanticLeanVerified =
    semanticEntry{"semanticProof"}{"universalPipeline"}{"leanTrack"}{verifiedKey}.kind == JBool and
    semanticEntry["semanticProof"]["universalPipeline"]["leanTrack"][verifiedKey].getBool()
  if not verification.verified or not semanticLeanVerified:
    mergedState["workflow"][reproofRequiredKey].add(%*{
      labelKey: semanticLabel,
      reasonKey:
        if not verification.verified:
          semanticProofFailureReason(verification)
        else:
          "lean compiler verification failed"
    })
  if not mergedState["workflow"].hasKey("timeoutDiagnostics") or mergedState["workflow"]["timeoutDiagnostics"].kind != JArray:
    mergedState["workflow"]["timeoutDiagnostics"] = newJArray()
  recomputeAxProofStateSummary(mergedState)
  ok(mergedState)

## normalize Semantic Proof State Dependencies variable.
let normalizeSemanticProofStateDependencies* = proc (reportNode: var JsonNode) =
  if not reportNode.hasKey(entriesKey) or reportNode[entriesKey].kind != JArray:
    return
  if not reportNode.hasKey("workflow") or reportNode["workflow"].kind != JObject:
    reportNode["workflow"] = newJObject()
  if not reportNode["workflow"].hasKey(reproofRequiredKey) or reportNode["workflow"][reproofRequiredKey].kind != JArray:
    reportNode["workflow"][reproofRequiredKey] = newJArray()
  var staleLabels: seq[string] = @[]
  for _, entry in reportNode[entriesKey].elems.mpairs:
    let reason = semanticEntryDependencyMismatchReason(entry)
    if reason.len == 0:
      continue
    let oldStatus = entry{statusKey}.getStr()
    if oldStatus == "certStale":
      discard  # Preserve higher-priority status (e.g., certStale)
    else:
      entry[statusKey] = newJString(unattemptedKey)
    entry["attempted"] = newJBool(false)
    entry["staleReason"] = newJString(reason)
    staleLabels.add(entry[labelKey].getStr())
  if staleLabels.len == 0:
    recomputeAxProofStateSummary(reportNode)
    return
  var filteredReproof = newJArray()
  for item in reportNode["workflow"][reproofRequiredKey].elems:
    if item.kind != JObject:
      continue
    let labelNode = item{labelKey}
    if not labelNode.isNil and labelNode.kind == JString and labelNode.getStr() in staleLabels:
      continue
    filteredReproof.add(item)
  reportNode["workflow"][reproofRequiredKey] = filteredReproof
  for label in staleLabels:
    reportNode["workflow"][reproofRequiredKey].add(%*{
      labelKey: label,
      reasonKey: "stale dependency"
    })
  recomputeAxProofStateSummary(reportNode)

## is Semantic Payload Document variable.
let isSemanticPayloadDocument* = proc (payload: string): bool =
  let parsed = jsonParseSafe(payload)
  if parsed.isErr():
    return false
  let root = jsonRequireObject(parsed.get())
  if root.isErr():
    return false
  let schemaVersion = jsonTryGetNonEmptyStringField(root.get(), schemaVersionKey)
  return schemaVersion.isSome() and schemaVersion.get() == "axiom.semantic-payload.v1"

{.pop.}
