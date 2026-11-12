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

# ─── Nimcache Shared-State Ownership Guard ─────────────────────────────
# config.nims' hermeticPreBuild MISS branch removes the whole `build/nimcache`
# TREE to force a deterministic cold rebuild. That tree is a shared parent, not
# an owned resource: `verify-contract` runs four gates in parallel and each owns
# a per-target nimcache underneath it (Makefile --nimcache:build/nimcache/<target>).
# A MISS raised by any one of them therefore deleted the object files of the
# other three while they were still linking — observed 2026-10-04 as
# `/usr/bin/ld: cannot find build/nimcache/<target>/@<mod>.nim.c.o`, with all four
# verify-contract gates failing together (serial run of the same commit passed).
#
# Ownership rule: the purge is authorized only for the build that is the SOLE
# occupant of the shared namespace. Occupancy is a liveness-checked lease
# registry: every `nim c` registers before it can create anything under
# build/nimcache, prunes leases whose owner has already exited, and yields the
# purge whenever another live build holds the namespace. The purge itself is
# untouched — a sole build still gets its deterministic clean rebuild.
#
# Yielding reuses AXIOM_CI_PRESERVE_CACHE, the gate config.nims consulted
# immediately before the purge: it was the only veto that reached config.nims'
# FROZEN MISS branch without editing that file. It also narrowed envHash by
# dropping the `.git/index` dirty-marker (config.nims:456) — the same
# deterministic key-narrowing the CI gate applied.
#
# STATUS 2026-10-05 (DEBT#417 fix): the purge and the `.git/index` term are both
# gone from config.nims, so AXIOM_CI_PRESERVE_CACHE no longer gates anything
# there and this lease guard is now inert. It is retained, NOT removed, so that
# (a) the guard remains available if a future purge is reintroduced, and (b) the
# same-commit diff stays surgical. Retiring the flag and this guard is a
# separate follow-up slice; see docs/spec/config_nims_hermetic_cache_quirk.md.
#
# A build that cannot prove sole occupancy yields the purge: failing toward
# "do not destroy state this process does not own" is the only safe direction.
# The probe is one shell call (register + prune + count) so the per-`nim c` cost
# stays at a single fork.
#
# Two NimScript details this guard depends on:
#   - `staticExec` inside an INCLUDED file runs with the CWD set to that file's
#     own directory, so the registry is anchored to `thisDir()` (the project
#     root) instead of a relative path.
#   - the compiler evaluates config.nims several times per `nim c`, and every
#     evaluation forks a fresh shell. The lease id is therefore `$PPID` — the
#     compiler process, which is stable across those evaluations — and not
#     `$$`, which would register one throwaway lease per evaluation.
if getEnv("AXIOM_CI_PRESERVE_CACHE", "") != "1":
  let leaseDir = thisDir() / ".axiom" / "cache" / "nimcache_leases"
  let occupancy = staticExec(
    "d=" & leaseDir & "; mkdir -p \"$d\" 2>/dev/null || { echo registry_unavailable; exit 0; }; " &
    "me=$PPID; : > \"$d/$me\"; n=0; " &
    "for f in \"$d\"/*; do [ -e \"$f\" ] || continue; p=${f##*/}; " &
    "[ \"$p\" = \"$me\" ] && continue; " &
    "if kill -0 \"$p\" 2>/dev/null; then n=$((n+1)); else rm -f \"$f\"; fi; done; " &
    "echo $n").strip()
  if occupancy != "0":
    let reason =
      if occupancy == "": "occupancy probe returned no result"
      elif occupancy == "registry_unavailable": "lease registry unavailable"
      else: occupancy & " concurrent build(s) hold build/nimcache"
    echo "[nimcache] " & reason & " — purge yielded (sole ownership unproven)"
    putEnv("AXIOM_CI_PRESERVE_CACHE", "1")
