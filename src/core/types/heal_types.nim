import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/trusted/axiom_pragmas
import core/types/hubs/semantic_hint_hub
import std/json
import std/options
import std/tables
type
  HealNodeInput* = object
    node*: JsonNode
    nodeId*: string
    inputIndex*: int
    fileContext*: string
    docContext*: string
    unsatCore*: seq[string]
    attemptCount*: int
    forceFormal*: bool
    cwdOverride*: string
    tomlHint*: Option[SemanticHint]
    modulePathCache*: Table[string, string]

  HealContext* = object
    input*: HealNodeInput
    trajectoryPath*: string

  HealNodeOutput* = object
    nodeId*: string
    inputIndex*: int
    status*: string
    hint*: Option[SemanticHint]
    logLines*: seq[string]
    bottleneckLog*: JsonNode
    strategy*: string
    attemptCount*: int
    judgeApproved*: bool
    judgeReason*: string
    judgeSmt2*: string
    judgeLean*: string
    reasoningTrail*: seq[JsonNode]
    provenanceLog*: seq[JsonNode]

  ## Pure state transition enum for the result-application loop.
  HealStatus* = enum
    hsUnverifiable
    hsVerified
    hsPendingSave

  ## Scheduler-side mutable context (encapsulates the old mutable state cluster).
  HealSchedulerContext* = object
    fileCache*: Table[string, seq[string]]
    modulePathCache*: Table[string, string]

  ## Pure decision enum emitted by heal_hint_manager (no side effects).
  HintAction* = enum
    haRunZ3
    haRunLean
    haWriteCert
    haRejectVacuous
    haAccept

  ## Pure state carried by the HintManager automata.
  HintManagerState* = object
    state*: string
    hint*: SemanticHint
    nodeId*: string
    safeId*: string
    certPath*: string
    modulePath*: string
    functionName*: string
    cwdOverride*: string
    fileContext*: string
    sourceReference*: string
    smtConstraint*: string
    leanProposition*: string
    isVerifiedAxiom*: bool
    verifiedAxiomId*: string
    verifiedAxiomVersion*: string
    verifiedAxiomHash*: string
    leanResultVerified*: bool
    leanResultNegativeTestVerified*: bool

  ## Pure result returned by heal_hint_manager.
  HintValidationResult* = object
    action*: HintAction
    error*: string
    hint*: Option[SemanticHint]

  ## HintManager state automaton type (moved from heal_injection.nim for layer purity).
  HintManager* = object
    cwdOverride*: string
    nodeId*: string
    hint*: SemanticHint
    fileContext*: string
    stateEntry*: JsonNode
    modulePath*: string
    functionName*: string
    canonicalModule*: string
    safeId*: string
    completed*: bool
    isVerifiedAxiom*: bool
    verifiedAxiomId*: string
    verifiedAxiomVersion*: string
    verifiedAxiomHash*: string
    leanArtifactPath*: string
    negativeArtifactPath*: string
    leanResultVerified*: bool
    leanResultDiagnostics*: seq[string]
    leanResultNegativeTestVerified*: bool
func initHintManager*(
  cwdOverride: string;
  nodeId: string;
  hint: SemanticHint;
  fileContext: string;
  stateEntry: JsonNode
): HintManager {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  HintManager(
    cwdOverride: cwdOverride,
    nodeId: nodeId,
    hint: hint,
    fileContext: fileContext,
    stateEntry: stateEntry,
    completed: false,
    leanResultDiagnostics: @[]
  )

{.pop.}
