# Structural Audit Report — Axiom Codebase
**Date**: 2026-05-29  
**Methodology**: 5 parallel subagent decomposition + shell cross-check + AGENTS.md §1.2 architecture table as canonical SSOT  
**Scope**: 1,484 files across entire working tree  
**Principles**: Ideal / Elegant / Fundamental / Deterministic (AGENTS.md §0.3)

---

## 1. Executive Summary

| Severity | Category | Count | First-Principle Violated |
|----------|----------|-------|--------------------------|
| **P0** | SSOT / Layer Boundary | 5 | Ideal (compile-time prevention breach) |
| **P1** | SoC Misplacement (root/docs/src) | 14 | Elegant (language-native structure abuse) |
| **P2** | Non-canonical directory / Naming | 20 | Fundamental (undocumented layers) |
| **P3** | Tracked runtime artifact | 4 | Deterministic (ephemeral → persistent leak) |
| **Total** | — | **43** | — |

---

## 2. P0 — SSOT & Layer Boundary Breaches (Fundamental)

> *"Types → `domain_types.nim`; Certificates → `certificate_manager.nim`; ASI → `metrics.nim`."* — AGENTS.md §1.3  
> *"Domain never imports Infrastructure, Presentation, or Gate."* — AGENTS.md §1.2

### 2.1 `domain_types.nim` SSOT Breach
| File | Size | Issue |
|------|------|-------|
| `src/core/domain_types.nim` | 11,205 B | Canonical Domain type SSOT |
| `src/gate/domain_types.nim` | 1,523 B | **Gate redefines Domain types** — direct SSOT violation |

**Rationale**: Gate layer MUST import from `core/domain_types.nim`, not maintain a shadow copy. Two type definitions diverge over time → fingerprint mismatches → ASI degradation.

### 2.2 Infrastructure ↔ Gate Circular Edge
| File | Layer | Imports | Violation |
|------|-------|---------|-----------|
| `src/verification/proof_state_builder.nim` | Infrastructure | `../gate/architecture_policy` | Infra depends on Gate |
| `src/gate/convergence_sidecar.nim` | Gate | `../verification/proof_state_convergence` | Gate depends on Infra |

**Rationale**: Creates a compile-time circular dependency risk. Gate must remain read-only and independent.

### 2.3 Gate Logic Living in Infrastructure Layer
| File | Current | Correct | Issue |
|------|---------|---------|-------|
| `src/verification/gate_registry.nim` | `src/verification/` | `src/gate/` | Gate code in Infra |
| `src/verification/gate_rules.nim` | `src/verification/` | `src/gate/` | Gate code in Infra |
| `src/verification/gate_rules_architecture.nim` | `src/verification/` | `src/gate/` | Gate code in Infra |
| `src/verification/gate_rules_module_classifier.nim` | `src/verification/` | `src/gate/` | Gate code in Infra |
| `src/verification/gate_rules_normalization.nim` | `src/verification/` | `src/gate/` | Gate code in Infra |

---

## 3. P1 — SoC Misplacement (Elegant)

### 3.1 Root Directory Clutter
Files that belong in categorized subdirectories:

| File | Correct Location | Violation | Notes |
|------|------------------|-----------|-------|
| `analyze_docs_final.py` | `scripts/` or remove | SoC + **Language Ban** | Python is banned per AGENTS.md §1.1 (Nim only; exceptions: Lean 4, Markdown, build configs) |
| `run_nimcheck.sh` | `scripts/` | SoC | Build utility |
| `run_nimcheck_all.sh` | `scripts/` | SoC | Build utility |
| `code_complexity_report.md` | `docs/reports/` | SoC | Generated report |
| `dependency_health_report.md` | `docs/reports/` | SoC | Generated report |
| `doc_gap_analysis.txt` | `docs/evidence/analysis/` | SoC | Analysis artifact |
| `doc_gap_analysis_report.txt` | `docs/reports/` | SoC | Report output |
| `proof_universe.lock` (root) | Remove (keep `logs/` copy only) | SSOT | Duplicate of `logs/proof_universe.lock` |
| `CODEBASE_INVENTORY.md` | `docs/reports/` | SoC | Generated inventory |

### 3.2 `docs/` Root Clutter
| File | Correct Location | Violation |
|------|------------------|-----------|
| `docs/false-positives.md` | `docs/spec/false-positives.md` | Categorical misplacement |
| `docs/known-limitations.md` | `docs/spec/known-limitations.md` | Categorical misplacement |

### 3.3 `src/` Artifact Pollution
| File | Correct Location | Violation |
|------|------------------|-----------|
| `src/.build_hash` | `build/` or project root | Build artifact in source tree |
| `src/allowed_imports.lock` | Project root or `config/` | Config file in source tree |
| `src/core/.physically_impure_modules` | `docs/` / `verifications/` | Audit marker in Domain |

---

## 4. P2 — Non-canonical Directories & Naming (Fundamental)

### 4.1 Undocumented `src/` Directories
These directories exist but are **absent from AGENTS.md §1.2 architecture table**:

| Directory | File Count | Import Direction | Architectural Assignment Needed |
|-----------|------------|------------------|--------------------------------|
| `src/engine/` | 1 | → Domain | Merge into `core/` or document as Infra |
| `src/frontend/` | 4 | → Domain | Merge into `core/` or document as Presentation |
| `src/translator/` | 2 | → Domain, → Infra | Merge into `verification/` or document as Infra |
| `src/types/` | 1 | → Domain | **Merge into `core/types/`** (redundant sibling) |
| `src/metrics/` | 1 | → Domain | Document as Presentation or merge |
| `src/personas/` | 5 | → Domain, → Infra | Document as Presentation or merge |
| `src/semantic_proofs/` | 0 (Lean only) | N/A | Acceptable — Lean 4 exception per §1.1 |

### 4.2 `scripts/` vs `bin/` vs `src/gate/` Confusion
| File | Current | Correct | Issue |
|------|---------|---------|-------|
| `scripts/gate_replay` | `scripts/` | `bin/gate_replay` | **Compiled ELF binary** in scripts/ |
| `scripts/gate_hook.nim` | `scripts/` | `src/gate/gate_hook.nim` | Gate source in scripts/ |
| `scripts/nim_check_gate.nim` | `scripts/` | `src/gate/runners/nim_check_gate.nim` | L2 gate source in scripts/ |
| `scripts/gateway_test_gate.nim` | `scripts/` | `src/gate/runners/gateway_test_gate.nim` | L2 gate source in scripts/ |
| `bin/nimtry_old` | `bin/` | **Delete** | Stale artifact; zero references |
| `scripts/deprecated/backfill_winning_strategies.nim` | `scripts/deprecated/` | **Delete** | Unreferenced; listed as deprecated in CODEBASE_INVENTORY |
| `scripts/deprecated/promote_green_to_verified_axiom.nim` | `scripts/deprecated/` | **Delete** | Unreferenced; listed as deprecated in CODEBASE_INVENTORY |

### 4.3 `tests/` Root Misplacement
| File | Target | Rename Required | Convention Broken |
|------|--------|-----------------|-------------------|
| `audit_unification_test.nim` | `tests/unit/` | No | Location |
| `ax_tui_reporter_test.nim` | `tests/unit/` | No | Location |
| `gate_registry_test.nim` | `tests/unit/` | No | Location |
| `integrity_check.nim` | `tests/unit/` | **→ `integrity_check_test.nim`** | Missing `_test` suffix + Location |
| `liquid_inference_test.nim` | `tests/unit/` | No | Location |
| `pipeline_lean_spec_inference_test.nim` | `tests/unit/` | No | Location |
| `pipeline_trace_artifacts_test.nim` | `tests/unit/` | No | Location |
| `test_nimtry_plugin.nim` | `tests/unit/` | **→ `nimtry_plugin_test.nim`** | `test_*` prefix → should be `*_test` |
| `test_nimtry_plugin` (binary) | `bin/` or `.gitignore` | No | Binary in `tests/` + missing ignore entry |
| `unit_test_orchestrator.nim` | `tests/unit/` | No | Infrastructure location |

### 4.4 Evidence SSOT Divergence
| Directory | Issue |
|-----------|-------|
| `verifications/` (16 `.txt` files) | Separate root-level evidence directory while `docs/evidence/` is declared SSOT. Format inconsistency (`.txt` vs `.md`). |

---

## 5. P3 — Tracked Runtime Artifacts (Deterministic)

| File/Pattern | Issue |
|--------------|-------|
| `logs/proof_universe.lock` | **Tracked in Git** despite being ephemeral lock file. Should be generated into `/tmp/` or `.cache/` |
| `logs/axiom.db` | SQLite DB — runtime artifact |
| `logs/axiom_vault.idx` | Index file — runtime artifact |
| `logs/*.cache.json` (6 files) | Cache JSONs — runtime artifacts |
| `logs/asi_cache.json` | Cache — runtime artifact |
| `logs/topology_cache.json` | Cache — runtime artifact |

**Rationale**: These files are deterministic function outputs, not source. Tracking them creates merge conflicts and violates the Zero-Footprint Integrity principle.

---

## 6. Remediation Roadmap

### Phase 1 — P0 SSOT/Layer (Breaking Risk)
1. Merge `src/gate/domain_types.nim` into `src/core/domain_types.nim`; update Gate imports
2. Break `src/verification/proof_state_builder.nim` → `gate/architecture_policy` dependency
3. Break `src/gate/convergence_sidecar.nim` → `verification/proof_state_convergence` dependency
4. Move `src/verification/gate_*.nim` → `src/gate/`

### Phase 2 — P1 SoC (Clutter Reduction)
5. Move all root `.sh`, `.py`, `.md` reports to categorized subdirectories
6. Remove duplicate `proof_universe.lock` from root
7. Move `src/.build_hash`, `src/allowed_imports.lock` to project root or `config/`
8. Move `docs/false-positives.md`, `docs/known-limitations.md` → `docs/spec/`

### Phase 3 — P2 Canonicalization (Structural Hygiene)
9. Move `scripts/gate_replay` → `bin/gate_replay`
10. Move gate sources from `scripts/` → `src/gate/runners/` (update `axiom.nimble`)
11. Delete `bin/nimtry_old` and `scripts/deprecated/*`
12. Move `tests/*.nim` (root) → `tests/unit/` with correct naming
13. Consolidate `verifications/` → `docs/evidence/verifications/` with `.md` conversion

### Phase 4 — P3 Cleanup (Ephemeral Artifact Purge)
14. `git rm --cached logs/proof_universe.lock`
15. Add `logs/*.db`, `logs/*.idx`, `logs/*.cache.json`, `logs/asi_cache.json`, `logs/topology_cache.json` to `.gitignore` if not already covered

---

## 7. Deterministic Verification Checklist

After remediation, the following shell commands must all return **zero matches**:

```bash
# P0: No duplicate domain_types
[ $(find src -name "domain_types.nim" | wc -l) -eq 1 ] || echo "FAIL: domain_types SSOT"

# P0: No gate code in verification/
find src/verification/ -name "gate_*.nim" | wc -l   # must be 0

# P1: No shell scripts in root
find . -maxdepth 1 -name "*.sh" | wc -l           # must be 0

# P1: No Python in root
find . -maxdepth 1 -name "*.py" | wc -l           # must be 0

# P2: No tests in tests/ root
grep -L "^import" tests/*.nim 2>/dev/null | wc -l  # must be 0 (after move)

# P3: No tracked lock in logs/
git ls-files logs/*.lock | wc -l                  # must be 0
```

---

*Report generated by parallel subagent decomposition per AGENTS.md §2.6a Mandatory Parallel Decomposition Protocol.*
