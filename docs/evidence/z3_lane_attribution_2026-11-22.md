# Z3 lane-attribution instrumentation - evidence (2026-11-22)

> Scope: instrumentation-only change on branch `perf/z3-lane-attribution` that
> adds lane attribution to the Z3 telemetry JSONL record (`execution_path`,
> worker acquire/roundtrip time, worker PID, RSS delta, get-model flag) and
> makes `queryType` explicit at every Z3 dispatch site.
> Recorder != approver: the recorder is an agent, the approver is the user
> (wintrover). This document records measurements only. The meaning of the
> canonical digest is owned by `docs/spec/execution_accounting_contract.md`.

## 1. Baseline and environment

| Item | Value |
|---|---|
| Base commit | `be6c14c2` (clean tree at branch creation) |
| Branch | `perf/z3-lane-attribution` (not pushed) |
| Host | 16 CPU, Linux 6.17.0-42-generic x86_64 |
| Nim | 2.2.10 |
| Build | `make build` exit 0 (42 s observed) |

The baseline was taken with the pre-change binary built at `be6c14c2`. The
post-change measurement used the rebuilt binary from this branch. Both runs
used a private state directory seeded by copying `data/`, and the same target.

Baseline command (post-change run is identical):

```sh
rm -rf /tmp/axiom_s1_pre && mkdir -p /tmp/axiom_s1_pre && cp -a data /tmp/axiom_s1_pre/data
AXIOM_STATE_DIR=/tmp/axiom_s1_pre AXIOM_CI=1 ./bin/ax prove --target normalizeMaxWorkers
AXIOM_STATE_DIR=/tmp/axiom_s1_pre ./bin/ax report --canonical-digest
```

## 2. Observations

| Observation | Baseline (pre-change) | Post-change |
|---|---|---|
| prove exit | 0 | 0 |
| report exit | 0 | 0 |
| canonical digest | `868d15ffb781caee65d26db4b4a0a920baae4ff848883027e3756bd16a3c1ac1` | `ca43e5914e4f817c22b3616a7ba2a96f32ae23bf2826ae6370b7244cfa44a240` |
| verdict | PASS / PASS | PASS / PASS |
| telemetry rows | 1 | 1 |
| `query_type` | `unknown` | `ir_pipeline_dual` (see 2.1) |

Baseline telemetry row:

```json
{"ts":"2026-11-21T15:11:39Z","query_type":"unknown","rlimit":30000000,"result":"error","time_ms":25,"memory_mb":36,"cegar_iters":0,"base_case_result":"","step_case_result":"","canonical_envelope_digest":"9a4c18ad2dd7187793fb56296cd1e72bac9561058813a7db8573e96dbde017f8","transport_payload_digest":"498db9bba63fa30c702d09550000af497add20f2ed59841aa3df940602070ac1"}
```

Post-change telemetry row (pre-fix build; the label is unchanged by the fix --
see 2.1 for why):

```json
{"ts":"2026-11-21T15:25:29Z","query_type":"ir_pipeline_dual","rlimit":30000000,"result":"error","time_ms":23,"memory_mb":36,"cegar_iters":0,"base_case_result":"","step_case_result":"","canonical_envelope_digest":"9a4c18ad2dd7187793fb56296cd1e72bac9561058813a7db8573e96dbde017f8","transport_payload_digest":"498db9bba63fa30c702d09550000af497add20f2ed59841aa3df940602070ac1","worker_acquire_ms":2,"worker_roundtrip_ms":20,"execution_path":"persistent","worker_pid":130588,"rss_before_kb":6620,"rss_after_kb":13140,"rss_delta_valid":true,"get_model_requested":true}
```

### 2.1 Lane label: the defect was latent, and the fix is now observable

The string overload `runZ3CheckViaIR(smtScript, ...)` is the shared body of four
distinct dispatch legs. Before this change it passed the literal
`queryType = "ir_pipeline_dual"` for all four, so a row produced by any other leg
would have been filed under the dual lane.

For `--target normalizeMaxWorkers` the leg that runs is the dual leg: it is
dispatched at `ir_pipeline_runner.nim:720` inside the `canonicalResult.success`
branch, which returns `IrPipelineResult` immediately afterwards. The BMC leg
(`:1366`) is reached only when the canonical path declines. Byte reconstruction
cannot separate the two for this subject, because
`irToSmtScript(funcDef, includeOverflowDefines = false, logic = dualSmtLogic)` and
the plain `irToSmtScript(funcDef)` emit the same bytes here -- the label is the
only field that identifies the producing leg. An earlier draft of this document
claimed `9a4c18ad...17f8` was the BMC leg; that claim is retracted. It is the
dual leg, and the pre-fix row was labeled correctly by luck, not by construction.

Fix: `queryType` is now a required parameter on both `runZ3CheckViaIR` (script
overload) and `z3ExecPersistent` -- no default, so a new dispatch site cannot
compile without naming its lane. The four script legs record
`ir_pipeline_dual`, `ir_pipeline_chc`, `ir_pipeline_chc_legacy`,
`ir_pipeline_bmc`. The `IRFuncDef` overload keeps `ir_pipeline_bmc`.

Observable result: five fresh post-fix runs still record `ir_pipeline_dual` for
this target, which is now a positive statement (the dual leg ran) rather than an
artifact of a shared label.

Notes:

- The approved plan recorded 41 ms for the baseline row; the observed value is
  25 ms. The envelope and result bytes are unchanged (`9a4c18ad...`, `error`);
  `time_ms` is wall-clock and varies between runs.
- A second post-change run in a fresh state directory reproduced
  `ca43e591...a240` exactly, so that build's post-change digest is deterministic.
- Re-digesting the baseline state directory with the post-change binary yields
  `28bb525f16768fb60f0285138d0647d754d955d5a9553d26bb50f4a446250114`
  (a third value). This is direct evidence that the digest depends on binary
  source identity, not only on run content.

### 2.2 Post-fix repeatability (committed build `2be9f281`)

Five fresh state directories, each seeded with `cp -a data`, same command:
`AXIOM_STATE_DIR=<dir> AXIOM_CI=1 ./bin/ax prove --target normalizeMaxWorkers`,
then `./bin/ax report --canonical-digest`.

| Run | prove exit | report exit | wall (s) | canonical digest | telemetry rows |
|---|---|---|---|---|---|
| 1 | 0 | 0 | 5.86 | `57f400bc34485e26bfcd74bab52ce3e696655ed6d6e9bb9ccd562836bb2fe85c` | 1 |
| 2 | 0 | 0 | 5.84 | `57f400bc34485e26bfcd74bab52ce3e696655ed6d6e9bb9ccd562836bb2fe85c` | 1 |
| 3 | 0 | 0 | 5.86 | `57f400bc34485e26bfcd74bab52ce3e696655ed6d6e9bb9ccd562836bb2fe85c` | 1 |
| 4 | 0 | 0 | 5.86 | `57f400bc34485e26bfcd74bab52ce3e696655ed6d6e9bb9ccd562836bb2fe85c` | 1 |
| 5 | 0 | 0 | 5.84 | `57f400bc34485e26bfcd74bab52ce3e696655ed6d6e9bb9ccd562836bb2fe85c` | 1 |

- Every run: `runOutcome.verdict = PASS`, `basis = PROVEN`,
  `gateVerdict = PASS`.
- `query_type = unknown`: 0 rows out of 5. Every row is `ir_pipeline_dual`.
- Envelope identity is stable across all five rows:
  `9a4c18ad2dd7187793fb56296cd1e72bac9561058813a7db8573e96dbde017f8`,
  `transport_payload_digest`
  `498db9bba63fa30c702d09550000af497add20f2ed59841aa3df940602070ac1`.
- Cross-run state equality: after removing the 42 volatile keys declared in
  `canonical_projection.nim` plus the three source-identity keys
  (`executionIdentity.verifierBuildId`, `summary.symbolCount`,
  `summary.bodyLoadCount`), run 1's entire state document equals each of runs
  2-5 exactly (0 differing paths, computed by recursive comparison).

## 3. Digest delta - root cause

### 3.1 The digest is a whole-tree hash of the run result

`docs/spec/execution_accounting_contract.md:225`:

> `canonicalRunDigest = sha256Hex(canonicalSerialize(runResult))` - the whole-tree
> canonical hash of the RUN RESULT (not the report document).

The same document states that digest changes at a fixed-key schema boundary are
"EXPECTED and correct (whole-tree canonical hash; no stored expected digest
exists)" (`docs/spec/execution_accounting_contract.md:234-237`).

### 3.2 Source identity is part of the hashed run result

`docs/spec/verifier_build_identity.md:31-40`, `:51-60`: `verifierBuildId` is a
chained sha256 over `(repo-relative path, sha256 of file bytes)` for every
`src/**/*.nim` file excluding `/generated/`, plus config files, `Makefile` and
dependency pins. Any patch under `src/` rotates it by construction.

This patch modifies `src/verification/solver/z3_pool.nim` and regenerates
`src/generated/type_registry_metadata.json`, so:

| Field | Baseline | Post-change |
|---|---|---|
| `executionIdentity.verifierBuildId` | `ea4e8aaf57296f16126ca811538371073b091e3dc10cfe1f2ab30f1206f4c479` | `1faafb84cb067879b6e698e321f28c47bae052571d9b287c8467ec86b243ce69` |
| `summary.symbolCount` | 16838 | 16841 |
| `summary.bodyLoadCount` | 2597 | 2598 |

### 3.3 Normalized comparison

The state canonicalization was re-implemented (volatile-key strip, `runtimeMeta`
strip, sorted keys, compact JSON, sha256). It reproduced both actual digests
exactly, which validates the method. Excluding the three source-identity keys
above (recursively, by key name) gives:

| Comparison | Value |
|---|---|
| baseline, source identity excluded | `283f6c30ca93514e2d569e5dcc0f7317207f61489cf0cd9ceff317cef3baeb22` |
| post-change, source identity excluded | `283f6c30ca93514e2d569e5dcc0f7317207f61489cf0cd9ceff317cef3baeb22` |
| `runOutcome` | equal |
| `runAccounting` | equal |
| `nodeReports` | equal |
| verdict | PASS / PASS |

Conclusion: the raw digest delta is fully explained by source-identity keys.
There is no behavioral, verdict, or accounting change. The step-7.4 requirement
that the post-change digest equal `868d15ff...1ac1` is unsatisfiable for any
patch that touches `src/`, because the digest transitively hashes the `src/`
tree. This is a plan-contract defect, not a code defect. The digest gate is NOT
claimed as passed.

### 3.4 Independent full-document comparison (no re-implemented hash)

The comparison above depends on a re-implementation of the canonicalizer. To
remove that dependency, the whole state documents were compared structurally
instead: parse both JSON files, recursively drop (a) every key listed in
`volatileKeys` in `src/core/utils/canonical_projection.nim` (42 keys, parsed
from the source at comparison time), (b) `runtimeMeta`, and (c) the three
source-identity keys, then diff every remaining path.

Result: **0 differing paths**. `runOutcome`, `runAccounting`, `nodeReports`,
`unitEvidenceRefs`, `eligibility`, `census`, `verificationQueue`, `gates`,
`closure`, `crossValidation` and `leanVerify` are identical; the only fields that
differ in the raw documents are the three source-identity keys and keys the
canonical projection already declares volatile. For example the sole difference
in `executionStats` is `depthStats[].startedAtMs/endedAtMs/elapsedMs/
parallelOverheadMs/activeNodeCount`, all of which are volatile by declaration.

This is a stronger statement than digest equality: it does not rely on any
hashing implementation, and it shows the semantic payload is unchanged while
showing exactly which fields moved.

## 4. D1 record - panic mode

Pinned toolchain: Nim 2.2.10. Release and danger builds set `--panics:on`
(`config.nims:47-49`). Nim manual, Panics section, verbatim:

> "When panics are turned on, the program dies with a panic, if they are turned
> off the runtime errors are turned into exceptions."

Source: https://nim-lang.org/docs/manual.html#panics (verified against the
pinned local copy at
`~/.choosenim/toolchains/nim-2.2.10/doc/html/manual.html`).

Decision: every new sampling or I/O site added by this change is inside
`try/except CatchableError`:

- `readProcStatusKb` (the single `/proc/<pid>/status` field parser);
- `getWorkerPeakMemoryMb` (refactored onto that parser, existing `try` kept);
- acquire-time sample and persistent PID/RSS sample in `z3ExecPersistent`;
- roundtrip start and success mark in the persistent dispatch loop;
- defer-time roundtrip fallback and same-PID `VmRSS` sample;
- one-shot `startProcess` PID/RSS sample and both roundtrip samples;
- `appendZ3Telemetry` execution-path normalization and JSON construction.

With panics on, runtime errors are Defects and are therefore not caught; a
defect aborts the process instead of being masked. The only swallowed failures
are best-effort `/proc` samples and the non-critical telemetry append, both
pre-existing and annotated `axiom:best-effort`.

## 5. D2 record - projection boundary

No change was made to `renderLegacyReport`, `renderPersist`, the projection
functions, scope-drift handling, or `verificationDecision`. The new keys are
produced only by the Z3 telemetry writer and sampled only in
`z3ExecPersistent`. `queryType` is now a required parameter of both
`z3ExecPersistent` and the script overload of `runZ3CheckViaIR` (the silent
`= "unknown"` / blanket `"ir_pipeline_dual"` defaults are gone); every call site
passes an explicit lane label. The dispatch labels in `src/` are: `gateway_prove`,
`gate_to_smt`, `vacuity_gate`, `ax_implication`, `ax_tautology`,
`ir_pipeline_dual`, `ir_pipeline_chc`, `ir_pipeline_chc_legacy`,
`ir_pipeline_bmc`, `refactor`, `cegar`, `healing`, `judge`, `fixedpoint_chc`,
`z3_provider`, `replay`, `triviality_filter`, `unsat_core_slice`,
`exec_z3_verified`, `spacer_chc`. The digest input shape is unchanged: the
raw-digest delta is the source-identity rotation described in section 3.

Contract references: `docs/spec/execution_accounting_contract.md:225` and
`:234-237` (whole-tree hash; no stored expected digest).

## 6. Field definitions

| Key | Type | Unit | Definition and zero semantics |
|---|---|---|---|
| `worker_acquire_ms` | int | ms | `epochMilliseconds() - startMs` measured after the lease and readiness barrier, so it includes the pre-dispatch preamble; 0 when the proc returns before a lease completes. |
| `worker_roundtrip_ms` | int | ms | Persistent: first payload write to sentinel/result (success marked before the post-query clean). Error/timeout: defer fallback from the first write. One-shot: `startProcess` to `waitForExit`, including kill+wait on timeout. 0 = never dispatched. |
| `execution_path` | string | enum | `persistent`, `one_shot_file`, or `none`. `none` = no query process dispatched; an empty string in a zero-initialized record serializes as `none`. |
| `worker_pid` | int | PID | Persistent: the leased worker at dispatch. One-shot: the `startProcess` PID. 0 = not sampled or no process. |
| `rss_before_kb` | int | kB | `VmRSS` of `worker_pid` sampled at dispatch. 0 = sample failed or no process. |
| `rss_after_kb` | int | kB | `VmRSS` of `worker_pid` sampled at defer time, persistent path only. 0 = sample failed, process exited, or worker restarted. |
| `rss_delta_valid` | bool | - | True iff `execution_path == "persistent"` and `worker_pid > 0` and `rss_before_kb > 0` and `rss_after_kb > 0`. |
| `get_model_requested` | bool | - | Final payload contains the literal `(get-model)`. |

## 7. Measurement

Pre-merge values are from the five runs in 2.2 (build `2be9f281`). The
main-acceptance rerun adds the same fields measured on the merged tree; until
then this table is branch evidence, not landing evidence.

| Measurement | Value (build `2be9f281`, 5 runs) |
|---|---|
| prove exit | 0 (5/5) |
| `runOutcome.verdict` / `basis` / `gateVerdict` | PASS / PROVEN / PASS (5/5) |
| canonical digest | `57f400bc34485e26bfcd74bab52ce3e696655ed6d6e9bb9ccd562836bb2fe85c` (5/5) |
| `query_type` | `ir_pipeline_dual` (5/5); `unknown` 0 rows |
| `worker_acquire_ms` | 2, 3, 3, 2, 2 |
| `worker_roundtrip_ms` | 17, 17, 17, 17, 17 |
| `time_ms` | 22, 22, 22, 22, 22 |
| `execution_path` | `persistent` (5/5) |
| `rss_before_kb` | 6768, 6688, 6688, 6660, 6652 |
| `rss_after_kb` | 13484, 13400, 13392, 13320, 13320 |
| `rss_delta_valid` | true (5/5) |
| `get_model_requested` | true (5/5) |
| `result` field | `error` (5/5) -- the `(get-model)` reply on an unsat query is `(error "model is not available")`; `classifyZ3Output` reads the first `unsat` token and skips the error line, so the verdict is `sosUnsat`. This field records the Z3 reply text class, not the verdict. |
| post-acceptance (main) digest | TBD after merge |

## 8. Verification performed

| Check | Result |
|---|---|
| `make build` | exit 0 (38.9 s, build `2be9f281`) |
| `bin/ax --check-provenance` | `OK -- embedded BuildSourceHash == live src tree`, exit 0 |
| `nim c -r --hints:off --nimcache:build/nimcache/vsi_z3tel -o:/tmp/vsi_z3tel tests/unit/test_z3_telemetry_attribution.nim` | 3/3 `[OK]`, exit 0 |
| `nim c -r --hints:off --nimcache:build/nimcache/vsi_budget -o:/tmp/vsi_budget tests/unit/z3_budget_clamp_test.nim` | all suites `[OK]`, exit 0 |
| `nim c -r --hints:off --nimcache:build/nimcache/vsi_bugverdict -o:/tmp/vsi_bugverdict tests/unit/test_bug_verdict_projection.nim` | 18 `[OK]`, no failures, exit 0 |
| `bin/debt_integrity_gate` | exit 0; 294 entries (28 open); 25 `{.axiomDebt.}` markers; no STALE |
| `.githooks/pre-commit` (commit `2be9f281`) | exit 0: nim check PASS, anti-theater PASS, layer enforcement PASS, decision-binding PASS, provenance PASS (6808 files) |
| 5 fresh prove runs | exit 0, PASS/PASS, identical digest, 0 `unknown` rows |
| Full-document state diff (3.4) | 0 differing paths after volatile + source-identity strip |
| `grep -P '[^\x00-\x7F]'` on this file | no match (ASCII only) |