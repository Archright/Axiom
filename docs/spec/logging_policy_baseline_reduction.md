# Logging Policy Baseline Reduction Plan

## Initial Baseline (2026-06-17)

| Metric | Count |
|--------|-------|
| Total Errors | 73 |
| Total Warnings | 94 |
| Files with Violations | 148 |

### Breakdown by Rule

| Rule ID | Severity | Count |
|---------|----------|-------|
| `sensitive-data-leak` | error | 73 |
| `stdout-operational-logs` | warning | 94 |

## Reduction Timeline

| Date | Errors ≤ | Warnings ≤ | Rationale |
|------|----------|------------|-----------|
| 2026-06-17 | 73 | 94 | Initial baseline capture |
| 2026-07-15 | 50 | 70 | Phase 1: Migrate `stdout.write` → `stderr.write` in CLI layer (`src/cli/`) |
| 2026-08-15 | 25 | 40 | Phase 2: Migrate gate runners and core modules |
| 2026-09-15 | 0 | 10 | Phase 3: Complete migration; remaining ≤10 warnings are false-positive `echo` statements in test fixtures |

## Migration Approach

### `stdout-operational-logs` (warnings → target 0)

The migration replaces `stdout.write` with `stderr.write` for all operational/informational log output. Structured diagnostic output (JSON, machine-readable) that MUST go to stdout for piping is excluded.

**Pattern**: `stdout.write(...)` → `stderr.write(...)`

**Scope per phase**:
1. **Phase 1** (`src/cli/`): CLI output formatting, workflow rendering, debug mode
2. **Phase 2** (`src/gate/`, `src/core/`): Gate runners, audit engines, topology modules
3. **Phase 3** (remainder): Tests, verification pipeline, sieve modules

### `sensitive-data-leak` (errors → target 0)

Most of these are false positives — the pattern `(?i)password|api_?key|secret|token|credential` matches variable names and comments like `# Compute SHA256 hash` → matches "secret" in variable names.

**Options**:
1. Narrow the regex to match actual log output lines (e.g., require `echo`/`Log.` prefix)
2. Add file-level suppression comments for false-positive files
3. Rename variables/comments to avoid pattern matches

**Recommended**: Option 1 — refine the pattern in `logging_policy.json` to reduce false positives before attempting file-level fixes.

## Ratchet Rule

The `logging_policy_baseline.json` file captures the current error/warning counts at baseline time. The gate enforces a **non-increasing ratchet**:

- **Any increase** in errors or warnings → gate **FAIL**
- **Same or decrease** → gate **PASS**
- **`--update-baseline` flag**: When current counts ≤ baseline counts, rewrite the baseline file and PASS. This is used after completing a reduction milestone.

This ensures progress is monotonically improving — once a violation is fixed, it cannot regress.
