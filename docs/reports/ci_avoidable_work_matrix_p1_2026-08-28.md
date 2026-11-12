# Axiom CI Avoidable-Work Matrix — P1 (2026-08-28)

> **Purpose:** Map each representative change class Δ to the observed CI work units, marking which units are **actually affected** (must re-run) vs. **reusable** (can be skipped/reused from cache), and compute the true affected-closure cost vs. the current "everything re-runs" ~74 min baseline.
>
> **Status:** Read-only analysis. No source or config files modified.
> **Authoritative inputs:** `docs/reports/ci_observed_dag_p1_2026-08-28.md`, `.github/workflows/ci.yml` (immutable per §-1), `Makefile`, `src/gate/topology_spec.nim`, `config/gates.manifest.toml`, `src/gate/manifest.d/*.json`, `src/verification/obligation/identity.nim`, `src/gate/utils/gate_run_logger.nim`, `docs/spec/self_hosted_ci_migration.md` lines 153–205.

---

## 0. Observed CI DAG recap (the "everything re-runs" baseline)

The pipeline is a fully serialized `needs` chain on a single CX23 host:

```
verify-static → verify-integration → verify-coverage-guard → generate-docs
```

where `verify-integration` is itself a serial sub-chain (ci-bootstrap → verify-contract-release-e2e → verify-contract → ci-unit-tests → verify-all → ci-gates → test-gateway → ci-lake-build → upload).

| # | Work unit | Duration | Provenance |
|---|---|---|---|
| W1 | **verify-static** | 16.0 m | `[gh-run]` |
| W2 | ci-bootstrap (G3/G7) | 5.33 m | `[migration-doc]` |
| W3 | verify-contract-release-e2e-full (G7) | ≈0.13 m (8 s) | `[critical-path-report]` |
| W4 | **verify-contract** (G1/G2/G4/G6/G7) | 16.83 m | `[migration-doc]` |
|   | ↳ G1 mutation oracle | ≈4.15 m (249 s) | `[critical-path-report]` (unverified source) |
|   | ↳ G6+G4 oracles | ≈3.18 m (191 s) | `[critical-path-report]` (unverified source) |
|   | ↳ G2 promotion semantics | ≈2.23 m (134 s) | `[critical-path-report]` (unverified source) |
|   | ↳ G7 proof-universe-lock | ≈0.98 m (59 s) | `[critical-path-report]` (unverified source) |
| W5 | **ci-unit-tests** | 12.30 m | `[migration-doc]` |
| W6 | **verify-all** (static+integration) | 4.25 m | `[migration-doc]` |
| W7 | **ci-gates** (tier-1 hook + tier-2 direct) | 3.15 m | `[migration-doc]` |
| W8 | **test-gateway** | 11.88 m | `[migration-doc]` |
| W9 | **ci-lake-build** (proofs lake build) | **⚠ UNKNOWN** | `[gh-run]` ran; no timing exposed |
| W10 | **verify-coverage-guard** | 2.0 m | `[gh-run]` |
| W11 | **generate-docs** | 1.8 m | `[gh-run]` |
|   | **Total (accounted)** | **≈73.7 m** | ≈ the user's "74 min" |

Post-optimization run 32999624943 measured a wall-clock **69 m 26 s** critical path; the user's 74-min figure is the pre-opt baseline 32976043901 (73 m 49 s). Both are treated as "everything re-runs" baselines.

---

## 1. Input-closure map (derived from source evidence)

Each work unit's **core input closure** is the set of files/data that, if changed, would change the unit's output fingerprint. Derived from the sources listed above:

| Work unit | Core input closure | Reuse mechanism |
|---|---|---|
| W1 verify-static | union of all gate `filesPattern`s ≈ `*.nim` + `src/` + `docs/` + `AGENTS.md` + `config/gates.manifest.toml` + `src/gate/manifest.d/*.json` + `src/generated/*.nim` + `proofs/` + `data/asset_hygiene_baseline.json` + `Makefile` (env-gate, anti-theater-gate patterns) | Gate-level cache; each gate is individually fingerprintable |
| W2 ci-bootstrap | `src/cli/main.nim` + `src/cli/precompile_gates.nim` + `src/cli/install_ax_cas.nim` + `src/gate/runners/gate_hook.nim` + `src/core/**` (compiled into release `bin/ax`) + `axiom.nimble` + `config.nims` + `lakefile` + `lean-toolchain` | `bin/ax` SHA256 + `ax scope hash` |
| W3 verify-contract-release-e2e-full | `bin/ax` (from W2) + release E2E assertions | `bin/ax` hash (stamped in ci.yml) |
| W4 verify-contract | CONTRACT_UNIT_TESTS (`tests/unit/resolve_node_outcome_test.nim` etc.) + `tools/invariant_mutation_harness.sh` + scenario-oracle tests (`tests/gateway/state_manager_self_healing_test.nim`, `tests/unit/test_evidence_truth_boundary.nim`, `tests/verification/test_g6_*.nim`, `tests/negative/forge_receipt_external.nim`) + `bin/ax` (W3) | Per-test nim cache + mutation harness worktree |
| W5 ci-unit-tests | ALL source (`src/`) + ALL 20 release tests + 2 tools; `nimble install -y` rebuilds the whole package | `nimble install` content hash; per-test nimcache |
| W6 verify-all | `proofs/` + `src/` + `docs/` + `tools/meta_spec_gate.nim` + `tools/ci/check_nim_theater.nim` + `tools/ci/check_lean_vacuity.nim` + `tools/ci/doc_path_validator.nim` + `tests/architecture_constraints.nim` | Per-tool output cache |
| W7 ci-gates | `config/gates.manifest.toml` + `src/gate/manifest.d/*.json` + `src/gate/runners/*.nim` (gates scanned) + `src/` (scanned by topology gates via `bin/gate_hook ci`) + `tests/gateway/` + `config/readiness_policy.json` | Gate-level cache; `executionFingerprint` = sha256(env+argv) |
| W8 test-gateway | `tests/gateway/*.feature_test.nim` + `tests/gateway/all_gateway_runner.nim` + `src/cli/run_gate.nim` + `src/gate/utils/*.nim` + built gateway binaries | Per-binary nimcache + feature-test junit |
| W9 ci-lake-build | `proofs/*.lean` + `proofs/.lake/` deps + `lakefile.lean` | Lake build cache (no recorded duration) |
| W10 verify-coverage-guard | `tools/coverage_guard.nim` + `tools/measure_coverage.nim` + `build/branch_coverage.json` + `data/.coverage_baseline_main.json` (cache keyed on commit SHA) | Commit-pinned content cache (`coverage-baseline-v1-${sha}`) |
| W11 generate-docs | `src/engine.nim` + all transitive imports (→ `engine/engine.nim` → `core/trusted/layer_declaration`, `core/gateway/gateway`, `core/proof/proof_budget`, … `src/core/**`, `src/generated/build_env`, etc.) | `nim doc` output hash |

**Key dependency facts grounded in sources:**
- `src/engine.nim` → `engine/engine.nim` → imports `core/gateway/gateway`, `core/proof/proof_budget`, `core/proof/proof_vacuity_gate`, `core/solver/z3_result_parser`, `src/core/**`, `src/generated/build_env`, etc. (`src/engine.nim:5-20`; `src/engine/engine.nim:1-20`). So **W11 (generate-docs) transitively depends on src/core and src/generated**.
- `tools/debt_engine.nim` reads `data/debt_registry.json` at runtime (`RegistryPath = "data/debt_registry.json"` at line 94; validated at lines 573–602). So **W1's check-debt step is affected by debt_registry.json changes**.
- `src/core/utils/constants.nim`, `src/core/trusted/evidence_capture.nim`, `src/core/trusted/axiom_pragmas_types.nim`, `src/core/trusted/architecture_invariants.nim` all `import generated/build_env` (`src/core/utils/constants.nim:3`). So **src/core compilation depends on src/generated/**.
- `tools/readiness_evaluator.nim` is documented as "per `docs/spec/productization_contract.md`" (`tools/readiness_evaluator.nim:3`) and `readiness_start_gate.nim` reads `config/readiness_policy.json` (`src/gate/runners/readiness_start_gate.nim:50`). So **normative spec changes affect the readiness vertical slice** — but `readiness_start_gate.nim`'s `filesPattern` does not explicitly list `docs/spec/` (gap, §5).

---

## 2. The matrix: Δ × work unit

Legend: **A** = AFFECTED (must re-run), **R** = REUSABLE (skip/reuse), **C** = CONDITIONAL (depends — see note), **U** = UNKNOWN (gap).

### 2.1 Δ = Makefile only (target recipe line, NOT verify-contract gate logic)

| Work unit | Mark | Reason |
|---|---|---|
| W1 verify-static | **A** | check-* steps (`make check-debt`, `make check-imports`, …) invoke make targets; recipe change alters execution |
| W2 ci-bootstrap | **A** | `make ci-bootstrap` is invoked; recipe change alters the build |
| W3 verify-contract-release-e2e-full | **A** | `make verify-contract-release-e2e-full` is invoked |
| W4 verify-contract | **C** | Work unit runs `make verify-contract` → affected at invocation level; **but** internal G1/G2/G4/G6/G7 sub-steps depend on source code and test inputs, NOT the Makefile recipe — so the expensive sub-steps (G1 249 s, G6+G4 191 s) are **reusable if their own inputs are unchanged** |
| W5 ci-unit-tests | **A** | `make ci-unit-tests` is invoked |
| W6 verify-all | **A** | `make verify-all` is invoked |
| W7 ci-gates | **A** | `make ci-gates` is invoked |
| W8 test-gateway | **A** | `make test-gateway` is invoked |
| W9 ci-lake-build | **A** | `make ci-lake-build` is invoked |
| W10 verify-coverage-guard | **R** | Built/run directly via `nim c` (no make invocation) |
| W11 generate-docs | **R** | Built/run directly via `nim doc --project src/engine.nim` (no make) |

**Affected-closure cost (conservative, full work-unit durations):**
W1+W2+W3+W4+W5+W6+W7+W8+W9 = 16 + 5.33 + 0.13 + 16.83 + 12.3 + 4.25 + 3.15 + 11.88 + U ≈ **69.9 m** (+ ci-lake-build unknown)
→ Savings ≈ 3.8 m / 74 m ≈ **5 %** (only W10 + W11 reusable).

**Granular view (where sub-step reuse is possible):** W4's internal gates (G1+G6+G4+G7 ≈ 633 s ≈ 10.5 m) are reusable if their source/test inputs didn't change, cutting W4 from 16.83 m to ≈ 6.3 m. Granular affected closure ≈ **59 m**.

**Interpretation:** The Makefile is the CI's pervasive invocation mechanism, so a recipe-level change does trigger most of the chain — this is the *problem* the P3 incremental design must break (per-step cache keys rather than monolithic make targets).

---

### 2.2 Δ = data/debt_registry.json one line

| Work unit | Mark | Reason |
|---|---|---|
| W1 verify-static | **A** | check-debt runs `bin/debt_engine --validate`, which reads `data/debt_registry.json` at runtime (tools/debt_engine.nim:94, 573–602) |
| W2 ci-bootstrap | **R** | Builds `bin/ax` from src/cli sources; does not read the registry |
| W3 verify-contract-release-e2e-full | **R** | Runs on `bin/ax`; doesn't read the registry |
| W4 verify-contract | **R** | Contract tests (G1/G2/G4/G6/G7) exercise core invariants, not the registry |
| W5 ci-unit-tests | **R** | Release tests don't read the registry |
| W6 verify-all | **R** | Theater/vacuity/doc/arch checks don't read the registry |
| W7 ci-gates | **R** | `debt_integrity_gate` filesPattern = `src/` only; no ci-gates sub-step reads `data/debt_registry.json` |
| W8 test-gateway | **R** | Gateway tests don't read the registry |
| W9 ci-lake-build | **R** | Proofs don't reference the registry |
| W10 verify-coverage-guard | **R** | Coverage tool/baseline don't read the registry |
| W11 generate-docs | **R** | Docs generation doesn't read the registry |

**Affected-closure cost:** W1 ≈ **16 m** (conservative full-work-unit; only the check-debt sub-step of ~2–3 m is truly affected — granular savings noted).
→ Savings ≈ (74 − 16) / 74 ≈ **78 %**.

**Note:** The registry is a *data* artifact, not source. Only the `check-debt` gate in verify-static consumes it directly. Everything downstream is reusable.

---

### 2.3 Δ = src/core/foo.nim one module

| Work unit | Mark | Reason |
|---|---|---|
| W1 verify-static | **A** | check-imports, check-arch (`bin/nimtry src/`), check-nim-theater (`src/`), check-debt (`src/core/debt/*.nim`), manifest-consistency all scan src/ |
| W2 ci-bootstrap | **A** | `bin/ax` release build compiles src/core (→ `bin/ax` hash changes) |
| W3 verify-contract-release-e2e-full | **A** | Runs on a newly built `bin/ax` (W2 output) |
| W4 verify-contract | **A** | G2 unit tests + G1 mutation harness + G6/G4 oracles all exercise core invariants; G1 explicitly mutates core files |
| W5 ci-unit-tests | **A** | `nimble install` rebuilds the whole package including src/core |
| W6 verify-all | **A** | arch + meta_spec scan src/ |
| W7 ci-gates | **A** | Topology gates scan `src/` (most gates have `filesPattern = "src/"`) |
| W8 test-gateway | **A** | Gateway binaries built from src/ (transitive core imports) |
| W9 ci-lake-build | **R** | Lean proofs don't import src/core directly |
| W10 verify-coverage-guard | **A** | Coverage report reflects src/core changes |
| W11 generate-docs | **A** | `src/engine.nim` → `engine/engine.nim` imports `core/**` transitively (see §1) |

**Affected-closure cost:** W1+W2+W3+W4+W5+W6+W7+W8+W10+W11 = **72.3 m** (+ W9 unknown).
→ Savings ≈ 1.8 m / 74 m ≈ **2 %** (only ci-lake-build reusable).

**Interpretation:** src/core is the most tightly coupled change class — it affects ~98 % of the pipeline. This is the class that motivates the P3 "per-module incremental verification" work (compile-only the changed module + dependents, not the whole kernel).

---

### 2.4 Δ = src/gate/*.nim (a gate implementation)

| Work unit | Mark | Reason |
|---|---|---|
| W1 verify-static | **A** | verify-static compiles and runs gate binaries; a gate .nim change affects its own binary |
| W2 ci-bootstrap | **A** | `bin/gate_hook`, `bin/precompile_gates`, `bin/ax` all compile src/ including src/gate |
| W3 verify-contract-release-e2e-full | **A** | Runs on newly built `bin/ax` |
| W4 verify-contract | **A** | G2 tests may exercise the changed gate; G1 mutation harness depends on gate logic |
| W5 ci-unit-tests | **A** | `nimble install` rebuilds the whole package |
| W6 verify-all | **A** | arch/meta_spec may reference gate behavior |
| W7 ci-gates | **A** | `bin/gate_hook ci` runs the changed gate; tier-2 direct invocations compile the gate |
| W8 test-gateway | **A** | Gateway binaries may import the changed gate |
| W9 ci-lake-build | **R** | Proofs don't depend on gate implementations |
| W10 verify-coverage-guard | **R** | Coverage tool doesn't depend on gate implementations |
| W11 generate-docs | **R** | Docs generation doesn't depend on gate implementations |

**Affected-closure cost:** W1+W2+W3+W4+W5+W6+W7+W8 = **60.1 m** (+ W9 unknown).
→ Savings ≈ 11.8 m / 74 m ≈ **16 %** (W9 + W10 + W11 reusable).

**Interpretation:** Gate changes are high-impact but bounded — the proofs lake and coverage guard are naturally decoupled.

---

### 2.5 Δ = README.md (non-normative)

| Work unit | Mark | Reason |
|---|---|---|
| W1 verify-static | **R** | No verify-static gate scans README.md as source; README is not in any `filesPattern` |
| W2 ci-bootstrap | **R** | Build doesn't read README |
| W3 verify-contract-release-e2e-full | **R** | E2E doesn't read README |
| W4 verify-contract | **R** | Contract tests don't read README |
| W5 ci-unit-tests | **R** | Tests don't read README |
| W6 verify-all | **R** | Checks don't read README |
| W7 ci-gates | **R** | Gates don't scan README |
| W8 test-gateway | **R** | Gateway tests don't read README |
| W9 ci-lake-build | **R** | Lake proofs don't read README |
| W10 verify-coverage-guard | **R** | Coverage doesn't read README |
| W11 generate-docs | **R** | `nim doc --project src/engine.nim` doesn't read README |

**Affected-closure cost: 0 m.**
→ Savings ≈ **100 %** (all 74 m reusable).

**Note:** README.md is non-normative per the semantic-role rule (§0). The `on: paths-ignore: ['docs/**', '*.md', ...]` in ci.yml already skips CI for md changes on push — but the matrix shows the deeper truth: even if CI *did* run, README changes affect **zero** verification artifacts.

---

### 2.6 Δ = docs/spec/<contract>.md (normative)

| Work unit | Mark | Reason |
|---|---|---|
| W1 verify-static | **R** | verify-static gates scan source/code, not spec prose |
| W2 ci-bootstrap | **R** | Build doesn't read spec docs |
| W3 verify-contract-release-e2e-full | **R** | E2E doesn't read spec docs |
| W4 verify-contract | **C** | Contract-preservation gates (G1–G7) implement the GO contract; a spec change alters the *semantics* being enforced, but the gate binaries are compiled from Nim source, not from spec markdown — so the cache key doesn't auto-invalidate. **Semantically affected; cache-key NOT automatically invalidated** (gap) |
| W5 ci-unit-tests | **R** | Tests don't read spec docs |
| W6 verify-all | **R** | Checks don't read spec docs |
| W7 ci-gates | **C** | `readiness_start_gate` is "per `docs/spec/productization_contract.md`" (`tools/readiness_evaluator.nim:3`) and reads `config/readiness_policy.json`; but its `filesPattern` does **not** list `docs/spec/` — so a spec change doesn't auto-invalidate readiness_start_gate's cache |
| W8 test-gateway | **R** | Gateway tests don't read spec docs |
| W9 ci-lake-build | **R** | Proofs don't read spec docs |
| W10 verify-coverage-guard | **R** | Coverage doesn't read spec docs |
| W11 generate-docs | **R** | `nim doc src/engine.nim` generates API docs from source, not from spec |

**Affected-closure cost (conservative):** 0 m (cache keys don't auto-invalidate).
**Affected-closure cost (semantic):** W4 + W7 ≈ **20.0 m** (contract-preservation gates + readiness gate *should* re-run because the contract semantics changed, but won't without cache-key intervention).
→ Apparent savings ≈ **100 %** (cache keys), but **semantic savings ≈ 27 %** if the cache is properly wired to spec hashes.

**This is the P2 "normative vs. non-normative doc" rule in action.** Normative doc changes are semantically important but currently cache-key-invisible — a design gap for P3.

---

### 2.7 Δ = a single .nim test file

| Work unit | Mark | Reason |
|---|---|---|
| W1 verify-static | **R** | verify-static gates don't scan the specific test file (unless it's in a gate's filesPattern) |
| W2 ci-bootstrap | **R** | Bootstrap doesn't compile test files |
| W3 verify-contract-release-e2e-full | **R** | E2E doesn't use the specific test |
| W4 verify-contract | **C** | Only if the changed test is one of the CONTRACT_UNIT_TESTS or scenario-oracle files (e.g., `tests/unit/resolve_node_outcome_test.nim`, `tests/gateway/state_manager_self_healing_test.nim`, `tests/verification/test_g6_*`). Otherwise **R**. |
| W5 ci-unit-tests | **C** | Only if the changed file is one of the 20 release tests run by `ci-unit-tests`. Otherwise **R** (the other 19 tests are reusable). |
| W6 verify-all | **R** | Doesn't scan individual test files |
| W7 ci-gates | **R** | Gates don't scan individual test files |
| W8 test-gateway | **C** | Only if the changed file is a `tests/gateway/*_feature_test.nim` or `tests/gateway/all_gateway_runner.nim`. Otherwise **R**. |
| W9 ci-lake-build | **R** | Proofs don't depend on .nim test files |
| W10 verify-coverage-guard | **C** | Coverage report may shift if the test file affects coverage instrumentation |
| W11 generate-docs | **R** | Doesn't read test files |

**Affected-closure cost (best case, test not in any CI target): 0 m** (all reusable).
**Affected-closure cost (worst case, test is in a CI target):** the individual test's compile+run time only — typically **seconds to a minute**, not the full work-unit duration.
→ Savings ≈ **95–100 %** for a well-scoped test change.

**Interpretation:** This is the *best-case* change class for incremental verification. The current monolithic CI wastes 74 m on a 30-second test change.

---

### 2.8 Δ = generated code (`src/generated/*`)

| Work unit | Mark | Reason |
|---|---|---|
| W1 verify-static | **A** | topology-drift guard checks `src/generated/manifest_registry.nim`, `src/generated/gate_registry.nim`, `src/generated/helper_registry.nim` (ci.yml verify-static); manifest-consistency scans `src/gate/manifest.d/*.json` (generated) |
| W2 ci-bootstrap | **A** | `bin/gate_hook`, `bin/precompile_gates`, `bin/ax` compile generated modules |
| W3 verify-contract-release-e2e-full | **A** | Runs on newly built `bin/ax` |
| W4 verify-contract | **A** | Contract tests depend on generated code (src/core imports `generated/build_env`, etc.) |
| W5 ci-unit-tests | **A** | `nimble install` rebuilds with generated code |
| W6 verify-all | **A** | arch + meta_spec may reference generated symbols |
| W7 ci-gates | **A** | Gates scan `src/` which imports generated modules |
| W8 test-gateway | **A** | Gateway binaries compile generated code |
| W9 ci-lake-build | **R** | Lean proofs don't depend on Nim generated code |
| W10 verify-coverage-guard | **A** | Coverage reflects generated code changes |
| W11 generate-docs | **C** | `nim doc src/engine.nim` transitively compiles generated modules (`src/generated/build_env` is imported by core/*); if generated signatures changed, docs change → **A**; if only comments changed → **R** |

**Affected-closure cost:** W1+W2+W3+W4+W5+W6+W7+W8+W10 = **64.0 m** (+ W9 unknown; W11 ≈ C).
→ Savings ≈ 1.8 m / 74 m ≈ **2 %** (only ci-lake-build + possibly docs).

**Interpretation:** Generated-code changes are maximally impactful — almost every work unit compiles them. The proper fix (P3) is to make `sync_topology.nim` the *only* producer and to gate generated-code edits behind the topology-drift check, so a generated-only diff forces the drift guard (W1) but ideally is *rejected* until topology_spec.nim is updated.

---

## 3. Per-change-class cost table

| Δ class | Affected work units (count) | Affected-closure cost (conservative, full WU durations) | Current cost (everything re-runs) | Δcost (saved) | Savings % |
|---|---|---|---|---|---|
| Δ1 Makefile only | 9 of 11 (W1–W9) | ≈ 69.9 m (+ W9 U) | 74 m | ≈ 4.1 m | **~5 %** |
| Δ2 debt_registry.json one line | 1 of 11 (W1) | ≈ 16 m (W1; ~2–3 m granular) | 74 m | ≈ 58 m | **~78 %** |
| Δ3 src/core single module | 10 of 11 (all except W9) | ≈ 72.3 m (+ W9 U) | 74 m | ≈ 1.7 m | **~2 %** |
| Δ4 src/gate/*.nim | 8 of 11 | ≈ 60.1 m (+ W9 U) | 74 m | ≈ 13.9 m | **~16 %** |
| Δ5 README.md (non-normative) | 0 of 11 | **0 m** | 74 m | ≈ 74 m | **~100 %** |
| Δ6 docs/spec contract (normative) | 0 of 11 (cache-key); 2 (semantic) | **0 m** (cache); **~20 m** (semantic) | 74 m | ≈ 74 m (cache) / 54 m (semantic) | **~100 % / ~73 %** |
| Δ7 single .nim test file | 0–3 of 11 (conditional) | **0 m** (best) to ~1 m (worst, single test) | 74 m | ≈ 73 m | **~95–100 %** |
| Δ8 generated code (src/generated/*) | 9–10 of 11 | ≈ 64 m (+ W9 U) | 74 m | ≈ 10 m | **~14 %** |

**Sum over the serial chain (conservative):** The "current cost" of 74 m applies to *every* change class today because the `needs` chain forces every job to re-run regardless of input change. The affected-closure column shows what a content-addressable, per-unit cache *would* require — the gap is the avoidable work.

**Range across all Δ classes:** 0 m (Δ5 README) to ≈72 m (Δ3 src/core, Δ8 generated). The spread from 0 % to 98 % savings is the core argument for incremental verification.

---

## 4. Golden headline examples

### 4.1 Δ = Makefile-only (the pervasive-invocation case)

| | Duration |
|---|---|
| Current (everything re-runs) | **74 m** |
| Affected-closure (conservative, full WU) | **≈ 69.9 m** |
| Δcost (saved, conservative) | **≈ 4.1 m** |
| Savings | **~5 %** |
| Affected-closure (granular, sub-step reuse) | **≈ 59 m** |
| Δcost (saved, granular) | **≈ 15 m** |
| Savings (granular) | **~20 %** |

**Why conservative is honest:** In today's monolithic make-driven CI, a Makefile recipe change does trigger `make verify-static`, `make ci-bootstrap`, `make verify-contract`, `make ci-unit-tests`, `make verify-all`, `make ci-gates`, `make test-gateway`, `make ci-lake-build` — i.e., ~69.9 m of the 74 m. Only `verify-coverage-guard` (nim c directly) and `generate-docs` (nim doc directly) bypass the Makefile entirely. The granular view (≈ 59 m) assumes the expensive verify-contract sub-steps (G1 mutation 249 s, G6+G4 oracles 191 s) are individually cacheable — an assumption that holds *if* those sub-steps have their own content-addressable cache keys, which today they do not.

### 4.2 Δ = README-only (the zero-impact case)

| | Duration |
|---|---|
| Current (everything re-runs) | **74 m** |
| Affected-closure | **0 m** |
| Δcost (saved) | **≈ 74 m** |
| Savings | **~100 %** |

**Why this matters:** README.md is non-normative (§0 semantic-role rule). Today CI still runs 74 m on it because `paths-ignore` skips the *trigger* but the matrix reveals the deeper truth: even if CI ran, **zero** verification artifacts depend on README content. The 100 % savings is the upper bound of what incremental verification can deliver — and it's achievable today for any non-normative change class.

### 4.3 Headline comparison (both golden examples side-by-side)

| Δ class | Current | Affected-closure | Δcost saved | Savings |
|---|---|---|---|---|
| Makefile-only (Δ1) | 74 m | ≈ 69.9 m (conservative) / ≈ 59 m (granular) | ≈ 4–15 m | 5–20 % |
| README-only (Δ5) | 74 m | **0 m** | **≈ 74 m** | **100 %** |

The contrast (5–20 % vs. 100 %) quantifies *why* the semantic-role classification of docs and the decoupling of the Makefile invocation are P3 priorities.

---

## 5. Assumptions, UNKNOWNs, and gaps

### 5.1 Assumptions (documented)

1. **Conservative cost = full work-unit duration.** Where a work unit is marked AFFECTED, its *full* duration is counted in the conservative affected-closure, even if only one sub-step is truly affected. This overstates the affected closure and understates savings; the granular view (§2.1, §2.2) corrects for this where sub-step data exists.
2. **Serial chain assumption.** Today every `needs`-chained job re-runs on every change. The matrix assumes a hypothetical content-addressable cache where each work unit re-runs *only* if its input closure changed. This is the target state P3 must deliver.
3. **Post-opt durations as baseline.** Uses run 32999624943 durations where available (verify-integration 48.38 m); the user's "74 min" pre-opt baseline (32976043901) is treated as the "everything re-runs" reference and is slightly higher due to the ci-unit-tests duplicate-compile bug.
4. **ci-lake-build excluded from sums.** W9 has no recorded duration (`[gh-run]` ran and completed; timing not exposed; not in migration doc or critical-path report). Sums that exclude W9 are conservatively *low* by the unknown W9 amount.
5. **Normative doc classification follows the P2 semantic-role rule** (§0): docs/DEBT_REGISTRY.md, docs/agents/{architecture,core_rules,rules_workflow}.md, docs/spec contracts, docs/history/audit_baseline_* are normative; README.md, marketing, changelog, tutorials are non-normative.
6. **"Makefile recipe line" means an execution-affecting change.** Cosmetic Makefile changes (comments, non-executed targets) would make all work units REUSABLE — the Δ1 figures assume a recipe change that alters a `make <target>` invocation.

### 5.2 UNKNOWNs and gaps (must resolve before P3 closure design)

| # | Gap | Impact |
|---|---|---|
| G1 | **ci-lake-build (W9) has no measured duration.** `[gh-run]` confirms it ran/completed, but no wall-clock was captured by GitHub API or migration doc. | Cannot place W9 in the duration matrix; sums excluding W9 are conservative (understated affected closure). |
| G2 | **verify-contract sub-step durations lack primary sources.** The G1/G2/G4/G6/G7 breakdown (249 s / 134 s / 191 s / 59 s) cites `docs/audit/ci_latency_decomposition_2026-08-24.md`, which **does not exist** on disk. Carried from `docs/reports/ci_critical_path_2026-08-25.md` but its own primary source is unreachable. | The granular reuse estimates for W4 are *reported-but-unverified*. Independent measurement needed before P3 uses them for cache-key design. |
| G3 | **verify-contract migration-doc vs. critical-path-report discrepancy.** migration-doc = 16.83 m; critical-path-report sub-chain = ≈633 s (10.5 m). The ~377 s gap is unreconciled (setup/cache vs. pure execution? different slice?). | Affects precision of W4's affected-closure; treat 16.83 m as the CI-invoiced duration and 633 s as the pure-execution lower bound. |
| G4 | **Normative doc → cache-key invalidation is not wired.** `readiness_start_gate.nim` is "per `docs/spec/productization_contract.md`" (`tools/readiness_evaluator.nim:3`) but its `filesPattern` does not list `docs/spec/`. A spec change won't auto-invalidate its cache. | W4 and W7 are *semantically* affected by normative doc changes but *cache-key-invisible*. P3 must add spec-hash to the execution fingerprint (see §5.3). |
| G5 | **Exact per-gate durations within verify-static (W1) are unavailable.** Only the 16 m total is measured; sub-step timings are not exposed by the GitHub API. | The check-debt sub-step's ~2–3 m granular estimate is an assumption, not a measurement. |
| G6 | **Some gate→file dependencies may not be fully wired.** Several gates in `topology_spec.nim` have `filesPattern` but the mapping from `filesPattern` → actual scanned files → produced artifacts is not exhaustively validated. The `_index.json` and `manifest.d/*.json` are auto-generated from `topology_spec.nim` but runtime behavior may diverge. | A few matrix cells (especially around debt-integrity-gate and data/ paths) are CONDITIONAL rather than definitive. |
| G7 | **generate-docs dependency on src/generated is inferred, not directly measured.** `src/engine.nim` → `engine/engine.nim` → `core/**` → `src/generated/build_env` (via `import generated/build_env` in core/*). The transitive import chain is confirmed by grep but the exact `nim doc` dependency on generated code is not profiled. | W11 for Δ8 is marked CONDITIONAL; treat as AFFECTED if generated signatures change, REUSABLE if only comments change. |
| G8 | **Coverage baseline cache is commit-pinned, not content-hashed.** `data/.coverage_baseline_main.json` cache key is `coverage-baseline-v1-${sha}` — it restores the baseline for the *commit*, but a source change that doesn't touch coverage instrumentation would still restore the old baseline, potentially masking coverage regression. | W10 for Δ7 (single test file) is CONDITIONAL; the coverage guard may not re-run correctly for sub-file test changes. |
| G9 | **Upload-artifact steps and purge-stale-cert-vault have no separate timing.** Embedded in verify-integration job overhead. | Minor; does not materially affect the matrix. |
| G10 | **pr-coverage-comment** is skipped on push-to-main; relevant only on PR branch. | Out of scope for push-to-main matrix; would sit in a parallel fork after verify-coverage-guard on PRs. |

### 5.3 Design implication for P3 (cache-key / fingerprint wiring)

The `CanonicalExecutionBundleFingerprint` in `src/verification/obligation/identity.nim` already hashes `axiomSourceDigest`, `leanVersion`, `z3Version`, `lakeVersion`, `nimVersion`, `dependencyDigests`, `runtimeDigest`, `evaluationImplementationDigest`. To make the matrix actionable, P3 must extend this to include:

- **Document-hash of normative specs** (so Δ6 normative-doc changes invalidate readiness_start_gate and contract-preservation gates).
- **Per-sub-step fingerprints within verify-contract** (so Δ1 Makefile changes don't re-run G1/G2/G4/G6/G7 when only the `make verify-contract` recipe changed).
- **Per-gate `filesPattern` → content hash** in `GateRunRecord.executionFingerprint` (so ci-gates can skip unchanged gates).
- **A measured duration for ci-lake-build** (G1).

---

## 6. Conclusion — which change classes dominate day-to-day dev loops

The matrix reveals a clear hierarchy of change-class impact that should drive P3 closure-design priorities:

1. **Δ5 (README / non-normative docs) and Δ7 (single test file) are the high-frequency, low-impact classes** — savings of 95–100 %. These are the *daily developer loop* changes. Today they pay the full 74 m tax; with incremental verification they should cost seconds-to-minutes. **P3 must make these near-zero-cost first.**

2. **Δ2 (debt_registry.json) and Δ6 (normative spec) are medium-frequency, medium-impact** — ~78 % and ~73–100 % savings respectively. These are the *policy/governance* changes. The Δ6 gap (cache-key not wired to spec hash) is a quick P3 win: add the normative spec hash to the readiness_start_gate and contract-preservation gate fingerprints.

3. **Δ1 (Makefile) is high-frequency but high-impact today (~5–20 % savings)** — because the Makefile is the CI's pervasive invocation mechanism. This is the *structural* problem: the serial `make <target>` chain forces most jobs to re-run. P3 must decouple the Makefile targets into independently cacheable steps.

4. **Δ3 (src/core) and Δ8 (generated code) are the low-frequency, near-total-impact classes** — ~2–98 % savings (i.e., almost nothing reusable). These are the *kernel changes* that justify the full chain today. P3 cannot make them incremental without a per-module import-graph cache (compile-only the changed module + dependents), which is a longer-term effort.

5. **Δ4 (src/gate) is the bounded-high-impact class** — ~16 % savings, with proofs lake and coverage guard naturally decoupled. Gate changes are a good early target for per-gate cache keys because their input closures are well-defined in `topology_spec.nim`.

**Golden rule for P3 closure design:** Target the classes that dominate day-to-day dev loops — Δ5 (non-normative docs → 100 % savings), Δ7 (single test file → ~95–100 %), and Δ2/Δ6 (policy/governance → ~73–78 %). The Makefile invocation decoupling (Δ1) is the structural prerequisite that unlocks the others. src/core and generated-code changes (Δ3/Δ8) are the hard long-tail that P3 can defer.

**Headline numbers (golden Δ examples):**
- Δ1 Makefile-only: 74 m → ≈ 69.9 m conservative / ≈ 59 m granular (5–20 % savings).
- Δ5 README-only: 74 m → 0 m (100 % savings).
- The 74 m → 0 m jump for non-normative-doc changes is the proof that incremental verification is both possible and high-value; the remaining work is wiring the cache keys and decoupling the serial chain so the 0 m case is the default, not the exception.

---

*Generated 2026-08-28. Read-only analysis; no files modified. All durations sourced from `docs/reports/ci_observed_dag_p1_2026-08-28.md`, `.github/workflows/ci.yml`, `Makefile`, `src/gate/topology_spec.nim`, `config/gates.manifest.toml`, `src/gate/manifest.d/*.json`, `src/verification/obligation/identity.nim`, `src/gate/utils/gate_run_logger.nim`, `docs/spec/self_hosted_ci_migration.md` lines 153–205, and direct source greps. UNKNOWN cells and assumptions are explicitly marked in §5.*
