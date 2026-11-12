import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import cli/cli_surface_generated
import cli/cli_outcome
import cli/queue_limit
import cli/selection_state
import cli/topology_cli
import cli/wf_render
import cli/wf_runners_common
import cli/wf_state
import core/trusted/axiom_pragmas
import core/trusted/env_access
import core/types/z3_solver_config
import core/utils/decision_algebra
import core/utils/file_utils
import core/utils/constants
import std/json
import std/monotimes
import std/os
import verification/solver/z3_pool
import core/types/asi_types
import infrastructure/logging_facade

proc stateJoin(parts: varargs[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## AXIOM_STATE_DIR 설정 시 <state>/<parts...>, 미설정 시 기존 CWD 상대 경로 그대로(zero-diff).
  let base = block:
    let v = getEnv("AXIOM_STATE_DIR")
    if v.len > 0: v else: getCurrentDir()
  result = base
  for p in parts: result = joinPath(result, p)

var lastZ3ProbeMono: int64 = 0
const z3ProbeCooldownNs: int64 = 60_000_000_000  # 60 seconds in nanoseconds

proc cachedZ3HealthCheck(): Z3HealthStatus {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Re-probe Z3 at most once per 60 seconds. Returns cached result otherwise.
  let now = getMonoTime().ticks
  if now - lastZ3ProbeMono < z3ProbeCooldownNs:
    return zhsHealthy  # assume healthy within cooldown window
  lastZ3ProbeMono = now
  let probe = probeZ3Health()
  probe.status

# @axiom-hint: lean="1 ∧ strict = true ∨ strict = false" smt="(assert (and 1 (or (= strict true) (= strict false))))"
proc axProofShortcutExitCode*(
  reportNode: JsonNode;
  requirePerfectAsi: bool = false;
  continueOnError: bool = false
): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Exit code of one `ax prove` / `ax report` run.
  ## Environment is read by the caller at the I/O boundary and passed in, so
  ## this decision depends on nothing but the report document.
  let failExit = exitCode(CliOutcome.VERIFICATION_FAILURE)
  let summary = reportNode.getOrDefault("summary")
  if summary.isNil or summary.kind != JObject:
    logError("wf_runners", "proof report summary missing/malformed — failing closed")
    return failExit
  if requirePerfectAsi and summary.hasKey("verifiedRatio") and summary["verifiedRatio"].getFloat() < 1.0:
    return failExit
  if requirePerfectAsi and summary.hasKey("lean4Reverified") and not summary["lean4Reverified"].getBool():
    return failExit
  if summary.hasKey("blockingFailure") and summary["blockingFailure"].getBool() and not continueOnError:
    return failExit
  if summary.hasKey("fatalErrors") and summary["fatalErrors"].getInt() > 0:
    return failExit
  # ── v1 exit contract §7: one rule, one projection ─────────────────────────
  # The run-exit rule lives in core/utils/decision_algebra.projectRunOutcome;
  # this function only consumes cli_outcome's single collapse of the decision
  # onto the exit axis. A second local derivation would be a second authority
  # for one fact.
  runExitCode(projectRunOutcome(reportNode))

## Default resolve Source Root From Folder Context.
proc defaultResolveSourceRootFromFolderContext(
  targetDirectory: string;
  cwdOverride: string = ""
): Result[string, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let baseDir = if cwdOverride.len > 0: cwdOverride else: getCurrentDir()
  let candidate = if targetDirectory.len > 0: joinPath(baseDir, targetDirectory) else: baseDir
  if dirExists(candidate):
    return ok(normalizePath(candidate))
  if dirExists(targetDirectory):
    return ok(normalizePath(targetDirectory))
  err("source root does not exist: " & targetDirectory)

## resolve Source Root From Folder Context mutable state.
var resolveSourceRootFromFolderContext*: proc (
  targetDirectory: string;
  cwdOverride: string = ""
): Result[string, string] = defaultResolveSourceRootFromFolderContext

## Resolve Ax State Path.
proc resolveAxStatePath*(override: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if override.len > 0:
    return override
  stateJoin("logs", "ax_proof_state.json")

## run Ax Verify Shortcut Cli variable.
let runAxVerifyShortcutCli* = proc (
  args: seq[string];
  cwdOverride: string = "";
  shortcutStatePathOverride: string = ""
): Result[AxCommandCliResult, string] =
  let flagsRes = parseAxProveFlags(args)
  if flagsRes.isErr():
    return err(flagsRes.error)
  let flags = flagsRes.get()
  let sourceRootRes = resolveSourceRootFromFolderContext("", cwdOverride)
  if sourceRootRes.isErr():
    return err(sourceRootRes.error)
  let sourceRoot = sourceRootRes.get()

  # ── Z3 Health Gate: front-door guard ─────────────────────────────────
  let z3Health = cachedZ3HealthCheck()
  if z3Health == zhsInfraCrash:
    echo "FATAL: Z3 infra crash detected at CLI entry. Pipeline halted."
    echo "  Z3 binary: ", resolveZ3Path()
    echo "  This prevents false positive certificates from entering the proof ledger."
    quit(1)
  elif z3Health == zhsNotFound:
    echo "FATAL: Z3 binary not found. Cannot proceed with verification."
    quit(1)

  let queueLimit = if flags.limit > 0: capped(flags.limit.Positive)
                   else: unlimited()
  let effectiveQueueLimit = queueLimit.resolve()
  let analysisRes = analyzeTopologySourceRoot(
    sourceRoot,
    queueLimit = effectiveQueueLimit,
    queueLimitExplicit = not queueLimit.isUnlimited(),
    diagnosisDepth = 0,
    diagnosisDepthExplicit = false
  )
  if analysisRes.isErr():
    return err(analysisRes.error)
  let bundle = analysisRes.get()
  let reportJson = jsonFromTopologyAnalysis(
    bundle.analysis,
    bundle.diagnoses,
    bundle.effectiveQueueLimit,
    bundle.sourceFileCount,
    bundle.effectiveDiagnosisDepth
  )
  # v1 report document identity (Phase 5 contract) — same schema as prove/
  # report output; consumed by ax report --json consumers.
  reportJson["schemaVersion"] = %axiomReportSchemaVersion

  # ── Selection State: record ASI and detect stall ──────────────────────
  let cacheDir = stateJoin(".axiom", "cache")
  var selectionState = loadSelectionState(cacheDir)
  let asiValue = reportJson{"summary"}{"verifiedRatio"}.getFloat(0.0)
  let asiRatio = initAsiRatio(asiValue).get(defaultAsiRatio())
  recordAsi(selectionState, asiRatio)
  saveSelectionState(selectionState, cacheDir)

  # Stall tracking: stallCount is now managed deterministically in selection_state.
  # No more env var budget — threshold relaxation is computed from stallCount.
  if isStalled(selectionState):
    inc selectionState.stallCount
    saveSelectionState(selectionState, cacheDir)
    logInfo("wf_runners", "stall detected (VKD=" & $asiRatio & " x3), stallCount=" & $selectionState.stallCount &
      ", relaxedThreshold=" & $computeRelaxedThreshold(selectionState.stallCount))
  else:
    discard

  let exitCode = axProofShortcutExitCode(reportJson,
    requirePerfectAsi = getAxiomEnv(evRequirePerfectAsi) == "1",
    continueOnError = getAxiomEnv(evContinueOnError) == "1")
  let statePath = resolveAxStatePath(shortcutStatePathOverride)
  let persisted = persistAxProofState(statePath, reportJson)
  if persisted.isErr():
    return err(persisted.error)
  ok(AxCommandCliResult(
    outputJson: renderJsonMultiline(reportJson),
    logLines: renderVerifyTopologySummaryLines(bundle.analysis, bundle.diagnoses) & @["stateFile=" & statePath],
    exitCode: exitCode
  ))


## run Ax Report Shortcut Cli variable.
let runAxReportShortcutCli* = proc (
  args: seq[string];
  cwdOverride: string = "";
  shortcutStatePathOverride: string = ""
): Result[AxCommandCliResult, string] =
  let flagsRes = parseAxReportFlags(args)
  if flagsRes.isErr():
    return err(flagsRes.error)
  let flags {.used.} = flagsRes.get()
  let statePath = resolveAxStatePath(shortcutStatePathOverride)
  let reportJson = loadAxProofState(statePath)
  if reportJson.isErr():
    return err(reportJson.error)
  let exitCode = axProofShortcutExitCode(reportJson.get(),
    requirePerfectAsi = getAxiomEnv(evRequirePerfectAsi) == "1",
    continueOnError = getAxiomEnv(evContinueOnError) == "1")
  ok(AxCommandCliResult(
    outputJson: renderJsonMultiline(reportJson.get()),
    logLines: renderAxReportLines(reportJson.get()) & @["stateFile=" & statePath],
    exitCode: exitCode
  ))
proc cmdEncodeSemanticPayload*() =
  ## Stub: semantic payload encoding command.
  logWarn("wf_runners", "[WARN] cmdEncodeSemanticPayload is not yet implemented")
  quit(1)
proc cmdVerifySemanticPayload*(args: seq[string]) =
  ## Stub: semantic payload verification command.
  logWarn("wf_runners", "[WARN] cmdVerifySemanticPayload is not yet implemented")
  quit(1)

{.pop.}

