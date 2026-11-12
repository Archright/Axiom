import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Judge Shadow Mode — Deterministic + LLM parallel execution with comparison.
##
## Phase 4 of the Architecture Evolution Plan:
##   Runs both the deterministic proof path (tryDeterministicProof) and the
##   LLM path in parallel, compares results, and logs agreement/disagreement
##   to JSONL. After requiredMatches consecutive agreements, logs readiness
##   for cut-over to deterministic-only mode.
##
## Shadow mode is a safe rollout mechanism: the deterministic path always
## executes, while the LLM path runs concurrently. Disagreements are logged
## but do not affect the pipeline output — the deterministic result is used.

import std/options
import std/json
import std/os
import std/times

import ../core/trusted/env_access

import core/boundary/axiom_pragmas_boundary
import personas/judge_automation
import personas/llm_response_guard

# ──────────────────────────────────────────────────────────────────────────────
# Types
# ──────────────────────────────────────────────────────────────────────────────

type
  ShadowModeConfig* = object
    ## Configuration for shadow mode comparison.
    enabled*: bool              ## Whether shadow mode is active
    requiredMatches*: int       ## Consecutive matches needed for cut-over (default 100)
    logPath*: string            ## Path for JSONL comparison log

  ShadowModeResult* = object
    ## Result of a single shadow mode comparison.
    deterministicVerified*: bool
    llmVerified*: bool
    agreed*: bool
    deterministicStrategy*: string  ## Strategy that succeeded (deterministic path)
    llmOutput*: string             ## LLM path output summary
    elapsedMs*: int

  ShadowModeState* = object
    ## Mutable state tracking shadow mode progress across invocations.
    config*: ShadowModeConfig
    totalComparisons*: int
    totalMismatches*: int
    consecutiveMatches*: int
    readyForCutOver*: bool

  LlmProofCallback* = proc (theoremSource: string): Option[bool] {.closure, gcsafe, raises: [CatchableError].}
    ## Callback for the LLM proof path.
    ## Returns Some(verified) if the LLM produced a result, None on timeout/failure.
    ## The callback is responsible for implementing its own timeout.

# ──────────────────────────────────────────────────────────────────────────────
# Constructors
# ──────────────────────────────────────────────────────────────────────────────

func initShadowModeConfig*(
  enabled: bool = false;
  requiredMatches: int = 100;
  logPath: string = ""
): ShadowModeConfig {.raises: [].} =
  ## Create a shadow mode configuration.
  ## Default logPath: logs/shadow_mode_comparisons.jsonl
  let actualLogPath = if logPath.len > 0: logPath
                      else:
                        let logDir = getAxiomEnv(evLogDir, "logs")
                        logDir / "shadow_mode_comparisons.jsonl"
  ShadowModeConfig(
    enabled: enabled,
    requiredMatches: requiredMatches,
    logPath: actualLogPath
  )

func initShadowModeState*(config: ShadowModeConfig): ShadowModeState {.raises: [].} =
  ## Create initial shadow mode state from config.
  ShadowModeState(
    config: config,
    totalComparisons: 0,
    totalMismatches: 0,
    consecutiveMatches: 0,
    readyForCutOver: false
  )

# ──────────────────────────────────────────────────────────────────────────────
# Comparison Logic
# ──────────────────────────────────────────────────────────────────────────────

func compareResults*(
  deterministicVerified: bool;
  llmVerified: bool
): bool {.raises: [].} =
  ## Check if both paths agree on the kernel verification verdict.
  ## Returns true when both paths produce the same boolean result.
  deterministicVerified == llmVerified

# ──────────────────────────────────────────────────────────────────────────────
# JSONL Logging
# ──────────────────────────────────────────────────────────────────────────────

proc logShadowComparison*(
  config: ShadowModeConfig;
  nodeId: string;
  result: ShadowModeResult;
  state: ShadowModeState
) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Append a shadow mode comparison entry to the JSONL log.
  ## Creates the log directory if it does not exist.
  if config.logPath.len == 0:
    return

  try:
    let logDir = parentDir(config.logPath)
    if logDir.len > 0:
      discard existsOrCreateDir(logDir)

    var logFile: File
    if not open(logFile, config.logPath, fmAppend):
      return

    let entry = %*{
      "nodeId": nodeId,
      "deterministicVerified": result.deterministicVerified,
      "llmVerified": result.llmVerified,
      "agreed": result.agreed,
      "deterministicStrategy": result.deterministicStrategy,
      "elapsedMs": result.elapsedMs,
      "totalComparisons": state.totalComparisons,
      "totalMismatches": state.totalMismatches,
      "consecutiveMatches": state.consecutiveMatches,
      "readyForCutOver": state.readyForCutOver,
      "timestamp": int(epochTime())
    }
    logFile.write(pretty(entry) & "\n")
    logFile.close()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# ──────────────────────────────────────────────────────────────────────────────
# Cut-over Readiness Check
# ──────────────────────────────────────────────────────────────────────────────

func checkCutoverReadiness*(state: var ShadowModeState) {.raises: [].} =
  ## Update cut-over readiness based on consecutive match count.
  ## When consecutiveMatches reaches requiredMatches, set readyForCutOver = true.
  if state.config.enabled and
     state.consecutiveMatches >= state.config.requiredMatches and
     not state.readyForCutOver:
    state.readyForCutOver = true

# ──────────────────────────────────────────────────────────────────────────────
# Shadow Mode Judge
# ──────────────────────────────────────────────────────────────────────────────

func extractDetResult*(
  detResult: Option[LeanProofResult]
): tuple[verified: bool; strategy: string] {.raises: [].} =
  ## Extract deterministic proof verification status and strategy name.
  if detResult.isSome:
    let r = detResult.get
    (verified: r.verified, strategy: $r.strategy)
  else:
    (verified: false, strategy: "")

proc executeLlmPath*(
  theoremSource: string;
  llmCallback: LlmProofCallback
): tuple[verified: bool; output: string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## [impure: calls llmCallback — I/O side effects via axiomEffect: IOEffect]
  ## Execute the LLM proof callback and return verification status.
  ## Phase B: Strips markdown noise from theoremSource before passing to callback.
  ## On parse failure, returns graceful fallback (verified: false).
  try:
    let cleaned = stripLeadingTrailingNoise(theoremSource)
    if cleaned.len == 0:
      return (verified: false, output: "llm_empty_after_strip")
    let llmResult = llmCallback(cleaned)
    if llmResult.isSome:
      (verified: llmResult.get, output: "llm_completed")
    else:
      (verified: false, output: "llm_timeout_or_failure")
  except CatchableError:
    (verified: false, output: "llm_exception")

proc logCutOverReadiness*(
  config: ShadowModeConfig;
  nodeId: string;
  state: ShadowModeState
) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## [impure: calls open/write/close — file I/O via axiomEffect: IOEffect]
  ## Log a cut-over readiness event to a dedicated JSONL file.
  try:
    let cutOverLogPath = config.logPath.parentDir / "shadow_mode_cutover_ready.jsonl"
    var cutFile: File
    if open(cutFile, cutOverLogPath, fmAppend):
      let mismatchRate = if state.totalComparisons > 0:
                           float(state.totalMismatches) / float(state.totalComparisons)
                         else: 0.0
      let cutEntry = %*{
        "event": "ready_for_cut_over",
        "nodeId": nodeId,
        "totalComparisons": state.totalComparisons,
        "totalMismatches": state.totalMismatches,
        "consecutiveMatches": state.consecutiveMatches,
        "mismatchRate": mismatchRate,
        "timestamp": int(epochTime())
      }
      cutFile.write(pretty(cutEntry) & "\n")
      cutFile.close()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

func updateShadowState*(state: var ShadowModeState; agreed: bool) {.raises: [].} =
  ## Update comparison counters and check cut-over readiness.
  inc state.totalComparisons
  if agreed:
    inc state.consecutiveMatches
  else:
    inc state.totalMismatches
    state.consecutiveMatches = 0
  checkCutoverReadiness(state)

func shadowModeDisabledResult(): ShadowModeResult {.raises: [].} =
  ShadowModeResult(
    deterministicVerified: false,
    llmVerified: false,
    agreed: true,
    deterministicStrategy: "shadow_disabled",
    llmOutput: "",
    elapsedMs: 0
  )

func buildComparisonResult*(
  det: tuple[verified: bool; strategy: string];
  llmVerified: bool; llmOutput: string;
  agreed: bool; elapsedMs: int
): ShadowModeResult {.raises: [].} =
  ShadowModeResult(
    deterministicVerified: det.verified,
    llmVerified: llmVerified,
    agreed: agreed,
    deterministicStrategy: det.strategy,
    llmOutput: llmOutput,
    elapsedMs: elapsedMs
  )

proc shadowModeJudge*(
  state: var ShadowModeState;
  nodeId: string;
  theoremSource: string;
  goalShape: GoalShape;
  llmCallback: LlmProofCallback = nil
): ShadowModeResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Run both deterministic and LLM proof paths, compare, and log.
  ##
  ## The deterministic path (tryDeterministicProof) always executes.
  ## The LLM path runs only when the callback is provided and shadow mode
  ## is enabled. Results are compared and logged to JSONL.
  ##
  ## Returns the comparison result. The caller should use the deterministic
  ## path's result for pipeline decisions — shadow mode is observation-only.

  if not state.config.enabled:
    return shadowModeDisabledResult()
  let startMs = int(getTime().toUnixFloat() * 1000)

  # ── Deterministic path ──────────────────────────────────────────────────────
  let det = extractDetResult(tryDeterministicProof(theoremSource, goalShape))

  # ── LLM path ───────────────────────────────────────────────────────────────
  var llmVerified = false
  var llmOutput = ""
  if llmCallback != nil:
    let llm = executeLlmPath(theoremSource, llmCallback)
    llmVerified = llm.verified
    llmOutput = llm.output
  else:
    llmOutput = "llm_not_provided"

  let elapsedMs = int(getTime().toUnixFloat() * 1000) - startMs

  # ── Compare results ─────────────────────────────────────────────────────────
  let agreed = compareResults(det.verified, llmVerified)

  # ── Update state ────────────────────────────────────────────────────────────
  updateShadowState(state, agreed)

  # ── Build and log comparison result ─────────────────────────────────────────
  let comparison = buildComparisonResult(det, llmVerified, llmOutput, agreed, elapsedMs)
  logShadowComparison(state.config, nodeId, comparison, state)

  # ── Log cut-over readiness ──────────────────────────────────────────────────
  if state.readyForCutOver:
    logCutOverReadiness(state.config, nodeId, state)

  result = comparison

# ──────────────────────────────────────────────────────────────────────────────
# Analysis Helpers
# ──────────────────────────────────────────────────────────────────────────────

func mismatchRate*(state: ShadowModeState): float {.raises: [].} =
  ## Compute the mismatch rate as a ratio [0.0, 1.0].
  if state.totalComparisons == 0:
    return 0.0
  state.totalMismatches.float / state.totalComparisons.float

func isHealthy*(state: ShadowModeState; maxMismatchRate: float = 0.05): bool {.raises: [].} =
  ## Check if shadow mode is healthy (mismatch rate below threshold).
  ## Default threshold: 5% mismatch rate.
  mismatchRate(state) <= maxMismatchRate

func summary*(state: ShadowModeState): string {.raises: [].} =
  ## Human-readable summary of shadow mode state.
  "ShadowMode: comparisons=" & $state.totalComparisons &
  " mismatches=" & $state.totalMismatches &
  " consecutive=" & $state.consecutiveMatches &
  " rate=" & $(int(mismatchRate(state) * 100)) & "%" &
  " cutOver=" & $state.readyForCutOver

{.pop.}
