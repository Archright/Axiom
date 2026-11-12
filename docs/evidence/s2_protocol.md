# S2 — AXIOM_JOBS 단일요인 측정 프로토콜 (CI Pareto v13)

> Experiment-plane runbook for the approved CI-optimization plan, S2 arm:
> **"Does raising in-job test parallelism (AXIOM_JOBS) reduce P95 end-to-end
> latency?"** Configs: **jobs=2 (baseline = current CI) vs 4 vs 8**.
> Owner 결정 #14: same-repo non-authoritative measurement plane — the
> experiment workflow is NOT a required check and is not referenced by
> admission/mint.
>
> Measurement backend: `tools/ci/pareto_harness.nim` `ingest` (GitHub-run
> ingestion, read-only `gh api`). Binary: `build/pareto_harness_v4`
> (build command: README §harness, §End-to-end demo).
>
> Scope: workflow `gateway-jobs-measure.yml` (NEW, uncommitted), this
> protocol, trace pre-registration commands, dispatch/ingest/compare runbook,
> budget ledger, validity threats.

---

## 1. Hypothesis and selection

| Item | Value |
|---|---|
| Null hypothesis | Full gateway suite wall (W) is independent of AXIOM_JOBS ∈ {2,4,8} |
| Alternative | Raising AXIOM_JOBS lowers W (runner worker pool grows) until the `countProcessors()` cap |
| Selection (v13) | **c\* = argmin P95_trace(W_c)** — P95 over the total per-run latency population (nearest-rank, no segment weighting) |
| Tie-break (EXACT P95 equality only) | 1. max λ_observed_max → 2. min mean queue → 3. min mean exec → 4. candidate id ascending |
| Regression ceiling | P95 ≤ 15 min reported as `withinRegressionCeiling` — a CEILING, not a target; candidates above it are still ranked |
| Budget | Target ≤ 200 runner-minutes (ledger §7); all costs diagnostic only |

**Expected outcome (rationale for the design, not a pre-judgment):**
`all_gateway_runner` caps workers at `cpuinfo.countProcessors()`
(`tests/gateway/all_gateway_runner.nim configuredWorkers`). GitHub-hosted
`ubuntu-24.04` = 4 vCPU (nproc=4), so **jobs=8 is capped to 4 workers and is
expected to measure identically to jobs=4** (the 8-arm documents the cap).
If nproc on the runner image is higher, jobs=8 genuinely exercises 8 workers;
the workflow echoes `nproc` and the runner's `workers=N` INFO line for
provenance.

---

## 2. Measurement design

### 2.1 Single-factor isolation

1. **Workload identical**: every measured dispatch checks out the SAME fixed
   ref (input `ref`, default `b529ad466` == optimize/ci-pareto tip). The ref is
   also passed as `cache-build-source` so the B-cache key is identical for
   every run. Workload = the full gateway suite at `SHARD_COUNT=1` (all
   `tests/gateway/*_feature_test.nim`; awk `NR % 1 == 0` selects all).
2. **Initial state identical**: A-layer toolchain restore (same warm
   toolchain; A-key = runner image + OS fingerprints + script hash — same for
   all runs). B-layer **restore-only** on every measured run
   (`cache-save-enabled: 'false'`, composite accepted — verified input).
   The restored payload comes from ONE provisioning dispatch (`warm: true`)
   that SAVES the B entry (exact key: `axiom-b-<ref>-<recipe_hash><a_fp>`).
   `build/gateway-tests/**` (the runner's per-test binaries, its isolated
   nimcache, logs, incremental cache) is never B-cached → every measured run
   compiles the gateway test binaries **native-cold identically**.
3. **Bootstrap-verified identical state (fail-closed)**: the measure job
   asserts `bin/ax`, `bin/gate_hook`, `bin/precompile_gates`,
   `bin/install_ax_cas` and `.axiom/cache/lean_verify_hash.txt` exist after
   restore. Missing payload → run fails (never silently falls back to a
   native build, which would deviate from the measured initial state).
4. **One run → one observation**: each dispatch is ONE workflow run with
   exactly one active job (the other job is absent via `if:`), producing
   exactly one ingestable observation (W = run `updated_at` −
   `run_started_at`; skipped jobs don't occupy runners and are excluded by
   the ingest anchor rule).

### 2.2 Why a provisioning (warm) run is required

`make ci-compile` (gate_hook, precompile_gates, bin/ax, install_ax_cas)
takes ~8–20 min native-cold on 4 vCPU — the run-level W of every measured
run would carry a large constant additive term, pushing every candidate
far over the 15-min ceiling AND blowing the 200-minute budget (12+ native
ci-compiles ≈ 150–300 min alone). Also, the suite's prove tests
(`productization_start_vertical_slice_feature_test.nim`) run the REAL
`bin/ax prove --target normalizeMaxWorkers`; `ax prove`'s lean-verify
(`src/verification/lean_build_sandbox.nim verifyWithSandbox`) skips the
sandbox build when `.axiom/cache/lean_verify_hash.txt` matches the current
proofs hash — the file rides the B payload in production, so a fresh
checkout at this ref must materialize it once. The provisioning run:
ci-compile + recipe-precursor compiles (warm `build/nimcache` for the B
payload) + `ci-bootstrap-cheap` + ONE real `ax prove` (materializes the
lean-verify hash cache via the honest path) + fingerprint manifest + B
save. It is **never ingested** (its initial state differs by construction).

Fresh-checkout `lake build` (the lean sandbox's work) was verified locally:
**9 s, 20 jobs, EXIT 0** on a copy of `proofs/` without `.lake` — well
inside the 120 s `DefaultBuildTimeout`.

### 2.3 The measured command — recipe faithfulness (option (a), no Makefile edit)

Makefile:773 inlines `AXIOM_JOBS=$(if $(filter $(AXIOM_CI),1),2,$(shell nproc))`
in the recipe — neither a make command-line variable nor an environment
variable can override it (verified: Makefile has no `AXIOM_JOBS ?=` hook).
Instead of editing the Makefile (`?=` hook, option (b)), the workflow
replicates the `test-gateway` recipe at SHARD_COUNT=1 SHARD_INDEX=0 and
invokes the runner directly with the factor:

**Byte-identical lines (verified mechanically):**
```bash
nim c --hints:off -d:release -o:bin/run_gate src/cli/run_gate.nim
nim c --hints:off -d:release -o:bin/nimtry src/gate/nimtry.nim
nim c --hints:off -d:release -o:build/git_wrapper src/gate/utils/git_wrapper.nim
nim c --hints:off -d:release -o:build/command_policy_gate src/gate/utils/command_policy_gate.nim
nim c --hints:off -d:release -o:bin/hotspot_coverage_gate src/gate/runners/hotspot_coverage_gate.nim
nim c --hints:off -d:release -o:bin/conflict_marker_gate src/gate/runners/conflict_marker_gate.nim
nim c --hints:off -d:release -o:bin/golden_master_gate src/gate/runners/golden_master_gate.nim
nim c --hints:off -d:release -o:bin/all_gateway_runner tests/gateway/all_gateway_runner.nim
AXIOM_JOBS=<jobs> ./bin/all_gateway_runner --skip-known-failing=config/known_failing_gateway.txt \
  --probe-known-failing --junit-output=build/gateway-junit.xml <all files>   # awk -v s=0 -v n=1 'NR % n == s'
```

**Documented divergences (none affect the factor):**
1. `AXIOM_JOBS` = dispatch input (the factor) instead of the recipe's
   `$(if $(filter $(AXIOM_CI),1),2,$(shell nproc))`.
2. `mkdir -p bin build` precedes the compiles (the recipe implicitly relies
   on those dirs existing from artifact download / B-restore; we make it
   explicit — no semantic change).
3. Shard-file list is materialized with `mapfile` + the same
   `ls | sort | awk -v s=0 -v n=1` command → identical argv array.
4. `make test-gateway-shard-audit SHARD_COUNT=1` (partition identity:
   union == full list && pairwise disjoint) instead of SHARD_COUNT=8 (the
   measured sharding is 1; the audit still asserts the same fail-closed
   partition predicate).
5. `ci-bootstrap-cheap` runs from the restored payload instead of
   downloaded ci-bootstrap artifacts (same 4 binaries, digest-verified).
6. Env parity with production shards kept: `AXIOM_PROVE_WORKERS: "1"`.

---

## 3. Trace pre-registration (parent must commit these FIRST)

The existing `data/ci_pareto/trace_train.json` (n=3, demo candidates
fast/slow) cannot be reused: ingest refuses candidates not declared in the
trace config (exit 2). S2 needs its own pre-registered TRAIN traces.

**Why n=2 (not the trace_train n=3):** harness `compare` requires `n`
observations per candidate; with two candidate-pairs and a ≤200-min budget
the n=3 sweep is expected at 250–320 min (§7), while n=2 (both orders
present ⇒ counterbalance invariant satisfied for n≥2) lands at ≈185–235
with the runbook stop rules. Pre-registered N is fixed per trace; pair
indices in the runbook must fit n=2.

```bash
export H=build/pareto_harness_v4
$H prepare-train --out:data/ci_pareto/trace_s2_jobs24_train.json \
  --cand-a:"jobs2:AXIOM_JOBS=2 ./bin/all_gateway_runner --skip-known-failing=config/known_failing_gateway.txt --probe-known-failing --junit-output=build/gateway-junit.xml" \
  --cand-b:"jobs4:AXIOM_JOBS=4 ./bin/all_gateway_runner --skip-known-failing=config/known_failing_gateway.txt --probe-known-failing --junit-output=build/gateway-junit.xml" \
  --arrivals:6 --duration-min:1 --seed:42 --n:2 --arrival-rate:24
$H prepare-train --out:data/ci_pareto/trace_s2_jobs28_train.json \
  --cand-a:"jobs2:AXIOM_JOBS=2 ./bin/all_gateway_runner --skip-known-failing=config/known_failing_gateway.txt --probe-known-failing --junit-output=build/gateway-junit.xml" \
  --cand-b:"jobs8:AXIOM_JOBS=8 ./bin/all_gateway_runner --skip-known-failing=config/known_failing_gateway.txt --probe-known-failing --junit-output=build/gateway-junit.xml" \
  --arrivals:6 --duration-min:1 --seed:142 --n:2 --arrival-rate:24
```

- Seed 42 mirrors the demo trace; trace 28 uses 142 (distinct content).
- Candidate ids sort A=jobs2 < B=jobs4/jobs8 → `candidateA`=jobs2 in both
  compares. Order labels are declared per pair (A->B / B->A) and must be
  IDENTICAL for both candidates at the same pair index (compare enforces
  this, exit 2 otherwise).
- The targets are documentation-only (ingest never executes them).
- Commit: workflow file + this protocol + the two trace files
  (experiment plane CONTROLLED scope: workflow/data/spec/tools/test + the
  `data/ci_pareto/**` glob).

---

## 4. Pair mapping (runs → trace slots → orders)

Both comparisons share the baseline candidate jobs2 (A). Per comparison,
n=2 counterbalanced pairs:

| Trace (cycle) | Pair | iter | Candidate | order (declared, used verbatim in ingest) |
|---|---|---|---|---|
| trace_s2_jobs24_train.json | 1 | jobs2 | A | `"--order:A->B"` |
| trace_s2_jobs24_train.json | 1 | jobs4 | B | `"--order:A->B"` |
| trace_s2_jobs24_train.json | 2 | jobs2 | A | `"--order:B->A"` |
| trace_s2_jobs24_train.json | 2 | jobs4 | B | `"--order:B->A"` |
| trace_s2_jobs28_train.json | 1 | jobs2 | A | `"--order:A->B"` |
| trace_s2_jobs28_train.json | 1 | jobs8 | B | `"--order:A->B"` |
| trace_s2_jobs28_train.json | 2 | jobs2 | A | `"--order:B->A"` |
| trace_s2_jobs28_train.json | 2 | jobs8 | B | `"--order:B->A"` |

Chronological order = declared order (jobs2 first on A->B pairs, the
raised config first on B->A pairs), which keeps the recorded order label
honest.

---

## 5. Runbook (exact parent commands)

### 5.1 Provision the B payload (once)

> Dispatch mechanics: `gh workflow run <file> --ref <exp-branch>` targets the
> BRANCH CARRYING the workflow + traces (the experiment branch the parent
> commits to); the `-f ref=<sha>` INPUT is the MEASURED commit (b529ad466 —
> checked out by the job, and the B-key's cache-build-source). The two differ
> by design.

```bash
gh workflow run gateway-jobs-measure.yml --ref optimize/ci-pareto \
  -f warm=true -f ref=b529ad466
# record RUN_ID from `gh run list -w gateway-jobs-measure.yml -L 1`; then
gh run watch <WARM_RUN_ID> --exit-status --interval 30
```
On success: run ONE sanity `gh api .../actions/cache`-independent probe —
simply dispatch the first measured run; its "Verify B-layer provisioned
prerequisites" step is the fail-closed check.

### 5.2 Measured dispatches (8; sequential, in table order)

```bash
W="gateway-jobs-measure.yml"
# --ref <exp-branch>: the branch carrying the workflow + traces
gh workflow run $W --ref optimize/ci-pareto -f jobs=2 -f iter=1 -f ref=b529ad466   # <- comp24 pair1 A (jobs2)
gh workflow run $W --ref optimize/ci-pareto -f jobs=4 -f iter=1 -f ref=b529ad466   # <- comp24 pair1 B (jobs4)
gh workflow run $W --ref optimize/ci-pareto -f jobs=2 -f iter=2 -f ref=b529ad466   # <- comp24 pair2 A (jobs2, B->A)
gh workflow run $W --ref optimize/ci-pareto -f jobs=4 -f iter=2 -f ref=b529ad466   # <- comp24 pair2 B (jobs4, B->A)
# ledger gate S3 (§7) — if consumed > 120 min, STOP and go to §5.4
gh workflow run $W --ref optimize/ci-pareto -f jobs=2 -f iter=1 -f ref=b529ad466   # <- comp28 pair1 A (jobs2)
gh workflow run $W --ref optimize/ci-pareto -f jobs=8 -f iter=1 -f ref=b529ad466   # <- comp28 pair1 B (jobs8)
gh workflow run $W --ref optimize/ci-pareto -f jobs=2 -f iter=2 -f ref=b529ad466   # <- comp28 pair2 A (jobs2, B->A)
gh workflow run $W --ref optimize/ci-pareto -f jobs=8 -f iter=2 -f ref=b529ad466   # <- comp28 pair2 B (jobs8, B->A)
```
Each dispatch returns a RUN_ID; record them in order
(`run24a1, run24b1, run24a2, run24b2, run28a1, run28b1, run28a2, run28b2`).
Observe each to completion with `gh run watch <ID> --exit-status --interval 30`
(AGENTS.md §2.3 — no hand polling). A failed run = that slot has no
observation; ingest will then exit 2 on compare (incomplete pairing). A
failed run MAY be re-dispatched (its slot carries no record yet) — the
duplicate-protection is per-recorded-observation, not per-run.

### 5.3 Ingest (one per run, with --record; shell-quote `"--order:A->B"`)

```bash
./build/pareto_harness_v4 ingest \
  --github-run:<RUN24A1> --candidate:jobs2 \
  --trace:data/ci_pareto/trace_s2_jobs24_train.json \
  --pair-index:1 "--order:A->B" --repo:Archright/Axiom --record
```
Full mapping (candidate/pair-index/order from §4 table; `--repo` optional —
origin is parsed if omitted):

| slot | run id | trace | candidate | pair | order |
|---|---|---|---|---|---|
| 24a1 | RUN24A1 | trace_s2_jobs24 | jobs2 | 1 | A->B |
| 24b1 | RUN24B1 | trace_s2_jobs24 | jobs4 | 1 | A->B |
| 24a2 | RUN24A2 | trace_s2_jobs24 | jobs2 | 2 | B->A |
| 24b2 | RUN24B2 | trace_s2_jobs24 | jobs4 | 2 | B->A |
| 28a1 | RUN28A1 | trace_s2_jobs28 | jobs2 | 1 | A->B |
| 28b1 | RUN28B1 | trace_s2_jobs28 | jobs8 | 1 | A->B |
| 28a2 | RUN28A2 | trace_s2_jobs28 | jobs2 | 2 | B->A |
| 28b2 | RUN28B2 | trace_s2_jobs28 | jobs8 | 2 | B->A |

Sanity: dry-run (omit `--record`) first for one slot → expect
`W (end-to-end) = <ms>` and the two `WARN` lines (queueLenAtStart=0,
stratum=cold — the honest GH-API stratum; identical for every config).

### 5.4 Compare + selection

```bash
./build/pareto_harness_v4 compare --trace:data/ci_pareto/trace_s2_jobs24_train.json
./build/pareto_harness_v4 compare --trace:data/ci_pareto/trace_s2_jobs28_train.json
```
First compare on a trace locks its cycle in `data/ci_pareto/cycle_registry.json`;
envelopes land in `build/ci_pareto/compare/` (gitignored; copy the two
envelope files + sha headers into the evidence record).

**3-way decision rule (documented extension of the binary compare):**
- `P95(jobs2) = max(P95 jobs2 from envelope-24, P95 jobs2 from envelope-28)`
  (conservative upper estimate of the shared baseline; the two traces are
  independent samples of the same workload).
- `P95(jobs4)` / `P95(jobs8)` from their envelopes.
- `c* = argmin` over the three; ties by the v13 chain (λ_observed_max →
  mean queue → mean exec → id ascending), reading the tie-break fields
  already present in the envelopes. λ_observed_max is computed by compare
  from the records (L2 observations only — single load; observed proxy,
  not a bound).
- Report `withinRegressionCeiling` per config (likely `false`: measured W
  includes the full job wall of a full-suite run; the flag is a CEILING,
  not a ranking input).

Holdout (P5) is out of scope for this diagnostic arm.

---

## 6. Budget estimate and ledger

Per-run wall estimates (ubuntu-24.04, A-layer hit, B restored):

| Component | jobs=2 | jobs=4 | jobs=8 |
|---|---|---|---|
| toolchain setup (A restore) | 2–4 min | same | same |
| B restore (~0.5–1 GB) | 1–3 min | same | same |
| bootstrap-cheap + audit | 1.5–2.5 min | same | same |
| recipe compiles (nimcache-warm → link) | 1–3 min | same | same |
| **measured runner (full suite)** | **18–28 min** | 9–16 min | 9–16 min* |
| junit upload | ~0.5 min | same | same |
| **run total** | **≈ 24–36** | ≈ 14–24 | ≈ 14–24 |

\* jobs=8 caps at countProcessors() (nproc=4 on ubuntu-24.04) — see §1.

| Ledger item | minutes (typ. / max) |
|---|---|
| warm provisioning (never ingested) | 30 / 50 (A-miss +20 on the very first dispatch; ci-compile 8–20; recipe compiles 3–6; prove 2–8; save 1–2) |
| comp24 (2× j2 + 2× j4) | 76 / 120 |
| comp28 (2× j2 + 2× j8) | 76 / 120 |
| **TOTAL** | **≈ 180 / 290** (target ≤ 200) |

**Stop rules (execute literally):**
- S1 — after warm: if B-save failed (cache save exception), STOP and report
  (measured runs would miss the identical-state gate).
- S2 — after the FIRST jobs=2 measured run (slot 24a1): if its run-level W
  (from `gh api .../runs/<id>` — or the ingest dry-run) exceeds 30 min, the
  jobs=2 suite is at the 35-min job-timeout edge → dispatch the remaining
  comp24 slots, finalize comp24, and DEFER comp28 to a follow-up cycle
  (new pre-registered trace; the comp24 comparison remains valid and
  complete).
- S3 — ledger gate after comp24 (§5.2): consumed > 120 min → STOP (defer
  comp28) and finalize the comp24 decision only.

---

## 7. Validity threats

1. **Runner hardware/image drift between dispatches** — mitigated: fixed
   runs-on label; A-key includes ImageOS/ImageVersion (any drift changes
   only the cache key, not the workload); sweep window is hours. Residual:
   per-run host variance — counterbalanced orders per pair.
2. **Cache initial-state drift** — mitigated: all runs restore the SAME
   B-key entry (same ref + recipe + runner image), digest-verified
   fail-closed; anything else (gateway-tests dir) is native-cold by
   construction. `build/gateway-tests` is gitignored and never cached —
   confirmed via `git check-ignore`.
3. **Commit-tree differences** — none by construction: every dispatch
   checks out the fixed `ref` input (default b529ad466); the ref is also the
   B-key's `cache-build-source`. If the parent later changes the default, a
   NEW trace/cycle + re-warm is required (pre-registration discipline).
4. **jobs=8 ≡ jobs=4 under the worker cap** — not a threat, an expected
   finding; provenance (`nproc`, runner `workers=N` INFO line) makes it
   observable.
5. **Queueing noise** (hosted-runner availability) — queueMs is part of W by
   the ingest convention (first-success-job start − run_started_at);
   identical stratum semantics (queueLenAtStart=0 + cold, WARNed) for all
   configs; pair interleaving is per-table.
6. **Lean-verify sandbox build** — on hash-miss the sandbox lake build must
   finish ≤ 120 s; locally measured 9 s (20 jobs) at this ref. The warm
   payload's lean_verify_hash.txt gives all measured runs the hash-hit path
   (identical to production shards).
7. **Within-run state writes** (ax prove writes evidence/certs into the
   worktree) — identical ref ⇒ identical writes; ephemeral VM per job.
8. **GitHub `updated_at` semantics** — same convention for every run
   (run-object completion marker, documented in README §ingest).
9. **15-min regression ceiling likely exceeded** for absolute W (full-suite
   job wall) — the ceiling is a flag only, never a ranking input; the
   DIFFERENCE across configs is the signal.
10. **`--probe-known-failing` / quarantined tests** — identical policy to
    production (same skip file), so the workload matches production.

---

## 8. Local validation (performed this session, before any dispatch)

| Check | Result |
|---|---|
| Workflow YAML parse (pyyaml; `on:`=True quirk handled) | OK — triggers: workflow_dispatch only; permissions contents: read; provision job adds actions: write (job-level); measure inherits least privilege |
| Admission/mint non-adoption | No reference to `gateway-jobs-measure` anywhere else in `.github/` (grep) |
| Composite inputs | `cache-save-enabled` (default 'true', 'false' → restore-only reader), `cache-build-source` (required) — accepted; A-save unconditional+guarded, B save caller-side (verified in action.yml) |
| Recipe faithfulness | Makefile:763-773 compile lines + runner argv vs workflow measured step — byte-identical modulo AXIOM_JOBS source and file-list mechanism (mechanical diff, §2.3) |
| Fresh lean sandbox lake build | `cp -r proofs → /tmp` (minus .lake) + `lake build`: **9 s, 20 jobs, EXIT 0** |
| Ingest planned sequence | 8 dry-runs (`--from-json` fixtures, W=1530000 ms each): exit 0 == 8/8; derived telemetry exact (queue 120000 / exec 1410000 / W 1530000; coreMin 23.0) |
| Ingest negative tests | B->C order 2; pair-index 3 > n=2 → 2; undeclared candidate → 2; conclusion failure → 2; status in_progress → 2; malformed JSON → 1 — all exact |
| Full record cycle + compare | 8× `--record` exit 0; duplicate rerun refused (2); both compares exit 0, counterbalanced pairs (A->B, B->A), complete pairing, envelopes with P95/tie-break fields; equal-fixture tie exercised the stable rule (jobs2) and the ceiling flag (false) |
| Repo untouched | Only `.github/workflows/gateway-jobs-measure.yml` + `docs/evidence/s2_protocol.md` added (uncommitted); all fixtures under /tmp; harness rebuilt to `build/pareto_harness_v4` (gitignored) |

---

## 9. Risks / unimplemented

- **Budget overrun** (worst case ≈ 290 min): the sanctioned response is S2/S3
  (complete comp24, defer comp28) — never to exceed the 50k ledger or to run
  unplanned native-cold compiles.
- **Warm-run B-save failure** (cache size/rate limit): fail-closed stop (S1);
  alternative warm with a reduced payload (drop `build/nimcache`) recorded as
  a deviation.
- **`make ci-bootstrap-cheap` on a restored payload** uses binaries NOT
  rebuilt at the measured ref if the warm payload were compromised — the
  manifest fingerprint (buildSha+bKey) binds them to the ref; restore-side
  digest verify is fail-closed in the composite.
- **Makefile hook (option (b))** deliberately NOT chosen — no Makefile diff
  to commit; the direct-invocation option (a) is byte-faithful (§2.3).
- **Not implemented**: holdout/verify-holdout (P5), characterize sweep
  (L1/L3), 3-way n=3 sweep (budget-infeasible — §3), non-aws runner arms
  (S3 sweep is a separate single-factor experiment).

---

## 8. S2 measurement results (round-3, ref=0a18291ee)

All 8 dispatches succeeded; measured commit ref `0a18291ee331…` (B-key
`cache-build-source`), warm B-cache (exp- namespace), harness v6.

**Run table (W = queue + exec, ingest convention):**

| run id | candidate | W (ms) | queue (ms) | exec (ms) | wall (min) |
|---|---|---|---|---|---|
| 36127165390 | jobs2 | 470000 | 5000 | 465000 | 7.83 |
| 36127169198 | jobs4 | 451000 | 4000 | 447000 | 7.52 |
| 36127173305 | jobs4 | 600000 | 5000 | 595000 | 10.00 |
| 36127177368 | jobs2 | 694000 | 4000 | 690000 | 11.57 |
| 36127181307 | jobs2 | 679000 | 4000 | 675000 | 11.32 |
| 36127184629 | jobs8 | 698000 | 6000 | 692000 | 11.63 |
| 36127188303 | jobs8 | 658000 | 5000 | 653000 | 10.97 |
| 36127193199 | jobs2 | 696000 | 5000 | 691000 | 11.60 |

Budget: 8 runs ≈ **82.4 runner-min** (Σ wall 7.83+7.52+10.00+11.57+11.32+
11.63+10.97+11.60) — inside the ≤200-min target.

**Envelope 24 (jobs2 vs jobs4), hash `5864cec95371…09a`:** P95 jobs2=
694000 ms, jobs4=600000 ms; ceiling true/true; λ 0.0623/0.0691 h⁻¹; mean
queue 4500/4500 ms; mean exec 577500/521000 ms; Δ 0.942 €/run (9.71%,
DIAGNOSTIC). **Winner: jobs4.**

**Envelope 28 (jobs2 vs jobs8), hash `2ae1143870a6…244`:** P95 jobs2=
696000 ms, jobs8=698000 ms; ceiling true/true; λ 0.0527/0.0535 h⁻¹; mean
queue 4500/5500 ms; mean exec 683000/672500 ms; Δ 0.158 €/run (1.38%,
DIAGNOSTIC). **Winner: jobs2.** Both hashes re-verified byte-identical on a
second compare run (envelope determinism).

**3-way verdict:** P95(jobs2) = max(694000, 696000) = **696000 ms**,
P95(jobs4) = **600000 ms**, P95(jobs8) = **698000 ms** → **c\* = jobs4**
(no exact P95 tie — tie-break chain not engaged). All three configs
`withinRegressionCeiling=true` (measured W ≤ 15 min; §5.4 "likely false"
prediction was conservative). Cost deltas diagnostic only.

**nproc cap finding:** every run log echoes `nproc=2` and the runner INFO
line `gateway tests=86 workers=2` — the runner was 2-vCPU, so
`countProcessors()` capped **all** configs at 2 workers (jobs4/jobs8 never
exceeded jobs2's pool; §1 expected nproc=4 — observed deviation below).
The AXIOM_JOBS factor therefore did not vary on the measured population;
the P95 differences (and the jobs4 selection) reflect counterbalanced
order/host variance, not parallelism. No config exercised > 2 workers, so
no evidence that raising AXIOM_JOBS lowers W — S2 arm stands as the cap
finding plus a mechanical v13 selection, pending a ≥4-vCPU re-run.