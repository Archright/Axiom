import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [Exception, IOEffect].}
# axiomIoBoundary

import std/os
import std/algorithm
import std/hashes

import std/sets
import std/strutils
import std/exitprocs

import cli/action_plan_cli
import cli/action_interpreter_cli
import cli/cli_outcome
import cli/ax_workflow_cli
import cli/vkd_sync_cli
import cli/debt_cli
import cli/budget_cli
import cli/lifecycle
import cli/version
import gate/lib/runner_common
import verification/solver/z3_pool
import core/trusted/axiom_pragmas
import core/utils/repo_root
import infrastructure/provenance_probe
import infrastructure/source_identity_cache
import generated/build_env


export action_plan_cli
export action_interpreter_cli
export ax_workflow_cli
export vkd_sync_cli
export debt_cli
export budget_cli

addExitProc(proc() = deinitZ3Pool())

## run Cli variable.
let runCli* = proc (args: seq[string]; executableName: string = "") {.raises: [Exception, IOEffect].} =
  bootstrapAxiomRuntime()
  let (processedArgs, _) = stripGlobalFlags(args)
  putEnv("AXIOM_FREEZE_GRAPH_CACHE", "1")
  let activeExecutable =
    if executableName.len > 0:
      executableName
    else:
      splitFile(paramStr(0)).name
  interpretCliActions(mainLoop(processedArgs, activeExecutable))

proc computeSourceTreeHash*(srcDir: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic hash of .nim source files in srcDir (fail-closed).
  ## Implementation SSOT is infrastructure/provenance_probe (shared with the
  ## other ci-compile binaries' provenance self-checks; pure digest kernel in
  ## core/utils/build_provenance); kept in lock-step with
  ## computeDeterministicSourceHash in tools/hermetic_build.nim. This entry
  ## point is the uncached derivation (probe/tests semantics).
  provenance_probe.computeSourceTreeHash(srcDir)

proc computeSourceTreeHashCached*(srcDir, cachePath: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Incremental derivation for the per-invocation bootstrap check: per-file
  ## digests are reused only under an unchanged kernel stat identity and a
  ## non-racy cache entry; the tree digest itself is always recomposed from the
  ## live walk (core/utils/build_provenance.sourceTreeDigest). The cache is an
  ## acceleration cache, never evidence (docs/spec/artifact_determinism.md).
  source_identity_cache.computeSourceTreeDigestCached(srcDir, cachePath)

proc checkAndSelfBootstrap*(repoRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let projectRoot = findRepoRoot()
  let canonicalLocalBin = (projectRoot / "bin" / "ax").absolutePath
  let currentBin = getAppFilename().absolutePath

  if currentBin != canonicalLocalBin:
    # A separately-invoked canonical binary is governed by the FATAL check below.
    # Do not rebuild or re-exec from a mismatched self-path.
    return

  let srcHash = computeSourceTreeHashCached(projectRoot / "src",
    projectRoot / SourceIdentityCacheRelPath)
  if srcHash == BuildSourceHash: return

  stderr.writeLine("[FATAL] Engine source/source mismatch (SourceCoherence FAIL) tree=" & srcHash & " embedded=" & BuildSourceHash & " — run 'make build' or 'make ci-bootstrap'")
  quit(1)

proc runMain*(args: seq[string]) {.raises: [Exception, IOEffect], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], refines: "src/cli/main_shadow.nim".} =
  ## Exported entry point for unified binary.
  if args.len > 0 and args[0] == ProvenanceSelfCheckFlag:
    # B-layer cache provenance probe contract: a strict self-check verdict
    # (no canonical-path early return — see verifyProvenanceOrFatal) that must
    # never consult the acceleration cache. Reaching the echo is the OK
    # verdict; mismatch FATAL-exits 1 inside.
    verifyProvenanceOrFatal("bin" / "ax")
    echo "AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (" & BuildSourceHash & ")"
    quit(0)
  checkAndSelfBootstrap(getCurrentDir())
  if args.len > 0 and (args[0] == "--version" or args[0] == "-v"):
    echo axiomVersionWithPrefix
  else:
    let (processedArgs, globalFlagsSet) = stripGlobalFlags(args)
    if globalFlagsSet.contains("cached"):
      putEnv("AXIOM_FREEZE_GRAPH_CACHE", "1")
    try:
      interpretCliActions(mainLoop(processedArgs, splitFile(paramStr(0)).name))
    except CatchableError as e:
      # R7 top-level internal-error handler: any exception that escapes the
      # dispatch boundary (not routed as a Result error) becomes INTERNAL_ERROR
      # → exit 2. This replaces the previous out-of-contract crash (SIGSEGV 139).
      stderr.writeLine("[ERROR] internal error: " & e.msg)
      exitWith(CliOutcome.INTERNAL_ERROR)
    except Defect as d:
      stderr.writeLine("[ERROR] internal defect: " & d.msg)
      exitWith(CliOutcome.INTERNAL_ERROR)

when isMainModule:
  runMain(commandLineParams())
{.pop.}

# ── Axiom Lockfile Generation (compile-time) ──
import std/macros
macro generateAxiomLock(): untyped =
  ## Generate axiom.lock from axiomRegistry at compile time.
  ## This ensures lockfile always matches what was actually compiled.
  var names: seq[string]
  for entry in axiomRegistry:
    names.add(entry.funcName)
  names.sort()
  var lockContent = "# Auto-generated from axiomRegistry. Do not edit.\n"
  for n in names:
    lockContent.add(n & "\n")
  # Write lockfile at compile time
  writeFile("axiom.lock", lockContent)
  result = newStmtList()

generateAxiomLock()
