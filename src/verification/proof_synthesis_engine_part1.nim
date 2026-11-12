import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/axiom_pragmas
import core/utils/constants
import core/contracts/universal_pipeline_contract
import core/identity/axiom_prelude as axprelude
import core/json/json_utils
import core/logic/lean_diagnostic as lean_diagnostic
import core/pipeline_core_types
import core/proof/proof_vacuity_gate
import core/translator/universal_assembler as ula
import core/utils/text_utils
import std/json
import std/os
import std/sequtils
import std/strutils
import std/times
import verification/lean_lsp
import verification/leanstral_gateway
import verification/leanstral_prompt
import verification/leanstral_repl
type
  CompileSuccessPredicate* = proc (result: LeanCompilerResult): bool {.noSideEffect, raises: [].}
## SynthesisConfig parameterizes a specific synthesis method's behavior.
type
  SynthesisConfig* = object
    maxRounds*: int
    timeoutMs*: int
    compileSuccess*: CompileSuccessPredicate
## default Synthesis Config variable.

let defaultSynthesisConfig* = SynthesisConfig(
  maxRounds: 3,
  timeoutMs: proofAttemptHardTimeoutMs,
  compileSuccess: proc (r: LeanCompilerResult): bool {.noSideEffect, raises: [].} = r.verified
)

## LeanstralRoundResult is the unified output of a single Leanstral round.
type
  LeanstralRoundResult* = object
    success*: bool
    leanstralSuccess*: bool
    theoremSource*: string
    tacticTrace*: seq[string]
    verified*: bool
    compilerExitCode*: int
    diagnostics*: seq[string]
    leanDiagnostics*: seq[lean_diagnostic.LeanDiagnostic]
    artifactPath*: string
    leanstralDiagnostics*: string
    rawOutput*: string
## SynthesisResult is the unified output of any synthesis strategy.
type
  SynthesisResult* = object
    theoremSource*: string
    tacticTrace*: seq[string]
    minimalProofPath*: seq[string]
    verified*: bool
    rounds*: seq[HealingRound]
    feedbackSummary*: string
    failedAttempts*: int
## SynthesisStrategy is a behavioral abstraction (proc type) that allows
## pluggable proof synthesis methods without modifying the orchestrator.
type
  SynthesisStrategy* = proc (
    payload: SemanticEqualityPayload;
    artifactPath: string;
    leanExe: string;
    vaultDir: string;
    config: SynthesisConfig
  ): SynthesisResult {.gcsafe, raises: [].}
## Try Leanstral Synthesis.
# @axiom-hint: lean="artifactPath.length ≥ 0 ∧ leanExe.length ≥ 0 ∧ vaultDir.length ≥ 0 ∧ config_maxRounds ≥ -9223372036854775808 ∧ config_maxRounds ≤ 9223372036854775807 ∧ config_timeoutMs ≥ -9223372036854775808 ∧ config_timeoutMs ≤ 9223372036854775807" smt="(assert (and (>= (str.len artifactPath) 0) (>= (str.len leanExe) 0) (>= (str.len vaultDir) 0) (and (>= config_maxRounds -9223372036854775808) (<= config_maxRounds 9223372036854775807)) (and (>= config_timeoutMs -9223372036854775808) (<= config_timeoutMs 9223372036854775807))))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
# @axiom-hint: lean="i ≥ source.length ∧ source.length ≥ 0" smt="(assert (and (>= i (str.len source)) (>= (str.len source) 0)))"
func stripLeadingWhitespace(source: string): string {.raises: [].} =
  var i = 0
  while i < source.len and source[i] in {' ', '\t', '\r', '\n'}:
    inc i
  if i >= source.len:
    return ""
  source[i .. ^1]

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
# @axiom-hint: lean="lineEnd < 0 ∧ (body ≥ 0)" smt="(assert (and (< lineEnd 0) (>= body 0)))"
func stripPreludePrefix(source: string): string {.raises: [].} =
  var body = stripLeadingWhitespace(source)
  if body.startsWith("import Std"):
    let lineEnd = body.find('\n')
    if lineEnd < 0:
      body = ""
    else:
      body = stripLeadingWhitespace(body[lineEnd + 1 .. ^1])
  let extendedPrelude = axprelude.getExtendedAxiomPrelude()
  if body.startsWith(extendedPrelude):
    body = stripLeadingWhitespace(body[extendedPrelude.len .. ^1])
  elif body.startsWith(axprelude.axiomPrelude):
    body = stripLeadingWhitespace(body[axprelude.axiomPrelude.len .. ^1])
  body

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
func stripLeanImportLines(source: string): string {.raises: [].} =
  for line in source.splitLines():
    if line.strip().startsWith("import "):
      continue
    result.add(line)
    result.add("\n")

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
func withExtendedAxiomPrelude*(source: string): string {.raises: [].} =
  ## Sanitize prelude before combining with source to prevent colon/Type/=
  ## artifacts from the axiom prelude leaking into Lean compiler input.
  let rawPrelude = axprelude.getExtendedAxiomPrelude()
  let (cleanPrelude, _) = ula.sanitizeLeanSource(rawPrelude)
  "import Std\n" & cleanPrelude & "\n\n" &
    stripLeanImportLines(stripPreludePrefix(source))

## Try Leanstral Synthesis.
# @axiom-hint: lean="artifactPath.length ≥ 0 ∧ leanExe.length ≥ 0 ∧ vaultDir.length ≥ 0 ∧ config_maxRounds ≥ -9223372036854775808 ∧ config_maxRounds ≤ 9223372036854775807 ∧ config_timeoutMs ≥ -9223372036854775808 ∧ config_timeoutMs ≤ 9223372036854775807" smt="(assert (and (>= (str.len artifactPath) 0) (>= (str.len leanExe) 0) (>= (str.len vaultDir) 0) (and (>= config_maxRounds -9223372036854775808) (<= config_maxRounds 9223372036854775807)) (and (>= config_timeoutMs -9223372036854775808) (<= config_timeoutMs 9223372036854775807))))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="source.length ≥ 0" smt="(assert (and (>= (str.len source) 0)))"
# @axiom-hint: lean="i ≥ source.length ∧ source.length ≥ 0" smt="(assert (and (>= i (str.len source)) (>= (str.len source) 0)))"
proc tryLeanstralSynthesis*(
  payload: SemanticEqualityPayload;
  artifactPath: string;
  leanExe: string;
  vaultDir: string;
  config: SynthesisConfig = defaultSynthesisConfig
): tuple[
  success: bool;
  theoremSource: string;
  tacticTrace: seq[string];
  rounds: seq[HealingRound];
  feedbackSummary: string
] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  var kernelFeedback = ""
  for leanstralRound in 1 .. config.maxRounds:
    let sourceContext = extractFunctionSignature(
      semanticModulePathString(payload.modulePath),
      semanticFunctionNameString(payload.functionName)
    )
    let prompt = buildLeanstralPromptFromPayload(
      payload,
      payload.unsatCore,
      sourceContext,
      kernelFeedback,
      vaultDir
    )
    let leanstralRes = callLeanstral(prompt, timeoutMs = config.timeoutMs)
    if leanstralRes.success and leanstralRes.theoremSource.len > 0:
      let sourceToCompile = withExtendedAxiomPrelude(leanstralRes.theoremSource)
      var compileResult: LeanCompilerResult
      try:
        compileResult = verifyGeneratedLeanSourceWithCompiler(sourceToCompile, artifactPath, leanExe)
      except CatchableError as e:
        compileResult = LeanCompilerResult(
          verified: false,
          exitCode: -1,
          diagnostics: @[lean_diagnostic.LeanDiagnostic(
            line: 0,
            character: 0,
            severity: 1,
            message: e.msg
          )],
          output: e.msg,
          artifactPath: artifactPath
        )
      try:
        let evidencePath = joinPath("logs", "evidence", sanitizeToken(semanticFunctionNameString(payload.functionName)) & "_leanstral_round_" & $leanstralRound & ".json")
        discard existsOrCreateDir(parentDir(evidencePath))
        discard writePrettyJsonFile(evidencePath, %*{
          "timestamp": now().utc.format("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"),
          "theoremSource": sourceToCompile,
          "leanCompilerExitCode": compileResult.exitCode,
          "diagnostics": compileResult.diagnostics.mapIt(it.message),
          "tacticTrace": leanstralRes.tacticTrace
        })
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
      let nodeId = semanticModulePathString(payload.modulePath) & "::" &
        semanticFunctionNameString(payload.functionName)
      let vacuityErr =
        if config.compileSuccess(compileResult):
          leanSourceVacuityReason(sourceToCompile, "", nodeId, sourceContext)
        else:
          ""
      if config.compileSuccess(compileResult) and vacuityErr.len == 0:
        result.success = true
        result.theoremSource = sourceToCompile
        result.tacticTrace = leanstralRes.tacticTrace
        result.feedbackSummary = "Leanstral synthesis accepted by kernel."
        result.rounds.add(HealingRound(
          round: leanstralRound,
          phase: "leanstral-synthesis",
          fixedKinds: @["proof_replay"],
          remainingVulnerabilities: 0,
          feedbackSummary: result.feedbackSummary,
          suggestedTactic: leanstralRes.tacticTrace.join("\n"),
          diagnosticCount: 0
        ))
        return
      else:
        if vacuityErr.len > 0:
          kernelFeedback = "Semantic integrity checkpoint rejected Leanstral output: " &
            vacuityErr
        elif compileResult.diagnostics.len > 0:
          kernelFeedback = compileResult.diagnostics[0].message
        result.rounds.add(HealingRound(
          round: leanstralRound,
          phase: "leanstral-synthesis",
          fixedKinds: @[],
          remainingVulnerabilities: 1,
          feedbackSummary: "Leanstral synthesis rejected: " & kernelFeedback,
          suggestedTactic: leanstralRes.tacticTrace.join("\n"),
          diagnosticCount: compileResult.diagnostics.len
        ))
    else:
      if isLeanstralSourcePolicyDiagnostic(leanstralRes.diagnostics):
        kernelFeedback = "Round " & $leanstralRound & " [lean_source_policy]: " &
          leanstralRes.diagnostics & "\n" &
          "Strategic hint for next round: Generate Lean 4 source with exactly `import Std` and no other import lines.\n"
      result.rounds.add(HealingRound(
        round: leanstralRound,
        phase: "leanstral-synthesis",
        fixedKinds: @[],
        remainingVulnerabilities: 1,
        feedbackSummary: "Leanstral invocation failed: " & leanstralRes.diagnostics,
        suggestedTactic: "",
        diagnosticCount: 0
      ))

## Try Leanstral REPL Synthesis — Phase 1: Interactive proof feedback loop
## Replaces one-shot generation with Lean REPL interaction.
## When REPL is available, LLM generates tactics one at a time,
## receiving real-time goal/error feedback from the Lean kernel.
proc tryLeanstralReplSynthesis*(
  payload: SemanticEqualityPayload;
  artifactPath: string;
  leanExe: string;
  vaultDir: string;
  config: SynthesisConfig = defaultSynthesisConfig
): tuple[
  success: bool;
  theoremSource: string;
  tacticTrace: seq[string];
  rounds: seq[HealingRound];
  feedbackSummary: string
] {.raises: [].} =
  let sourceContext = extractFunctionSignature(
    semanticModulePathString(payload.modulePath),
    semanticFunctionNameString(payload.functionName)
  )
  let basePrompt = buildLeanstralPromptFromPayload(
    payload,
    payload.unsatCore,
    sourceContext,
    "",
    vaultDir
  )
  # Build theorem source skeleton for tactic mode entry
  let theoremSource = "theorem " &
    semanticFunctionNameString(payload.functionName) &
    " : " & sourceContext & " := by sorry"

  let replRes = tryLeanstralReplSynthesis(
    basePrompt, theoremSource,
    timeoutMs = config.timeoutMs,
    maxRounds = 10
  )

  result.success = replRes.success
  result.theoremSource = replRes.theoremSource
  result.tacticTrace = replRes.tacticTrace
  result.feedbackSummary = replRes.diagnostics
  result.rounds.add(HealingRound(
    round: replRes.rounds,
    phase: "leanstral-repl",
    fixedKinds: if replRes.success: @["proof_replay"] else: @[],
    remainingVulnerabilities: if replRes.success: 0 else: 1,
    feedbackSummary: replRes.diagnostics,
    suggestedTactic: replRes.tacticTrace.join("\n"),
    diagnosticCount: 0
  ))

{.pop.}
