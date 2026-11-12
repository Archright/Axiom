import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Binary Freshness Gate
##
## Detects stale binaries via SHA-256 source fingerprinting and CAS lookup.
## Does NOT auto-rebuild — the `cli-build` gate handles actual builds.
## Exits with code 1 if the binary is stale, with actionable error message.
## Part of L2 Functional gate layer.
##
## Usage:
##   ./binary_freshness_gate              # check default bin/ax vs CLI sources
##   ./binary_freshness_gate --binary PATH # override binary path
##   ./binary_freshness_gate --binary bin/gate_hook  # check gate_hook freshness

import std/os
import std/times
import std/strformat
import std/strutils
import checksums/sha2
import std/json
import core/axiom_pragmas
import core/utils/repo_root
import core/gate/gate_cas
import core/gate/gate_vfs
import infrastructure/logging_facade


# axiomIoBoundary

const
  FreshnessManifestPath = "logs/binary_freshness_manifest.json"
  AxiomRootMarker = ".axiom_root" ## Canonical root marker — same as orchestrator_hook.
  CliSourcePaths* = [
    "src/cli/action_interpreter_cli.nim",
    "src/cli/action_output_cli.nim",
    "src/cli/action_plan_cli.nim",
    "src/cli/ax_workflow_cli.nim",
    "src/cli/ax_workflow_shortcuts.nim",
    "src/cli/axiom_engine.nim",
    "src/cli/cli_io.nim",
    "src/cli/cli_io_error.nim",
    "src/cli/cli_io_input.nim",
    "src/cli/cli_surface_generated.nim",
    "src/cli/cli_types.nim",
    "src/cli/convergence_sidecar.nim",
    "src/cli/main.nim",
    "src/cli/payload_bridge.nim",
    "src/cli/report_cli.nim",
    "src/cli/report_format.nim",
    "src/cli/report_layout.nim",
    "src/cli/report_render.nim",
    "src/personas/legislator.nim",
    "src/personas/detective.nim",
    "src/personas/scribe.nim",
    "src/personas/judge.nim",
    "src/verification/batch_uap/loop_driver.nim",
    "src/verification/universal_pipeline.nim",
    "src/verification/unified_trajectory.nim",
    "src/verification/cegar_engine.nim",
    "src/verification/certificate_manager.nim",
    "src/verification/layer1_bmc.nim",
    "src/core/proof/proof_budget.nim",
    "src/core/solver/induction.nim",
    "src/core/solver/solver_bridge.nim",
    "src/core/proof/proof_artifact.nim",
    "src/sieve/sieve_engine.nim",
    "src/sieve/sieve_rules.nim"
  ]
  DefaultBinaryPath* = "bin/ax"
  GateHookBinaryPath* = "bin/gate_hook"
  GateHookSourcePaths* = [
    "src/gate/runners/gate_hook.nim",
    "src/gate/orchestrator_hook.nim",
    "src/gate/orchestrator/hook/context.nim",
    "src/gate/orchestrator/hook/executor.nim",
    "src/gate/gate_list.nim",
    "src/gate/gate_utils.nim",
    "src/gate/git.nim",
    "src/gate/types.nim"
  ]

# ── CAS gate parameter resolution ──────────────────────────────────────────────

proc resolveGateParams(binaryPath: string): tuple[gateId, sourcePath, entry: string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Map a stable binary path to CAS string parameters.
  if binaryPath == GateHookBinaryPath or binaryPath.endsWith("/gate_hook"):
    return ("gate-hook", "src/gate/runners/gate_hook.nim", GateHookBinaryPath)
  ("axiom-cli", "src/cli/main.nim", DefaultBinaryPath)

type
  FreshnessResult* = object
    binaryPath*: string
    binaryExists*: bool
    isStale*: bool
    staleSources*: seq[string]

  EnvironmentIntegrity* = object
    rootValid*: bool     ## .axiom_root exists — binary presence proves root identity.

proc stableEntryPointsTo(stablePath, casPath: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if stablePath exists and resolves to casPath.
  ## Handles symlinks (primary), hardlinks (fallback).
  if not fileExists(stablePath):
    return false
  # Symlink check
  try:
    if expandSymlink(stablePath) == casPath:
      return true
  except OSError:
    discard
  # Hardlink check (same inode)
  try:
    if sameFile(stablePath, casPath):
      return true
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  false

proc verifyEnvironmentIntegrity*(repoRoot: string): EnvironmentIntegrity {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check `.axiom_root` marker exists — binary presence proves root identity.
  ## No content parsing. Deterministic: exists = valid, missing = invalid.
  result.rootValid = fileExists(repoRoot / AxiomRootMarker)

proc computeSha256File(path: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 hex digest of a file's contents.
  var hasher = initSha_256()
  let data = readFile(path)
  hasher.update(data)
  let digest = hasher.digest()
  result = $digest

proc computeSha256String(data: string): string {.axiomEffect: IOEffect.} =
  ## Compute SHA-256 hex digest of a string.
  var hasher = initSha_256()
  hasher.update(data)
  let digest = hasher.digest()
  result = $digest

proc computeSourceHashes*(paths: seq[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute a single content fingerprint from SHA-256 hashes of all source files.
  var combined = ""
  for path in paths:
    try:
      combined &= computeSha256File(path)
    except CatchableError:
      combined &= "MISSING:" & path
  result = computeSha256String(combined)

proc loadManifestHash(): string {.axiomEffect: IOEffect.} =
  ## Read the source_fingerprint from the manifest file. Returns "" if missing.
  if not fileExists(FreshnessManifestPath):
    return ""
  try:
    let content = readFile(FreshnessManifestPath)
    let manifest = parseJson(content)
    result = manifest["source_fingerprint"].getStr("")
  except CatchableError:
    result = ""

proc saveManifest*(binaryPath: string, paths: seq[string]) {.axiomEffect: IOEffect.} =
  ## Write a JSON manifest recording the current source fingerprint.
  let fingerprint = computeSourceHashes(@paths)
  var manifest = newJObject()
  manifest["binary"] = newJString(binaryPath)
  manifest["source_fingerprint"] = newJString(fingerprint)
  manifest["built_at"] = newJString(getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"))
  let dir = parentDir(FreshnessManifestPath)
  if not dirExists(dir):
    createDir(dir)
  try:
    writeFile(FreshnessManifestPath, manifest.pretty())
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc checkBinaryFreshness*(
    binaryPath: string;
    sources: openArray[string]
): FreshnessResult =
  ## Check whether `binaryPath` is stale relative to `sources`.
  ## Uses SHA-1 content hashing compared against the stored manifest fingerprint.
  result.binaryPath = binaryPath
  result.binaryExists = fileExists(binaryPath)

  if not result.binaryExists:
    result.isStale = true
    return

  let currentHash = computeSourceHashes(@sources)
  let manifestHash = loadManifestHash()

  if manifestHash.len == 0 or currentHash != manifestHash:
    # Manifest missing or fingerprint differs — binary is stale
    for source in sources:
      if not fileExists(source):
        result.staleSources.add(source & " (missing)")
    if result.staleSources.len == 0:
      # All sources exist but hash mismatch
      result.staleSources.add("(content hash mismatch vs manifest)")
    result.isStale = true
  else:
    result.isStale = false

proc formatFreshnessReport*(fr: FreshnessResult): string =
  ## Format a human-readable freshness report for stderr output.
  if not fr.binaryExists:
    return &"[binary-freshness] FAIL: {fr.binaryPath} does not exist"

  if not fr.isStale:
    return &"[binary-freshness] PASS: {fr.binaryPath} is up to date"

  var lines: seq[string]
  lines.add(&"[binary-freshness] STALE: {fr.binaryPath}")
  lines.add(&"  {fr.staleSources.len} source(s) newer than binary:")
  for src in fr.staleSources:
    lines.add(&"    - {src}")
  lines.add(&"  Recompile with: nimble build")
  return lines.join("\n")

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let args = commandLineParams()
  let repoRoot = if args.len >= 1 and not args[0].startsWith("-"):
                   args[0]
                 else:
                   findRepoRoot()
  setCurrentDir(repoRoot)

  var binaryPath = DefaultBinaryPath

  # Simple flag parsing for --binary override
  var i = if args.len >= 1 and not args[0].startsWith("-"): 1 else: 0
  while i < args.len:
    if args[i] == "--binary" and i + 1 < args.len:
      binaryPath = args[i + 1]
      i += 2
    else:
      i += 1

  # Determine gate parameters and source paths based on binary target
  let (gateId, sourcePath, entry) = resolveGateParams(binaryPath)
  var sourcePaths: seq[string]
  if binaryPath == GateHookBinaryPath or binaryPath.endsWith("/gate_hook"):
    sourcePaths = @GateHookSourcePaths
  else:
    sourcePaths = @CliSourcePaths

  # Phase 0: Environment integrity — warn if .axiom_root is missing.
  let envIntegrity = verifyEnvironmentIntegrity(repoRoot)
  if not envIntegrity.rootValid:
    logWarn("binary_freshness_gate", "[binary-freshness] WARN: .axiom_root missing at " & repoRoot)

  # Phase 1: CAS-aware freshness (primary check).
  # CAS key match IS freshness: if CAS binary exists and stable entry points to it.
  let srcHash = gate_cas.computeSourceHash(sourcePath)
  let casPath = gate_cas.resolveCasPath(gateId, srcHash, repoRoot)
  if not fileExists(casPath) or not stableEntryPointsTo(binaryPath, casPath):
    logError("binary_freshness_gate", "[binary-freshness] FAIL: " & binaryPath & " is stale (CAS miss).")
    logInfo("binary_freshness_gate", "  Run: nim c -o:" & binaryPath & " " & sourcePath)
    quit(1)

  # Phase 2: Secondary defense — source fingerprint check.
  # Catches source changes that CAS key alone may miss.
  let fr = checkBinaryFreshness(binaryPath, sourcePaths)
  if fr.isStale:
    logError("binary_freshness_gate", "[binary-freshness] FAIL: " & binaryPath & " is stale.")
    logInfo("binary_freshness_gate", "  Run: nim c -o:" & binaryPath & " " & sourcePath)
    quit(1)

  # Binary is fresh — ensure manifest is saved.
  let report = formatFreshnessReport(fr)
  logInfo("binary_freshness_gate", report)
  saveManifest(binaryPath, sourcePaths)
  quit(0)

# ---------------------------------------------------------------------------
# VFS-aware entry point (Wave 5D-1)
# ---------------------------------------------------------------------------

proc mainWithVfs(ctx: GateContext) =
  ## VFS-aware entry point for pipeline orchestrator integration.
  setCurrentDir(ctx.repoRoot)

  var binaryPath = DefaultBinaryPath

  let args = commandLineParams()
  var i = if args.len >= 1 and not args[0].startsWith("-"): 1 else: 0
  while i < args.len:
    if args[i] == "--binary" and i + 1 < args.len:
      binaryPath = args[i + 1]
      i += 2
    else:
      i += 1

  let (gateId, sourcePath, entry) = resolveGateParams(binaryPath)
  var sourcePaths: seq[string]
  if binaryPath == GateHookBinaryPath or binaryPath.endsWith("/gate_hook"):
    sourcePaths = @GateHookSourcePaths
  else:
    sourcePaths = @CliSourcePaths

  # Phase 0: Environment integrity — check via VFS
  let envIntegrity = verifyEnvironmentIntegrity(ctx.repoRoot)
  if not envIntegrity.rootValid:
    logWarn("binary_freshness_gate", "[binary-freshness] WARN: .axiom_root missing at " & ctx.repoRoot)

  # Phase 1: CAS-aware freshness
  let srcHash = gate_cas.computeSourceHash(sourcePath)
  let casPath = gate_cas.resolveCasPath(gateId, srcHash, ctx.repoRoot)
  if not fileExists(casPath) or not stableEntryPointsTo(binaryPath, casPath):
    logError("binary_freshness_gate", "[binary-freshness] FAIL: " & binaryPath & " is stale (CAS miss).")
    logInfo("binary_freshness_gate", "  Run: nim c -o:" & binaryPath & " " & sourcePath)
    quit(1)

  # Phase 2: Secondary defense — source fingerprint check
  let fr = checkBinaryFreshness(binaryPath, sourcePaths)
  if fr.isStale:
    logError("binary_freshness_gate", "[binary-freshness] FAIL: " & binaryPath & " is stale.")
    logInfo("binary_freshness_gate", "  Run: nim c -o:" & binaryPath & " " & sourcePath)
    quit(1)

  let report = formatFreshnessReport(fr)
  logInfo("binary_freshness_gate", report)
  saveManifest(binaryPath, sourcePaths)
  quit(0)

when isMainModule:
  main()

{.pop.}

