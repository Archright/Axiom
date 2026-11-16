# V3-G: config.nims Shell-Invocation Inventory

**Date**: 2026-06-28
**Scope**: All `gorge()`, `gorgeEx()`, `staticExec()`, `staticRead()`, `staticFileExists()`, and `exec` calls in `config.nims`
**Goal**: Classify every shell/file invocation to determine migration path toward hermetic build.

---

## Summary

| Category | Count | Action |
|---|---|---|
| `gorge()`/`gorgeEx()` | 6 sites (re-measured 2026-11-16 across `config.nims` + `config/*.nims` includes: 2 task-only in `config.nims` — `:152` computeSourceHash, `:249` binary checksums; 3 in the `config/integrity.nims` merkle block — `:36` probe, `:60` per-file, `:63` root — **6 invocations on every compile**; 1 `gorgeEx` AST-checker dispatch in `config/strict.nims:320`) | Replace with `build_env.nim` or pure-Nim; the merkle 6 are the DEBT#546 theater site |
| `staticRead()` | 5 | Keep — compile-time policy guard (zero shell) |
| `staticFileExists()` | 2 | Keep — compile-time existence check (zero shell) |
| `exec` (NimScript runtime) | 12 | Keep — all inside `task` blocks, not on main path |
| **Total shell-spawning calls on main build path** | **6 gorge invocations per compile (merkle block — DEBT#546) + 1 gorgeEx AST-checker dispatch when armed** | **Not hermetic — the 2026-06-28 "0 / Already hermetic" verdict predates the merkle theater finding** |
| **Total compile-time file reads** | **7** | **Zero shell dependency** |

---

## §1. gorge() / gorgeEx() Calls

These are the only compile-time shell-spawning calls. This 2026-06-28 inventory predates the `config/*.nims` decomposition and counted exactly 1 site in the then-monolithic `config.nims`. Re-measured 2026-11-16 across `config.nims` and its includes, there are **6** call sites, of which the merkle block's 3 sites execute on **every `nim c`** (6 invocations: 1 probe + 4 per-file + 1 root) — that block is the DEBT#546 theater site: the verdict binds to the `sha256sum:` diagnostic prefix, not to guarded file content.

| # | Line | Call | Context | Purpose | Category | Can Replace? |
|---|---|---|---|---|---|---|
| G1 | 501 | `gorgeEx("sha256sum " & bin)` | `task buildGateRunners` | SHA256 checksum of compiled gate runner binaries → stored in `.axiom/cache/binary_checksums.json` | `build_metadata` | **yes** — can use `std/sha256` in Nim or move to `build_metadata.json` |
| G2 | config/integrity.nims:36 | `gorge("echo axiom_gorge_probe")` | merkle self-test | detect whether gorge() is operational (main path, every compile) | `integrity_guard` | yes |
| G3 | config/integrity.nims:60 | `gorge("sha256sum " & fullPath.extractFilename())` | merkle per-file hash (×4 per compile) | intended per-file digest — actual (DEBT#546): bare filename → ENOENT → `split(" ")[0]` harvests the `sha256sum:` diagnostic prefix | `integrity_guard` | yes — VS-MERKLE-RESTORE-1 (absolute path, fail-closed) |
| G4 | config/integrity.nims:63 | `gorge("echo -n " & concat & " \| sha256sum")` | merkle root | hashes the concatenation of the 4 `sha256sum:` prefixes (main path, every compile) | `integrity_guard` | yes |
| G5 | config/strict.nims:320 | `gorgeEx(checkerBin & " " & args)` | AST invariant checker | run the native checker over src/core, src/verification, src/engine (main path when armed) | `strict_guard` | no — NimScript VM iteration limits |
| G6 | config.nims:152 | `gorge(cmd)` | `computeSourceHash` (task-only, via `task buildGateRunners`) | gate-runner freshness source hash | `build_metadata` | yes |

### Analysis for G1

- **Location**: Inside `task buildGateRunners` (line 429), which is only invoked via `nim buildGateRunners`, NOT on every `nim c`.
- **Impact**: Low — does not affect normal build path.
- **Replacement**: `std/sha256` is not available in NimScript (depends on `std/endians` → `copyMem`). Options:
  1. Move checksum computation to a Nim tool (e.g., `tools/checksum_binaries.nim`) and store in `build_metadata.json`.
  2. Use `std/hashes` (FarmHash, already used in `computeSourceHash` at line 427) as a lighter alternative.
  3. Keep as-is — it's in a task block, not on the main build path.

---

## §2. staticRead() Calls

Compile-time file reads. These are **not shell invocations** — they are Nim compile-time intrinsics that read file content during compilation. Zero runtime overhead.

| # | Line | Call | Purpose | Category | Keep? |
|---|---|---|---|---|---|
| S1 | 244 | `staticRead("AGENTS.md")` | Verify AGENTS.md exists and is non-empty | `policy_guard` | **yes** — immutable policy artifact |
| S2 | 246 | `staticRead("docs/agents/architecture.md")` | Verify architecture.md exists and is non-empty | `policy_guard` | **yes** — immutable policy artifact |
| S3 | 248 | `staticRead("docs/agents/rules_workflow.md")` | Verify rules_workflow.md exists and is non-empty | `policy_guard` | **yes** — immutable policy artifact |
| S5 | 265 | `staticRead("src/policy/build_constraint.nim")` | Verify build constraint policy contains "nim" and does not allow bare "python3" | `build_constraint` | **yes** — security policy guard |

### Analysis

All `staticRead()` calls serve as **compile-time policy guards** that fail the build if critical files are missing or empty. They are:
- **Zero shell dependency** — pure compile-time intrinsic
- **Deterministic** — identical file content → identical result
- **Required** — removing them would remove build-time safety guarantees

**Verdict**: Keep all. No migration needed.

---

## §3. staticFileExists() Calls

Compile-time file existence checks. Also **not shell invocations**.

| # | Line | Call | Purpose | Category | Keep? |
|---|---|---|---|---|---|
| F1 | 264 | `staticFileExists("src/policy/build_constraint.nim")` | Check if build constraint policy file exists before reading it | `build_constraint` | **yes** — prerequisite for S5 |
| F2 | 278 | `staticFileExists("bin/main")` | Verify build artifact exists | `build_prerequisite` | **yes** — build guard |

### Analysis

- F1 is the existence check that gates S5 (`staticRead` of the same file). Both are in a `static:` block.
- F2 ensures `bin/main` exists before normal builds. This is a build artifact check, not a shell call.

**Verdict**: Keep both. No migration needed.

---

## §4. exec Calls (NimScript Runtime Shell)

These are NimScript `exec` calls that spawn a shell process at **runtime** (not compile-time). All are inside `task` blocks or conditional blocks that only execute when explicitly invoked.

| # | Line | Command | Context | Purpose | On Main Path? |
|---|---|---|---|---|---|
| E1 | 295 | `nim c -r --hints:off tools/feature_manifest_generator.nim` | `block manifestBootstrap` | Auto-generate `feature_manifest.json` if missing | conditional — only if file missing |
| E2 | 303 | `nim c -r --hints:off tools/feature_manifest_generator.nim` | `block manifestBootstrap` | Regenerate manifest if `.feature` files are newer | conditional — only if stale |
| E3 | 472-477 | `nim c --hints:off -d:release ...` | `task buildGateRunners` | Compile `bin/authorize_commit` with metadata flags | task only |
| E4 | 480-482 | `nim c --hints:off -d:release -d:useMalloc ...` | `task buildGateRunners` | Compile `bin/gate_hook` with isolated nimcache | task only |
| E5 | 484 | `nim c --hints:off -d:release -o:...` | `task buildGateRunners` | Compile other gate runners | task only |
| E6 | 509 | `mv .axiom/cache/.checksums.tmp .axiom/cache/binary_checksums.json` | `task buildGateRunners` | Atomic rename for checksum file | task only |
| E7 | 515 | `nim c -r --hints:off tools/feature_manifest_generator.nim` | `task genmanifest` | Generate feature manifest on demand | task only |
| E8 | 521 | `nim c --hints:off -o:bin/pbt_generator tools/pbt_generator.nim` | `task buildPbtTools` | Build PBT generator tool | task only |
| E9 | 522 | `nim c --hints:off -o:bin/pbt_seed_parser tools/pbt_seed_parser.nim` | `task buildPbtTools` | Build PBT seed parser | task only |
| E10 | 523 | `nim c --hints:off -o:bin/generate_forwarding_stubs tools/generate_forwarding_stubs.nim` | `task buildPbtTools` | Build forwarding stubs tool | task only |
| E11 | 530 | `nim c --hints:off -o:tests/solver/mock_lean_repl tests/solver/mock_lean_repl.nim` | `task contractTest` | Build mock Lean REPL server | task only |
| E12 | 531 | `nim c --hints:off -r tests/solver/test_lean_contract.nim` | `task contractTest` | Run Lean REPL contract tests | task only |

### Analysis

- **E1/E2**: In `block manifestBootstrap` — runs on every `nim c` but is **conditional** (only when file is missing or stale). Already partially hermetic via `mdInt64` timestamps from `build_metadata.json`.
- **E3-E6, E7-E12**: All inside `task` blocks — only execute when explicitly invoked via `nim buildGateRunners`, `nim genmanifest`, etc. **Never on the main build path.**

**Verdict**: Keep all. The `exec` calls are either conditional (E1/E2) or task-only (E3-E12). None affect normal `nim c` compilation.

---

## §5. build_env.nim Coverage Analysis

### Current constants in `src/generated/build_env.nim` (generated by config.nims)

| Constant | Value | Source |
|---|---|---|
| `BuildEnvZ3Version` | `"4.13.3"` | Declared constant (`ExpectedZ3Version`) — no shell call |
| `BuildEnvCommitCount` | `417` | `mdInt("commitCount")` from `build_metadata.json` |
| `BuildEnvGitHash` | `"refs/heads/core"` | `mdStr("gitHash")` from `build_metadata.json` |

### Constants in `tools/hermetic_build.nim`'s version of `build_env.nim`

| Constant | In config.nims? | In hermetic_build.nim? | Notes |
|---|---|---|---|
| `BuildEnvZ3Version` | ✅ | ✅ | Both sources agree |
| `BuildEnvCommitCount` | ✅ | ✅ | Both sources agree |
| `BuildEnvGitHash` | ✅ | ✅ | Both sources agree |
| `BuildEnvProjectRoot` | ❌ | ✅ | Only hermetic_build generates this |

### What `hermetic_build.nim` captures via gorge that config.nims does not

| Data | hermetic_build.nim | config.nims | Notes |
|---|---|---|---|
| Z3 version | `gorge("z3 --version")` then parsed | `const ExpectedZ3Version = "4.13.3"` | config.nims uses declared constant (better) |
| Git commit count | `gorge("git rev-list --count HEAD")` | `mdInt("commitCount")` from metadata | config.nims reads pre-generated data (better) |
| Git hash | `gorge("git rev-parse --short HEAD")` | `mdStr("gitHash")` from metadata | config.nims reads pre-generated data (better) |
| Project root | `getCurrentDir()` | Not captured | Could be added if needed |
| glibc version | `gorge("ldd --version")` | `mdStr("glibcVersion")` from metadata | config.nims reads pre-generated data (better) |
| Nim version | `NimVersion` (built-in) | `mdStr("nimVersion")` from metadata | Both read metadata |

### Remaining gorge() calls in hermetic_build.nim (for reference)

`hermetic_build.nim` itself still has gorge calls for Z3 version, git hash, commit count, etc. These are **expected** — it is the *generator* that runs once and produces `build_metadata.json` + `build_env.nim`. The key invariant is that `config.nims` and `src/` modules never call gorge directly.

---

## §6. Migration Status

### Already Migrated (no gorge on main build path)

| Previous gorge() | Current mechanism | Status |
|---|---|---|
| `gorge("git rev-parse HEAD")` | `build_metadata.json` → `mdStr("gitHash")` | ✅ migrated |
| `gorge("git rev-list --count HEAD")` | `build_metadata.json` → `mdInt("commitCount")` | ✅ migrated |
| `gorge("z3 --version")` | `const ExpectedZ3Version` declaration | ✅ migrated (upgraded to declared constant) |
| `gorge("ldd --version")` | `build_metadata.json` → `mdStr("glibcVersion")` | ✅ migrated |
| `gorge("uname -m")` | `build_metadata.json` → `mdStr("arch")` | ✅ migrated |
| `walkDirRec("src")` for source list | `build_metadata.json` → `mdStrArray("sourceFileList")` | ✅ migrated |
| `walkDir()` for manifest.d files | `build_metadata.json` → `mdStrArray("manifestFiles")` | ✅ migrated |
| `walkDir()` for nimble package paths | `injectAxiomDependencies()` (pure NimScript, no shell) | ✅ no shell |

### Remaining (actionable)

| Call | Location | Effort | Priority |
|---|---|---|---|
| `gorgeEx("sha256sum " & bin)` (G1) | `task buildGateRunners` L501 | Low — task-only, not main path | Low |

---

## §7. Conclusion

**config.nims is NOT hermetic on the main build path (corrected 2026-11-16).** The merkle block in `config/integrity.nims` spawns 6 gorge invocations on every `nim c` (DEBT#546 theater — the verdict binds to the `sha256sum:` diagnostic prefix, not content), and `config/strict.nims` dispatches the AST invariant checker via `gorgeEx` when armed. The task-only calls (G1, G6) and the 7 compile-time intrinsics (`staticRead`/`staticFileExists`) are as originally classified.

### Breakdown by Category

```
gorge()/gorgeEx():    6 sites (2 task-only; 3 merkle = 6 invocations
                      per compile — DEBT#546; 1 gorgeEx AST checker)
staticRead():         5 calls (zero shell, keep)
staticFileExists():   2 calls (zero shell, keep)
exec (task/conditional): 12 calls (runtime, keep)
────────────────────────────────────────
Total on main path:   6 shell invocations per compile (merkle, DEBT#546)
                      + 1 gorgeEx when the AST checker is armed
                      ← NOT hermetic (2026-06-28 "0" count superseded)
```
