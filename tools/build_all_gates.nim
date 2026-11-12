import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

## build_all_gates.nim — Standalone Gate Binary Builder
##
## Discovers all gate runners from `src/gate/runners/*.nim` at compile time
## and builds them in parallel using the throttled process pool.
##
## This is a standalone tool — it does NOT modify config.nims (immutable
## per AGENTS.md §-1).  It duplicates only the build invocation that
## config.nims would perform, keeping the two fully decoupled.
##
## Accepted-dead honest skip: a gate runner whose source file carries a
## closed WONT_FIX "Theater/Dead Gate" verdict in `data/debt_registry.json`
## (sha256 contentHash still matching the on-disk file) is *skipped with a
## printed reason* — never reported PASS, never reported FAIL.  The skip is
## content-bound: editing the source voids it and the gate is compiled and
## judged normally again.  A missing or unreadable registry skips nothing
## (fail-closed to normal judgment).
##
## Usage:
##   nim c -o:bin/build_all_gates tools/build_all_gates.nim
##   bin/build_all_gates
##
## Options:
##   --release           Build with -d:release (default: debug)
##   --dry-run           Print the exact command line without executing
##   --verbose           Show per-gate build output
##   --nimcache:DIR      Per-module nimcache root (default: build/nimcache_pool).
##                       Set this to a private directory when other builds share
##                       the checkout.

import std/[os, osproc, strutils, strtabs, tables, json, sets, sequtils,
            parseopt, algorithm, cpuinfo]
import checksums/sha2
import tools/process_pool

# ── axiomEffect pragma stub (standalone tool — cannot import src/) ──
type
  AxiomEffectKind* = enum
    Pure, IoEffect
template axiomEffect*(effectType: AxiomEffectKind) {.pragma.}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  GateRunnersDir = "src/gate/runners"
  BinDir = "bin"
  PoolNimcacheBase = "build/nimcache_pool"

  ## tools/ci gate binaries the Makefile builds explicitly (Makefile
  ## `^bin/<name>: tools/ci/<name>.nim` targets are the SSOT for this list —
  ## a new target must be added here too). The pre-push staleness guard
  ## checks these binaries, so a tool that only discovers src/gate/runners
  ## leaves them stale and blocks pushes (observed 2026-10-22:
  ## epoch_transaction_gate).
  ToolsCiGates = [
    "proof_unit_consistency_gate",
    "proof_reconcile_gate",
    "epoch_transaction_gate",
    "merge_admission_cert_mirror_gate",
    "core_purity_gate",
    "check_nim_theater",
    "check_lean_vacuity",
    "doc_path_validator",
  ]

  ## Registry verdicts are the SSOT for which dead gate sources are
  ## honestly skipped (see `registryBoundDeadSkips`); this tool only reads
  ## it — `data/debt_registry.json` is a CONTROLLED surface.
  DebtRegistryPath = "data/debt_registry.json"

  # Under this variable `config/integrity.nims` executes the shared
  # integrity-hook binaries read-only instead of relinking them, and fails
  # closed when one is missing.  Setting it is only valid *after*
  # `prebuildSharedArtifacts` has materialized them.
  FanoutEnvVar* = "AXIOM_VERIFY_CONTRACT_FANOUT"

  # (output binary, tool source, trailing flag) for the shared artifacts
  # that the integrity hooks relink on every `nim c`.  Keep in sync with the
  # `verify-contract-artifacts` target in the Makefile.
  SharedArtifacts = [
    ("bin/feature_manifest_generator", "tools/feature_manifest_generator.nim", "ensure"),
    ("bin/sync_certs", "tools/sync_certs.nim", "--ensure")
  ]

  # Plain (no AXIOM_GATE_BOND) compile of one small tool.  Its config.nims
  # phase runs hermeticPreBuild exactly once, serially: builds bin/hermetic_build
  # and bin/sync_topology, runs the type-registry / topology / env-hash stamping
  # path, and materializes `.axiom/cache/hermetic_env_hash.txt`.  On a fresh
  # worktree that file is absent, and a parallel fan-out would otherwise run the
  # whole MISS machinery — including builds of the same shared bin/ outputs —
  # concurrently in every worker.  Keep in sync with the tool the hermetic block
  # itself builds (config.nims `dbBin`).
  HermeticSeedTool = "tools/decision_binding_checker.nim"
  HermeticSeedBin = "bin/decision_binding_checker"

  # Set on the fan-out children.  config.nims `hermeticPreBuild` executes
  # unconditionally on every `nim c` and ends by writing a FIXED temp path
  # (`.axiom/cache/.hermetic_env_hash.tmp`) then `mv`-ing it onto
  # `.axiom/cache/hermetic_env_hash.txt` (config.nims ~L577-579, HIT and MISS
  # alike).  With N pool workers mid-`nim c`, one worker's `mv` removes the tmp
  # between another worker's `writeFile` and `mv` — that worker dies with
  # `Error: unhandled exception: FAILED: mv ... [OSError]` and its gate binary
  # is reported FAIL (observed 2026-10-07: failure set differs run to run —
  # run1: anti_theater/debt_integrity/hermetic_test, run2: lean_z3_consensus/
  # nim_check_runner).  Pre-setting this var makes the children skip the block
  # entirely; the serial seed above has just materialized everything it owns.
  # This is the DEBT#457 pattern (build once serially → freeze → fan-out
  # read-only) applied to hermeticPreBuild's maintenance artifacts.
  HermeticBuildingEnvVar = "AXIOM_HERMETIC_BUILDING"

# ---------------------------------------------------------------------------
# Gate Discovery
# ---------------------------------------------------------------------------

proc discoverGates(): seq[string] {.raises: [CatchableError].} =
  ## Return the basenames (without extension) of every gate runner directly
  ## under `src/gate/runners/`.  Sorted for deterministic build order.
  ##
  ## Deliberately not recursive.  `walkDirRec` also yields library modules
  ## under `spec_binding/private/`, and reducing those to a basename
  ## synthesises runner paths that do not exist — `spec_binding/private/
  ## utils.nim` would be requested as `src/gate/runners/utils.nim` and fail
  ## with "cannot open".  Every runner is a direct child of this directory.
  result = @[]
  for entry in walkDir(GateRunnersDir):
    if entry.path.endsWith(".nim"):
      let name = entry.path.extractFilename()
      # Strip the .nim extension
      let gateName = name[0 .. ^5]
      result.add(gateName)
  result.sort()

# ---------------------------------------------------------------------------
# Accepted-Dead Honest Skip (registry-bound)
# ---------------------------------------------------------------------------

type
  AcceptedDeadSkip = object
    ## A non-judgment record: why a gate runner is not built and not judged.
    debtId: string
    title: string

proc fileSha256Hex(path: string): string {.raises: [CatchableError].} =
  ## Lowercase hex SHA-256 of a file — the same rendering the debt registry
  ## stores behind its `sha256:` contentHash prefix.
  toLowerAscii($secureHash(Sha_256, readFile(path)))

proc registryBoundDeadSkips(gates: seq[string]): Table[string, AcceptedDeadSkip] {.
    raises: [CatchableError].} =
  ## Index the discovered gates whose source is registered in
  ## `data/debt_registry.json` as a closed WONT_FIX "Theater/Dead Gate"
  ## verdict, keyed by gate name.
  ##
  ## §0.9 honesty contract of the skip:
  ## - The skip is a *non-judgment*, not a pass — the registry id and title
  ##   (the reason) are printed next to every SKIPPED line.
  ## - The skip is bound to the exact bytes the owner accepted: the file's
  ##   sha256 must equal the verdict's `contentHash`, so any later edit
  ##   (e.g. making the source compile again) or deletion voids the skip
  ##   and the gate is built and judged normally.
  ## - No verdict, no skip: a missing/unreadable registry or an entry that
  ##   no longer matches yields normal compilation and a plain FAIL where
  ##   applicable.  Fail-closed, never fail-silent.
  ##
  ## The set is never hardcoded here: any future accepted-dead verdict in
  ## the same registry category is picked up automatically, and a retired
  ## verdict stops skipping immediately.
  if not fileExists(DebtRegistryPath):
    return
  var node: JsonNode
  try:
    node = parseJson(readFile(DebtRegistryPath))
  except CatchableError:
    return
  if node.kind != JObject:
    return
  let entries = node.getOrDefault("entries")
  if entries.kind != JArray:
    return
  let gateSet = gates.toHashSet()
  for entry in entries.items:
    if entry.kind != JObject:
      continue
    if entry.getOrDefault("status").getStr("") != "closed":
      continue
    if not entry.getOrDefault("resolution").getStr("").startsWith("WONT_FIX"):
      continue
    if entry.getOrDefault("category").getStr("") != "Theater/Dead Gate":
      continue
    let debtId = entry.getOrDefault("id").getStr("")
    let title = entry.getOrDefault("title").getStr("")
    let expected = entry.getOrDefault("contentHash").getStr("")
                     .replace("sha256:", "").toLowerAscii()
    if debtId.len == 0 or expected.len == 0:
      continue
    let files = entry.getOrDefault("files")
    if files.kind != JArray:
      continue
    for f in files.items:
      let rel = f.getStr("")
      if not rel.startsWith(GateRunnersDir & "/") or not rel.endsWith(".nim"):
        continue
      let gateName = rel.extractFilename()[0 .. ^5]
      if gateName notin gateSet or result.hasKey(gateName):
        continue
      let srcPath = GateRunnersDir / gateName & ".nim"
      if not fileExists(srcPath):
        continue
      if fileSha256Hex(srcPath) != expected:
        continue
      result[gateName] = AcceptedDeadSkip(debtId: debtId, title: title)

proc prebuildSharedArtifacts(): int =
  ## Materialize the shared integrity-hook binaries serially, once.
  ##
  ## DEBT#457: `config/integrity.nims` relinks these on EVERY `nim c`, and
  ## Nim has no binary-freshness skip, so a parallel fan-out has all
  ## workers relinking the same output path concurrently — which yields
  ## ETXTBSY ("Text file busy") and half-linked binaries.  This mirrors the
  ## `verify-contract-artifacts` target in the Makefile: build once, then
  ## let the fan-out execute the frozen binaries read-only.
  ##
  ## Returns the exit code of the first failing step; the caller refuses to
  ## fan out on a non-zero result (fail-closed).
  for (binPath, srcPath, flag) in SharedArtifacts:
    let cmd = "nim c -r --hints:off -d:AXIOM_GATE_BOND=1 -d:skipImportLint" &
              " --skipUserCfg --out:" & binPath & " " & srcPath & " " & flag
    echo "[prebuild] ", binPath
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      echo output
      return exitCode
  0

proc prebuildHermeticBootstrap(): int =
  ## Materialize the hermeticPreBuild maintenance artifacts serially, once.
  ##
  ## A plain `nim c` (no AXIOM_GATE_BOND, no AXIOM_HERMETIC_BUILDING) runs
  ## config.nims `hermeticPreBuild` in this single process: it builds
  ## bin/hermetic_build + bin/sync_topology, regenerates the generated
  ## registries on a fresh worktree, and stamps
  ## `.axiom/cache/hermetic_env_hash.txt`.  Doing this before the fan-out
  ## keeps every worker on the cheap HIT path instead of racing the shared
  ## bin/ outputs and the fixed env-hash tmp path concurrently.
  ##
  ## Returns the exit code of the seed compile; the caller refuses to fan out
  ## on a non-zero result (fail-closed).
  let cmd = "nim c --hints:off --out:" & HermeticSeedBin & " " & HermeticSeedTool
  echo "[prebuild] hermetic bootstrap seed: ", HermeticSeedTool
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    echo output
  exitCode

# ---------------------------------------------------------------------------
# Build Logic
# ---------------------------------------------------------------------------

proc gateSourcePath(gateName: string): string =
  ## The gate's source path: ``src/gate/runners/<name>.nim`` for discovered
  ## runners, ``tools/ci/<name>.nim`` for the Makefile-declared tools/ci
  ## gates (ToolsCiGates; the Makefile ``bin/<name>:`` targets are the SSOT
  ## for that list). The pre-push staleness guard checks every built binary,
  ## so a tool that skips either set leaves it stale and blocks pushes.
  if gateName in ToolsCiGates:
    "tools/ci" / gateName & ".nim"
  else:
    GateRunnersDir / gateName & ".nim"

proc buildGateCmd(gateName: string, release: bool): BuildCommand =
  ## Build the structured invocation for a single gate.
  ##
  ## The process pool calls this per-module and injects its own
  ## `--nimcache:` flag into the *option* section, so we must NOT include
  ## one here.  The project file lives in its own field and is rendered
  ## last by `toArgv` — Nim rejects switches that follow it.
  let srcPath = gateSourcePath(gateName)
  let binPath = BinDir / gateName

  result = BuildCommand(program: "nim", command: "c", projectFile: srcPath)
  if release:
    result.options.add("-d:release")
  result.options.add("-o:" & binPath)

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------

type
  BuildOutcome = object
    gate: string
    ok: bool
    output: string

# ---------------------------------------------------------------------------
# CLI Options
# ---------------------------------------------------------------------------

type
  Options = object
    release: bool
    dryRun: bool
    verbose: bool
    nimcacheBase: string

proc parseCliOptions(): Options =
  ## Parse command-line flags.
  result = Options(release: false, dryRun: false, verbose: false,
                   nimcacheBase: PoolNimcacheBase)
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "release", "r":
        result.release = true
      of "dry-run", "n":
        result.dryRun = true
      of "verbose", "v":
        result.verbose = true
      of "nimcache":
        if val.len == 0:
          quit("--nimcache requires a directory, e.g. --nimcache:/tmp/gate_pool")
        result.nimcacheBase = val
      else:
        discard
    of cmdArgument:
      discard
    of cmdEnd:
      discard

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() =
  let opts = parseCliOptions()
  let gates = discoverGates() & ToolsCiGates.toSeq()
  let deadSkips = registryBoundDeadSkips(discoverGates())

  echo "=== Build All Gates ==="
  echo "  Discovered: ", $discoverGates().len, " gate(s) in ", GateRunnersDir,
       " + ", $ToolsCiGates.len, " Makefile-declared tools/ci gate(s)"
  echo "  Mode:       ", (if opts.release: "release" else: "debug")
  echo "  Skips:      ", $deadSkips.len, " accepted-dead (registry-bound)"
  echo ""

  if gates.len == 0:
    echo "No gate runners found in ", GateRunnersDir
    quit(1)

  # Ensure bin/ exists.
  if not dirExists(BinDir):
    createDir(BinDir)

  # ── Dry-run: print the exact argv the pool would execute ──
  if opts.dryRun:
    var commands = 0
    for i, gate in gates:
      if deadSkips.hasKey(gate):
        let s = deadSkips[gate]
        echo "# [SKIPPED] ", gate, " — accepted dead (", s.debtId, "): ", s.title
        continue
      let args = buildGateCmd(gate, opts.release)
                  .withOption("--nimcache:" & nimcacheFor(opts.nimcacheBase, i))
                  .toArgv()
      echo args.join(" ")
      inc commands
    echo ""
    echo "Dry run — ", $commands, " command(s) printed, ",
         $(gates.len - commands), " accepted-dead skip(s) — see [SKIPPED] above."
    quit(0)

  # ── Parallel build via process pool ──
  # Build the shared integrity-hook binaries once, serially, before fanning
  # out — otherwise every worker relinks them concurrently (DEBT#457).
  if prebuildSharedArtifacts() != 0:
    quit("Shared artifact prebuild failed — refusing to fan out.", 1)

  # Run hermeticPreBuild's maintenance once, serially, before fanning out —
  # a fresh worktree has no hermetic env-hash stamp, and N workers racing the
  # MISS machinery (and the fixed tmp path) fail nondeterministically.
  if prebuildHermeticBootstrap() != 0:
    quit("Hermetic bootstrap seed failed — refusing to fan out.", 1)

  # `startProcess` replaces the child environment wholesale (osproc.nim:
  # `envToCStringArray(env)`), so seed it from the parent before adding the
  # fan-out marker — otherwise the child nim loses PATH/HOME.
  var fanoutEnv = newStringTable()
  for key, val in envPairs():
    fanoutEnv[key] = val
  fanoutEnv[FanoutEnvVar] = "1"
  # Children skip hermeticPreBuild entirely (the serial seed just ran it);
  # without this, every child re-executes the block and races the shared
  # `.hermetic_env_hash.tmp` path (see HermeticBuildingEnvVar comment).
  fanoutEnv[HermeticBuildingEnvVar] = "1"

  let cmdTemplate = proc(gate: string): BuildCommand =
    buildGateCmd(gate, opts.release)

  # Only non-skipped gates are built; skipped gates produce no judgment.
  let buildable = gates.filterIt(not deadSkips.hasKey(it))
  let results = runPool(buildable, cmdTemplate, env = fanoutEnv,
                        nimcacheBase = opts.nimcacheBase)

  # ── Report results ──
  var
    succeeded = 0
    failed = 0
    failedGates: seq[string]

  for r in results:
    let ok = r.exitCode == 0
    if ok:
      inc succeeded
    else:
      inc failed
      failedGates.add(r.module)

    if not ok or opts.verbose:
      let status = if ok: "OK" else: "FAIL"
      echo "[", status, "] ", r.module, " (exit=", $r.exitCode, ")"
      if not ok and r.output.len > 0:
        # Indent build output for readability.
        for line in r.output.splitLines():
          if line.len > 0:
            echo "  ", line

  # ── Honest skips: reasons printed, never silently swallowed ──
  for gate in gates:
    if deadSkips.hasKey(gate):
      let s = deadSkips[gate]
      echo "[SKIPPED] ", gate, " — accepted dead (", s.debtId, "): ", s.title
      echo "  verdict:  ", DebtRegistryPath, " — closed, WONT_FIX, Theater/Dead Gate"
      echo "  binding:  source sha256 matches the accepted contentHash — ",
           "editing or deleting the file voids this skip and restores normal judgment"

  # ── Summary ──
  echo ""
  echo "---"
  echo "Total:   ", $gates.len
  echo "Passed:  ", $succeeded
  echo "Skipped: ", $deadSkips.len, "  (accepted dead — see [SKIPPED] above; not judged)"
  echo "Failed:  ", $failed

  if failed > 0:
    echo ""
    echo "Failed gates:"
    for g in failedGates:
      echo "  - ", g
    quit(1)
  elif deadSkips.len > 0:
    echo ""
    echo "All ", $succeeded, " buildable gates built; ", $deadSkips.len,
         " accepted-dead skip(s) reported with reasons above."
  else:
    echo ""
    echo "All gates built successfully."

main()
