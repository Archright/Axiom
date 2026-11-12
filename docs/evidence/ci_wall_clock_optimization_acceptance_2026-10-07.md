# CI Wall-Clock Optimization Production Acceptance — A-cache default-branch seeding + ci-compile -j4 (2026-10-07)

## Scope

Production observations for the two workstream slices landed this day, closing the merge-group wall-clock bottleneck mechanically attributed after the cert-ledger fact minimization ([cert_ledger_fact_minimization_acceptance_2026-10-06.md](cert_ledger_fact_minimization_acceptance_2026-10-06.md)):

- **#527** — PR #527 (mergeCommit `bc2fcc904`, merged 2026-10-07T01:39:55Z, +42/−1, single file `ci-cache-publisher.yml`): publisher A-cache default-branch re-seeding — removes the merge_group A-save branch-scope trap.
- **#531** — PR #531 (mergeCommit `71da39193`, merged 2026-10-07T03:07:02Z, single file `ci/checker.mk`, +6/−2): `ci-bootstrap` forwards `-j4` to its `ci-compile` sub-make.

Observation set: 13 consecutive `admission-gate` merge_group runs, 2026-10-06T23:57Z → 2026-10-07T03:07Z (queue heads `a43993e7` → `71da3919`), all `success`, plus a post-#531 validation extension of 3 further merge groups (2026-10-07T03:41Z → 04:13Z, queue heads `48f9d8edf` → `47d5695bb`), all `success` (recorded in the #531 section below). All timestamps below are verbatim from GitHub job logs / the Jobs API (`steps[].started_at`/`completed_at`, 1 s granularity).

## Background — the post-#512 bottleneck profile

After #512 zeroed the cert-ledger scan, the dominant merge_group wall-clock consumer is the `attest / build-base-artifacts` job ("job1"). Measured share across the 12 pre-#531 groups (definition: job1 `started_at`→`completed_at` over run `run_started_at`→`updated_at`): **53.2–66.5%, median ≈62%** (e.g. #520 group: 320 s / 544 s = 58.8%; #529 group: 337 s / 507 s = 66.5%). Internal decomposition in the A-cold regime (11 groups, n=11):

- `Run ./.github/actions/setup-axiom-toolchain`: **98–131 s** (median ≈110 s; max 131 s observed at the #520 group, job 112569174681, 00:26:05→00:28:16Z).
- `[build] Build bin/ax + harness from B`: **101–196 s** (serial builds throughout this window).

## PR #527 — publisher A-cache default-branch re-seeding (merged bc2fcc904, 2026-10-07T01:39:55Z)

- **Root cause (branch-scope trap).** The in-job A-save (`action.yml:647-666`, step "A-layer save (any run; first save wins; lock-complete or runtime)") executes inside merge_group runs whose branch is `gh-readonly-queue/main/pr-NNN-*`. Per GitHub's restore rule — "Workflow runs can restore caches created in either the current branch or the default branch (usually main)" — a cache written on a queue branch is invisible to every later group. Each group therefore paid a cold A setup.
- **Trap evidence (production logs, verbatim; same exact key in all three groups):**

```
01:31:47.5977175Z Cache not found for input keys: axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-f68ce8afffa41d74d496edc22da74983821d4f5d   [#527 group job 112587138588]
01:33:44.5671679Z Cache saved with key: axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-f68ce8afffa41d74d496edc22da74983821d4f5d            [#527 group job — saved into gh-readonly-queue/main/pr-527-*, trapped]
01:54:40.9547223Z Cache not found for input keys: axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-f68ce8afffa41d74d496edc22da74983821d4f5d   [#528 group job 112593018764]
01:56:29.2087630Z Cache saved with key: axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-f68ce8afffa41d74d496edc22da74983821d4f5d            [#528 group job — trapped again]
01:55:55.8556098Z Cache not found for input keys: axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-f68ce8afffa41d74d496edc22da74983821d4f5d   [#529 group job 112593333186]
01:57:48.2521794Z Cache saved with key: axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-f68ce8afffa41d74d496edc22da74983821d4f5d            [#529 group job — trapped again]
```

- **Fix (+42/−1, single file).** `ci-cache-publisher.yml` runs as `workflow_run` in the default-branch context, so the new `A seed` step re-runs `./.github/actions/setup-axiom-toolchain` (full scope) after a successful merge-group gate; the action's **pre-existing** internal A-save then lands in the default-branch scope. No new cache authority: same key domain (OS+gcc fp+glibc fp+script hash, `action.yml:163-173`), same lock-completeness guard, first-save-wins, `continue-on-error`, exact-key only, merge_group-only. The platform's low-trust default for `workflow_run` is read-only cache access ("Runs triggered by any other event that resolves to the default branch are given read-only access to caches in the default branch's scope"); the publisher already declares `cache-mode: write` (`ci-cache-publisher.yml:94`).

### Production acceptance

- **Seed write.** Publisher run 37559967895 (`workflow_run`, head_branch `main`, head_sha `bc2fcc904`, conclusion success), job 112594773486 — verbatim:

```
02:01:42.3981053Z Cache not found for input keys: axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-f68ce8afffa41d74d496edc22da74983821d4f5d
02:03:32.3646533Z Cache saved with key: axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-f68ce8afffa41d74d496edc22da74983821d4f5d
```

  (the seed provision itself ran A-cold; upload `Sent 1059718277 of 1059718277 (100.0%)`, save step `duration_ms=22282`).

- **First consumer.** #530 group (run 37561259135, head `015085783`, 02:17:16Z) — job1 112598799888, verbatim:

```
02:18:28.6704893Z Cache restored from key: axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-f68ce8afffa41d74d496edc22da74983821d4f5d
02:18:29.2517694Z AXIOM_CACHE_A_VERIFY: OK — nim=2.2.10 lean=4.33.0 z3=4.13.3 gccFp=8497f84b2b8334c4 glibcFp=e881beabc91bfbd3 key=axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-f68ce8afffa41d74d496edc22da74983821d4f5d
```

  setup-axiom-toolchain step 02:17:30→02:18:52Z = **82 s** (of which A-restore `duration_ms=57960`); the in-job A-save was auto-skipped by the restore-hit guard (`##[end-action id=__self.__actions_cache;outcome=skipped;conclusion=skipped;duration_ms=0]`).

- **Transition window behaved as predicted.** The two groups that ran between the #527 merge (01:39:55Z) and the seed completion (02:03:32Z) stayed cold — #528 group: setup **109 s**, "Cache not found" 01:54:40.9547223Z; #529 group: setup **113 s**, "Cache not found" 01:55:55.8556098Z. From the #530 group onward every merge_group restored the same exact A key (see table).

## PR #531 — ci-bootstrap forwards -j4 (merged 71da39193, 2026-10-07T03:07:02Z)

- **Change.** `ci/checker.mk:495` (inside the `ci-bootstrap` target at `:494`): `$(MAKE) -f ci/checker.mk ci-compile -j4`. Single file, +6/−2. `ci-bootstrap-cheap` stays serial (strictly sequential steps).
- **mtime-invalidation hypothesis — rejected.** (1) The B-restore payload (`action.yml:294-304`) contains only `build/nimcache`, `.axiom/cache`, `proofs/.lake`, `proofs/build`, `build/.axiom-b-fingerprint.json`, `bin/ax`, `bin/gate_hook`, `bin/precompile_gates`, `bin/install_ax_cas` — no source-tree paths, so a restore cannot touch source mtimes. (2) Nim 2.2.10's recompile decision (`compiler/cgen.nim:2215-2237 shouldRecompile`) consumes a frontend changed flag, a **content** comparison of the generated `.c` (`equalsFile`), and only `.o`-vs-`.c` mtimes (`os.fileNewer`) — never source `.nim` mtimes. (3) `actions/cache` extraction preserves archive mtimes (no `tar -m`). Details in the PR #531 body.

### Production observations — measured facts and an attribution correction

The two adjacent groups bracketing the #531 landing measured, via the Jobs API steps:

| job | group (queue head) | checked-out tree (job log, verbatim) | setup | `Build bin/ax + harness from B` | job1 total |
|---|---|---|---|---|---|
| 112598799888 | `015085783` (#530) | `ba4fb5694` | 82 s | **165 s** (02:19:11→02:21:56Z) | 285 s |
| 112609357306 | `71da39193` (#531 landing) | `015085783` | 66 s | **117 s** (03:00:45→03:02:42Z) | 206 s |

**The 165 s→117 s step delta is NOT a #531 effect, and this record retracts the draft claim that it is.** Verified from the logs:

- job1 checks out the group's **base** commit ("[build] Checkout B only (base.sha — verifier source)"): `02:59:26.5639808Z [command]/usr/bin/git checkout --progress --force 015085783340c3525b15a9a471d5c6b657604bdd`. `checker.mk` at `015085783` still has the serial recipe — the `-j4` line first exists in `71da39193`.
- Both builds ran serial: the sub-make echo is `make -f ci/checker.mk ci-compile` (no `-j4`), and the four `nim c` invocations start staggered (03:00:45.63 / 03:00:52.41 / 03:01:04.03 / 03:01:07.92Z) — the serial signature.
- The two built trees (`ba4fb5694` vs `015085783`) differ by **one docs file** (`git diff --stat`: 1 file, +17/−1), so the −29% residual is not the fan-out. **Update 2026-10-07: the −46 s residual is attributed — uniform hosted-runner VM speed variance (~1.4–1.5×) on the #530 runner — and the B-cache-warmth candidate confound (exact-key HIT in both jobs, probe PASS 1797 vs 1746 entries) is rejected; see "Residual closure" below.**

**job1 `-j4` production validation was therefore PENDING** at the time of the original record: it becomes exercisable only in a merge group whose base contains `71da39193`. No merge_group run existed after 03:07Z at recording time (API query `created=2026-10-07T03:00:00Z..23:59:59Z` returned none). **Update 2026-10-07T04:13Z: now exercised and measured — see "job1 `-j4` production validation — post-#531 groups" below in this section; the fan-out is confirmed, and no wall-clock effect is attributed.**

**Where the fan-out is visible in the landing group** (signature only, not a before/after — this lane always ran `-j4`, `ci/checker.mk:463` + `runner-pool-acceptance.yml:525,637`): `gateway / ci-bootstrap` job 112609602421 checked out `71da39193` (`03:00:23.2187000Z [command]/usr/bin/git checkout --progress --force 71da39193ef7665354ab6af5208e71189895407b`), ran `##[group]Run make ci-compile -j4`, and launched all four `nim c` invocations within 26 ms (03:01:02.7267398 / .7487715 / .7506219 / .7526324Z) — A-HIT, B-cold for the merge-commit tree (b-key `axiom-b-5cd7f10e…`), compile step 03:01:02→03:03:43Z (161 s).

- **Local A/B (commit `311d59e26` message, verbatim):** "Measured (same worktree, warm nimcache, same tree): plain ci-bootstrap 105.3s -> 94.1s (-10.6%); cold serial 115.3s". Execution-closure oracle: membership diff = the `checker.mk` blob entry only, UNRESOLVED 0, exit 0.

### job1 `-j4` production validation — post-#531 groups (measured 2026-10-07T03:41–04:13Z)

The next three merge groups have bases containing `71da39193` (ancestry verified: `71da39193` → `48f9d8edf` → `95da48f58`), so job1's base checkout finally exercised the changed path. All three `attest / build-base-artifacts` jobs ran the sub-make with the flag — verbatim from the logs: `03:42:55.9033439Z make -f ci/checker.mk ci-compile -j4` (#532 group), `04:05:08.7259479Z make -f ci/checker.mk ci-compile -j4` (#533 group), `04:07:24.8096264Z make -f ci/checker.mk ci-compile -j4` (#534 group) — and `ci/checker.mk:495` is `	$(MAKE) -f ci/checker.mk ci-compile -j4` at all three checked-out bases (`git show <base>:ci/checker.mk`). All three groups concluded `success` (job shape unchanged, no regression).

| job | group (queue head) | checked-out base (job log, verbatim) | A / B cache | setup | `Build bin/ax + harness from B` | job1 total | job1 share |
|---|---|---|---|---|---|---|---|
| 112619818994 | `48f9d8edf` (#532) | `71da39193` (03:41:45.6708705Z) | HIT / HIT (`buildSha=5cd7f10eb654`, probe PASS 1746) | 48 s | **171 s** (03:42:55→03:45:46Z) | 254 s | 61.7% (254/412) |
| 112625078712 | `95da48f58` (#533) | `48f9d8edf` (04:03:39.2465800Z) | HIT / HIT (`buildSha=3a55fd42a63f`, probe PASS 1746) | 70 s | **155 s** (04:05:08→04:07:43Z) | 258 s | 60.0% (258/430) |
| 112625745238 | `47d5695bb` (#534) | `95da48f58` (04:06:19.1490070Z) | HIT / **MISS** (`Cache not found for input keys: axiom-b-3e2d3464…`, probe `SKIP — no restored build/nimcache`) | 64 s | **150 s** (04:07:24→04:09:54Z) | 228 s | 57.1% (228/399) |

The B MISS in the #534 group is mechanically consistent: its base tree `95da48f58` was never built by an earlier job in the chain (the #533 group's `gateway / ci-bootstrap` lane was skipped), so no B save existed for it.

**Fan-out signature (verbatim `nim c` echo timestamps).** In all three job1s the four `nim c` invocations start within milliseconds — 03:42:55.9061243 / .9066411 / .9077094 / .9118234Z (#532 group, spread ≈6 ms); 04:05:08.7342085 / .7362405 / .7402975 / .7442181Z (#533 group, ≈10 ms); 04:07:24.8121235 / .8122522 / .8179958 / .8209439Z (#534 group, ≈9 ms) — versus the staggered serial signature recorded above (03:00:45.63 / 03:00:52.41 / 03:01:04.03 / 03:01:07.92Z, spread ≈22 s). Concurrency is also visible in the interleaved compile output (four `merkle concat` lines at 04:07:26.10–.13Z, four `build_env.nim seed guard` lines at 04:07:36.13–.22Z in the #534 group job).

**Measured wall-clock verdict — no `-j4` effect is attributable.** The three Build-step samples (171 / 155 / 150 s) straddle the serial references (165 s at job 112598799888; 117 s at job 112609357306). The B-warm-only comparison is serial {165, 117} vs `-j4` {171, 155} — overlapping ranges. Three confounds prevent attribution, and none is controlled in this observation set: (1) each sample built a **different tree** (bases `71da39193`, `48f9d8edf`, `95da48f58`; the #532 landing diff alone changes 15 files across `src/`, `proofs/`, and `tests/`, and the record above already shows a one-docs-file tree diff moving this step 165 s → 117 s); (2) cache state differs across samples (B-HIT vs B-MISS); (3) n=3 with no paired same-tree control. The locally measured −10.6% (≈ −11 s on this step) is below the observed group-to-group noise floor (tens of seconds). **The record therefore claims: the `-j4` path is exercised, correct, and regression-free in job1; it does not claim any job1 wall-clock improvement from these samples.** A decisive measurement would require same-tree paired runs (serial vs `-j4` on one base, cache state held fixed).

### Residual closure — the 165 s → 117 s (−46 s) delta attributed to hosted runner VM speed variance (measured 2026-10-07)

The unexplained residual recorded above is closed by a direct log-level comparison of the two serial builds. Pair: #530 group job 112598799888 (run 37561259135, runner `1000009370`) vs #531 landing job 112609357306 (run 37564604913, runner `1000009396`) — both `ubuntu-24.04`, both serial `checker.mk`.

- **Step deltas.** Build step 165 s vs 117 s (Δ−48 s); the sub-make `make -f ci/checker.mk ci-compile` wall clock is **155.36 s vs 109.24 s** (Δ = 46.12 s — the recorded "−46 s").
- **Same work, uniformly slower machine.** The `ax(-d:release)` stage logs, compared with timestamps stripped, are **1287 vs 1287 lines and identical as multisets** (sole difference: two gcc warning blocks emitted in swapped order). Timing the 1183 corresponding lines gives a per-line slowdown ratio with **median 1.447 (min 1.401 / max 1.463)** and ~2% drift across quintiles — a uniform ~1.45× slowdown of the whole compile, not a localized hot spot.
- **Warmth-independent controls** (operations with no gcc/nimcache dependence, same runner pair): nimcache probe (`nim check`, no gcc) 18.1 s vs 12.6 s = **1.43×**; identical apt transaction (`libpcre3` install) **19.97 s vs 7.94 s**; identical 1,059,718,277 B A-payload download **57.96 s vs 52.41 s**.
- **B-nimcache warmth — rejected.** B keys are tree-OID identities (`axiom-b-<tree>-<recipe>-<afp>`); both jobs were exact-key HITs of their **own** trees (49 MB / 77 MB restores; `Cache restored from key: axiom-b-…` in both). The restore-age difference (12 min vs 21 s) is immaterial — warmth is set by content identity, not cache age.
- **Input difference — rejected.** The tree diff between the two checked-out bases is the single docs file already recorded above (+17/−1) — not a compile input.
- **Attribution (closes the residual).** The #530 runner VM executed uniformly ~1.4–1.5× slower than the #531 runner VM across every measured operation class. The −29% figure is single-VM-pair hosted-runner variance; no code or cache change is associated with it.

## Cumulative measured state

| Metric | A-cold baseline (n=11 groups) | after #527 (#530 group, job 112598799888) | #531 landing group (job 112609357306) | post-#531 groups, `-j4` exercised (n=3; jobs 112619818994 / 112625078712 / 112625745238) |
|---|---|---|---|---|
| setup-axiom-toolchain | 98–131 s (median ≈110 s; 131 s = #520 group, job 112569174681) | **82 s** | **66 s** (A-restore `duration_ms=52410` — download-size variance, not a further mechanism) | **48–70 s** (A exact-key HIT in all three) |
| `Build bin/ax + harness from B` | 101–196 s | 165 s | 117 s (serial build of base `015085783`; **not** a #531 effect — see above) | **150–171 s** (171/155 B-HIT, 150 B-MISS; fan-out confirmed — **no `-j4` effect attributed**, see above) |
| job1 total | 232–341 s (320 s at the #520 baseline group) | 285 s (−10.9%) | 206 s (−35.6% vs #520 baseline) | **228–258 s** |
| job1 share of group wall | 53.2–66.5% | 60.0% | 47.1% | **57.1–61.7%** |
| A-cache state | cold every group (scope trap) | exact-key HIT | exact-key HIT | exact-key HIT (all three) |
| verdict semantics | GO | GO | GO | GO |

The setup column is the mechanically attributed #527 effect (131 s cold → 82 s/66 s restore-hit, same exact key, verifier `AXIOM_CACHE_A_VERIFY: OK` in every inspected consumer including the post-#531 column).

## Invariants verified unchanged

- **Exact-key only**: A/B restore steps are display-named "A-layer restore (toolchain — exact key only, no restore-keys)" / "B-layer restore (per-base build artifact — exact key only, no restore-keys)"; no restore-keys output appears in any inspected log.
- **A-verify fail-closed chain**: the discard branch is present and wired ("AXIOM_CACHE_A_VERIFY: DISCARDED — native install runs (fail-closed: cache is acceleration, never evidence)"); every inspected post-#527 consumer passed `AXIOM_CACHE_A_VERIFY: OK` with key-fingerprint echo (including the three post-#531 job1s).
- **B semantics unchanged**: `AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 entries digest-verified, buildSha=8c4d03f9f9c4, key exact-hit` (#530 group) and `…5/5…, buildSha=4e4c5a1cc8a6, key exact-hit` (#531 group); nimcache probe PASS in both (fail-closed discard path intact; the #534 group's B MISS degraded to probe `SKIP` + native build — the fail-open path, see above).
- **Cache = performance layer, never evidence (fail-open)**: per GitHub's eviction policy — "GitHub will remove any cache entries that have not been accessed in over 7 days" and "the cache eviction policy will create space by deleting the caches in order of last access date, from oldest to most recent" — cache loss degrades to native install/build, never to a missing supply or a wrong verdict.
- **Verdict path / required checks**: all 16 observed groups concluded `success` (13 in the primary observation set + the 3 post-#531 groups) with the same admission-gate job shape; no check name or gate semantics changed in either PR's diff (#527: publisher workflow only; #531: `checker.mk` build plumbing only).

## Policy status (recorded 2026-10-07)

### The 8-minute P95 is a policy SLO, not a constitutional invariant

The 8-minute P95 is **policy/SLO**, not a constitutional invariant. It remains the SLO of record; it is **not** treated as an automatic obligation to pursue further optimization. The next optimization step proceeds only with explicit Owner approval, bounded by a complexity budget. This record attaches no new optimization claim to that SLO.

### Bootstrap-scan parallelization — CLOSED

**CLOSED** (recorded 2026-10-07). Resumption condition: an explicit product requirement appears (e.g. "bootstrap recovery must complete within N seconds"). Closure rationale — a complexity-budget judgment: introducing a concurrency model (asyncdispatch + bounded concurrency + 429 retry + partial-failure semantics + deterministic evidence ordering) costs more than the expected benefit on the current evidence base. The "bootstrap ≈4.5%" figure occasionally cited in this debate is **NOT_FOUND in this repository's evidence base**; the nearest match, `data/ci_pareto_baseline.json`, records `ci-bootstrap 4.52` as **minutes of duration** ("FULL L2 (workflow_dispatch): select 0.42 + ci-bootstrap 4.52 + 8 shards ~4.55 ea + identity 0.17 + reconcile 0.12"), not a share of anything.

### `-j4` status re-confirmed

Production-exercised and fan-out-confirmed in job1 (four `nim c` starts within 6–10 ms in all three post-#531 groups, versus the ≈22 s staggered serial signature — see above); the wall-clock effect remains **unattributed** (samples straddle the serial references; tree/cache/runner confounds uncontrolled — see "Residual closure" above). A same-tree paired serial-vs-`-j4` experiment is **on-demand only**: it runs when a decision requires the number, not speculatively.

## Not claimed / Follow-up

- **#531 job1 wall-clock effect is measured-but-unattributed (not claimed).** The changed path is now exercised by three merge_group job1s (fan-out confirmed, all groups `success`); measured `Build bin/ax + harness from B` 171/155 s (B-HIT) and 150 s (B-MISS) vs serial references 165 s (job 112598799888) and 117 s (job 112609357306) — the deltas are within group-to-group variance, so no improvement is attributed to `-j4`. A decisive A/B requires same-tree paired runs (cache state held fixed); the local −10.6% effect (≈ −11 s on this step) is below the observed noise floor. Any such paired experiment is on-demand only (see Policy status above).
- **The 165 s→117 s attribution is retracted** as a #531 effect (both builds serial; adjacent base trees differ by one docs file). The −46 s residual between the two groups is **attributed and closed** — uniform hosted-runner VM speed variance on the #530 runner (measured ~1.4–1.5× across warmth-independent controls and per-line ratios; see "Residual closure" above). B-nimcache warmth was rejected as the confound.
- **Residual job1 dominance**: setup 66 s of which A-restore download is 52.4 s (`duration_ms=52410`) — further reduction (cache payload slimming / mirror) is a separate workstream.
- **V1 (gate-binary purge from the attest set)** remains out of scope: `repository_surface` v58 FROZEN — owner-policy path approval pending (implementation and verification done locally, retained, not landed here).
- **Bootstrap-scan parallelization is CLOSED** (see Policy status above) — it is no longer a follow-up; resumption requires an explicit product requirement. **Old-binary live comparison** remains a recorded-only follow-up from the #512 record; not scheduled.
- **Runner VM speed variance is a measurement confound going forward**: the measured ~1.4–1.5× single-pair spread (see "Residual closure" above) means future wall-clock comparisons of this step must use paired runs and/or multiple runner samples.
- Wall-share percentages depend on the stated wall definition (job duration over `run_started_at`→`updated_at`); narrower definitions shift individual values, not the dominance conclusion.
