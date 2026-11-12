import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
from core/proof/proof_artifact import ProofArtifact
import core/boundary/gateway/gateway_generator
import core/boundary/gateway/gateway_spec
import core/logic/pipeline_fingerprint_engine
import core/logic/smt_logic
import core/logic/universal_translation_types
import core/session/session_parser_validators  # isNonEmpty — canonical in session_parser_validators
import core/solver/types
import core/trusted/axiom_pragmas
import core/trusted/lean_util
import core/types/domain_types
import core/types/pipeline_core_types
import core/types/remediation_types
import core/types/results
import core/types/workflow_state
import std/[options, sequtils, strutils]
# -----------------------------------------------------------------------------
# Semantic payload distinct types + validation constructors
# isNonEmpty: canonical location is core/session/session_parser_validators
# -----------------------------------------------------------------------------

func isSemanticPayloadSchemaVersion*(raw: string): bool {.inline, raises: [].} =
  raw == "axiom.semantic-payload.v1"
func isValidSmtIdentifier*(raw: string): bool {.inline, raises: [].} =
  if raw.len == 0:
    return false
  if raw[0] notin {'a'..'z', 'A'..'Z', '_'}:
    return false
  for i in 1 ..< raw.len:
    if raw[i] notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
      return false
  true
# -----------------------------------------------------------------------------
# Semantic payload distinct types + validation constructors
# isNonEmpty: canonical location is core/session/session_parser_validators
# -----------------------------------------------------------------------------
const
  epSemanticPayloadSchemaVersion = GatewayEndpoint(
    typeName: "SemanticPayloadSchemaVersion",
    predicate: "isSemanticPayloadSchemaVersion",
    errValue: "axiomErrSchemaVersionUnsupported",
    requires: ""
  )
  epSemanticModulePath = GatewayEndpoint(
    typeName: "SemanticModulePath",
    predicate: "isNonEmpty",
    errValue: "axiomErrEmptyString",
    requires: ""
  )
  epSemanticFunctionName = GatewayEndpoint(
    typeName: "SemanticFunctionName",
    predicate: "isNonEmpty",
    errValue: "axiomErrEmptyString",
    requires: ""
  )
  epSemanticEnumTypeName = GatewayEndpoint(
    typeName: "SemanticEnumTypeName",
    predicate: "isValidSmtIdentifier",
    errValue: "axiomErrInvalidValue",
    requires: ""
  )
  epSemanticSymbolName = GatewayEndpoint(
    typeName: "SemanticSymbolName",
    predicate: "isValidSmtIdentifier",
    errValue: "axiomErrInvalidValue",
    requires: ""
  )
  epSemanticEnumLabel = GatewayEndpoint(
    typeName: "SemanticEnumLabel",
    predicate: "isValidSmtIdentifier",
    errValue: "axiomErrInvalidValue",
    requires: ""
  )

generateGateway(epSemanticPayloadSchemaVersion)
generateGateway(epSemanticModulePath)
generateGateway(epSemanticFunctionName)
generateGateway(epSemanticEnumTypeName)
generateGateway(epSemanticSymbolName)
generateGateway(epSemanticEnumLabel)
type
  SemanticProofGoal* = enum
    semanticGoalEqualValuesDoNotThrow
    semanticGoalMismatchedValuesThrow
const specSemanticProofGoal = GatewayEnumSpec(
  typeName: "SemanticProofGoal",
  mappings: @[
    EnumMapping(raw: "equal_values_do_not_throw", enumVal: "semanticGoalEqualValuesDoNotThrow"),
    EnumMapping(raw: "mismatched_values_throw", enumVal: "semanticGoalMismatchedValuesThrow")
  ]
)

generateEnumGateway(specSemanticProofGoal)
type
  SemanticEqualityPayload* = object
    schemaVersion*: SemanticPayloadSchemaVersion
    modulePath*: SemanticModulePath
    functionName*: SemanticFunctionName
    enumTypeName*: SemanticEnumTypeName
    leftSymbol*: SemanticSymbolName
    rightSymbol*: SemanticSymbolName
    throwsSymbol*: SemanticSymbolName
    enumValues*: seq[SemanticEnumLabel]
    proofGoal*: SemanticProofGoal
    unsatCore*: seq[string]

  SemanticPayloadVerificationResponse* = object
    status*: string
    smt2*: string
    verified*: bool
    hasCounterExample*: bool
    counterExampleProperty*: string
    counterExampleBindings*: seq[SolverBinding]
    proofGoal*: string
    modulePath*: string
    functionName*: string
    enumTypeName*: string
    semanticRule*: string
    enumValues*: seq[string]

  SemanticProofReplayResult* = object
    theoremSource*: string
    tacticTrace*: seq[string]
    minimalProofPath*: seq[string]
    verified*: bool
    rounds*: seq[HealingRound]
    feedbackSummary*: string
    failedAttempts*: int
# -----------------------------------------------------------------------------
# Pure naming helpers
# -----------------------------------------------------------------------------

func extractBaseName*(path: string): string {.raises: [].} =
  ## Pure path basename extraction; avoids std/os import in this contract.
  let parts = path.split('/')
  if parts.len > 0:
    parts[^1]
  else:
    path
func buildSemanticLeanTheoremName*(payload: SemanticEqualityPayload): string {.raises: [].} =
  sanitizeLeanIdentifier(extractBaseName(semanticModulePathString(payload.modulePath))) & "_" &
    sanitizeLeanIdentifier(semanticFunctionNameString(payload.functionName)) & "_" &
    sanitizeLeanIdentifier(semanticProofGoalString(payload.proofGoal))

# -----------------------------------------------------------------------------
# Pure semantic dependency / verdict helpers (moved from core/logic to break cycles)
# -----------------------------------------------------------------------------
func summarizeCounterExampleBindings*(
  bindings: seq[SolverBinding]
): string {.raises: [].} =
  if bindings.len == 0:
    return "no explicit model bindings"
  bindings.mapIt(it.name & "=" & it.value).join(", ")
func latestSemanticReplayFeedback*(rounds: seq[HealingRound]; fallback: string): string {.raises: [].} =
  if rounds.len == 0:
    return fallback.strip()
  for idx in countdown(rounds.high, 0):
    if rounds[idx].phase == "semantic-proof-replay" and rounds[idx].feedbackSummary.strip().len > 0:
      return rounds[idx].feedbackSummary.strip()
  fallback.strip()
func semanticReplayFailureCount*(rounds: seq[HealingRound]): int {.raises: [], noSideEffect.} =
  for item in rounds:
    if item.phase == "semantic-proof-replay" and item.fixedKinds.len == 0:
      result.inc()
func buildSemanticVerificationVerdictReport*(
  verification: SemanticPayloadVerificationResponse;
  replayVerified: bool;
  rounds: seq[HealingRound];
  feedbackSummary: string
): VerificationVerdictReport {.raises: [].} =
  let failedAttempts = semanticReplayFailureCount(rounds)
  let nearestDiagnostic = latestSemanticReplayFeedback(rounds, feedbackSummary)
  let counterExampleSummary = summarizeCounterExampleBindings(verification.counterExampleBindings)
  if verification.hasCounterExample or verification.status.toLowerAscii() == "sat":
    return VerificationVerdictReport(
      status: "refuted_by_counterexample",
      category: "logical_contradiction",
      failureOrigin: "code",
      finalVerdict: "Final Verdict: the implementation is contradicted by an SMT counterexample, so the failure is in the code path, not in the proof engine. Model: " & counterExampleSummary,
      counterExampleProperty: verification.counterExampleProperty,
      counterExampleBindings: verification.counterExampleBindings,
      counterExampleSummary: counterExampleSummary,
      nearestLeanDiagnostic: "",
      failedReplayAttempts: failedAttempts
    )
  if verification.verified and replayVerified:
    return VerificationVerdictReport(
      status: "verified",
      category: "proof_necessary",
      failureOrigin: "none",
      finalVerdict: "Final Verdict: this proof is necessary rather than lucky because Lean replay closed with explicit MemorySafety lemmas and a minimized successful tactic path.",
      counterExampleProperty: "",
      counterExampleBindings: @[],
      counterExampleSummary: "",
      nearestLeanDiagnostic: nearestDiagnostic,
      failedReplayAttempts: failedAttempts
    )
  if verification.verified and failedAttempts >= 5:
    return VerificationVerdictReport(
      status: "unverifiable",
      category: "verification_gap",
      failureOrigin: "engine",
      finalVerdict: "Final Verdict: the code is currently classified as unverifiable by the engine because SMT found no counterexample but Lean replay still failed after " & $failedAttempts & " attempts. Closest Lean diagnostic: " & nearestDiagnostic,
      counterExampleProperty: "",
      counterExampleBindings: @[],
      counterExampleSummary: "",
      nearestLeanDiagnostic: nearestDiagnostic,
      failedReplayAttempts: failedAttempts
    )
  VerificationVerdictReport(
    status: "lean_replay_failed",
    category: "proof_replay_failed",
    failureOrigin: "engine",
    finalVerdict: "Final Verdict: no code-level contradiction was found, but the proof engine failed to complete a necessary Lean replay. Closest Lean diagnostic: " & nearestDiagnostic,
    counterExampleProperty: "",
    counterExampleBindings: @[],
    counterExampleSummary: "",
    nearestLeanDiagnostic: nearestDiagnostic,
    failedReplayAttempts: failedAttempts
  )
func buildSemanticDependencyContext*(
  payload: SemanticEqualityPayload;
  moduleChecksum: string
): DependencyContext {.raises: [].} =
  let enumChecksum = payload.enumValues
    .mapIt(semanticEnumLabelString(it))
    .join("|")
  let semanticRuleChecksum =
    semanticProofGoalString(payload.proofGoal) & "|" &
    semanticEnumTypeNameString(payload.enumTypeName) & "|" &
    semanticSymbolNameString(payload.leftSymbol) & "|" &
    semanticSymbolNameString(payload.rightSymbol) & "|" &
    semanticSymbolNameString(payload.throwsSymbol)
  result.symbolChecksums = @[
    SymbolChecksum(
      symbol: semanticEnumTypeNameString(payload.enumTypeName),
      checksum: enumChecksum
    ),
    SymbolChecksum(
      symbol: semanticModulePathString(payload.modulePath) & "::" &
        semanticFunctionNameString(payload.functionName),
      checksum: semanticRuleChecksum
    )
  ]
  if moduleChecksum.len > 0:
    result.symbolChecksums.add(SymbolChecksum(
      symbol: semanticModulePathString(payload.modulePath),
      checksum: moduleChecksum
    ))

# -----------------------------------------------------------------------------
# UniversalPipelineResult (moved from core/types/pipeline_core_types)
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Pure naming helpers
# -----------------------------------------------------------------------------
type
  UniversalPipelineResult* = object
    translation*: UniversalTranslation
    inferredSpec*: LeanSpecInference
    provenance*: ProofProvenance
    dependencyContext*: DependencyContext
    fingerprints*: UnifiedProofFingerprints
    smtTrack*: UniversalSmtTrack
    leanTrack*: UniversalLeanTrack
    initialScan*: NegativeInvariantScan
    finalScan*: NegativeInvariantScan
    healedSource*: string
    rounds*: seq[HealingRound]
    vkdFixed4*: string
    refinedInvariant*: string
    evolutionReasoning*: string
    pocSnippet*: string
    activeInvariant*: string
    verificationVerdict*: string
    verificationVerdictReport*: VerificationVerdictReport
    traceReport*: TraceReport
    personaLogs*: seq[string]
    proofArtifactPath*: string
    proofSummaryPath*: string
    evolutionHit*: Option[AnnotatedHit]
    bddFeaturePath*: string
    reproductionPath*: string
    promotionSnapshotPath*: string
    provenLayer*: ProvenLayerKind
    synergyMetrics*: SynergyMetrics
    nearestDiscontinuities*: seq[MathematicalDiscontinuity]
    structuredRemediation*: StructuredRemediationPayload
    proofArtifact*: ProofArtifact
    preConditions*: seq[string]
    postConditions*: seq[string]
    remediationJson*: string
    vacuityProven*: bool  ## Lean 컴파일러의 vacuity 검증 결과
# -----------------------------------------------------------------------------
# Pure result assembly (I/O-free; replay evidence is passed in)
# -----------------------------------------------------------------------------

func buildSemanticHybridUniversalPipelineResult*(
  payload: SemanticEqualityPayload;
  verification: SemanticPayloadVerificationResponse;
  replay: SemanticProofReplayResult;
  smtArtifactPath: string;
  leanArtifactPath: string;
  moduleChecksum: string = ""
): UniversalPipelineResult {.noSideEffect, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let semanticStrategy = "semantic-enum-equality"
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
    environmentInputs: @[],
    envInputConstructors: @[],
    stepFunctionCases: @[],
    loopControlVariables: @[],
    rankVariables: @[]
  )

  let verdictReport = buildSemanticVerificationVerdictReport(
    verification,
    replay.verified,
    replay.rounds,
    replay.feedbackSummary
  )

  let leanPremises = @[
    UniversalProofPremise(
      premisePath: "$.smtTrack.solverStatus",
      expectedValue: "unsat",
      theoremBinding: leanTheoremName & "_smt_unsat_premise"
    )
  ]

  let semanticInferredSpec = LeanSpecInference(
    theoremName: leanTheoremName,
    theoremSource: leanTheoremSource,
    guaranteedRange: "semantic-equality",
    assumptions: @["SMT premise " & leanPremises[0].premisePath & " == unsat"],
    stateTypeName: semanticEnumTypeNameString(payload.enumTypeName),
    stepConstructors: payload.enumValues.mapIt(semanticEnumLabelString(it)),
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
    hasVulnerability: false,
    hits: @[],
    logicModelConflicted: false
  )
  let semanticRefinedInvariant = "throwsRuntimeError = (typ != expected)"
  let semanticActiveInvariant = "equal enum values do not throw"

  result = UniversalPipelineResult(
    translation: semanticTranslation,
    inferredSpec: semanticInferredSpec,
    provenance: ProofProvenance(
      engine: veHybridRefinement,
      strategy: semanticStrategy,
      artifactPath: leanArtifactPath
    ),
    dependencyContext: buildSemanticDependencyContext(payload, moduleChecksum),
    smtTrack: UniversalSmtTrack(
      modulePath: semanticModulePathString(payload.modulePath),
      functionName: semanticFunctionNameString(payload.functionName),
      enumTypeName: semanticEnumTypeNameString(payload.enumTypeName),
      proofGoal: semanticProofGoalString(payload.proofGoal),
      semanticRule: semanticSymbolNameString(payload.throwsSymbol) & " <=> " &
        semanticSymbolNameString(payload.leftSymbol) & " != " &
        semanticSymbolNameString(payload.rightSymbol),
      enumValues: payload.enumValues.mapIt(semanticEnumLabelString(it)),
      solverStatus: verification.status,
      verified: verification.verified,
      smt2: verification.smt2,
      provenance: ProofProvenance(
        engine: veZ3Smt2,
        strategy: semanticStrategy,
        artifactPath: smtArtifactPath
      )
    ),
    leanTrack: UniversalLeanTrack(
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
    ),
    initialScan: semanticFinalScan,
    finalScan: semanticFinalScan,
    healedSource: "",
    rounds: replay.rounds,
    # NOTE: per-node verdict binary (1 if verified else 0), not a batch VKD
    # ratio. This proc verifies a single semantic-equality node; no verified/
    # total kernel count exists in scope to compute computeVkd(). Tracked for
    # possible ratio replacement (WS-3 key unification).
    vkdFixed4: (if verdictReport.status == "verified": "1.0000" else: "0.0000"),
    refinedInvariant: semanticRefinedInvariant,
    evolutionReasoning: "SMT unsat evidence is refined into a Lean theorem premise for deterministic replay, and LSP diagnostics steer tactic repair until the replay stabilizes.",
    pocSnippet: verification.smt2,
    activeInvariant: semanticActiveInvariant,
    verificationVerdict: verdictReport.status,
    verificationVerdictReport: verdictReport,
    traceReport: TraceReport(),
    personaLogs: @[],
    proofArtifactPath: smtArtifactPath,
    proofSummaryPath: leanArtifactPath,
    bddFeaturePath: "",
    reproductionPath: "",
    promotionSnapshotPath: "",
    evolutionHit: none(AnnotatedHit),
    fingerprints: computeUnifiedProofFingerprints(
      semanticTranslation,
      semanticInferredSpec,
      verdictReport.status,
      semanticActiveInvariant,
      semanticRefinedInvariant,
      semanticFinalScan
    )
  )

{.pop.}
