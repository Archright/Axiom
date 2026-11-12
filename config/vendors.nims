# config/vendors.nims — Hermetic Build, Source Scanner
# Extracted from config.nims lines 380-458
# Provides: glibc check, source scanner, hermetic build env

# Import (hashes) is inherited from the orchestrator config.nims

# ─── Hermetic Build Environment ──────────────────────────────────────
# Generate src/generated/build_env.nim with content-hash idempotency.
# Only writes if content actually changed (preserves mtime → cache-safe).
# Prevents unnecessary recompilation from volatile fields (commitCount, gitHash).

# ── Z3 Version Pin (Hermetic Declaration) ──────────────────────
# 호스트 환경에서 발견(discover)하지 않고, 프로젝트가 요구하는 버전을 선언(declare)한다.
# Z3 업그레이드 시 이 상수만 변경하면 된다.

# Layer 1: glibc 호환성 사전 검증 (metadata에서 읽기)
let glibcVer = mdStr("glibcVersion", "")
if glibcVer.len == 0:
  echo "⚠️ [Hermetic] Cannot detect glibc version. Z3 may fail on this platform."
elif "2.3" in glibcVer:
  let minorStart = glibcVer.find("2.3")
  if minorStart >= 0 and minorStart + 4 < glibcVer.len:
    let minor = glibcVer[minorStart+3..minorStart+4]
    try:
      if parseInt(minor) < 5:
        echo "❌ [Hermetic] glibc " & glibcVer & " is too old for Z3 4.13.3."
        echo "  Required: glibc >= 2.35. Install via: vendor/z3/install.sh"
        quit(1)
    except ValueError: discard

# Bootstrap guard: bin/hermetic_build overwrites build_env.nim with real values.
# If it hasn't run yet, materialize src/generated/build_env.nim.default (copy-only,
# never overwrites a present file — same rule as canonical-bootstrap/action.yml).
# Hermetic builds (AXIOM_HERMETIC_BUILDING=1) skip config.nims' hermeticPreBuild
# materialization, so a fresh checkout would otherwise fail `import generated/build_env`.
when not staticFileExists("src/generated/build_env.nim"):
  let buildEnvDefault = "src/generated/build_env.nim.default"
  if not staticFileExists(buildEnvDefault):
    echo "❌ [Bootstrap] src/generated/build_env.nim missing and template " & buildEnvDefault & " not found."
    echo "  Run `nimble hermetic` (or `bin/hermetic_build`) to populate real values."
    quit(1)
  writeFile("src/generated/build_env.nim", readFile(buildEnvDefault))
  echo "⚠️ [Bootstrap] src/generated/build_env.nim not found."
  echo "  Seeded from build_env.nim.default constants (run `nimble hermetic` for real values)."

# ── Z3 FFI REMOVED (v30 rationale: z3_ffi_architecture.md §10) ──────────────
# Z3 FFI linker flags removed. All Z3 solver interactions now use CLI
# subprocess path via z3_pool.nim. See config.nims for compile-time guard.
# ─── @pending guard migrated to compile-time ──────────────────────
# Validated by src/core/trusted/compile_time_manifest.nim (staticRead + macros).
# Zero runtime overhead — fails at compile time if @pending features exist.

# ─── Compile-Time Source Scanner — AxiomSourceFiles Injection ────────
# Reads pre-computed source file list from build_metadata.json.
# Previously used walkDirRec("src") on every nim c invocation (100-500ms).
# Skips generated files (already filtered by build_metadata_generator).
if not defined(AxiomParsingImports):
  let metadataSourceFiles = mdStrArray("sourceFileList")
  if metadataSourceFiles.len > 0:
    var axiomFiles: seq[string] = @[]
    for file in metadataSourceFiles:
      let absPath = getCurrentDir() / "src" / file
      if fileExists(absPath):
        axiomFiles.add(absPath)  # skip deleted facades (staticRead guard)
    if axiomFiles.len > 0:
      switch("define", "AxiomSourceFiles:" & axiomFiles.join(","))

# ─── Nimcache Shared-State Ownership Guard (Retired) ───────────────────
# The `nimcache_leases` shell probe was retired under VS-C1c: DEBT#417 removed
# the `build/nimcache` purge from `config.nims`, making `AXIOM_CI_PRESERVE_CACHE`
# and the per-compile lease probe inert. See
# docs/spec/config_nims_hermetic_cache_quirk.md §8.4.
