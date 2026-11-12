# Legacy Violations Quarantine Registry

**Date**: 2026-06-12  
**Action**: Ratchet Effect quarantine of pre-existing nimtry violations  
**SSOT Authority**: `src/gate/architecture_policy.lock` §`[legacy_violations]`  
**File List SSOT**: `data/legacy_violations.txt`

---

## Summary

| Metric | Value |
|--------|-------|
| Total files quarantined | 504 |
| Total violations tolerated | 1,232 |
| Quarantine method | `architecture_policy.lock` `[legacy_violations]` section |
| Enforcement tool | `src/gate/nimtry/nimtry_cli.nim` |

---

## Violation Categories

### SAFETY (796 violations)

| Sub-category | Count | Description |
|--------------|-------|-------------|
| SAFETY-unbalanced-pragma-stack | 401 | Unbalanced `{.push}` / `{.pop}` pragma stacks |
| SAFETY-no-try-in-no-raise | 196 | `try` blocks in `{.raises: [].}` contexts |
| SAFETY-proc-purity | 112 | `proc` declarations with no transitive I/O (should be `func`) |
| SAFETY-unsafe-parse | 53 | Unsafe parse operations without error handling |
| SAFETY-no-main-module-in-src | 21 | `isMainModule` blocks in `src/` (belongs in `tests/`) |
| SAFETY-duplicate-import | 11 | Redundant duplicate import statements |
| SAFETY-hardcoded-home | 2 | Hardcoded home directory paths |

### SOLID (331 violations)

| Sub-category | Count | Description |
|--------------|-------|-------------|
| solid-srp | 26 | LCOM cohesion threshold violations (SRP breach) |
| solid-ocp | 67 | Case-branch count without registry pattern (OCP breach) |
| solid-forbidden-pragmas | 17 | Use of `{.dynlib.}` / `{.importc.}` outside allowed callers |
| solid-forbidden-calls | 3 | Direct solver backend calls outside allowed callers |

*Note: SOLID sub-total above = 113. The remaining 218 violations are `soc-surface-area` (function length / exported count / import count overages) classified under SOLID by nimtry.*

### SoC (68 violations)

| Sub-category | Count | Description |
|--------------|-------|-------------|
| soc-layer-imports | 24 | Cross-layer import violations (e.g., `core` → `verification`) |
| SOC-domain-placement | 22 | Domain logic in wrong layer |
| SOC-leaf-module-imports | 21 | Leaf modules importing non-leaf modules |
| SoC (general) | 1 | General separation-of-concerns |

### SSOT (35 violations)

| Sub-category | Count | Description |
|--------------|-------|-------------|
| SSOT-type-duplication | 34 | Duplicate type definitions across modules |
| SSOT-type-placement | 1 | Type defined outside canonical SSOT module |

### SECURITY (2 violations)

| Sub-category | Count | Description |
|--------------|-------|-------------|
| SECURITY-weak-hash | 2 | Use of weak hash algorithm |

---

## Excluded from Quarantine

The following categories were **excluded** (being handled separately):

| Category | Count | Status |
|----------|-------|--------|
| FEATURE-zombie-runner | 36 | Deleted separately |
| HYGIENE-when-isMainModule-in-test | 7 | Deleted separately |

---

## Ratchet Effect Policy

### Principle

Files listed in `data/legacy_violations.txt` have **pre-existing violations that are tolerated** — the violations existed before this quarantine was established.

### Forced Evolution Rule

> **When a quarantined file is MODIFIED, it MUST comply with ALL architecture rules.**

This means:
1. A developer or agent touches a quarantined file → ALL violations in that file must be fixed as part of the same change.
2. The "legacy tolerance" applies only to **untouched** files.
3. Each modification is an opportunity to ratchet the codebase toward compliance.

### Zero Tolerance for New Debt

> **New files MUST NOT create violations.**

Any new `.nim` file added to `src/` that triggers nimtry violations will be rejected at gate time. There is no quarantine path for new code.

### Enforcement

The `[legacy_violations]` section in `architecture_policy.lock` is read by:
- `src/gate/nimtry/nimtry_cli.nim` — architecture principle gate
- Pre-commit hooks — incremental check on changed files

The `file_list` field points to `data/legacy_violations.txt` which contains one file path per line. The `enabled` flag allows the quarantine to be toggled without removing the file list.

---

## Appendix: File Distribution by Layer

| Layer | Files | Percentage |
|-------|-------|------------|
| `src/core/` | 307 | 60.9% |
| `src/gate/` | 80 | 15.9% |
| `src/verification/` | 74 | 14.7% |
| `src/cli/` | 26 | 5.2% |
| `src/personas/` | 6 | 1.2% |
| `src/ui/` | 4 | 0.8% |
| `src/mcp/` | 4 | 0.8% |
| `src/sieve/` | 6 | 1.2% |
| `src/api/` | 1 | 0.2% |
| `src/engine/` | 1 | 0.2% |
| **Total** | **504** | **100%** |
