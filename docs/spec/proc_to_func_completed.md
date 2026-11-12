# proc→func Migration Status

## Overview

AGENTS.md §0.6 mandates that all core engine logic MUST default to `func`. The
`proc→func` migration converts pure procedures (no transitive I/O calls) from
`proc` to `func` to leverage Nim's compile-time effect system.

## Migration Status: COMPLETE

As of 2026-06-15, the automated migration pipeline reports:

| Metric | Value |
|--------|-------|
| Files scanned | 327 |
| Procs converted to func | 0 (remaining convertible procs) |
| Whitelist entries (impure) | 0 (newly discovered) |
| Status | **All convertible procs have been migrated** |

## Enforcement Layers

### 1. Compile-time Regression Guard

`src/core/trusted/architecture_invariants.nim` contains a static block that
counts `proc` declarations in `src/core/*.nim` at compile time via `gorge()`.
If the count exceeds 40 (38 known I/O boundary procs + 2 margin), compilation
fails with an error referencing AGENTS.md §0.6.

```nim
static:
  let procCount = gorge("grep -c '^proc ' src/core/*.nim 2>/dev/null || echo 0")
  let count = parseInt(procCount.strip)
  if count > 40:
    {.error: "proc→func regression: too many proc declarations in src/core/. Use func. See AGENTS.md §0.6".}
```

### 2. Nimtry Gate (CI)

`src/gate/nimtry/purity_queries.nim` enforces the proc→func policy via two
queries:

- **`safety-proc-purity`**: Reverse BFS from I/O modules identifies procs with
  no transitive I/O calls. These should be `func`.
- **`purity-new-code-must-be-func`**: Any `proc` declaration in a non-I/O
  module (`src/` excluding `src/cli/`, `src/mcp/`, `src/gate/runners/`) triggers
  an error. Legacy files and procs in the `impure_procedures_whitelist` are
  downgraded to warnings.

### 3. Auto-Conversion Pipeline

`tools/ci/auto_convert_proc_to_func.py` performs automated bulk conversion with
iterative convergence. It:
1. Analyzes call graphs to determine which procs have transitive I/O.
2. Converts safe procs to `func`.
3. Builds a whitelist of impure procs that cannot be converted.
4. Reports non-side-effect errors for manual review.

## Whitelist Maintenance

The `impure_procedures_whitelist` in `src/gate/architecture_policy.lock`
enumerates procs that are genuinely impure (transitive I/O) and cannot be
converted to `func`. This list must be updated whenever:
- New impure procs are added to non-I/O modules.
- Existing procs are refactored to remove I/O calls (remove from whitelist).

## Key Files

| File | Role |
|------|------|
| `src/core/trusted/architecture_invariants.nim` | Compile-time regression guard |
| `src/gate/nimtry/purity_queries.nim` | Nimtry gate queries |
| `tools/ci/auto_convert_proc_to_func.py` | Automated conversion pipeline |
| `src/gate/architecture_policy.lock` | Whitelist SSOT |
| `AGENTS.md §0.6` | Policy SSOT |

## References

- AGENTS.md §0.6 — Static First Enforcement
- `docs/spec/nim_effect_system_quirks.md` — Nim side-effect quirks registry
- GUARDIAN §17 — Constructor pattern for `noSideEffect` false positives
