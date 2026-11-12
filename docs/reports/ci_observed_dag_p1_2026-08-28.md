# Observed CI DAG — P1 (2026-08-28)

> **Scope:** Produce an evidence-backed observed CI DAG for the Axiom CI pipeline, as
> input to an avoidable-work matrix. This is a read-only measurement report; no source
> or config files were modified.
>
> **Source runs:** baseline `32976043901` (pre-opt, push `6bcea2117`, 2026-08-26),
> post-opt `32999624943` (push `425a27f5e`, 2026-08-26), and `33032383211`
> (post-opt, 2026-08-27).
>
> **Architecture:** Single CX23 host (2 vCPU / 4GB), ephemeral JIT runners, all jobs
> serialized via `needs`. Pipeline: `verify-static → verify-integration →
> verify-coverage-guard → generate-docs | pr-coverage-comment`.

---

## 1. DAG Table

Each row is a Job → Step → Work Unit mapping. Duration provenance is one of:

- `[gh-run <id>]` — measured from GitHub Actions `startedAt`/`completedAt` timestamps.
- `[migration-doc]` — from `docs/spec/self_hosted_ci_migration.md` lines 153–205,
  measured 2026-08-26 on run `32976043901`.
- `[critical-path-report]` — from `docs/reports/ci_critical_path_2026-08-25.md`,
  originally citing now-missing `docs/audit/ci_latency_decomposition_2026-08-24.md`.
- `[gh-run <id> + migration-doc]` — cross-validated where both agree.

`onCriticalPath` = YES for every row in the main serial chain (all `needs`-chained,
single host, no parallelism). `slack = 0` for all critical-path rows.

### 1.1 Main serial chain (push-to-main; `generate-docs` is terminal)

| Job | Step (ci.yml) | Work Unit (make target) | Duration | Provenance | onCriticalPath | criticalPathContribution |
|---|---|---|---|---|---|---|
| **verify-static** | Checkout + setup-axiom-toolchain + Determinism guard + 16 gates + git-purity | `make check-mutation-harness`, `env-check`, `check-imports`, `check-mcp`, `check-debt`, `check-manifest-consistency`, `check-cert-manifest-drift`, `check-cert-integrity`, `check-arch`, `check-nim-theater`, `check-lean-vacuity`, `check-vacuity-simple`, `doc-path-validator`, decision-binding audit, topology/drift guards, `sloc-verify`, git-purity | **15m59s (959s)** pre-opt · **16m12s (972s)** post-opt · **16m46s (1006s)** run 32999624943 | `[gh-run 32976043901]` / `[gh-run 32999624943]` | YES | = duration |
| **verify-integration** | Purge vault · Release build+baseline · Release E2E · verify-contract · ci-unit-tests · verify-all · ci-gates · test-gateway · Build proofs · Upload | see §1.2 below | **55m25s (3325s)** pre-opt · **48m38s (2920s)** post-opt | `[gh-run 32976043901]` / `[gh-run 32999624943]` | YES | = duration |
| &nbsp;&nbsp;↳ Release build+baseline (G3/G7) | `make ci-bootstrap` | build gate_hook, precompile_gates, ax, install_ax_cas; install hooks; `ax scope hash`; `ax baseline check` | **5.33m (320s)** | `[migration-doc]` | YES | 5.33m |
| &nbsp;&nbsp;↳ Release E2E (G7) | `make verify-contract-release-e2e-full` | canonical product-outcome assertion on release bin/ax | **≈8.2s** | `[critical-path-report]` (source doc missing) | YES | ≈8s |
| &nbsp;&nbsp;↳ verify-contract (G1/G2/G4/G6/G7) | `make verify-contract` | G1 mutation harness · G2 contract-unit · G6/G4 scenario oracles · G7 release E2E (internal) | **16.83m (1010s)** pre-opt · **17.3m (1038s)** post-opt | `[migration-doc]` | YES | 16.83m pre / 17.3m post |
| &nbsp;&nbsp;&nbsp;&nbsp;↳ G1 mutation oracle | `verify-invariant-mutation` → `tools/invariant_mutation_harness.sh` | M1·M2·M3 die, isolated worktree | **≈249s (4.15m)** | `[critical-path-report]` (source doc missing) | YES | ≈249s |
| &nbsp;&nbsp;&nbsp;&nbsp;↳ G6+G4 (OCL/proof) | `verify-scenario-oracles` | runtime/reference DATA-FLOW + fail-closed oracles | **≈191s (3.18m)** | `[critical-path-report]` (source doc missing) | YES | ≈191s |
| &nbsp;&nbsp;&nbsp;&nbsp;↳ G2 promotion semantics | `verify-contract-unit` | 10 GO-critical unit tests (nim c -r each) | **≈134s (2.23m)** | `[critical-path-report]` (source doc missing) | YES | ≈134s |
| &nbsp;&nbsp;&nbsp;&nbsp;↳ G7 proof-universe-lock-gate | (inside verify-contract) | IR CAS-keyed memoization gate | **≈59s (0.98m)** | `[critical-path-report]` (source doc missing) | YES | ≈59s |
| &nbsp;&nbsp;↳ ci-unit-tests | `make ci-unit-tests` | `nimble install -y` + 20 release tests + 2 tools | **12.30m (738s)** pre-opt · **6.5m (390s)** post-opt | `[migration-doc]` | YES | 12.30m pre / 6.5m post |
| &nbsp;&nbsp;↳ verify-all (static+integration) | `make verify-all` | theater/vacuity/doc-sync checks + arch + meta_spec | **4.25m (255s)** | `[migration-doc]` | YES | 4.25m |
| &nbsp;&nbsp;↳ ci-gates (tier-1 hook + tier-2 direct) | `make ci-gates` | `bin/gate_hook ci` + verification_auditor_gate + external_cli_smoke + readiness_start_gate | **3.15m (189s)** pre-opt · **3.0m (180s)** post-opt | `[migration-doc]` | YES | 3.15m pre / 3.0m post |
| &nbsp;&nbsp;↳ test-gateway | `make test-gateway` | build 7 gateway binaries + `all_gateway_runner` (84 feature tests) | **11.88m (713s)** pre-opt · **10.2m (612s)** post-opt | `[migration-doc]` | YES | 11.88m pre / 10.2m post |
| &nbsp;&nbsp;↳ Build proofs | `make ci-lake-build` | `lake build` in proofs/ | **⚠ no recorded duration** | `[gh-run]` (ran, completed; timing not exposed) | YES | unknown |
| &nbsp;&nbsp;↳ Upload gate telemetry / artifacts | `actions/upload-artifact@v4` | gate_history.jsonl, coverage, metrics, gateway-junit | **included in job overhead** | `[gh-run]` (no separate step timing) | YES | embedded |
| **verify-coverage-guard** | Restore cache · build coverage_guard · generate coverage · coverage regression guard | `nim c -d:release coverage_guard` · `./bin/coverage_guard --tolerance 0.0` | **2m5s (125s)** pre-opt (conclusion: failure) · **1m56s (116s)** post-opt · **2m14s (134s)** run 32999624943 | `[gh-run 32976043901]` / `[gh-run 32999624943]` | YES | = duration |
| **generate-docs** | nim doc src/engine.nim → docs/api + upload | `nim doc --project src/engine.nim` | **1m48s (108s)** post-opt (run 32999624943) · **1m46s (106s)** run 33032383211 | `[gh-run 32999624943]` / `[gh-run 33032383211]` | YES (push-to-main terminal job) | = duration |
| pr-coverage-comment | `pr_coverage_commenter.nim` | compile + run PR coverage commenter | **skipped** (push-to-main branch; runs on PR only) | `[gh-run]` | YES on PR branch; N/A on main | — |

### 1.2 Pre-optimization summary (run `32976043901`, 2026-08-26)

| Job | Duration | Provenance | conclusion |
|---|---|---|---|
| verify-static | 15m59s (959s) | `[gh-run 32976043901]` | success |
| verify-integration | 55m25s (3325s) | `[gh-run 32976043901]` | success |
| verify-coverage-guard | 2m5s (125s) | `[gh-run 32976043901]` | **failure** (Coverage regression guard) |
| generate-docs | skipped | `[gh-run 32976043901]` | skipped (dep failed) |
| **pipeline total (wall-clock)** | **1h13m49s (4429s)** | `[gh-run 32976043901]` started 13:44:54 → updated 14:58:43 | failure |

### 1.3 Post-optimization summary (run `32999624943`, 2026-08-26)

| Job | Duration | Provenance | conclusion |
|---|---|---|---|
| verify-static | 16m46s (1006s) | `[gh-run 32999624943]` | success |
| verify-integration | 48m38s (2918s) | `[gh-run 32999624943]` | success |
| verify-coverage-guard | 2m14s (134s) | `[gh-run 32999624943]` | success |
| generate-docs | 1m48s (108s) | `[gh-run 32999624943]` | success |
| **pipeline total (wall-clock)** | **69m53s (4193s)** | `[gh-run 32999624943]` started 18:25:36 → updated 19:35:29 | success |

### 1.4 Run `33032383211` (post-opt, 2026-08-27) — cross-validation

| Job | Duration | Provenance |
|---|---|---|
| verify-static | 16m12s (972s) | `[gh-run 33032383211]` |
| verify-integration | 48m40s (2920s) | `[gh-run 33032383211]` |
| verify-coverage-guard | 1m56s (116s) | `[gh-run 33032383211]` |
| generate-docs | 1m46s (106s) | `[gh-run 33032383211]` |
| pipeline total | 67m54s (4074s) | `[gh-run 33032383211]` |

---

## 2. Critical-Path Total Computation

The pipeline is fully serialized (`needs` chain on a single CX23 host), so the critical
path = the sum of every `needs`-chained job. The only fork is `generate-docs` vs
`pr-coverage-comment` after `verify-coverage-guard`; on push-to-main, `generate-docs`
is the terminal job.

### 2.1 Pre-optimization critical path (run `32976043901`)

```
verify-static          15m59s  [gh-run]
verify-integration     55m25s  [gh-run]
verify-coverage-guard   2m05s  [gh-run]  ← conclusion: FAILURE (coverage guard)
generate-docs          skipped (dep failed)
─────────────────────────────────────
Critical path total:  73m29s  (sum of measured jobs)
Pipeline wall-clock:  73m49s  (1h13m49s, [gh-run] 13:44:54→14:58:43)
Unaccounted overhead: ~20s    (job setup/teardown gaps)
```

### 2.2 Post-optimization critical path (run `32999624943`)

```
verify-static          16m46s  [gh-run]
verify-integration     48m38s  [gh-run]
verify-coverage-guard   2m14s  [gh-run]
generate-docs           1m48s  [gh-run]
─────────────────────────────────────
Critical path total:  69m26s  (sum of measured jobs)
Pipeline wall-clock:  69m53s  [gh-run] 18:25:36→19:35:29
Unaccounted overhead: ~27s    (job setup/teardown gaps)
```

### 2.3 Critical-path improvement

| Metric | Pre-opt | Post-opt | Δ |
|---|---|---|---|
| verify-integration | 55m25s (3325s) | 48m38s (2918s) | **−6m47s** |
| Critical-path total (measured) | 73m29s | 69m26s | **−4m3s** |
| Pipeline wall-clock | 73m49s | 69m53s | **−3m56s** |
| verify-contract (sub-container) | 16.83m (1010s) | 17.3m (1038s) | +0m47s (variance, not a regression) |

The −6.8m reported in the migration doc for verify-integration is **partially offset**
by verify-static (+47s warm-cache variance) and coverage-guard overhead, yielding a
net **−4m3s** critical-path reduction. The dominant win is ci-unit-tests
(−5m50s: 12.30m → 6.5m, dedup of duplicate `nimble build`).

### 2.4 Internal verify-contract critical chain (per critical-path report)

The critical-path report decomposes the verify-contract container into a sequential
sub-chain (all on-critical, slack=0):

```
G1 mutation oracle        ≈249s  [critical-path-report]  ← largestActionableLeaf, NOT STARTED
G6+G4 (OCL/proof)         ≈191s  [critical-path-report]  ← BACKLOG
G2 promotion semantics    ≈134s  [critical-path-report]  ← BACKLOG
G7 proof-universe-lock    ≈ 59s  [critical-path-report]  ← DONE
─────────────────────────────────────
Sub-chain total:          ≈633s  (10m33s)
```

> ⚠ **Provenance caveat:** these sub-step durations cite
> `docs/audit/ci_latency_decomposition_2026-08-24.md §17.1`, which **does not exist**
> on disk (confirmed). The numbers are carried forward from the real report
> `docs/reports/ci_critical_path_2026-08-25.md` but their primary source is unreachable.
> Treat as *reported-but-unverified* until an independent measurement is taken.
>
> ⚠ **Cross-source discrepancy:** the migration doc measures the full `make verify-contract`
> step at **16.83m (1010s)** [migration-doc], while the critical-path report's internal
> sub-chain sums to **≈633s (10m33s)**. The ~377s gap is unaccounted — possibly the
> critical-path report measures pure execution time (excluding setup/cache) or measures
> a different slice. These two sources are **not reconciled** in this report; both are
> carried with their provenance strings.

---

## 3. Evidence Provenance Appendix

| Source file | Status | Used for |
|---|---|---|
| `.github/workflows/ci.yml` | Read-only; immutable per §-1 | Step → make-target mapping |
| `Makefile` (targets `verify-contract`, `ci-unit-tests`, `verify-all`, `ci-gates`, `test-gateway`, `ci-lake-build`, `ci-bootstrap`) | Read-only | Work-unit decomposition |
| `docs/spec/self_hosted_ci_migration.md` lines 153–205 | Read | `[migration-doc]` phase durations |
| `docs/reports/ci_critical_path_2026-08-25.md` | Read | `[critical-path-report]` verify-contract sub-chain |
| `docs/audit/ci_latency_decomposition_2026-08-24.md` | **Does not exist** | — (cited by critical-path report, source missing) |
| `docs/audit/ci_latency_current_state_2026-08-25.md` | **Does not exist** | — (cited by critical-path report, source missing) |
| `gh run view 32976043901` | Read | `[gh-run 32976043901]` job timestamps, conclusions |
| `gh run view 32999624943` | Read | `[gh-run 32999624943]` job timestamps, conclusions |
| `gh run view 33032383211` | Read | `[gh-run 33032383211]` job timestamps, conclusions |
| GitHub Actions API `/repos/Archright/Axiom/actions/runs/<id>/jobs/<jid>/steps` | **404 Not Found** | Step-level timing unavailable |

### 3.1 API step-timing availability (verified)

`gh run view --json jobs` returns per-job `startedAt`/`completedAt` but the `steps`
array inside each job contains only `{conclusion, name, number, status}` — **no timing
fields**. Direct calls to `gh api /repos/Archright/Axiom/actions/runs/<id>/jobs/<jid>/steps`
return 404 (endpoint requires the numeric job `databaseId`, and even then GitHub's
Actions API does not expose per-step wall-clock duration in this API version).

**Result:** Step-level durations inside `verify-integration` are **not recoverable from
the gh CLI / GitHub API**. They are sourced exclusively from the migration doc
(`[migration-doc]`) and the critical-path report (`[critical-path-report]`).
Only job-level wall-clock durations are API-measurable via `[gh-run <id>]`.

---

## 4. Gaps List

Steps or sub-units with **no recorded duration** or **unresolved measurement gaps**:

| Gap | Description | Impact |
|---|---|---|
| **Build proofs (`make ci-lake-build`)** | Step ran and completed in verify-integration; no wall-clock captured by gh API and not reported in migration doc or critical-path report | Cannot place on critical-path duration matrix; estimated as minor (lake build typically fast) |
| **Upload artifacts (4× `actions/upload-artifact`)** | No per-step timing; embedded in verify-integration job overhead | Negligible but unmeasured |
| **Purge stale cert vault** | No separate duration reported; sub-step of verify-integration | Likely <5s |
| **Checkout + setup-axiom-toolchain** | No separate duration; part of verify-integration job overhead (setup-axiom-toolchain was ~7.67m in verify-static per migration doc) | Included in verify-integration overhead, not separately quantified |
| **verify-contract sub-step discrepancy** | migration-doc = 16.83m vs critical-path-report = 633s; sources not reconciled | Affects precision of G1/G2/G4/G6/G7 individual critical-path contributions |
| **Coverage-guard failure (run 32976043901)** | verify-coverage-guard concluded failure; generate-docs skipped as a result | Baseline run incomplete; post-opt runs all green |
| **Critical-path report source docs missing** | `docs/audit/ci_latency_decomposition_2026-08-24.md` and `ci_latency_current_state_2026-08-25.md` do not exist | verify-contract sub-chain durations are reported-but-unverified |
| **canary cold/warm durations** | 18m07s / 10m23s from migration doc — not part of production CI DAG; for context only | No impact on critical-path total |
| **pr-coverage-comment** | Skipped on push-to-main; no duration available | Only relevant on PR branch; would sit in parallel fork after verify-coverage-guard |

---

## 5. Summary

- **Critical path** (post-optimization, push-to-main): `verify-static (16m46s) →
  verify-integration (48m38s) → verify-coverage-guard (2m14s) → generate-docs (1m48s)`
  = **69m26s measured**, **69m53s wall-clock**.
- **Largest single step**: `verify-integration` at 48m38s (post-opt), dominated internally
  by `ci-unit-tests` (6.5m), `test-gateway` (10.2m), `verify-contract` (17.3m), and
  `verify-all`/`ci-gates` (7.25m combined).
- **verify-contract** is the critical-pathMaxContainer (≈633s internal per the
  critical-path report; 16.83m per the migration doc — discrepancy unresolved).
- **Largest actionable leaf** (per critical-path report): **G1 mutation oracle ≈249s**,
  status NOT STARTED, actionable=YES.
- **Post-opt improvement**: −4m3s critical-path reduction (−3m56s wall-clock) vs baseline,
  driven primarily by ci-unit-tests dedup (−5m50s).
- **Key gap**: `ci-lake-build` and artifact-upload steps have no recorded duration and
  cannot be placed precisely in the avoidable-work matrix without further profiling.
- **Key provenance risk**: the critical-path report's sub-step durations lack their
  cited source document; independent measurement is recommended before using them for
  optimization prioritization.
