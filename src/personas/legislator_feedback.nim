import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

from core/boundary/verification_interface import StageKind, StageStatus
import core/boundary/boundary_forwarding
import core/boundary/gateway_boundary
import core/boundary/results_boundary
import core/contracts/logic_contract
import core/encoding/type_logic_registry
import core/resilience/error_classifier
import core/resilience/error_context
import core/resilience/resilience_config
import core/types/lean_lsp_types
import personas/legislator
import personas/llm_response_guard
import std/options
import std/sets
import std/strutils
verifySpecCompleteness("legislator_feedback", ModuleMetrics(
  hotspotDepth: 2.0,
  astNodeCount: 276.0,
  inDegree: 7.0
))

let ctx = initPersonaContext()
var feedbackResilienceCfg = defaultResilienceConfig()

## Prompt template for counterexample-aware invariant revision.
## Enhanced with structured constraint specification (§4 Meta-Verification Layer).
const LegislatorFeedbackPromptTemplate = """You are the Legislator (입법자) of the Axiom integrity system.

Your task: draft a formal invariant for function {functionName} in module {modulePath}.

## Previous Attempt (FAILED)
The previous invariant was:
```
{failedInvariant}
```

## Counterexample from Lean 4 Kernel
The Lean 4 verifier rejected the invariant with the following diagnostic:
```
{leanDiagnostic}
```

## SMT Counterexample
```
{smtCounterExample}
```

## Failing Lean Source Code
```
{failingLeanSource}
```

{constraintSpec}

## Context
{traceReport}

## Instructions
1. Analyze WHY the previous invariant failed using the counterexample and constraint specification above.
2. Revise the invariant to EXCLUDE this counterexample while preserving correctness.
3. Ensure the new invariant is STRONGER than the previous one (narrower set of allowed states).
4. The revised invariant MUST satisfy ALL constraints in the specification above.
5. Output ONLY the revised invariant as a single boolean expression. No prose.
"""

## Phase 5: Tactic History Fingerprinting for deduplication.
const MaxFeedbackRounds* = 3
type
  TacticAttempt* = object
    ## Record of a single tactic attempt with its error fingerprint.
    tactic*: string
    errorType*: string
    errorHash*: uint64
    goalSnapshot*: string

  TacticHistory* = object
    ## Accumulated tactic attempts with deduplication set.
    attempts*: seq[TacticAttempt]
    deduplicationSet*: HashSet[uint64]
func fingerprint*(tactic: string; errorType: string): uint64 {.raises: [], noSideEffect.} =
  ## FNV-1a hash of "tactic:errorType" for deduplication.
  ## Matches the FNV-1a pattern in refinement_string.nim but returns raw uint64.
  var hash = 1469598103934665603'u64
  let payload = tactic & ":" & errorType
  for ch in payload:
    hash = hash xor uint64(ord(ch))
    hash = hash * 1099511628211'u64
  hash
func initTacticHistory*(): TacticHistory {.raises: [].} =
  ## Create an empty tactic history.
  TacticHistory(
    attempts: @[],
    deduplicationSet: initHashSet[uint64]()
  )
func isDuplicate*(history: TacticHistory; hash: uint64): bool {.raises: [], noSideEffect.} =
  ## Check if a tactic fingerprint has already been attempted.
  hash in history.deduplicationSet
func recordAttempt*(history: var TacticHistory; tactic: string;
                    errorType: string; goalSnapshot: string = "") {.raises: [].} =
  ## Record a tactic attempt and update the deduplication set.
  let h = fingerprint(tactic, errorType)
  history.attempts.add(TacticAttempt(
    tactic: tactic,
    errorType: errorType,
    errorHash: h,
    goalSnapshot: goalSnapshot
  ))
  history.deduplicationSet.incl(h)
func buildDoNotRepeatSection*(history: TacticHistory): string {.raises: [].} =
  ## Build a DO NOT REPEAT section for the Legislator prompt.
  ## Lists all previously failed tactic+error combinations.
  if history.attempts.len == 0:
    return ""
  result = "\n## DO NOT REPEAT — Previously Failed Tactics\n"
  result.add("The following tactic+error combinations have already been attempted and FAILED. ")
  result.add("DO NOT suggest any of these tactics for this goal:\n\n")
  for attempt in history.attempts:
    result.add("- `" & attempt.tactic & "` → " & attempt.errorType &
               " (fingerprint: 0x" & toHex(attempt.errorHash, 16) & ")\n")
  result.add("\nFocus on NOVEL approaches not listed above.\n")
func goalDeltaToFeedbackStrings*(deltas: seq[GoalDelta]): seq[string] {.raises: [].} =
  ## Convert structured GoalDelta objects to human-readable strings
  ## for the Legislator feedback prompt.
  ## Each delta becomes a block showing resolved/created/unchanged goals.
  for i, delta in deltas:
    var entry = ""
    if delta.resolvedGoals.len > 0:
      entry.add("Resolved: " & delta.resolvedGoals.join(", "))
    if delta.newGoals.len > 0:
      if entry.len > 0: entry.add(" | ")
      entry.add("Created: " & delta.newGoals.join(", "))
    if delta.unchangedGoals.len > 0:
      if entry.len > 0: entry.add(" | ")
      entry.add("Unchanged: " & delta.unchangedGoals.join(", "))
    if delta.typeErrors.len > 0:
      if entry.len > 0: entry.add(" | ")
      entry.add("TypeErrors: " & delta.typeErrors.join(", "))
    if entry.len > 0:
      result.add("[Tactic " & $(i + 1) & "] " & entry)
func buildConstraintSpecification*(
  unsatCoreVars: seq[string];
  goalDelta: seq[string] = @[]
): string {.raises: [].} =
  ## Build a structured constraint specification for the Legislator.
  ## This transforms unstructured error messages into actionable constraints.
  ##
  ## Principle (Gulwani CEGIS): structured feedback prunes the search space
  ## more effectively than raw error messages.
  if unsatCoreVars.len == 0 and goalDelta.len == 0:
    return ""

  result = "## Structured Constraint Specification\n"
  result.add("The following constraints MUST be satisfied by the revised invariant:\n\n")

  if unsatCoreVars.len > 0:
    result.add("### Unsat Core Variables (Z3 minimal unsatisfiable set)\n")
    result.add("These variables form a minimal set that caused the Z3 conflict. " &
               "The revised invariant MUST constrain these variables consistently:\n")
    result.add("```json\n")
    result.add("{\n")
    result.add("  \"unsatCoreVars\": [")
    for i, v in unsatCoreVars:
      if i > 0: result.add(", ")
      result.add("\"" & v & "\"")
    result.add("],\n")
    result.add("  \"constraint\": \"The invariant must provide consistent bounds on all unsat core variables\"\n")
    result.add("}\n")
    result.add("```\n\n")

  if goalDelta.len > 0:
    result.add("### Tactic Goal Delta (from proof search)\n")
    result.add("The proof search resolved some goals but failed on others. " &
               "Focus the invariant on the UNRESOLVED goals:\n")
    result.add("```\n" & goalDelta.join("\n") & "\n```\n\n")
func buildFeedbackPrompt*(
  req: UniversalPipelineRequest;
  cx: CounterExamplePayload;
  unsatCoreVars: seq[string] = @[];
  goalDelta: seq[string] = @[];
  failingLeanSource: string = ""
): string {.raises: [].} =
  ## Serialize CounterExamplePayload into the Legislator's system prompt.
  ## Enhanced with structured constraint specification and failing Lean source.
  let constraintSpec = buildConstraintSpecification(unsatCoreVars, goalDelta)
  LegislatorFeedbackPromptTemplate
    .replace("{functionName}", req.functionName)
    .replace("{modulePath}", req.modulePath)
    .replace("{failedInvariant}", cx.failedInvariant)
    .replace("{leanDiagnostic}", cx.leanDiagnostic)
    .replace("{smtCounterExample}", cx.smtCounterExample)
    .replace("{failingLeanSource}", failingLeanSource)
    .replace("{constraintSpec}", constraintSpec)
    .replace("{traceReport}", $cx.traceReport)
func buildStagnationArtifact(
  priorPromotion: tuple[invariant: string; snapshotPath: string]
): LegislatorArtifact {.raises: [].} =
  ## Build the artifact returned when the stagnation guard is triggered.
  let traceReport = buildTraceReport(none(AnnotatedHit))
  LegislatorArtifact(
    baselineInvariant: priorPromotion.invariant,
    refinedInvariant: "",
    activeInvariant: priorPromotion.invariant,
    evolutionReasoning: "LegislatorFeedback: stagnation guard — max rounds (" & $MaxFeedbackRounds & ") reached",
    traceReport: traceReport,
    logLines: @["LegislatorFeedback: stagnation guard triggered after " & $MaxFeedbackRounds & " rounds"]
  )
func buildFallbackArtifact(
  priorPromotion: tuple[invariant: string; snapshotPath: string];
  reasoning: string
): LegislatorArtifact {.raises: [].} =
  ## Build the artifact returned when the LLM fails or the prompt is empty.
  let traceReport = buildTraceReport(none(AnnotatedHit))
  LegislatorArtifact(
    baselineInvariant: priorPromotion.invariant,
    refinedInvariant: "",
    activeInvariant: priorPromotion.invariant,
    evolutionReasoning: reasoning,
    traceReport: traceReport,
    logLines: @[reasoning]
  )
func processLlmResult*(
  revisedInvariantRaw: string;
  priorPromotion: tuple[invariant: string; snapshotPath: string];
  latestCx: CounterExamplePayload
): LegislatorArtifact {.raises: [].} =
  ## Transform a successful LLM result into a LegislatorArtifact.
  ## Uses LLM response guard to strip markdown fences and noise.
  let revisedInvariant = stripLeadingTrailingNoise(revisedInvariantRaw)
  let activeInvariant =
    if revisedInvariant.len > 0:
      mergeInvariantClauses(priorPromotion.invariant, revisedInvariant)
    else:
      priorPromotion.invariant
  let traceReport = buildTraceReport(none(AnnotatedHit))
  LegislatorArtifact(
    baselineInvariant: priorPromotion.invariant,
    refinedInvariant: revisedInvariant,
    activeInvariant: activeInvariant,
    evolutionReasoning: "Revised via counterexample feedback: " & latestCx.leanDiagnostic,
    traceReport: traceReport,
    logLines: @["LegislatorFeedback: counterexample injected, LLM revised invariant"]
  )
proc runFeedbackRetryLoop(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  sourceCode: string;
  priorPromotion: tuple[invariant: string; snapshotPath: string];
  basePrompt: string;
  cxHistory: seq[CounterExamplePayload];
  returnType: string = "void"
): Result[LegislatorArtifact, AxiomError] {.raises: [].} =
  ## Execute the retry loop for LLM feedback with response guard.
  ## Returns the revised artifact on success, or a fallback artifact on failure.
  try:
    var attemptCount = 0
    var lastError = ""
    while attemptCount < MaxFeedbackRounds:
      let currentPrompt =
        if attemptCount == 0: basePrompt
        else: buildRetryPrompt(lastError, basePrompt)
      let lsResult = ctx.callLeanstral(currentPrompt)
      if not lsResult.success or lsResult.theoremSource.len == 0:
        lastError = "LLM returned empty or failed result"
        inc attemptCount
        continue
      let cleaned = stripLeadingTrailingNoise(lsResult.theoremSource)
      if cleaned.len == 0:
        lastError = "LLM response was empty after noise stripping"
        inc attemptCount
        continue
      # Type validation BEFORE returning — catches vacuous invariants early
      let typeCheck = validateHintTypeConsistency(cleaned, cleaned, returnType)
      if not typeCheck.valid:
        lastError = "TYPE ERROR: " & typeCheck.error &
          " | Allowed: " & typeCheck.allowedConstraints &
          " | Forbidden: " & getNegativeConstraints(returnType).join(", ")
        inc attemptCount
        continue
      return ok(processLlmResult(cleaned, priorPromotion, cxHistory[^1]))
    ok(buildFallbackArtifact(priorPromotion,
      "LegislatorFeedback: all " & $MaxFeedbackRounds &
      " LLM attempts failed, retaining prior invariant"))
  except CatchableError as e:
    let errCtx = captureErrorContext(
      "feedback", "runFeedbackRetryLoop", e,
      errorClass = classifyError(e),
      recoveryAction = raLocalAbort
    )
    dumpErrorContext(errCtx, feedbackResilienceCfg.dumpDir)
    err(axiomErrInconsistentState)
proc legislateWithFeedback*(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  initialScan: NegativeInvariantScan;
  priorPromotion: tuple[invariant: string; snapshotPath: string];
  sourceCode: string;
  cxHistory: seq[CounterExamplePayload];
  unsatCoreVars: seq[string] = @[];
  goalDelta: seq[string] = @[];
  failingLeanSource: string = ""
): Result[LegislatorArtifact, AxiomError] {.raises: [].} =
  ## Closed-loop variant of legislate.legislate that incorporates
  ## Judge's counterexample history as contextual constraints.
  ##
  ## Enhanced with structured constraint specification (§4 Meta-Verification Layer):
  ##   - unsatCoreVars: Z3 minimal unsatisfiable set for constraint-based prompting
  ##   - goalDelta: Tactic Goal Delta for goal-aware feedback
  ##   - failingLeanSource: Lean source code that failed kernel verification
  ##
  ## This enables the self-evolution loop:
  ##   Judge( rejection ) → Legislator( revision ) → Judge( re-verification )
  ##
  ## Phase B: LLM response guard with retry loop. If the LLM output is empty
  ## or noise-only after stripping, retry with buildRetryPrompt up to MaxFeedbackRounds.
  try:
    # Phase 5: Stagnation guard — stop after MaxFeedbackRounds attempts
    if cxHistory.len >= MaxFeedbackRounds:
      return ok(buildStagnationArtifact(priorPromotion))
    let basePrompt = buildFeedbackPrompt(req, cxHistory[^1], unsatCoreVars, goalDelta, failingLeanSource)
    if basePrompt.len == 0:
      return ok(buildFallbackArtifact(priorPromotion,
        "LegislatorFeedback: empty history, retaining prior invariant"))
    let returnType = extractReturnType(sourceCode, req.functionName)
    runFeedbackRetryLoop(req, translation, sourceCode, priorPromotion, basePrompt, cxHistory, returnType)
  except CatchableError as e:
    let errCtx = captureErrorContext(
      "feedback", "legislateWithFeedback", e,
      errorClass = classifyError(e),
      recoveryAction = raLocalAbort
    )
    dumpErrorContext(errCtx, feedbackResilienceCfg.dumpDir)
    err(axiomErrInconsistentState)

{.pop.}
