import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
from core/types/workflow_state import ProofReplayResult
import core/types/domain_types
import std/json
type
  LeanSpecInference* = object
    theoremName*: string
    theoremSource*: string
    guaranteedRange*: string
    assumptions*: seq[string]
    stateTypeName*: string
    stepConstructors*: seq[string]
    environmentInputs*: seq[string]
    stateInvariants*: seq[string]
    proofReplay*: ProofReplayResult
    refinementTheorem*: string
    refinementProven*: bool
    terminationArgument*: string
    loopControlVariables*: seq[string]
    rankVariables*: seq[string]

  VerificationEngine* = enum
    veZ3Smt2
    veLean4Lsp
    veHybridRefinement

  ProofProvenance* = object
    engine*: VerificationEngine
    strategy*: string
    artifactPath*: string

  SymbolChecksum* = object
    symbol*: string
    checksum*: string

  DependencyContext* = object
    symbolChecksums*: seq[SymbolChecksum]

  UnifiedProofFingerprints* = object
    smt*: string
    lean*: string
    cert*: string
    unified*: string

  UniversalProofPremise* = object
    premisePath*: string
    expectedValue*: string
    theoremBinding*: string

  UniversalSmtTrack* = object
    modulePath*: string
    functionName*: string
    enumTypeName*: string
    proofGoal*: string
    semanticRule*: string
    enumValues*: seq[string]
    solverStatus*: string
    verified*: bool
    smt2*: string
    provenance*: ProofProvenance

  UniversalLeanTrack* = object
    theoremName*: string
    theoremSource*: string
    verified*: bool
    premiseSatisfied*: bool
    premises*: seq[UniversalProofPremise]
    provenance*: ProofProvenance
    vacuityProven*: bool          ## Anti-vacuity linter result (Phase A-2)
    negativeMutationPass*: bool

  ProofArtifactBundle* = object
    proofArtifactPath*: string
    proofSummaryPath*: string
    verificationVerdict*: string

  VerificationVerdictReport* = object
    status*: string
    category*: string
    failureOrigin*: string
    finalVerdict*: string
    counterExampleProperty*: string
    counterExampleBindings*: seq[SolverBinding]
    counterExampleSummary*: string
    nearestLeanDiagnostic*: string
    failedReplayAttempts*: int
    provenLayer*: ProvenLayerKind

  # Layer 1: Domain-specific payloads (complete isolation)
  BufferOverflowInfo* = object
    address*: uint64
    size*: int

  NullPointerInfo* = object
    derefInstruction*: string

  IntegerOverflowInfo* = object
    registerName*: string
    isOverflow*: bool

  GhostUpdateInfo* = object
    shadowStateVariable*: string

  DeadlockInfo* = object
    trace*: string

  # Layer 2: Pure ADT
  VulnerabilityKind* = enum
    vkBufferOverflow,
    vkNullPointerDereference,
    vkIntegerOverflowUnderflow,
    vkGhostUpdate,
    vkDeadlockRaceCondition

  ProvenLayerKind* = enum
    plkUnknown      ## Not yet determined
    plkL1Bmc        ## Proven by Layer 1 BMC (SWAT)
    plkL2Cegar      ## Proven by Layer 2 CEGAR (Detective)
    plkL2Pdr        ## Proven by Layer 2 CHC/Fixedpoint (Detective → fixedpoint_engine). Legacy name kept for compatibility.
    plkL3Scribe     ## Proven by Layer 3 Scribe + Leanstral (Scribe)
    plkL4Judge      ## Proven by Layer 4 Judge + Lean Kernel (Judge)

  VulnerabilityHit* = object
    case kind*: VulnerabilityKind
    of vkBufferOverflow: boInfo*: BufferOverflowInfo
    of vkNullPointerDereference: npInfo*: NullPointerInfo
    of vkIntegerOverflowUnderflow: ioInfo*: IntegerOverflowInfo
    of vkGhostUpdate: guInfo*: GhostUpdateInfo
    of vkDeadlockRaceCondition: dlInfo*: DeadlockInfo

  AnnotatedHit* = object
    hit*: VulnerabilityHit
    sat*: bool
    violatedProperty*: string
    counterExampleInput*: string
    remediation*: string

  NegativeInvariantScan* = object
    hasVulnerability*: bool
    hits*: seq[AnnotatedHit]
    logicModelConflicted*: bool

  HealingRound* = object
    round*: int
    phase*: string
    fixedKinds*: seq[string]
    remainingVulnerabilities*: int
    feedbackSummary*: string
    suggestedTactic*: string
    diagnosticCount*: int

  TraceReport* = object
    vulnerabilityKind*: string
    violatedProperty*: string
    branchPoints*: seq[string]
    pathSignature*: string
    counterExampleSummary*: string
    traceRef*: string
    traceUrl*: string
    evolutionReasoning*: string

  UniversalPipelineRequest* = object
    language*: string
    modulePath*: string
    functionName*: string
    astJson*: string
    sourceCode*: string
    irHash*: string
    isKernel*: bool
    maxRounds*: int
    proofVaultDir*: string
    bddDir*: string
    preConditions*: seq[string]
    postConditions*: seq[string]
    unsatCoreVars*: seq[string]
    logic*: SmtLogic
    verificationContext*: AxiomVerificationContext
type
  PipelineCommand* = enum
    ## Yielded by the pipeline closure iterator at each persona boundary.
    ## The caller dispatches to the appropriate persona based on this enum.
    cmdRequireSwat         ## Dispatch to swat.executeRaid
    cmdRequireDetective    ## Dispatch to detective.openCase
    cmdRequireLegislator   ## Dispatch to legislator.legislate or legislator_feedback
    cmdRequireScribe       ## Dispatch to scribe.synthesizeLeanTheorem
    cmdRequireJudge        ## Dispatch to judge.certify
    cmdRequirePostProcess  ## Dispatch to detective.investigate
    cmdPipelineComplete    ## Pipeline finished; ctx.result is populated
type
  PayloadSerializable* = concept x
    x.getFingerprintSeed() is string
    x.toJsonNode() is JsonNode
func getFingerprintSeed*(bo: BufferOverflowInfo): string {.raises: [].} =
  "bo|" & $bo.address & "|" & $bo.size

func getFingerprintSeed*(np: NullPointerInfo): string {.raises: [].} =
  "np|" & np.derefInstruction

func getFingerprintSeed*(io: IntegerOverflowInfo): string {.raises: [].} =
  "io|" & io.registerName & "|" & $io.isOverflow

func getFingerprintSeed*(gu: GhostUpdateInfo): string {.raises: [].} =
  "gu|" & gu.shadowStateVariable

func getFingerprintSeed*(dl: DeadlockInfo): string {.raises: [].} =
  "dl|" & dl.trace

func toJsonNode*[T: object](info: T): JsonNode =
  ## Generic serialization via compile-time field iteration.
  ## Handles all *Info types without manual overloads.
  result = newJObject()
  for name, value in info.fieldPairs:
    result[name] = %*value

func toJson*(ah: AnnotatedHit): JsonNode {.raises: [].} =
  let payloadJson = case ah.hit.kind
  of vkBufferOverflow: ah.hit.boInfo.toJsonNode()
  of vkNullPointerDereference: ah.hit.npInfo.toJsonNode()
  of vkIntegerOverflowUnderflow: ah.hit.ioInfo.toJsonNode()
  of vkGhostUpdate: ah.hit.guInfo.toJsonNode()
  of vkDeadlockRaceCondition: ah.hit.dlInfo.toJsonNode()
  %*{
    "kind": $ah.hit.kind,
    "sat": ah.sat,
    "violatedProperty": ah.violatedProperty,
    "counterExampleInput": ah.counterExampleInput,
    "remediation": ah.remediation,
    "payload": payloadJson
  }
