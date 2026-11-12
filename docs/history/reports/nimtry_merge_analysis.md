# nimtry vs nimtry-gate Merge Analysis

**Date**: 2026-06-21
**Author**: Code Agent (automated analysis)
**Status**: Analysis only — no code changes made

---

## 1. Executive Summary

Two gates — `nimtry` and `nimtry-gate` — perform **identical architecture rule checks** on the same file set at the same stages. The only difference is that `nimtry-gate` wraps the same logic in a quarantine/error-suppression layer for a known upstream `IndexDefect` bug. **They should be merged.** Running both means every commit and push executes the full architecture check **twice**, wasting CI minutes and developer wait time.

---

## 2. Gate Manifest Comparison

| Attribute | `nimtry` | `nimtry-gate` |
|---|---|---|
| **id** | `nimtry` | `nimtry-gate` |
| **name** | Axiom nimtry architecture gate | Axiom nimtry gate (quarantine wrapper) |
| **entry** | `bin/nimtry` | `src/gate/runners/nimtry_gate_wrapper` |
| **stages** | pre-commit, pre-push | pre-commit, pre-push |
| **filesPattern** | `src/\|tests/` | `src/\|tests/` |
| **passFilenames** | false | false |
| **weight** | medium | medium |
| **tier** | 1 | *(none)* |
| **envVars** | *(none)* | `NIM_COMPILE_FLAGS=--exceptions:quirky` |
| **after** | *(none — others depend on it)* | *(none)* |

**Downstream dependents** (gates with `"after": ["nimtry"]`):
- `debt-reduction-gate`
- `monotonic-whitelist-gate`
- `policy-validator`

---

## 3. Runner Source Analysis

### 3.1 `nimtry` — Direct Architecture Gate

**Runner chain:**
```
bin/nimtry  →  src/gate/runners/nimtry_gate.nim  →  src/gate/nimtry/nimtry_cli.nim
```

**`src/gate/runners/nimtry_gate.nim`** (14 lines):
- Thin forwarding stub: `import gate/nimtry/nimtry_cli; when isMainModule: nimtry_cli.main()`
- Compiled as a standard binary into `bin/nimtry`.

**`src/gate/nimtry/nimtry_cli.nim`** (491 lines) — the actual gate logic:
- **AST extraction**: Parses all `.nim` files under `src/` (or specific files) into `ModuleFacts` via `extractModuleFactsV4`.
- **Query engine**: Runs 10+ query categories via `runAllQueries`:
  - SoC (Separation of Concerns) transitive
  - SOLID (LSP, SRP) via `solid_queries`
  - SSOT (Single Source of Truth) placement
  - DRY duplicate detection
  - SAFETY (forbidden patterns)
  - PURITY (side-effect analysis)
  - TEST HYGIENE
  - FEATURE UNIVERSE
  - EFFECT queries
  - FACADE queries
- **Policy loading**: Reads `architecture_policy.lock` for rule definitions.
- **Baseline ratchet protocol**:
  - v1: count-only baseline (`data/nimtry_baseline.json`)
  - v2: fingerprint-based per-violation tracking with SHA-256 hashes
  - Prevents regression: error count and total count must not increase
- **CLI flags**: `--full-tree`, `--strict`, `--update-baseline`, `--diff-baseline`, `--update-lock`, `--base-ref`, `--list`
- **Cache system**: File-level caching keyed on policy hash + binary hash.
- **Compiler version lock**: Warns on version mismatch from `data/nimtry_compiler_lock.json`.
- **Break-glass bypass**: Honors `AXIOM_GATE_BYPASS_TOKEN`.

### 3.2 `nimtry-gate` — Quarantine Wrapper

**Runner chain:**
```
src/gate/runners/nimtry_gate_wrapper  →  runs build/nimtry_gate as subprocess
```

**`src/gate/runners/nimtry_gate_wrapper.nim`** (83 lines):
- **Does NOT contain any architecture checking logic.**
- Runs `build/nimtry_gate` as a subprocess via `execCmdEx`.
- `build/nimtry_gate` is a **separate compilation** of the same `nimtry_cli` logic, compiled with `--exceptions:quirky`.
- **Quarantine logic**:
  1. If subprocess succeeds (exit 0) → pass through.
  2. If subprocess fails → check `data/gate_exceptions.json` for `nimtry-gate` entry with unexpired TTL.
  3. If quarantined → convert failure to `KNOWN_ISSUE` (exit 0) with informational log messages.
  4. If not quarantined → propagate original exit code.
- **Missing binary fallback**: If `build/nimtry_gate` doesn't exist → treat as `KNOWN_ISSUE` (exit 0).
- **Exception safety**: Top-level `except IndexDefect` converts crash to `KNOWN_ISSUE`.
- **VFS-aware entry**: `mainWithVfs(ctx: GateContext)` for pipeline orchestrator integration.
- **Requires `--exceptions:quirky`**: Set via `envVars` in manifest to catch `IndexDefect` from the nimtry library.

### 3.3 `build/nimtry_gate` — The Hidden Inner Binary

- Path: `build/nimtry_gate` (2.9 MB ELF binary, built 2026-06-19)
- This is the **actual** nimtry gate logic, compiled separately from `bin/nimtry`.
- Its source is `src/gate/runners/nimtry_gate.nim` (same forwarding stub as `bin/nimtry`).
- The wrapper calls this binary as a subprocess, adding quarantine around it.

---

## 4. Why They Exist (Historical Context)

The quarantine wrapper (`nimtry-gate`) was introduced to work around an **upstream nimtry library bug**:

> **IndexDefect in `targetToString`**: Accesses `n[1]` on `nkBracketExpr` without `safeLen >= 2` guard (`nimtry_extract_part3_part1.nim:217`).

This is documented in:
- `data/gate_exceptions.json` — quarantine manifest with 30-day TTL (expires 2026-07-19)
- `nimtry_gate_wrapper.nim` — inline comments referencing the bug

The wrapper was a temporary measure to keep the gate functional while the upstream bug is pending a fix. However, it was registered as a **separate gate** rather than replacing the original, creating the current duplication.

---

## 5. The Problem: Duplicate Execution

Since both gates share identical `filesPattern` (`src/|tests/`) and `stages` (`pre-commit`, `pre-push`), **every commit and push runs the full architecture check twice**:

1. `nimtry` runs `bin/nimtry` directly — full check, no quarantine.
2. `nimtry-gate` runs `build/nimtry_gate` via wrapper — same full check, with quarantine.

This means:
- **2× CPU time** for architecture analysis (AST extraction + 10 query categories + baseline comparison).
- **2× wall-clock time** in the gate pipeline.
- **Confusion**: Developers see two separate gate results for the same check.
- **Inconsistent behavior**: `nimtry` does NOT have quarantine protection, but `nimtry-gate` does — if the IndexDefect fires, `nimtry` would fail while `nimtry-gate` would pass.

---

## 6. Can They Be Merged? — YES

### 6.1 Why Merge Is Safe

| Criterion | Assessment |
|---|---|
| Same logic? | ✅ Both ultimately run `nimtry_cli.main()` |
| Same files? | ✅ Both use `src/\|tests/` |
| Same stages? | ✅ Both run pre-commit + pre-push |
| Same weight? | ✅ Both medium |
| Same queries? | ✅ SoC, SOLID, SSOT, DRY, SAFETY, PURITY, HYGIENE, FEATURE, EFFECT, FACADE |
| Downstream deps? | ⚠️ 3 gates depend on `"after": ["nimtry"]` — must preserve this ID |

### 6.2 Recommended Merge Strategy

**Keep `nimtry` as the sole gate. Remove `nimtry-gate`.**

1. **Integrate quarantine into `nimtry_cli.nim`** (or the wrapper logic into the main binary):
   - Add `--exceptions:quirky` behavior natively: catch `IndexDefect` at the top level of `nimtry_cli.main()`.
   - On catch, check `data/gate_exceptions.json` for quarantined status.
   - If quarantined → exit 0 with `KNOWN_ISSUE` log.
   - This eliminates the need for a separate subprocess wrapper.

2. **Remove `nimtry-gate` from `src/gate/manifest.d/`**:
   - Delete `src/gate/manifest.d/nimtry-gate.json` and remove its entry from `_index.json`.

3. **Delete wrapper source**:
   - `src/gate/runners/nimtry_gate_wrapper.nim`
   - `src/gate/runners/nimtry_gate` (symlink to cache)
   - `build/nimtry_gate` (binary)

4. **Update `data/gate_exceptions.json`**:
   - Change `gateId` from `"nimtry-gate"` to `"nimtry"`.

5. **No downstream impact**:
   - `debt-reduction-gate`, `monotonic-whitelist-gate`, and `policy-validator` all reference `"after": ["nimtry"]` — unchanged.

### 6.3 Alternative: Keep Wrapper, Remove Direct Gate

If the quarantine behavior is deemed essential even after the IndexDefect fix timeline:

1. **Remove `nimtry` from manifest** (the direct binary).
2. **Rename `nimtry-gate` to `nimtry`** in manifest (keep the wrapper as the sole entry).
3. **Update downstream `after` references** — already `"nimtry"`, so no change needed.
4. **Move `build/nimtry_gate` to `bin/nimtry`** or update the wrapper path.

**This approach is less recommended** because it adds subprocess overhead and quarantines code for every execution, even when the bug is fixed.

---

## 7. Final Recommendation

| Action | Priority |
|---|---|
| Merge quarantine logic into `nimtry_cli.nim` | **High** |
| Remove `nimtry-gate` from `src/gate/manifest.d/` | **High** |
| Delete `nimtry_gate_wrapper.nim` and related files | **High** |
| Update `gate_exceptions.json` gateId | **Medium** |
| Verify downstream gates still resolve correctly | **Medium** |
| Set calendar reminder to re-evaluate quarantine TTL (2026-07-19) | **Low** |

**Net result**: One gate instead of two. Same checks. Same results. Half the execution time. No behavioral change for developers.

---

## 8. Appendix: nimtry-lite

No `nimtry-lite` gate exists in the current manifest or codebase. A grep for `nimtry-lite` across the entire repository returned zero results. This may have been a historical name or a planned variant that was never implemented.
