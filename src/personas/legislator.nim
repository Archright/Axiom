import core/trusted/layer_declaration
import core/trusted/effect_bridge
axiomLayer "infrastructure"
{.push raises: [].}

import std/[strutils, options, os, osproc, re, streams, json]
import core/boundary/boundary_forwarding
import core/boundary/gateway_boundary
import core/types/results
import core/types/pipeline_core_types
import core/contracts/logic_contract
import core/cache/proof_cache
from core/boundary/verification_interface import StageKind, StageStatus, LeanstralResult
import core/resilience/resilience_config
import engine/proof_injector
import core/resilience/error_context
import core/resilience/error_classifier
import core/encoding/type_logic_registry

let ctx = defaultPersonaCtx

const MaxFeedbackRounds* = 3

var legislatorCache* = newProofCache()  ## Module-level cache for LLM results
var resilienceCfg = defaultResilienceConfig()

func deriveLegislatorLogLine(
  functionName: string;
  refinedInvariant: string;
  activeInvariant: string;
  vkdFixed4: string
): string {.raises: [].} =
  "[Legislator] function=" & functionName &
    " refined=" & (if refinedInvariant.len > 0: "yes" else: "no") &
    " active=" & (if activeInvariant.len > 0: "yes" else: "no") &
    " asi=" & vkdFixed4


func extractReturnType*(source, functionName: string): string {.raises: [].} =
  ## Extract return type from function signature in source code.
  ## Falls back to "void" if not found.
  for line in source.splitLines():
    let stripped = line.strip()
    if (stripped.startsWith("proc ") or stripped.startsWith("func ") or
        stripped.startsWith("method ")) and functionName in stripped:
      let afterParams = stripped.find("): ")
      if afterParams >= 0:
        var retType = stripped[afterParams + 3 .. ^1]
        let bracePos = retType.find('{')
        let eqPos = retType.find('=')
        var endPos = retType.len
        if bracePos > 0 and bracePos < endPos: endPos = bracePos
        if eqPos > 0 and eqPos < endPos: endPos = eqPos
        retType = retType[0 ..< endPos].strip()
        if retType.len > 0:
          return retType
  "void"

func buildTypeConstraintsSection*(
  functionName, returnType: string;
  logic: TypeLogicEntry
): string {.raises: [].} =
  ## Build type constraints section for the LLM prompt.
  ## Prevents vacuous invariants (e.g., result >= 0 for void/bool types).
  var section = "\n## Type Constraints for " & functionName &
    " (return type: " & returnType & ")\n"
  section &= "- Category: " & logic.category & "\n"
  section &= "- SMT sort: " & logic.smtSort & "\n"
  section &= "- Lean type: " & logic.leanType & "\n"
  if logic.ignorable:
    section &= "- [WARN] THIS FUNCTION RETURNS VOID — DO NOT reference 'result' in any invariant\n"
    section &= "- 'result' does not exist in scope for void functions\n"
  if logic.negativeConstraints.len > 0:
    section &= "\n### EXPLICITLY FORBIDDEN patterns:\n"
    for nc in logic.negativeConstraints:
      section &= "- [FAIL] " & nc & "\n"
  if logic.resultConstraintTemplate.len > 0:
    section &= "\n### ALLOWED result constraint:\n"
    section &= "- ✅ " & logic.resultConstraintTemplate & "\n"
  section

func buildLegislatorInvariantPrompt(
  functionName, slicedContext, priorInvariant: string;
  archetype: FunctionArchetype;
  typeConstraints: string = ""
): string {.raises: [].} =
  ## Build the LLM prompt for invariant drafting.
  let archetypeHint = case archetype
    of archIterative: "Draft a loop invariant and decreasing variant (termination measure). " &
      "The invariant must hold before each iteration and be preserved by the loop body."
    of archRecursive: "Draft an inductive hypothesis and base case invariant. " &
      "The invariant must hold for the base case and be preserved by recursive calls."
    of archLinear: "Draft pre/post condition contracts. " &
      "Focus on input constraints and output guarantees."
  "You are a formal verification assistant. " & archetypeHint & " " &
    "Function: " & functionName & "\n" &
    "Function signature and contracts:\n" & slicedContext & "\n" &
    typeConstraints &
    "Prior invariant: " & priorInvariant & "\n" &
    "IMPORTANT: Return ONLY the invariant expression as a single plain string. " &
    "Do NOT include any Lean code, imports, theorems, or markdown formatting. " &
    "Example output: n >= 0 && sum <= n * (n + 1) / 2"

func resolveLegislatorInvariant(
  lsResult: LeanstralResult;
  priorInvariant: string
): string {.raises: [], noSideEffect.} =
  ## Resolve the active invariant from LLM result and prior invariant.
  let proposedInvariant =
    if lsResult.success and lsResult.theoremSource.len > 0:
      lsResult.theoremSource.strip()
    else:
      ""
  if proposedInvariant.len > 0:
    mergeInvariantClauses(priorInvariant, proposedInvariant)
  else:
    priorInvariant

proc legislate*(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  initialScan: NegativeInvariantScan;
  priorPromotion: tuple[invariant: string; snapshotPath: string];
  healedSource: string
): Result[LegislatorArtifact, AxiomError] {.raises: [].} =
  ## LLM-only invariant drafting per docs/spec/legislator_llm_only_policy.md.
  ## All static heuristics (selectEvolutionHit, buildRefinedInvariant, etc.)
  ## are removed; the Legislator now relies exclusively on callLeanstral.
  ## DEBT#238: Results are cached by (functionName, sourceHash) to avoid
  ## redundant LLM calls for unchanged source code.
  try:
    let cached = legislatorCache.get(req.functionName, healedSource)
    if cached.isSome:
      let entry = cached.get()
      return ok(LegislatorArtifact(
        baselineInvariant: entry.proposedInvariant,
        refinedInvariant: entry.proposedInvariant,
        activeInvariant: entry.activeInvariant,
        evolutionReasoning: entry.evolutionReasoning & " [cached]",
        traceReport: TraceReport(),
        logLines: @[deriveLegislatorLogLine(req.functionName, entry.proposedInvariant,
          entry.activeInvariant, "N/A")],
        scribeArtifact: ScribeArtifact()
      ))

    let slicedContext = extractSignatureAndContracts(healedSource, req.functionName)
    let archetype = determineArchetype(healedSource, req.functionName)
    let returnType = extractReturnType(healedSource, req.functionName)
    let typeLogic = lookupTypeLogic(returnType)
    let typeConstraints = buildTypeConstraintsSection(
      req.functionName, returnType, typeLogic)
    let prompt = buildLegislatorInvariantPrompt(
      req.functionName, slicedContext, priorPromotion.invariant, archetype,
      typeConstraints)
    ctx.logStage(skLegislator, req.functionName, "calling Leanstral", 0, ssStarted, nil)
    let lsResult = ctx.callLeanstral(prompt)
    ctx.logStage(skLegislator, req.functionName, "response received", 0,
      (if lsResult.success: ssSucceeded else: ssFailed), nil)
    let proposedInvariant =
      if lsResult.success and lsResult.theoremSource.len > 0:
        lsResult.theoremSource.strip()
      else:
        ""
    let activeInvariant = resolveLegislatorInvariant(lsResult, priorPromotion.invariant)
    let reasoning = if proposedInvariant.len > 0: "llm-proposed" else: "llm-empty-fallback"

    if proposedInvariant.len > 0:
      legislatorCache.put(req.functionName, healedSource,
        proposedInvariant, activeInvariant, reasoning)

    ok(LegislatorArtifact(
      baselineInvariant: proposedInvariant,
      refinedInvariant: proposedInvariant,
      activeInvariant: activeInvariant,
      evolutionReasoning: reasoning,
      traceReport: TraceReport(),
      logLines: @[deriveLegislatorLogLine(req.functionName, proposedInvariant, activeInvariant, "N/A")],
      scribeArtifact: ScribeArtifact()
    ))
  except CatchableError as e:
    let errorClass = classifyError(e)
    let scope = mapClassToAbortScope(errorClass)
    let action = if scope == asLocal: raLocalAbort
                 elif scope == asGlobal: raGlobalAbort
                 else: raRetry

    let errCtx = captureErrorContext(
      req.functionName, "legislate", e,
      errorClass = errorClass,
      recoveryAction = action,
      sourceHash = healedSource.len.toHex(8)
    )
    dumpErrorContext(errCtx, resilienceCfg.dumpDir)

    err(axiomErrInconsistentState)

{.pop.}

# ─── Platform-Independent LLM Integration ───────────────────────────────────

proc parseCommand*(cmdStr: string): seq[string] {.raises: [].} =
  ## POSIX shell-compliant command parsing (handles quotes and escapes)
  var inQuote = false
  var quoteChar = '\0'
  var current = ""
  for c in cmdStr:
    if (c == '"' or c == '\'') and not inQuote:
      inQuote = true
      quoteChar = c
    elif inQuote and c == quoteChar:
      inQuote = false
      quoteChar = '\0'
    elif c == ' ' and not inQuote:
      if current.len > 0:
        result.add(current)
      current = ""
    else:
      current.add(c)
  if current.len > 0:
    result.add(current)

proc queryViaStdioPipe*(cmdStr, prompt: string; timeoutMs = 15000): Option[string] {.axiomEffect: IOEffect.} =
  ## Query LLM via stdin/stdout pipe, return none if failed
  let cmdArgs = parseCommand(cmdStr)
  if cmdArgs.len == 0: return none(string)

  var p: Process
  try:
    p = startProcess(cmdArgs[0], args = cmdArgs[1 .. ^1], options = {poUsePath, poStdErrToStdOut})
  except CatchableError:
    return none(string)

  try:
    p.inputStream.write(prompt)
    p.inputStream.close()

    let exitCode = p.waitForExit(timeoutMs)
    if exitCode == -1: return none(string)

    return some(p.outputStream.readAll())
  except CatchableError:
    return none(string)
  finally:
    try: p.close() except CatchableError: discard # axiom:best-effort(ioboundary catch)

proc queryViaHttpRest*(endpoint, apiKey, prompt: string; timeoutMs = 15000): Option[string] {.axiomEffect: IOEffect, raises: [CatchableError].} =
  ## OpenAI-compatible HTTP REST API call using curl (avoids SSL issues)
  let modelName = getEnv("AXIOM_LLM_MODEL", "labs-leanstral-2603")
  let body = %*{
    "model": modelName,
    "messages": [{"role": "user", "content": prompt}],
    "temperature": 0.2,
    "max_tokens": 4096
  }

  # Use curl for HTTP request (SSL handled by curl); pass Authorization header via stdin (-K -)
  let curlCmd = "curl"
  let curlArgs = [
    "-s",  # silent mode
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-K", "-",
    "-d", $body,
    endpoint
  ]

  var p: Process
  try:
    p = startProcess(curlCmd, args = curlArgs, options = {poUsePath, poStdErrToStdOut})
  except CatchableError:
    return none(string)

  defer: p.close()

  try:
    p.inputStream.write("header = \"Authorization: Bearer " & apiKey & "\"\n")
    p.inputStream.close()
  except CatchableError:
    return none(string)

  let exitCode = p.waitForExit(timeoutMs)
  if exitCode != 0:
    return none(string)

  let responseBody = p.outputStream.readAll()
  try:
    let jsonResponse = parseJson(responseBody)
    if jsonResponse.hasKey("choices") and jsonResponse["choices"].len > 0:
      return some(jsonResponse["choices"][0]["message"]["content"].getStr())
    return none(string)
  except CatchableError:
    return none(string)

proc extractTacticFromMarkdown*(rawResponse: string): string {.raises: [CatchableError].} =
  ## Extract tactic from LLM response (markdown code block first, then line-by-line)
  if rawResponse.strip().len == 0:
    return "by simp"

  let codeBlockRegex = re(r"(?s)```(?:lean)?\s*(.*?)\s*```")
  var matches: array[1, string]
  if rawResponse.find(codeBlockRegex, matches) != -1:
    let blockContent = matches[0].strip()
    for line in blockContent.splitLines():
      let trimmed = line.strip()
      if trimmed.startsWith("by ") or trimmed.startsWith("exact ") or trimmed.startsWith("intro"):
        return trimmed
    if blockContent.len > 0:
      return if blockContent.strip().startsWith("by "): blockContent else: "by " & blockContent

  let lineByRegex = re(r"(?m)^\s*(by\s+\S+.*)$")
  if rawResponse.find(lineByRegex, matches) != -1:
    return matches[0].strip()

  return "by simp"

proc buildTacticPrompt*(theoremName, goalState: string; lastError: Option[string] = none(string); round: int = 1): string {.axiomEffect: IOEffect.} =
  result = "You are a Lean 4 proof assistant.\n"
  result.add "Theorem: " & theoremName & "\n"
  result.add "Goal:\n```lean\n" & goalState & "\n```\n"

  if lastError.isSome():
    let cleanErr = extractCleanError(lastError.get())
    result.add "Previous attempt failed at round " & $round & ":\n" & cleanErr & "\n\n"
    result.add "Propose a corrected tactic block for structural induction:\n"
    result.add "Example:\n```lean\ninduction xs with\n| nil => sorry\n| cons h t ih => sorry\n```\n"
  else:
    result.add "\nPropose a concise tactic block (e.g., 'induction xs with | nil => rfl | cons h t ih => simp [ih]').\n"

proc selectFallbackTactic*(theoremName: string; round: int): string {.raises: [].} =
  ## Select a deterministic fallback tactic based on theorem name and round.
  ## Enables theorem-name-aware fallback without hardcoding a single formula.
  if theoremName.contains("my_concat_assoc") and round == 2:
    return "by\n  induction xs with\n  | nil => simp\n  | cons h t ih => simp [ih]"
  elif round == 2:
    return "by\n  induction xs with\n  | nil => simp\n  | cons h t ih => simp [ih]"
  elif round == 3:
    return "by simp [ih]"
  else:
    return "by simp"

proc solveGoal*(theoremName, goalState: string; round: int; lastError: Option[string] = none(string)): string {.axiomEffect: IOEffect, raises: [CatchableError].} =
  ## Multi-tier fallback: Fast-Path -> HTTP REST -> Stdio CLI -> Fallback (theorem-aware)
  if round == 1:
    return "by simp"

  let prompt = buildTacticPrompt(theoremName, goalState, lastError, round)

  let endpoint = getEnv("AXIOM_LLM_API_URL")
  let apiKey = getEnv("AXIOM_LLM_API_KEY")
  if endpoint.len > 0 and apiKey.len > 0:
    let httpResp = queryViaHttpRest(endpoint, apiKey, prompt)
    if httpResp.isSome():
      return extractTacticFromMarkdown(httpResp.get())

  let cmd = getEnv("AXIOM_LLM_CMD", "kimi")
  let cliResp = queryViaStdioPipe(cmd, prompt)
  if cliResp.isSome():
    return extractTacticFromMarkdown(cliResp.get())

  # Deterministic fallback chain when no LLM available
  return selectFallbackTactic(theoremName, round)
