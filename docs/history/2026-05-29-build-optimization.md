# Build Optimization: Sub-Second Warm Build

## Problem

`ax.nim` warm build took **~9 seconds** despite shared nimcache. Root cause analysis revealed two accidental bottlenecks:

1. **`config.nims` ran `all_gateway_runner` (~6.7s) for EVERY `nim c` invocation** via `gorgeEx` compile-time gate bond. With 6 targets, this wasted **~40s per `refresh_cli_binaries` run**.
2. **`main.nim` and `ax.nim` were compiled as separate binaries** despite sharing 99.5% of code.
3. **`trackedSourceFiles()` used incorrect paths** (`cli/main.nim` instead of `src/cli/main.nim`), causing `--only-if-stale` to silently skip source files and fail to detect staleness.

## Changes

### Gate Bond Deduplication

- `scripts/refresh_cli_binaries.nim`: Run `all_gateway_runner` ONCE at startup, then set `gate bonding=1` for all child `nim c` processes.
- Saves **~6.7s per target** by eliminating redundant compile-time gate bond execution.

### Merge `main` and `ax` Binaries

- `src/cli/main.nim`: Ported `ax.nim` behaviors (`--version`/`-v` handling, `cached` global flag) into `main.nim` `isMainModule` block.
- `scripts/refresh_cli_binaries.nim`: Removed `ax.nim` compilation target. Replaced with cross-platform link:
  - Unix: `createSymlink("main", "bin/ax")`
  - Windows: `copyFile("bin/main", "bin/ax")` (symlink requires admin privileges)
- Eliminates one redundant target entirely.

### Sequential Compilation for Shared Nimcache Safety

- Shared nimcache is **not safe for parallel target compilation** because multiple `nim c` processes can race on C code generation for the same module.
- Default `jobs=1` unless `AXIOM_BUILD_JOBS` is explicitly set.
- Prevents linker undefined reference errors caused by cache corruption.

### Bug Fixes

- `src/cli/procedure_gate.nim`: Fixed commit type parsing for scoped types (`refactor(build)` → `refactor`).
- `src/cli/procedure_gate.nim`: Allow merge commits (no colon) to pass validation.
- `scripts/refresh_cli_binaries.nim`: `trackedSourceFiles()` now uses `joinPath(root, path)` to produce correct file paths.

## Verification

- `nim check` passes for `scripts/refresh_cli_binaries.nim`, `src/cli/main.nim`, `src/cli/procedure_gate.nim`
- `bin/ax --version` outputs `v0.3.6` correctly
- Full build (`refresh_cli_binaries` with 5 targets) completes in ~40s cold, ~1s when up-to-date
- `--incremental:on` evaluated but rejected: causes internal compiler error (`=copy operator not found for type string`)

## Files Modified

- `scripts/refresh_cli_binaries.nim`
- `src/cli/main.nim`
- `src/cli/procedure_gate.nim`
- `tests/features/refresh_cli_binaries.feature`
- `tests/unit/procedure_gate_test.nim`

## Related

- Plan: `wasp-animal-man-longshot.md`
- Phase 4 (shared nimcache): `docs/history/2026-05-29-gate-memoization.md`


### Phase 2: Unified Binary (Single Frontend Pass)

- Created `src/cli/axiom_unified.nim`: Imports `main`, `server`, `unified_sentry` and dispatches via `paramStr(0)` basename.
- Refactored entry points to export `run*` procs:
  - `src/cli/main.nim` → `runMain*(args)`
  - `src/mcp/server.nim` → `runServer*(args)`
  - `src/gate/runners/unified_sentry.nim` → `runUnifiedSentry*(args)`
- `scripts/refresh_cli_binaries.nim`: Compiles `axiom_unified` once; creates aliases (`main`, `ax`, `server`, `unified_sentry`) via symlinks/copies.
- Keeps `gate_hook` and `all_gateway_runner` as separate targets (different import graphs).

### Result

| Metric | Before | After Phase 1 | After Phase 2 |
|--------|--------|---------------|---------------|
| Targets compiled | 6 | 5 | 3 |
| Cold build total | ~60s+ | ~43s | **~18s** |
| Up-to-date check | N/A | ~1s | **~0.4s** |
| Frontend passes | 6 | 5 | **3** |

### Additional Verification

- `bin/axiom --version` → `v0.3.6`
- `bin/main --version` → `v0.3.6` (symlink dispatch)
- `bin/pre-commit` (symlink) → runs pre-commit tier chain correctly
- `--only-if-stale` → ~0.4s when up-to-date

### Additional Files Modified

- `src/cli/axiom_unified.nim` (new)
- `src/mcp/server.nim`
- `src/gate/runners/unified_sentry.nim`
