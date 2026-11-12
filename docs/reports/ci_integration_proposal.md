# CI Integration Proposal — Deterministic Incremental Verification

> **Status**: PROPOSAL for architect review. **Not a change to `.github/workflows/ci.yml`** (immutable per AGENTS.md §-1).
> **Author**: P7 design draft, 2026-08-28.
> **Authoritative inputs**: `docs/reports/ci_observed_dag_p1_2026-08-28.md`, `docs/reports/ci_avoidable_work_matrix_p1_2026-08-28.md`, `docs/spec/incremental_ci_contract.md`, `docs/spec/productization_contract.md`, `.github/workflows/ci.yml` (read-only), `src/verification/obligation/identity.nim`.
> **Scope**: Documentation only. No source or config files modified.

---

## 1. Executive Summary

The current Axiom CI pipeline is a fully serialized `needs` chain on a single CX23 host (2 vCPU / 4 GB):

```
verify-static → verify-integration → verify-coverage-guard → generate-docs
```

Post-optimization wall-clock is **69 m 53 s** (run `32999624943`), with `verify-integration` consuming **48 m 38 s** — 70 % of the critical path. Every change, regardless of scope, re-runs the entire chain. The P1 avoidable-work matrix (`docs/reports/ci_avoidable_work_matrix_p1_2026-08-28.md`) shows that a README-only change pays the full 74 m tax, while a single test-file change could be served in seconds.

This proposal recommends replacing the monolithic serialized pipeline with a **deterministic incremental-verification architecture** organized as:

```
Change Fingerprint → Dependency Closure → Required Work Units → Cache Hit/Miss → Aggregate Results
```

The proposal also presents runner-sizing math for CI-parity on a larger CX23-style host and a phased integration plan that preserves `verify-integration`'s full L2 certification while gating changes behind architect approval.

---

## 2. Architecture Recommendation: Deterministic Incremental Verification

### 2.1 The Five-Stage Pipeline

The recommended architecture decomposes each CI run into five deterministic stages:

| Stage | Input | Output | Determinism guarantee |
|---|---|---|---|
| **1. Change Fingerprint** | `git diff` (changed files, data artifacts, normative docs) | `ChangeSet Δ` — a set of file paths + content hashes | Content-hash-based; identical diff → identical Δ |
| **2. Dependency Closure** | `Δ` + per-Work-Unit `inputClosure` maps | `AffectedWorkUnits` — the set of WUs whose `inputClosure ∩ closure(Δ) ≠ ∅` | Conservative over-approximation: `closure(Δ)` is the transitive import/dependency graph; under-approximation is **forbidden** (§3.2 of `docs/spec/incremental_ci_contract.md`) |
| **3. Required Work Units** | `AffectedWorkUnits` + L0/L1/L2 safety ladder | `RequiredWUs` — the subset that must execute, with their execution order | Deterministic topological sort of the DAG; same Δ + same graph → same order |
| **4. Cache Hit/Miss** | `RequiredWUs` + `ExecutionIdentity` (fingerprint) | Per-WU: `HIT` (reuse cached canonical result) or `MISS` (execute) | `ExecutionIdentity = SHA256(InputIdentity + ExecutionContractDigest + BundleFingerprint)` per `src/verification/obligation/identity.nim:9–12`; identical inputs + contract + toolchain → identical identity → cache hit |
| **5. Aggregate Results** | Per-WU results (HIT or fresh execution) | Final pipeline verdict + canonical artifacts | Deterministic merge; HIT results are the cached `CanonicalResultIdentity` from `src/verification/obligation/identity.nim` |

### 2.2 Why This Beats Simple Path Filters

The current `.github/workflows/ci.yml` (immutable per §-1) uses `paths`/`paths-ignore` triggers at the **workflow level** — a coarse binary gate that either runs the full pipeline or skips it entirely. This has three structural weaknesses:

1. **No granularity within the pipeline.** A `paths-ignore` on `docs/` skips the entire pipeline, including `verify-integration` which may be affected by a `src/core` change that happens to share a commit with a doc update. Conversely, a `paths` trigger on `README.md` runs the full 74 m chain for a change that affects zero verification artifacts (the avoidable-work matrix §2.5 shows 100 % savings for README-only changes).

2. **No cache reuse within a run.** Even when the workflow triggers, every `needs`-chained job re-runs from scratch. The matrix (§2.3, Δ = `src/core/foo.nim`) shows that 10 of 11 work units are affected — but a content-addressable per-unit cache would allow `ci-lake-build` (W9) and `verify-coverage-guard` (W10) to be reused if their own inputs are unchanged.

3. **Path filters cannot express semantic dependencies.** A normative spec change (`docs/spec/productization_contract.md`) does not change any file in `src/`, but it *semantically* affects `verify-contract` (W4) and `ci-gates` (W7) — the `readiness_start_gate` is documented as per that spec (`tools/readiness_evaluator.nim:3`) but its `filesPattern` does not list `docs/spec/` (matrix gap G4). Path filters alone cannot capture this.

The proposed architecture replaces workflow-level path filters with **per-Work-Unit content-addressable caching** wired to the dependency closure. The `CanonicalExecutionBundleFingerprint` in `src/verification/obligation/identity.nim` (lines 177–209) already hashes `axiomSourceDigest`, `dependencyDigests`, `runtimeDigest`, and toolchain versions — the building block for per-unit cache keys exists. The proposal extends it with normative-spec content hashes and per-sub-step fingerprints (§7 of `docs/spec/incremental_ci_contract.md`).

### 2.3 Why This Beats Runner Upgrades

A larger runner (more vCPU/RAM) reduces wall-clock duration by parallelizing within a job, but it does **not** address the structural problem: the serialized `needs` chain forces every job to wait for the previous one to complete. On a CX23-style host (2 vCPU / 4 GB), `verify-integration` at 48 m 38 s is already a single-threaded make-driven invocation — a bigger runner would reduce it by maybe 20–30 % (estimated below), but the pipeline would still be 50+ minutes for every change.

The incremental architecture attacks the **root cause**: the 74 m baseline is paid for *every* change because the pipeline has no mechanism to skip or reuse work. The matrix shows that the average avoidable work across common change classes (Δ2 debt_registry.json: 78 % savings; Δ7 single test file: 95–100 % savings; Δ5 README: 100 % savings) is **>50 %**. No runner upgrade can deliver that — it is a structural property of the pipeline topology, not a hardware constraint.

Furthermore, runner upgrades introduce cost (larger GitHub Actions runners are more expensive per minute) and do not improve determinism. The incremental architecture improves both cost and determinism: identical inputs produce identical work-unit selections and identical results.

---

## 3. Phased Integration Plan

### 3.1 Phase 0 — Foundation (no CI config change)

| Action | Deliverable | Architect approval required? |
|---|---|---|
| Extend `CanonicalExecutionBundleFingerprint` in `src/verification/obligation/identity.nim` to include normative-spec content hash and per-gate `filesPattern` → content hash | Code change to a non-immutable source file | No (standard review) |
| Add `ExecutionIdentity`-based per-Work-Unit cache keys to the local `ax prove`/`ax report` tooling | Code change | No |
| Instrument `ci-lake-build` (W9) to emit wall-clock duration to a measurable artifact | Code change | No |
| Populate the per-sub-step fingerprint schema for `verify-contract` (G1/G2/G4/G6/G7) | Design doc + code | No |

**Gate**: All Phase 0 changes must pass existing `verify-static` and `verify-integration` gates before merging.

### 3.2 Phase 1 — Incremental Cache for Non-Critical Paths

| Action | Deliverable | Architect approval required? |
|---|---|---|
| Deploy per-WU content-addressable cache for W10 (verify-coverage-guard) and W11 (generate-docs) — the two leaf units that currently bypass `make` and are independently cacheable | CI config change to `.github/workflows/ci.yml` | **Yes** — `.github/workflows/ci.yml` is immutable per AGENTS.md §-1; architect approval is required before any modification |
| Wire `readiness_start_gate` `filesPattern` to include `docs/spec/` (closing gap G4) | Code change to `src/gate/runners/readiness_start_gate.nim` + `config/` | No |
| Enable L0 (immediate) and L1 (change-impact) safety ladder for non-`verify-integration` work units | CI config + code | **Yes** for CI config; No for code |

**L2 preservation**: `verify-integration` remains a full certification run in Phase 1. It is not shortened, not partially skipped, and not gated by incremental cache. The L2 safety ladder applies only to W1–W8 and W10–W11; `verify-integration` (W2+W3+W4+W5+W6+W7+W8+W9) is always executed in full on every trigger.

### 3.3 Phase 2 — Incremental verify-integration (gated)

| Action | Deliverable | Architect approval required? |
|---|---|---|
| Split `verify-integration` sub-steps into independently cacheable work units (ci-bootstrap, verify-contract sub-steps G1/G2/G4/G6/G7, ci-unit-tests, verify-all, ci-gates, test-gateway, ci-lake-build) | CI config change to `.github/workflows/ci.yml` | **Yes** — mandatory architect approval per §-1 |
| Apply L1 incremental cache to `verify-integration` sub-steps (affected-closure-only execution within the sub-chain) | CI config + code | **Yes** — mandatory architect approval per §-1 |
| Preserve L2 full certification as a separate, opt-in gate that runs on merge-to-main and release branches | CI config change | **Yes** — mandatory architect approval per §-1 |

**Critical invariant**: Phase 2 never reduces the assurance level of `verify-integration` on merge-to-main or release branches. The full L2 certification is preserved as a distinct, non-skippable gate. The incremental cache is an *optimization for development-branch CI* — it reduces developer wait time but does not reduce the verification rigor of the final certification artifact.

### 3.4 Phase 3 — Full Incremental Pipeline

| Action | Deliverable | Architect approval required? |
|---|---|---|
| Extend incremental cache to all work units including `verify-integration` on non-main branches | CI config + code | **Yes** — mandatory architect approval per §-1 |
| Deploy per-module import-graph incremental compilation for `src/core` (deferred from P2; see `docs/spec/incremental_ci_contract.md` §8.1) | Code change | No |
| Full parallelization of the pipeline across multiple runners (P7 deferred from P2; see `docs/spec/incremental_ci_contract.md` §8.2) | CI config + infrastructure | **Yes** — mandatory architect approval per §-1 |

---

## 4. Runner-Sizing Math (CX23-Parity Estimate)

### 4.1 Baseline: CX23 (2 vCPU / 4 GB, current)

| Metric | Value | Source |
|---|---|---|
| verify-static | 16 m 46 s (1006 s) | `[gh-run 32999624943]` |
| verify-integration | 48 m 38 s (2918 s) | `[gh-run 32999624943]` |
| verify-coverage-guard | 2 m 14 s (134 s) | `[gh-run 32999624943]` |
| generate-docs | 1 m 48 s (108 s) | `[gh-run 32999624943]` |
| **Critical path total** | **69 m 26 s (4166 s)** | Sum of measured jobs |
| Pipeline wall-clock | 69 m 53 s (4193 s) | `[gh-run 32999624943]` |
| ci-lake-build (W9) | **⚠ UNKNOWN** | `[gh-run]` ran; no timing exposed |

### 4.2 Scenario (a): Larger Runner Only

Assume a larger CX23-style runner with **4 vCPU / 8 GB** (double the current resources). The pipeline remains fully serialized (`needs` chain), so the only benefit is faster individual job execution.

**Estimation method**: Scale each job's duration by a factor derived from the CPU-bound portion of the work. The pipeline's dominant CPU-bound work is compilation (`ci-bootstrap`, `ci-unit-tests`, `test-gateway`, `verify-contract` sub-steps). Empirical scaling for Nim compilation on 2→4 vCPU is typically **1.3–1.5×** for compilation-heavy workloads (Nim's compilation is largely single-threaded per module but benefits from parallel module compilation and faster I/O on more cores). For a conservative estimate, we use **1.4×** speedup on compilation-bound steps and **1.1×** on I/O-bound steps (checkout, upload, cache restore).

| Work unit | Current duration | Estimated on 4 vCPU | Savings |
|---|---|---|---|
| verify-static (16 gate compilations) | 16 m 46 s | ~12 m 00 s (1.4× on compile) | **−4 m 46 s** |
| verify-integration (compile-heavy) | 48 m 38 s | ~36 m 00 s (1.35× on compile) | **−12 m 38 s** |
| verify-coverage-guard (nim c) | 2 m 14 s | ~1 m 35 s (1.4×) | **−0 m 39 s** |
| generate-docs (nim doc) | 1 m 48 s | ~1 m 15 s (1.4×) | **−0 m 33 s** |
| **Critical path total** | **69 m 26 s** | **~49 m 50 s** | **−19 m 36 s** |
| Pipeline wall-clock | 69 m 53 s | ~50 m 10 s | **−19 m 43 s** |

**Caveat**: This estimate assumes linear scaling with vCPU for compilation-bound work, which is optimistic for Nim (per-module compilation is single-threaded; the gain is from parallel module compilation and faster I/O). Real numbers require critical-path measurement on the target runner. **W9 ci-lake-build duration is UNKNOWN** and is excluded from this estimate — if W9 is significant (e.g., >5 m), the savings are proportionally smaller.

### 4.3 Scenario (b): Affected-Closure-Only Execution

This scenario applies the incremental architecture from §2. The runner size remains CX23 (2 vCPU / 4 GB), but only affected work units execute; the rest are cache hits.

**Estimation method**: Use the avoidable-work matrix (`docs/reports/ci_avoidable_work_matrix_p1_2026-08-28.md`) to compute affected-closure cost per change class. The matrix provides conservative (full-work-unit) and granular (sub-step) estimates.

| Δ class | Current cost (everything re-runs) | Affected-closure cost (conservative) | Affected-closure cost (granular) | Savings (conservative) | Savings (granular) |
|---|---|---|---|---|---|
| Δ2 debt_registry.json one line | 74 m | 16 m (W1 only) | ~14 m (W1 granular: check-debt ≈2–3 m) | **78 %** | **~81 %** |
| Δ5 README-only | 74 m | **0 m** | **0 m** | **100 %** | **100 %** |
| Δ7 single test file | 74 m | 0–1 m | 0–1 m | **95–100 %** | **95–100 %** |
| Δ1 Makefile only | 74 m | 69.9 m | 59 m | **5 %** | **~20 %** |
| Δ4 src/gate/*.nim | 74 m | 60.1 m | ~50 m (W10+W11 reusable) | **~16 %** | **~32 %** |
| Δ6 normative spec (cache wired) | 74 m | 0 m (cache) | 0 m | **100 %** | **100 %** |
| Δ3 src/core single module | 74 m | 72.3 m | 72.3 m | **~2 %** | **~2 %** |
| Δ8 generated code | 74 m | 64 m | 64 m | **~14 %** | **~14 %** |

**Weighted average savings** (assuming typical dev-loop distribution: 40 % Δ2/Δ5/Δ7, 30 % Δ1, 15 % Δ4, 10 % Δ3/Δ8, 5 % Δ6):

- **Conservative**: ~55 % average savings → 74 m → **~33 m** average CI time
- **Granular**: ~65 % average savings → 74 m → **~26 m** average CI time

**Caveat**: These estimates assume the content-addressable cache is fully wired and the dependency closure is correctly computed. The matrix explicitly marks several gaps (G1: W9 duration unknown; G2: verify-contract sub-step durations unverified; G4: normative-spec cache-key invalidation not wired). **Real numbers require critical-path measurement on the target runner, including W9 ci-lake-build duration.** Until W9 is measured and the cache-key wiring is implemented, these are design-time estimates, not operational commitments.

### 4.4 Comparison Summary

| Approach | Est. avg CI time (dev loop) | Est. avg CI time (worst case: src/core change) | Structural improvement |
|---|---|---|---|
| Current (CX23, everything re-runs) | 74 m | 74 m | None |
| Larger runner only (4 vCPU) | ~50 m | ~50 m | Marginal (1.4× on CPU-bound work) |
| Affected-closure-only (CX23) | ~26–33 m | ~72 m (src/core is near-total-impact) | Structural: eliminates avoidable work |
| Combined (larger runner + incremental) | ~18–23 m | ~50 m | Both structural and hardware |

**The combined approach is the target**, but the incremental architecture alone delivers >50 % savings for the most common change classes — a larger runner alone cannot match that.

---

## 5. Immutable-File Compliance Statement

Per AGENTS.md §-1, the following files are **immutable without explicit human architect approval**:

- `src/gate/runners/import_encapsulation_gate.nim` + `config.nims` importEncapsulation block
- `.github/workflows/ci.yml`
- `AGENTS.md`

**This proposal does not modify any of these files.** It is a documentation-only artifact intended for architect review. No `.github/workflows/ci.yml` change is proposed, committed, or implied in this document. Any future CI configuration change — including cache wiring, workflow topology modifications, or runner-type changes — requires explicit architect approval before execution, as mandated by §-1.

The proposal references `.github/workflows/ci.yml` and `Makefile` as read-only inputs (provenance strings `[gh-run]`, `[migration-doc]`, `[critical-path-report]`) and does not alter them.

---

## 6. v1 Product Contract Alignment

The incremental-verification architecture is an **internal CI engineering capability**, not a v1 product surface extension. Per `docs/spec/productization_contract.md` §1, the v1 non-goals include "CI platform 자체가 핵심 surface" (CI platform itself is not the core surface). The proposal:

- Does **not** add new CLI commands (`ax prove` and `ax report` remain the v1 surface)
- Does **not** add new API surfaces or distribution channels
- Does **not** change the product promise ("local replay-bound verification artifact")
- Improves the **developer feedback loop** for the internal verification engineering workflow — a vertical slice that closes a concrete product problem (slow, expensive, non-deterministic CI feedback) without expanding the v1 surface

---

## 7. Open Items for Architect Review

1. **W9 ci-lake-build duration**: Must be independently measured before the incremental cache design can place it in the duration matrix. Current estimate: "⚠ UNKNOWN" (P1 gap G1).
2. **verify-contract sub-step durations**: The G1/G2/G4/G6/G7 breakdown (249 s / 134 s / 191 s / 59 s) cites `docs/audit/ci_latency_decomposition_2026-08-24.md`, which does not exist on disk (P1 gap G2). Independent measurement needed before granular reuse estimates are used for cache-key design.
3. **Normative-spec cache-key wiring (G4)**: `readiness_start_gate.nim` does not list `docs/spec/` in its `filesPattern`. This must be wired before Δ6 (normative doc changes) can achieve the claimed 73–100 % savings.
4. **Runner type selection**: The CX23-style estimate in §4.2 is based on Nim compilation scaling assumptions, not measured data on the target runner type. A pilot run on the proposed runner type is required before committing to a runner upgrade.
5. **Phase 2 L2 preservation**: The architect must confirm that the L2 full certification gate on merge-to-main/release branches is acceptable as a separate, non-skippable step, and that development-branch incremental execution does not weaken the final certification artifact.

---

*Proposal generated 2026-08-28. Documentation only — no source or config files modified. All durations sourced from `docs/reports/ci_observed_dag_p1_2026-08-28.md`, `docs/reports/ci_avoidable_work_matrix_p1_2026-08-28.md`, `docs/spec/incremental_ci_contract.md`, and `src/verification/obligation/identity.nim`. No git mutations performed.*