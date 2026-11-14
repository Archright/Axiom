import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import cli/cli_types
import cli/shared/proof_hydration
import cli/upstream_report_cli
import core/axiom_pragmas
import core/json/std_redirect
import core/resilience/resilience_config
import core/results
import core/telemetry/verification_scope
import core/trusted/env_access
import core/types/vkd_types
import core/io/io_utils
import core/utils/io_utils
import core/utils/repo_root
import core/utils/constants
import core/utils/canonical_projection
import std/algorithm
import std/json
import std/os
import std/sequtils
import std/strutils
import std/tables
import std/times
import verification/report_engine
const
  axProofStatePath = "logs/ax_proof_state.json"

# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------

## Render Report Stdout Lines.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func renderReportStdoutLines*(
  output: AxCommandCliResult
): seq[string] {.noSideEffect.} =
  if output.emitJson and output.outputJson.len > 0:
    @[output.outputJson]
  else:
    output.logLines

## Render Report Stderr Lines.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func renderReportStderrLines*(
  output: AxCommandCliResult
): seq[string] {.noSideEffect.} =
  output.logLines

## Render Output Block.
# @axiom-hint: lean="lines.size ≥ 0 ∧ ∀ (i : Fin lines.size), (lines.get i).length ≥ 0" smt="(assert (and (>= (seq.len lines) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len lines))) (>= (str.len (seq.nth lines i)) 0)))))"
# @axiom-hint: lean="lines.length = 0 ∧ (∀ (linesIdx : Fin lines.size), (lines.get linesIdx).length ≥ 0)" smt="(assert (and (= (str.len lines) 0) (forall ((linesIdx Int)) (=> (and (>= linesIdx 0) (< linesIdx (seq.len lines))) (>= (str.len (seq.nth lines linesIdx)) 0)))))"
func renderOutputBlock*(lines: seq[string]): string {.noSideEffect.} =
  if lines.len == 0:
    return ""
  lines.join("\n") & "\n"

# ---------------------------------------------------------------------------
# State path resolution
# ---------------------------------------------------------------------------

## resolve Ax State Path variable.
let resolveAxStatePath* = proc (statePathOverride: string): string =
  if statePathOverride.len > 0:
    return absolutePath(statePathOverride)
  # State identity is the writer's identity: `ax prove` persists through
  # `stateJoin` (src/cli/wf_runners.nim), which roots the state file at
  # AXIOM_STATE_DIR when set. Resolving against CWD instead served a
  # different document than the one that run wrote (productization_contract
  # §10.3 — state relocates with AXIOM_STATE_DIR).
  let stateDir = getEnv("AXIOM_STATE_DIR", "").strip()
  if stateDir.len > 0:
    return absolutePath(joinPath(stateDir, axProofStatePath))
  let envOverride = getAxiomEnv(evStatePath)
  if envOverride.len > 0:
    return absolutePath(envOverride)
  let cwdCandidate = joinPath(getCurrentDir(), axProofStatePath)
  if fileExists(cwdCandidate):
    return absolutePath(cwdCandidate)
  let appCandidate = joinPath(getAppDir(), axProofStatePath)
  if fileExists(appCandidate):
    return absolutePath(appCandidate)
  absolutePath(cwdCandidate)

## resolve Ax Ux Proof State Path variable.
let resolveAxUxProofStatePath* = proc (cwdOverride: string = ""): string =
  let baseDirectory =
    if cwdOverride.len > 0:
      absolutePath(cwdOverride)
    else:
      getCurrentDir()
  joinPath(baseDirectory, "logs", "ux-proof-state.json")

## resolve Ax Workspace Proof State Path variable.
let resolveAxWorkspaceProofStatePath* = proc (cwdOverride: string = ""): string =
  let envOverride = getAxiomEnv(evStatePath)
  if envOverride.len > 0:
    return absolutePath(envOverride)
  let baseDirectory =
    if cwdOverride.len > 0:
      absolutePath(cwdOverride)
    else:
      getCurrentDir()
  let cwdCandidate = joinPath(baseDirectory, axProofStatePath)
  if fileExists(cwdCandidate):
    return absolutePath(cwdCandidate)
  let appCandidate = joinPath(getAppDir(), axProofStatePath)
  if fileExists(appCandidate):
    return absolutePath(appCandidate)
  absolutePath(cwdCandidate)

## resolve Ax State Report Path variable.
let resolveAxStateReportPath* = proc (statePathOverride: string; cwdOverride: string = ""): string =
  if statePathOverride.len > 0:
    return statePathOverride
  let uxStatePath = resolveAxUxProofStatePath(cwdOverride)
  if fileExists(uxStatePath):
    return uxStatePath
  let workspaceProofStatePath = resolveAxWorkspaceProofStatePath(cwdOverride)
  if fileExists(workspaceProofStatePath):
    return workspaceProofStatePath
  resolveAxStatePath("")

## load Ax Proof State variable.
# ---------------------------------------------------------------------------
# Proof state archive
# ---------------------------------------------------------------------------

## Archive Stale Proof State.
# @axiom-hint: lean="repoRoot.length ≥ 0" smt="(assert (and (>= (str.len repoRoot) 0)))"
# @axiom-hint: lean="ageHours > 24" smt="(assert (and (> ageHours 24)))"
proc archiveStaleProofState*(repoRoot: string)  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let proofStatePath = joinPath(repoRoot, axProofStatePath)
  if fileExists(proofStatePath):
    try:
      let info = getFileInfo(proofStatePath)
      let ageHours = (getTime().toUnix - info.lastWriteTime.toUnix) / 3600
      if ageHours > 24:
        let stalePath = proofStatePath & ".stale." & getTime().utc.format("yyyyMMddHHmmss")
        discard moveFileOpt(proofStatePath, stalePath)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# Certificate vault scanner
# ---------------------------------------------------------------------------

# @axiom-hint: lean="status.length ≥ 0" smt="(assert (and (>= (str.len status) 0)))"
# @axiom-hint: lean="verifiedKey" smt="(assert (and verifiedKey))"


# ---------------------------------------------------------------------------
# Ax Shortcut rendering (restored from phantom _part5)
# ---------------------------------------------------------------------------

## uses Ax Shortcut Json Flag.
func usesAxShortcutJsonFlag*(args: seq[string]): bool {.noSideEffect.} =
  for arg in args:
    if arg == "--json":
      return true
  false

## Render Ax Shortcut Stdout Lines.
func renderAxShortcutStdoutLines*(
  output: AxCommandCliResult; emitJson: bool
): seq[string] {.noSideEffect.} =
  if emitJson and output.outputJson.len > 0:
    @[output.outputJson]
  else:
    @[]

## Render Ax Shortcut Stderr Lines.
func renderAxShortcutStderrLines*(
  output: AxCommandCliResult; emitJson: bool
): seq[string] {.noSideEffect.} =
  output.logLines

# ---------------------------------------------------------------------------
# Resilience summary & cleanup
# ---------------------------------------------------------------------------

## Render Resilience Summary.
## Reads all *.jsonl error dump files from dumpDir, parses each line as JSON,
## and counts entries by errorClass and recoveryAction.
proc renderResilienceSummary*(dumpDir: string = "logs/evidence"): seq[string]  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var errorClassCounts = initCountTable[string]()
  var recoveryActionCounts = initCountTable[string]()
  var totalCount = 0
  var lastTimestamp = ""
  var lastErrorClass = ""
  var lastNodeId = ""

  if not dirExists(dumpDir):
    return @["=== Resilience Summary ===", "  No dump directory found: " & dumpDir]

  for kind, path in walkDir(dumpDir):
    if kind != pcFile: continue
    if not path.endsWith(".jsonl"): continue

    try:
      let content = readFile(path)
      for line in content.splitLines():
        let trimmed = line.strip()
        if trimmed.len == 0: continue

        let parsed = safeParseJson(trimmed)
        if parsed.isErr(): continue
        let node = parsed.get()

        # Count by errorClass
        let ecNode = node{"errorClass"}
        let errorClass = if not ecNode.isNil and ecNode.kind == JString: ecNode.getStr() else: "unknown"
        errorClassCounts.inc(errorClass)

        # Count by recoveryAction
        let raNode = node{"recoveryAction"}
        let recoveryAction = if not raNode.isNil and raNode.kind == JString: raNode.getStr() else: "unknown"
        recoveryActionCounts.inc(recoveryAction)

        # Track last error by timestamp
        let tsNode = node{"timestamp"}
        let ts = if not tsNode.isNil and tsNode.kind == JString: tsNode.getStr() else: ""
        if ts > lastTimestamp:
          lastTimestamp = ts
          lastErrorClass = errorClass
          let nidNode = node{"nodeId"}
          lastNodeId = if not nidNode.isNil and nidNode.kind == JString: nidNode.getStr() else: ""

        inc totalCount
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  result = @["=== Resilience Summary ==="]
  result.add("  Total errors: " & $totalCount)

  if errorClassCounts.len > 0:
    result.add("  By class:")
    for ec, count in errorClassCounts.pairs:
      result.add("    " & ec & ":" & align($count, 15 - ec.len))

  if recoveryActionCounts.len > 0:
    result.add("  By action:")
    for ra, count in recoveryActionCounts.pairs:
      result.add("    " & ra & ":" & align($count, 15 - ra.len))

  if lastTimestamp.len > 0:
    result.add("  Last error: " & lastTimestamp & " [" & lastErrorClass & "] " & lastNodeId)

## Clean Resilience Logs.
## Deletes files older than maxAgeHours, then deletes oldest files if
## more than maxCount remain.
proc cleanResilienceLogs*(dumpDir: string  = "logs/evidence";
                          maxAgeHours: int = 72;
                          maxCount: int = 500): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var deletedCount = 0
  var remaining: seq[(string, int64)] = @[]

  if not dirExists(dumpDir):
    return @["=== Resilience Cleanup ===", "  No dump directory found: " & dumpDir]

  let now = getTime().toUnix

  for kind, path in walkDir(dumpDir):
    if kind != pcFile: continue
    if not path.endsWith(".jsonl"): continue

    try:
      let info = getFileInfo(path)
      let ageHours = (now - info.lastWriteTime.toUnix) div 3600

      if ageHours > maxAgeHours:
        try:
          removeFile(path)
          inc deletedCount
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
      else:
        remaining.add((path, info.lastWriteTime.toUnix))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  # If more than maxCount remain, delete oldest first
  if remaining.len > maxCount:
    remaining.sort(proc(a, b: (string, int64)): int = cmp(a[1], b[1]))
    let toDelete = remaining.len - maxCount
    for i in 0 ..< toDelete:
      try:
        removeFile(remaining[i][0])
        inc deletedCount
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

  @["=== Resilience Cleanup ===",
    "  Deleted " & $deletedCount & " file(s)",
    "  Remaining: " & $min(remaining.len, maxCount) & " file(s)"]

# ---------------------------------------------------------------------------
# Certificate vault scanner helper
# ---------------------------------------------------------------------------

proc scanCertLookup*(certDir: string): Table[string, JsonNode] {.raises: [].} =
  ## Scans a certificate directory and builds a canonical-key lookup table.
  ## Canonical key = `<modulePath>::<functionName>` so that `moduleA::foo` and
  ## `moduleB::foo` never collide (Phase 4 — canonical symbol identity).
  result = initTable[string, JsonNode]()
  if not dirExists(certDir):
    return
  for certPath in walkFiles(certDir / "*.json"):
    try:
      let content = readFile(certPath)
      let parsed = safeParseJson(content)
      if parsed.isErr(): continue
      let cert = parsed.get()
      if cert.kind != JObject: continue
      let modulePath = cert.getOrDefault("modulePath").getStr("")
      let funcName = cert.getOrDefault("functionName").getStr("")
      let irHash = cert.getOrDefault("irHash").getStr("")
      if modulePath.len == 0 or funcName.len == 0: continue
      let canonicalKey = modulePath & "::" & funcName
      # Only keep the first cert per canonical symbol (prefer irHash-named over legacy)
      if canonicalKey notin result or irHash.len > 0:
        result[canonicalKey] = cert
    except CatchableError:
      continue

# ---------------------------------------------------------------------------
# runReportCli (restored from phantom _part5)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Canonical digest CLI (--canonical-digest)
# ---------------------------------------------------------------------------
## Thin entry for the canonical semantic result digest. Hashing lives in
## core/utils/canonical_projection.nim (the single implementation).
proc runCanonicalDigestCli*(args: seq[string]): Result[AxCommandCliResult, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var stateFilePath = resolveAxStatePath("")
  for i in 0 ..< args.len:
    if args[i] == "--state-file" and i + 1 < args.len:
      stateFilePath = args[i + 1]
  let stateRes = loadReportProofState(stateFilePath)
  if stateRes.isErr():
    return err(stateRes.error)
  let stateJson = stateRes.get()
  let existingVersion = stateJson{"schemaVersion"}.getStr("")
  if existingVersion.len == 0:
    stateJson["schemaVersion"] = %axiomReportSchemaVersion
  elif existingVersion != axiomReportSchemaVersion:
    return err("report schemaVersion '" & existingVersion & "' != contract '" & axiomReportSchemaVersion & "'")
  ok(AxCommandCliResult(
    outputJson: "",
    logLines: @[canonicalProjectionHash(stateJson)],
    exitCode: 0,
    emitJson: false
  ))

## Resilience subcommand handler (`ax report resilience [--clean]`).
proc runResilienceCli*(args: seq[string]): Result[AxCommandCliResult, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let cleanMode = "--clean" in args
    let dumpDir = loadResilienceConfig().dumpDir
    let lines =
      if cleanMode:
        cleanResilienceLogs(dumpDir)
      else:
        renderResilienceSummary(dumpDir)
    ok(AxCommandCliResult(
      logLines: lines,
      exitCode: 0,
      emitJson: "--json" in args
    ))
  except CatchableError as e:
    err("resilience report failed: " & e.msg)

func renderDashboardLines(stateJson: JsonNode): seq[string] {.raises: [].} =
  ## Binary Dashboard: plain-text rendering for stdout (non-JSON mode).
  ## Values projected from persisted stateJson — no rescanning.
  result = @[]
  result.add("")
  result.add("Axiom Soundness Registry")
  result.add("=================================")
  result.add("")
  let verified = stateJson{"summary"}{"verified"}.getInt(0)
  let totalNodes = stateJson{"summary"}{"totalNodes"}.getInt(0)
  let densityPct = stateJson{"summary"}{"density_pct"}.getFloat(0.0)
  let vkdRatio = stateJson{"metrics"}{"vkd"}{"ratio"}.getFloat(0.0)
  result.add("VKD — Verified Kernel Density (Kernel Only)")
  result.add("   " & formatDensityBar(densityPct) & " " &
    formatFloat(densityPct, ffDecimal, 1) & "% Verified")
  result.add("   - Verified Symbols : " & $verified)
  result.add("   - VKS (Verifiable Kernel Scope)    : " & $totalNodes)
  let unproven = totalNodes - verified
  if unproven > 0:
    result.add("   - Unverified Symbols     : " & $unproven)
  result.add("   - Coverage Ratio  : " & $vkdRatio)
  result.add("")

## Run Report Cli — thin wrapper for `ax report`.
## Business logic lives in verification/report_engine.nim.
proc runReportCli*(args: seq[string]): Result[AxCommandCliResult, string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if args.len > 0 and args[0] == "resilience":
    return runResilienceCli(args)
  if "--canonical-digest" in args:
    return runCanonicalDigestCli(args)

  var stateFilePath = resolveAxStatePath("")
  for i in 0 ..< args.len:
    if args[i] == "--state-file" and i + 1 < args.len:
      stateFilePath = args[i + 1]

  # ── `ax report --upstream` (docs/spec/upstream_reporting_contract.md) ─────
  # Trusted-executor upstream issue reporter: full pipeline including the gh
  # submission unless --dry-run. Dispatched BEFORE the VKD report path — it
  # consumes the display block, not the metrics projection — and AFTER the
  # shared --state-file resolution (single resolution authority).
  if "--upstream" in args:
    return runUpstreamReportCli(args, stateFilePath)

  let stateRes = loadReportProofState(stateFilePath)
  if stateRes.isErr():
    return err(stateRes.error)

  let stateJson = stateRes.get()
  if "--canonical-digest" in args:
    return runCanonicalDigestCli(args)
  # ── v1 report JSON contract (Phase 5): schema identity ───────────────────
  # The report document is a v1 product surface; schemaVersion is a contract
  # field consumers must check before parsing (productization_contract.md §7).
  # It is injected idempotently — an existing identical value is preserved.
  let existingVersion = stateJson{"schemaVersion"}.getStr("")
  if existingVersion.len == 0:
    stateJson["schemaVersion"] = %axiomReportSchemaVersion
  elif existingVersion != axiomReportSchemaVersion:
    return err("report schemaVersion '" & existingVersion & "' != contract '" & axiomReportSchemaVersion & "' — report state was produced by an incompatible Axiom version")

  let repoRoot = findRepoRoot()
  if not fileExists(repoRoot / ".axiom_root"):
    return err("ax report must be executed within an Axiom repository worktree. " &
               "Set AXIOM_ROOT env var or run from project root.")

  # ── Phase 3 single-canonical-wire (docs/spec/verification_density.md) ────
  # metrics.vkd is the ONLY user-facing VKD exposure and must equal the direct
  # getCanonicalVkdMetrics projection: the numerator is admitted v1 full-cert
  # certGreen evidence from the TrustCommit journal (data/trusted/journal)
  # under the current source/toolchain/profile context, and the denominator is
  # |VKS| from verification_scope.lock. The reference vault and the L1 cache
  # are not authority for this metric. Fail-closed: a failed canonical read
  # (missing/corrupt scope lock or journal) is an explicit report error —
  # never a fabricated ratio, and never a metrics-less document that
  # downstream readers dereference into a nil crash (§0.9).
  let canonicalVkd = getCanonicalVkdMetrics(repoRoot)
  if canonicalVkd.failed:
    return err("canonical VKD metrics unavailable (fail-closed): " &
               "verification scope lock missing or corrupt at " & repoRoot)
  # SSOT ratio: division only through the vkd_types.initKernelRatio factory
  # (docs/spec/verification_density.md) — no ad-hoc ratio math in the CLI layer.
  let vkdRatio = initKernelRatio(canonicalVkd.verifiedCount, canonicalVkd.totalCount)
    .getKernelRatioOr(defaultKernelRatio()).toFloat
  stateJson["metrics"] = %*{
    "vkd": {
      "verified": canonicalVkd.verifiedCount,
      "total": canonicalVkd.totalCount,
      "ratio": vkdRatio
    }
  }

  let exitCode = computeReportExitCode(stateJson)

  ok(AxCommandCliResult(
    outputJson: $stateJson,
    logLines: renderDashboardLines(stateJson),
    exitCode: exitCode,
    emitJson: args.anyIt(it == "--json")
  ))
{.pop.}
