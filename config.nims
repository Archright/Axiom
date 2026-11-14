# Axiom project config.nims — Declarative Build Orchestrator
# Decomposed into config/ includes for maintainability.
# See: docs/spec/config_nims_decomposition.md
import std/[os, strutils, json, algorithm, hashes]

# ── Import Path (must be early for all includes) ───────────────────────────
switch("path", "src")
switch("path", "tools")

# ── Idempotent Nimcache Guard ────────────────────────────────────
# axiom:idempotent-guard — prevents duplicate switch() application on rebuilds.
# Each build mode gets its own isolated nimcache under build/nimcache/<mode>.
when not defined(axiomNimcacheConfigured):
  switch("define", "axiomNimcacheConfigured")
  when defined(release) or defined(danger):
    switch("nimcache", "build/nimcache/release")
  elif defined(test):
    switch("nimcache", "build/nimcache/test")
  else:
    switch("nimcache", "build/nimcache/debug")

# ── Build Optimizations ──────────────────────────────────────────
# Deterministic memory-aware parallelism: compute safe parallel C-backend job
# count from host RAM (/proc/meminfo) and CPU count (nproc) at compile time.
# VM-safe: std/strutils only (std/os triggers fopen importc error in NimScript VM).
# memPerJobGiB=6.0 → ~5 jobs on 30 GiB host (17.5 GiB peak, ~13 GiB safety margin).
proc getDeterministicParallelJobs*(memPerJobGiB: float = 6.0): int =
  let memKbStr = staticExec("awk '/MemTotal/ {print $2}' /proc/meminfo").strip()
  let cpuStr   = staticExec("nproc").strip()
  var totalMemGiB = 16.0
  var cpuCores = 4
  try:
    if memKbStr.len > 0: totalMemGiB = parseFloat(memKbStr) / (1024.0 * 1024.0)
  except ValueError: discard
  try:
    if cpuStr.len > 0: cpuCores = parseInt(cpuStr)
  except ValueError: discard
  let safeJobsByMem = max(1, int(totalMemGiB / memPerJobGiB))
  min(cpuCores, safeJobsByMem)

switch("parallelBuild", $getDeterministicParallelJobs(6.0))

# ── Gate Scanner Enforcement ──────────────────────────────────────
# Enable strict pragma checking by default (atomic switch)
switch("define", "AXIOM_ENFORCE_GATE_PRAGMAS=1")

when (defined(release) or defined(danger)) and defined(gcc):
  switch("opt", "speed")
  switch("panics", "on")
  # VS-R3 (2026-11-13): LTO is opt-in (-d:axiomLto); default release/danger
  # builds link WITHOUT LTO. U1 cross-measurement: runtime gain 0%, link cost
  # +98.60s (docs/evidence/vs_r2_authority_followups_acceptance_2026-11-13.md
  # §4). Precedence: -d:axiomNoLto wins when both defines are present.
  # GCC-only contract (docs/spec/lto_link_parallelism.md §1): `defined(gcc)`
  # cannot block a later --cc:clang selection (Nim 2-pass config processing),
  # so -d:axiomLto combined with --cc:clang would pass GCC-only flags.
  when defined(axiomLto) and not defined(axiomNoLto):
    switch("passC", "-flto")
    switch("passC", "-Wno-stringop-overflow")
    # L1-a (CI): parallel-balance LTO (was serial one/1). Actual CX23 observation:
    # candidate completed successfully with peak RSS ≈1.9GB and no OOM (4GB runner),
    # while enabling parallel link (~32% link wall-clock ↓ vs serial).
    switch("passL", "-flto -flto-partition=balanced -flto=2")
else:
  # Dev/Debug: LTO disabled — Nim debug default (-g, -O0) applies, link memory minimal.
  discard

# ── Bootstrap: Generate import_rules_static.nim from JSON SSOT ────────────────
block bootstrapImportRules:
  let staticRulesPath = "src/generated/import_rules_static.nim"
  if not fileExists(staticRulesPath):
    let jsonPath = "data/import_rules.json"
    if fileExists(jsonPath):
      let rules = parseJson(readFile(jsonPath))
      var code = "# Auto-generated from data/import_rules.json — DO NOT EDIT\n"
      code &= "const forbiddenCoreImports* = ["
      if rules.hasKey("rules") and rules["rules"].hasKey("src/core/"):
        for rule in rules["rules"]["src/core/"]["forbidden"]:
          code &= "\"" & rule.getStr() & "\", "
      code &= "]\n"
      writeFile(staticRulesPath, code)
      echo "[bootstrap] Generated " & staticRulesPath
when (NimMajor, NimMinor) >= (2, 0):
  import std/staticos
else:
  # Nim 1.6 fallback: provide thisDir() that staticos offers in Nim 2.x
  proc thisDir(): string {.compileTime.} = parentDir(currentSourcePath())

# ── Project Root for Layer Enforcement ──────────────────────────────────────
# Provides -d:axiomProjectPath for compile-time layer enforcement macro.
# The macro uses currentSourcePath() normalized relative to this path.
# CI environments must ensure this define is set for deterministic resolution.
switch("define", "axiomProjectPath=" & thisDir())

# ── Import Path (required for direct nim c without nimbledeps) ───────────────
switch("path", "src")
switch("path", "tools")

include "config/paths.nims"      # Build metadata, dependency injection, path switches
include "config/lint.nims"       # Import boundary lint
include "config/effects.nims"    # Compilation flags, warnings, effects
switch("maxLoopIterationsVM", "100000000")  # architecture_invariants compile-time evaluation
include "config/strict.nims"     # Strict mode, architecture invariants
include "config/integrity.nims"  # Immutable verification, merkle root, constraints
include "config/vendors.nims"    # Hermetic build, Z3 FFI, source scanner

# ── Manifest Index Ownership ─────────────────────────────────────────
# _index.json은 tools/sync_topology.nim가 단독 생성 (gate-ID 포맷).
# 과거 manifestIndexAutoSync 블록이 파일명 포맷으로 재작성해 두 writer가
# flip-flop을 일으켜 hermetic env-hash 캐시 게이트가 안정화되지 못했음.
# Removed 2026-08-07 (sync_topology 단일 writer 유지).

# ── Gate Runner Freshness Guard (sha256sum via gorge) ──────────────────────────
# Freshness check shells out to external `sha256sum` through one gorge() call —
# no std/hashes / FarmHash involvement. NimScript cannot use std/sha1 or
# std/sha256 (both depend on copyMem via std/endians, rejected by the VM), so
# the external sha256sum primitive stays (docs/spec/gorge_inventory.md G1 lineage).
proc computeSourceHash(path: string): string =
  ## SHA-256 digests of the target file's content PLUS the shared gate-infrastructure
  ## set, flat-concatenated per slot in fixed order — NOT a merkle root and NOT the
  ## config/integrity.nims chain (that hashes a disjoint src/core/trusted set).
  ## 단일 sha256sum 호출로 전체 파일 목록을 한 번에 계산 (fork 절감).
  ## Missing files occupy their slot as the literal `MISSING:<path>` sentinel, so
  ## a missing input is visible in (and changes) the returned value.
  let infraPaths = @[
    "src/gate/runners/gate_hook.nim",
    "src/gate/orchestrator_hook.nim",
    "src/gate/gate_utils.nim",
    "src/gate/git.nim",
    "src/gate/types.nim"
  ]
  # De-duplicated, deterministic order: target first, then infra files that differ
  # from it (the gate_hook target IS infraPaths[0] — dedups to 5 slots).
  var paths: seq[string] = @[path]
  for p in infraPaths:
    if p != path:
      paths.add(p)
  var slots: seq[string] = @[]       # per-path digest or MISSING:<path> sentinel
  var hashedSlotIdx: seq[int] = @[]  # slot index -> hashed-file ordinal
  var cmdPaths: seq[string] = @[]
  for p in paths:
    if fileExists(p):
      hashedSlotIdx.add(slots.len)
      slots.add("")
      cmdPaths.add(p)
    else:
      slots.add("MISSING:" & p)
  if cmdPaths.len == 0:
    return slots.join("")
  # 존재하는 파일 전체를 하나의 sha256sum 호출로 처리.
  let cmd = "sha256sum " & cmdPaths.join(" ")
  let raw = gorge(cmd)
  # sha256sum은 operand 순서대로 `<digest>  <file>` 줄을 출력 — 첫 필드만 추출.
  var digests: seq[string] = @[]
  for line in raw.splitLines():
    let h = line.split(" ")[0]
    if h.len > 0:
      digests.add(h)
  if digests.len != cmdPaths.len:
    echo "[config.nims] ERROR: computeSourceHash: sha256sum returned " &
      $digests.len & " digests for " & $cmdPaths.len & " files: " & cmd
    quit(1)
  for i, slotIdx in hashedSlotIdx:
    slots[slotIdx] = digests[i]
  return slots.join("")

proc storedHashFor(prevHashes: seq[(string, string)]; bin: string): string =
  ## Pure lookup over the persisted (binary, source-hash) pairs. Kept a
  ## module-level proc with an explicit parameter rather than a task-local
  ## closure: under `--mm:orc` (config/vendors.nims) the NimScript VM cannot
  ## destroy a closure environment that captures a seq
  ## ("system module needs: nimDestroyAndDispose").
  for (b, h) in prevHashes:
    if b == bin: return h
  return ""

task buildGateRunners, "Gate runner freshness check & build (sha256sum via gorge)":
  # Exactly the runner sources that exist. Two historical entries were removed
  # here after the fail-loud guard below exposed them as phantom: 
  # ("bin/structural_safety_gate", "src/gate/runners/structural_safety_gate.nim")
  # and ("bin/drnim", "src/gate/runners/drnim_gate.nim") — neither source has
  # ever existed at this commit and no Makefile/ci/gates.json consumer references
  # either binary (DEBT#517 follow-through: unbuildable entries are not runners).
  let runners = @[
    ("bin/gate_hook", "src/gate/runners/gate_hook.nim"),
    ("bin/conflict_marker_gate", "src/gate/runners/conflict_marker_gate.nim"),
    ("bin/hotspot_coverage_gate", "src/gate/runners/hotspot_coverage_gate.nim"),
    ("bin/hermetic_test_gate", "src/gate/runners/hermetic_test_gate.nim"),
  ]
  let hashStore = ".axiom/cache/gate_hashes.json"

  # Ensure cache directory exists
  if not dirExists(".axiom/cache"):
    mkDir(".axiom/cache")

  # Load previous hashes
  var prevHashes: seq[(string, string)] = @[]
  if fileExists(hashStore):
    for line in readFile(hashStore).split("\n"):
      if "\t" in line:
        let parts = line.split("\t", 1)
        prevHashes.add((parts[0], parts[1]))

  var newHashes: seq[(string, string)] = @[]
  for (bin, src) in runners:
    # Fail-loud: a missing runner source or freshness input must never yield a
    # silent "✓ Up-to-date" verdict (DEBT#517 fail-open closure).
    if not fileExists(src):
      echo "[config.nims] ERROR: buildGateRunners: source not found: " & src
      quit(1)
    let srcHash = computeSourceHash(src)
    if "MISSING:" in srcHash:
      echo "[config.nims] ERROR: buildGateRunners: freshness input missing for " &
        bin & ": " & srcHash
      quit(1)
    let storedHash = storedHashFor(prevHashes, bin)
    if not fileExists(bin) or srcHash != storedHash:
      echo "Rebuilding: " & bin & " (hash mismatch or missing)"
      if bin == "bin/gate_hook":
        # gate_hook needs release mode, useMalloc, and isolated nimcache
        exec "nim c --hints:off -d:release -d:useMalloc" &
             " --nimcache:build/nimcache/gate_hook" &
             " -o:" & bin & " " & src
      else:
        exec "nim c --hints:off -d:release -o:" & bin & " " & src
    else:
      echo "✓ Up-to-date: " & bin
    newHashes.add((bin, srcHash))

  # Persist hashes
  var hashContent = ""
  for (b, h) in newHashes:
    if hashContent.len > 0: hashContent.add("\n")
    hashContent.add(b & "\t" & h)
  writeFile(hashStore, hashContent)
  echo "Gate runner hashes saved: " & hashStore

  # Atomic checksum storage: temp + mv (POSIX rename is atomic).
  # Each line stores the SHA-256 of the compiled BINARY itself (sha256sum <bin>)
  # keyed by binary name — the docs/spec/gorge_inventory.md G1 intent.
  # 모든 바이너리를 하나의 sha256sum 호출로 처리 (fork 절감); 출력 줄은
  # operand 순서와 1:1로 대응.
  var bins: seq[string] = @[]
  for (bin, _) in runners:
    if fileExists(bin):
      bins.add(bin)
  if bins.len > 0:
    let raw = gorge("sha256sum " & bins.join(" "))
    var binDigests: seq[string] = @[]
    for line in raw.splitLines():
      let h = line.split(" ")[0]
      if h.len > 0:
        binDigests.add(h)
    if binDigests.len != bins.len:
      echo "[config.nims] ERROR: buildGateRunners: sha256sum returned " &
        $binDigests.len & " digests for " & $bins.len & " binaries"
      quit(1)
    var checksumContent =
      "# format: one line per runner — <binaryName> TAB <sha256-hex of the compiled binary>"
    for i, bin in bins:
      checksumContent.add("\n" & bin.split("/")[^1] & "\t" & binDigests[i])
    let tmpPath = ".axiom/cache/.checksums.tmp"
    writeFile(tmpPath, checksumContent)
    exec "mv " & tmpPath & " .axiom/cache/binary_checksums.json"
    echo "Binary checksums saved (atomic): .axiom/cache/binary_checksums.json"

# ─── Phase 3A: Manifest-driven gate binary builder ──────────────────────

proc buildGatesFromManifest*() =
  ## Build all gate runner binaries referenced by src/gate/manifest.d/_index.json.
  ## Each manifest JSON in manifest.d/ defines gate metadata including the entry point.
  ## Skips binaries that are already up-to-date (source unchanged).
  let indexPath = "src/gate/manifest.d/_index.json"
  if not fileExists(indexPath):
    echo "[buildGates] index not found: ", indexPath
    return
  let indexContent = readFile(indexPath)
  var built = 0
  var skipped = 0
  var failed = 0
  for line in indexContent.split("\n"):
    let manifestFile = line.strip()
    if manifestFile.len == 0:
      continue
    let manifestPath = "src/gate/manifest.d/" & manifestFile
    if not fileExists(manifestPath):
      echo "[buildGates] SKIP (manifest missing): ", manifestFile
      inc skipped
      continue
    var manifest: JsonNode
    try:
      manifest = parseJson(readFile(manifestPath))
    except CatchableError:
      echo "[buildGates] SKIP (invalid JSON): ", manifestFile
      inc skipped
      continue
    let gateId = manifest{"id"}.getStr("")
    let entryPath = manifest{"entry"}.getStr("")
    if gateId.len == 0 or entryPath.len == 0:
      continue
    let srcPath = entryPath & ".nim"
    if not fileExists(srcPath):
      # Try src/cli/ path
      let cliSrc = entryPath.replace("src/gate/runners/", "src/cli/") & ".nim"
      if fileExists(cliSrc):
        let binPath = "bin/" & gateId.replace("-", "_")
        echo "[buildGates] building ", gateId, " from ", cliSrc
        try:
          exec "nim c --hints:off -d:AXIOM_GATE_BOND=1 -d:skipImportLint --skipUserCfg -o:" & binPath & " " & cliSrc
          inc built
        except CatchableError:
          echo "[buildGates] FAILED: ", gateId
          inc failed
      else:
        echo "[buildGates] SKIP (no source): ", gateId, " → ", srcPath
        inc skipped
      continue
    let binPath = "bin/" & gateId.replace("-", "_")
    echo "[buildGates] building ", gateId, " from ", srcPath
    try:
      exec "nim c --hints:off -d:AXIOM_GATE_BOND=1 -d:skipImportLint --skipUserCfg -o:" & binPath & " " & srcPath
      inc built
    except CatchableError:
      echo "[buildGates] FAILED: ", gateId
      inc failed
  echo "[buildGates] done: built=", built, " skipped=", skipped, " failed=", failed

task test, "Run all tests with Makefile":
  exec "make test"

task buildGates, "Build all gate runner binaries from manifest":
  buildGatesFromManifest()

# ── Feature Manifest Task ──────────────────────────────────────────────────────
# Run before builds if .feature files changed: nim genmanifest
task genmanifest, "Generate feature manifest (run before nim c if .feature files changed)":
  exec "nim c -r --hints:off tools/feature_manifest_generator.nim"

# ── PBT & Forwarding Stub Tools (Pure Nim, zero Python dependency) ─────────────
# Replaces: bin/generate-pbt-tests (Python), tools/ci/pbt_seed_parser.py (Python)
# Usage: nim buildPbtTools
task buildPbtTools, "Build PBT generator, seed parser, and forwarding stubs tool":
  exec "nim c --hints:off -o:bin/pbt_generator tools/pbt_generator.nim"
  exec "nim c --hints:off -o:bin/pbt_seed_parser tools/pbt_seed_parser.nim"
  exec "nim c --hints:off -o:bin/generate_forwarding_stubs tools/generate_forwarding_stubs.nim"
  echo "Built: bin/pbt_generator, bin/pbt_seed_parser, bin/generate_forwarding_stubs"

# ── AST Invariant Checker (Native Binary) ────────────────────────────────
# Scans source files using parseStmt + AST traversal to detect forbidden patterns.
# Called from strict.nims via gorgeEx() to avoid NimScript VM iteration limits.
# Usage: nim buildAstInvariantChecker
task buildAstInvariantChecker, "Build native AST invariant checker binary":
  exec "nim c --hints:off -d:release -o:bin/ast_invariant_checker tools/ast_invariant_checker.nim"
  echo "Built: bin/ast_invariant_checker"

# ── Lean REPL Contract Tests (Phase E CI Integration) ──────────────────────
# Build mock server, compile and run contract tests.
# Usage: nim contractTest
task contractTest, "Build and run Lean REPL contract tests":
  exec "nim c --hints:off -o:tests/solver/mock_lean_repl tests/solver/mock_lean_repl.nim"
  exec "nim c --hints:off -r tests/solver/test_lean_contract.nim"

# M7: switch("path", "src/core/gateway") REMOVED — forwarding stubs make this unnecessary

# ── Structural Safety Gate (CI-only) ──────────────────────────────────
# When -d:axiomStrict is active (CI builds via -d:axiom_gateway_build),
# inject the structural safety macro globally. Checks 1 (ref object proc fields)
# and 7 (cast ban) are enforced at compile time.
when defined(axiomStrict):
  switch("import", "src/core/trusted/enforce_structural_safety")

# ── Topology Integrity Checker (always active) ────────────────────────────
# Validates topology SSOT at compile time via static: assert.
# Injected unconditionally — no manual import needed.
# switch("import", "gate/framework/topology_checker")  # DISABLED - causes issues with sync_topology

# Z3 FFI removed (v30 rationale: z3_ffi_architecture.md §10).
# All Z3 solver interactions now use CLI subprocess path via z3_pool.nim.
when defined(z3FFIAvailable) or defined(z3FFIDisabled):
  {.error: "Z3 FFI removed. Use CLI subprocess path via z3_pool.nim.".}

# Nim compiler internals path (for nimtry's AST manipulation)
# Allows importing compiler/ast, compiler/idents, etc.
let nimRoot = getEnv("HOME") / ".choosenim" / "toolchains" / ("nim-" & NimVersion)
if dirExists(nimRoot / "compiler"):
  switch("path", nimRoot)
# signIntegrityResidueGuard was removed — the AXIOM_INTERNAL_BYPASS rename was completed and the full-tree scan caused build timeouts (2026-07). No residue guard active.

# begin Nimble config (version 2)
switch("noNimblePath")
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

# ── Effect Verification Gate (CI/pre-commit Hard-Fail Stapper) ──────────
# Phase 4-F: Hard-fail gate that scans src/ for proc→func conversion
# candidates. Fails on non-zero exit from the tool (compilation error or
# violation found). This is a CI/pre-commit stapper, not a compile-time block.
# Existing tool: tools/effect_auto_fixer.nim (AST-safe token replacement).
# Positioned here so Phase3-D enforcement upgrade propagates automatically.
task enforceEffects, "Hard-fail stapper: scan src/ for proc→func candidates":
  exec "nim c -r --hints:off tools/effect_auto_fixer.nim --check-only --dir src"

# ── Source-tree hash (mirrors computeDeterministicSourceHash in hermetic_build.nim) ──
# Formula vs1-tree-hash/1 — byte-identical to core/utils/build_provenance.nim
# (sourceTreeDigest) and the walk in src/infrastructure/source_identity_cache.nim:
#   fileDigest = $hash(bytes);  tree = "vs1-tree-hash/1:" & $hash(
#     "vs1-tree-hash/1\n" & Σ relPath & "\0" & fileDigest & "\n")
# relPath is the path relative to srcDir with '/' separators (paths are bound
# into the digest, so old concatenation-era values are distinguishable).
proc computeSourceTreeHash(srcDir: string): string =
  var files: seq[string] = @[]
  for f in walkDirRec(srcDir):
    if f.endsWith(".nim") and not f.contains("/generated/"):
      files.add(f)
  files.sort()
  var stream = "vs1-tree-hash/1" & "\n"
  for f in files:
    var rel = f
    if rel.startsWith(srcDir):
      rel = rel[srcDir.len .. ^1]
      while rel.len > 0 and rel[0] == '/':
        rel = rel[1 .. ^1]
    stream.add(rel)
    stream.add("\0")
    stream.add($hash(readFile(f)))
    stream.add("\n")
  result = "vs1-tree-hash/1:" & $hash(stream)

# ── Hermetic PreBuild Orchestrator (v28) ───────────────────────────────────────
# Runs before every `nim c` invocation. Generates/updates build_env.nim with
# frozen build constants (Z3 version, git hash, commit count, source hash) and
# performs import boundary validation, invariant hash verification, and manifest
# staleness checks.
# Guard env var AXIOM_HERMETIC_BUILDING prevents recursive re-entry when this
# block invokes `nim c` (e.g., to self-build bin/hermetic_build).
# See: docs/spec/nim_effect_system_quirks.md §14
block hermeticPreBuild:
  # AXIOM_GATE_BOND=1 중첩 nim c(manifestBootstrap의 feature_manifest_generator,
  # 게이트 self-build)는 이 블록을 재진입하지 않음 — env-hash가 2회 계산되어
  # 캐시 게이트가 항상 miss 되는 재귀를 방지.
  if getEnv("AXIOM_HERMETIC_BUILDING", "") != "1" and not defined(AXIOM_GATE_BOND):
    putEnv("AXIOM_HERMETIC_BUILDING", "1")
    
    # NOTE: build/nimcache is NEVER cleared by this block. Recompile decisions
    # belong to the compiler: Nim 2.2.10 byte-compares the generated `.nim.c`
    # (compiler/cgen.nim:2215-2237 shouldRecompile), and that generated file
    # embeds the full C compile command line (compiler/extccomp.nim:657-664),
    # so any source, `-d:`, `--passC/--passL`, `-I` or compiler-version change
    # alters the `.nim.c` and forces exactly the affected recompiles. Comment-only
    # edits are invisible by design (Nim keys on the parsed AST, not raw bytes).
    # What this block still owns is narrower: WHEN to re-run Axiom's own
    # orchestration tool (`bin/hermetic_build`, below). See
    # docs/spec/config_nims_hermetic_cache_quirk.md (DEBT#417).
    
    let hbBin = "bin/hermetic_build"
    let hbSrc = "tools/hermetic_build.nim"
    var hbStale = not fileExists(hbBin)
    if not hbStale:
      let hbBinMtime = staticExec("stat -c %Y " & hbBin).strip()
      let hbSrcMtime = staticExec("stat -c %Y " & hbSrc).strip()
      if hbBinMtime.len == 0 or (hbSrcMtime.len > 0 and hbSrcMtime > hbBinMtime):
        hbStale = true
    if hbStale:
      echo "[hermetic] Building " & hbBin & " from " & hbSrc
      exec "nim c --hints:off -o:" & hbBin & " " & hbSrc
    # 환경 해시 기반 건너뛰기: hermetic build input이 변하지 않았으면 매 nim c마다
    # 전체트리 스캔하는 bin/hermetic_build 실행을 생략 (Zero-Redundancy Gate).
    # 다이제스트는 std/hashes hash() — 프로세스 간 결정성 실증됨 (실험 2026-08-07:
    # hash() 상수 seed, std/sha1·sha2는 NimScript VM에서 컴파일 불가).
    #
    # Hermetic cache (Single Authority delegation to bin/hermetic_build):
    #   - Key: VerifierBuildId inputs + config/*.nims + manifest.d/*.json +
    #     src/ content hash + cheap lean fingerprint. VCS state (git HEAD,
    #     .git/index) is NOT part of the key.
    #   - Case A (Full HIT): envHash matches stamp AND build_env.nim is coherent
    #     with liveSourceHash, VerifierBuildId, and gitHeadRef → zero writes
    #     (both build_env.nim and hermetic_env_hash.txt preserve mtime & inode).
    #   - Case B (Git-HEAD-only HIT): envHash matches stamp AND build_env.nim is
    #     coherent except BuildEnvGitHash → delegate to `bin/hermetic_build --materialize`.
    #   - Case C (MISS): delegate to `bin/hermetic_build` (or `--generate-build-env`
    #     under AXIOM_FAST_BUILD=1) and atomically stamp hermetic_env_hash.txt
    #     using a PID-unique temp file + mv.
    let envCachePath = ".axiom/cache/hermetic_env_hash.txt"
    var envHash = ""
    for p in ["config.nims", "config/effects.nims", "src/gate/config.nims",
              "Makefile", "axiom.nimble", "axiom.lock", "proofs/lean-toolchain",
              "config/lint.nims", "config/strict.nims", "config/integrity.nims",
              "config/paths.nims", "config/vendors.nims", hbSrc,
              "src/gate/topology_spec.nim", "config/gates.manifest.toml",
              "src/generated/build_env.nim.default"]:
      if fileExists(p):
        envHash &= $hash(readFile(p))
    if dirExists("src/gate/manifest.d"):
      var manifestPaths: seq[string] = @[]
      for kind, path in walkDir("src/gate/manifest.d"):
        if path.endsWith(".json"):
          manifestPaths.add(path)
      manifestPaths.sort()
      for p in manifestPaths:
        envHash &= $hash(readFile(p))
    # Compute liveSourceHash once per hermeticPreBuild invocation and fold into envHash.
    let liveSourceHash = computeSourceTreeHash("src")
    envHash &= liveSourceHash
    # Git HEAD resolution via pure .git file reads — NO gorge (§17 quirk: gorge
    # returns empty under `nim check`, so it cannot be used here). Deterministic:
    # identical HEAD → identical SHA.
    let gitHeadPath = ".git/HEAD"
    var gitHeadRef = ""
    let envGitHash = getEnv("AXIOM_GIT_HASH", "")
    if envGitHash.len > 0:
      gitHeadRef = envGitHash
    elif fileExists(gitHeadPath):
      let headContent = readFile(gitHeadPath).strip()
      if headContent.startsWith("ref: "):
        let refName = headContent[5..^1].strip()
        let refFile = ".git/" & refName
        if fileExists(refFile):
          gitHeadRef = readFile(refFile).strip()
        else:
          gitHeadRef = refName
      else:
        gitHeadRef = headContent
    if gitHeadRef.len == 0:
      gitHeadRef = "unknown"
    # Lean fingerprint: a cheap dirExists signal that the proofs/ tree is present.
    envHash &= (if dirExists("proofs"): "lean:present" else: "lean:absent")
    var cachedHash = ""
    if fileExists(envCachePath):
      cachedHash = readFile(envCachePath).strip()

    let targetPath = "src/generated/build_env.nim"
    let defaultPath = "src/generated/build_env.nim.default"
    let bodyPath = ".axiom/cache/build_env.body"

    # Read-only validity & coherence check on src/generated/build_env.nim.
    # bin/hermetic_build is the SOLE writer of src/generated/build_env.nim.
    var buildEnvValid = false
    var gitHashMatches = false
    if fileExists(targetPath):
      let envContent = readFile(targetPath)
      let hasSourceHash = envContent.contains("BuildSourceHash* = \"" & liveSourceHash & "\"")
      let hasVerifierSourceHash = envContent.contains("VerifierBuildSourceHash* = \"" & liveSourceHash & "\"")
      var hasValidVerifierId = false
      for line in envContent.splitLines():
        if line.startsWith("  VerifierBuildId* = \"") and line.endsWith("\""):
          let val = line["  VerifierBuildId* = \"".len .. ^2]
          if val.len == 64:
            hasValidVerifierId = true
            for ch in val:
              if ch notin {'0'..'9', 'a'..'f'}:
                hasValidVerifierId = false
                break
          break
      buildEnvValid = hasSourceHash and hasVerifierSourceHash and hasValidVerifierId
      gitHashMatches = envContent.contains("BuildEnvGitHash* = \"" & gitHeadRef & "\"")

    let isHit = (envHash == cachedHash) and buildEnvValid
    if isHit and gitHashMatches:
      # Case A — Full HIT: zero writes to build_env.nim and hermetic_env_hash.txt
      echo "[hermetic] Environment unchanged (HIT)"
    elif isHit and not gitHashMatches and fileExists(bodyPath):
      # Case B — Git-HEAD-only change: materialize via bin/hermetic_build
      echo "[hermetic] Environment unchanged (HIT)"
      exec hbBin & " --materialize"
    else:
      # Case C — MISS: delegate to bin/hermetic_build (sole writer)
      echo "[hermetic] Environment changed (MISS)"
      if getEnv("AXIOM_FAST_BUILD") == "1":
        exec hbBin & " --generate-build-env"
      else:
        exec hbBin
        if not dirExists(".axiom/cache"):
          mkDir(".axiom/cache")
        let pid = staticExec("echo $PPID").strip()
        let stampSuffix = if pid.len > 0: pid else: "0"
        let stampTmpPath = ".axiom/cache/.hermetic_env_hash.tmp." & stampSuffix
        writeFile(stampTmpPath, envHash)
        exec "mv " & stampTmpPath & " " & envCachePath

    # Sync topology SSOT with manifest.d/*.json
    # Stale-binary guard: sync_topology EMBEDS the topology spec at compile
    # time — a cache-restored binary from an older run regenerates the manifest
    # SSOT from its embedded STALE spec (observed 2026-09-10 CI race:
    # verify-contract G1 purity FAIL "working tree dirtiness changed"). Rebuild
    # whenever any spec-dependent source is newer than the binary. VM-safe
    # mtime compare via staticExec stat (std/os mtime procs are not on the
    # NimScript target).
    let syncBin = "bin/sync_topology"
    let syncSrc = "tools/sync_topology.nim"
    let syncSpecSrcs = [syncSrc, "src/gate/topology_spec.nim", "src/gate/helper_spec.nim",
                        "src/gate/framework/topology_types.nim"]
    var syncStale = not fileExists(syncBin)
    if not syncStale:
      let binMtime = staticExec("stat -c %Y " & syncBin).strip()
      if binMtime.len == 0:
        syncStale = true
      else:
        for s in syncSpecSrcs:
          if fileExists(s):
            let sMtime = staticExec("stat -c %Y " & s).strip()
            if sMtime.len > 0 and sMtime > binMtime:
              syncStale = true
    if syncStale:
      echo "[hermetic] Building " & syncBin & " from " & syncSrc
      exec "nim c --hints:off -o:" & syncBin & " " & syncSrc
    echo "[hermetic] Syncing topology..."
    exec syncBin

    # Decision binding integrity check (audit mode - warn only)
    let dbBin = "bin/decision_binding_checker"
    let dbSrc = "tools/decision_binding_checker.nim"
    if not fileExists(dbBin):
      echo "[hermetic] Building " & dbBin & " from " & dbSrc
      exec "nim c --hints:off -o:" & dbBin & " " & dbSrc
    if getEnv("AXIOM_FAST_BUILD") != "1":
      echo "[hermetic] Checking decision bindings (audit)..."
      exec dbBin & " --escalation-threshold 30"

    # Final guard: ensure build_env.nim exists for nim check/c imports.
    if not fileExists(targetPath):
      writeFile(targetPath, readFile(defaultPath))
      echo "[hermetic] build_env.nim created from .default template (final guard)"

# ── SourceCoherence seed guard (top-level — runs even when hermeticPreBuild
#    is skipped under AXIOM_HERMETIC_BUILDING=1, i.e. every CI ci-compile) ──
# vendors.nims seeds build_env.nim from .default (BuildSourceHash="") on a
# fresh checkout; the skip gate then prevents the live-hash body restore, so
# `nim c` embeds BuildSourceHash="" and bin/ax FATALs SourceCoherence the
# moment it runs as a REGULAR FILE (admission-check job 2 — the job-1 CAS
# symlink self-path guard hides it; observed run 35956968918, embedded empty).
# Fires only on empty/placeholder; a non-empty hash is never touched
# (bin/hermetic_build remains the SSOT writer). Logic mirrors the body-restore
# replacement above (config.nims ~L512-515).
block sourceHashSeedGuard:
  let shgPath = "src/generated/build_env.nim"
  if fileExists(shgPath):
    var shgContent = readFile(shgPath)
    let shgEmpty = "BuildSourceHash* = \"\""
    let shgPlaceholder = "BuildSourceHash* = \"__AXIOM_BUILD_SOURCE_HASH__\""
    if shgContent.contains(shgEmpty) or shgContent.contains(shgPlaceholder):
      let shgLive = computeSourceTreeHash("src")
      shgContent = shgContent.replace(shgEmpty, "BuildSourceHash* = \"" & shgLive & "\"")
      shgContent = shgContent.replace(shgPlaceholder, "BuildSourceHash* = \"" & shgLive & "\"")
      writeFile(shgPath, shgContent)
      echo "[coherence] build_env.nim seed guard: injected live BuildSourceHash " & shgLive

# ── Tier 3: Runner Pool Canonical Schema (C1) ──────────────────────
# RunnerPoolSpecDigest & ObservedRunnerPoolDigest share ONE canonical
# schema (os, arch, nim, lean, z3, system_deps) + ONE normalize + ONE
# identity utility (SSOT). NO duplicated normalize/serialize code.

type
  RunnerPoolSpecDigest* = object
    os*: string
    arch*: string
    nim*: string
    lean*: string
    z3*: string
    system_deps*: seq[string]

  ObservedRunnerPoolDigest* = object
    os*: string
    arch*: string
    nim*: string
    lean*: string
    z3*: string
    system_deps*: seq[string]

func normalize*(d: var RunnerPoolSpecDigest | ObservedRunnerPoolDigest) =
  ## ONE normalize — strip, lowercase os/arch, sort system_deps for
  ## deterministic identity. Shared by both digest kinds (SSOT).
  d.os = d.os.strip().toLowerAscii()
  d.arch = d.arch.strip().toLowerAscii()
  d.nim = d.nim.strip()
  d.lean = d.lean.strip()
  d.z3 = d.z3.strip()
  d.system_deps.sort()

func identity*(d: RunnerPoolSpecDigest | ObservedRunnerPoolDigest): string =
  ## ONE identity utility (SSOT). Hashes the normalized fields into a
  ## single deterministic fingerprint using std/hashes (same hash as
  ## hermetic_env_hash in this block).
  result = $hash(d.os & ":" & d.arch & ":" & d.nim & ":" & d.lean & ":" & d.z3 & ":" & d.system_deps.join(":"))
