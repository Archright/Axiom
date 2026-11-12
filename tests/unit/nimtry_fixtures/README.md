# Nimtry Synthetic Violation Fixtures

## Purpose

These fixtures are intentionally-bad Nim modules that should trigger architecture
policy violations (SoC, SOLID, SSOT, DRY). They are used by `run_all_fixtures.nim`
to validate that `bin/nimtry` correctly detects violations.

## Why Fixtures Must Be at Matching Layer Paths

`bin/nimtry` uses `layerForPath()` (defined in `src/gate/architecture_policy.nim`)
to determine which architectural layer a file belongs to. The policy layers are
defined as path globs in `src/gate/architecture_policy.lock`:

```toml
[layer]
core = "src/core"
cli = "src/cli"
mcp = "src/mcp"
verification = "src/verification"
gate = "src/gate"
```

A file at `tests/unit/nimtry_fixtures/soc_violation.nim` does **not** match any
of these patterns, so `layerForPath()` returns `""` (empty string), and all
layer-dependent checks are skipped — the fixture passes instead of failing.

## Test Runner (`run_all_fixtures.nim`)

The test runner works around this by:

1. Creating a temporary directory (e.g., `/tmp/nimtry_fixtures_XXX/`)
2. Copying the architecture policy to `src/gate/architecture_policy.lock`
3. Copying each fixture to a matching `src/<layer>/<fixture>.nim` path
4. Running `bin/nimtry` with **relative paths** from within the temp dir
5. Verifying the expected violations appear in the output
6. Cleaning up the temp directory

Using relative paths is critical because `bin/nimtry` strips the repo-root
prefix via `normalizedPath()`, and loads the policy relative to `getCurrentDir()`.

## Fixture Summary

| Fixture | Target Layer | Expected Violations | Status |
|---------|-------------|---------------------|--------|
| `soc_violation.nim` | `src/core/` | 3× [SoC] [soc-layer-imports] | ✅ PASS |
| `solid_srp_violation.nim` | `src/core/` | [SOLID] [soc-surface-area] (23 fns, max 15), [SOLID] [solid-ocp] (6 branches, 0 registry calls) | ✅ PASS |
| `ssot_violation.nim` | `src/cli/` | [SSOT] [ssot-type-placement] (ValidatedAsi outside metrics.nim) | ✅ PASS |
| `dry_violation.nim` + `dry_violation_b.nim` | `src/core/` | 2× [SOLID] [solid-srp] (LCOM > 0.6) | ✅ PASS |
| `solid_dip_violation.nim` | `src/cli/` | Known limitation — current policy [forbidden_calls] uses callee-name keys, not path patterns | ⚠️ Known |

## Known Limitation: `solid_dip_violation`

The `solid_dip_violation.nim` fixture documents that the current
`architecture_policy.lock` `[forbidden_calls]` section uses callee names as
keys (e.g., `"z3ExecPersistent" = { ... allowedCallers = ["src/core"] }`),
but `checkForbiddenCallsWrapper` in `solid_queries.nim` matches file paths
against allowed-caller patterns. The call extraction (via PNode parser)
correctly identifies the calls; the issue is that the policy lookup cannot
resolve callee names to path patterns.

To enable this check, the `[forbidden_calls]` section would need path-pattern
keys such as:
```toml
[forbidden_calls]
"src/**" = ["z3ExecPersistent", "z3Spawn"]
```

Or the `[forbidden_call_patterns]` section could be extended with broader
caller patterns.

## Running

```bash
cd /path/to/Axiom_Enterprise-core
nim c -r tests/unit/nimtry_fixtures/run_all_fixtures.nim
```
