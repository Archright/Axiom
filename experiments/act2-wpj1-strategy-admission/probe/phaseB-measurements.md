# WP4-j.1 Phase B — getBitsBE E2E Replay Measurements

## Procedure

1. Created experiment directories: `runs/` and `probe/` under `experiments/act2-wpj1-strategy-admission/`.
2. Seeded `$AXIOM_STATE_DIR=/tmp/axanchor/wpk-state` with Axiom data files.
3. Ran `bin/ax prove --project nim-stew-clean-c75502c --target 'stew/bitops2.nim::getBitsBE' --limit 1` twice (Run A, Run B) with `timeout 300`.
4. Captured stdout+stderr to `runs/runA-stdout.txt` and `runs/runB-stdout.txt`.
5. Snapshot `z3_telemetry.jsonl` at 4 points: pre-Run A, post-Run A / pre-Run B, post-Run B.
6. Gathered git revisions for both repos.
7. Grep-extracted key terms from stdout: `getBitsBE`, `obligation`, `ogrGenerated`, `requests=`, `results=`, `psFail`, `srNoTransform`, `vtStructural`, `ir-cas`, `drop`.

## Subject & Toolchain

| Field | Value |
|---|---|
| Project under test | nim-stew (`-clean-c75502c`) |
| Subject | `stew/bitops2.nim::getBitsBE` |
| Subject revision | `c75502ceedb5ed2a37b7b5e4744fc71313682859` |
| Axiom revision | `44fefd470fc6ad9c24ba40350d5721d4d6a9605c` |
| AXIOM_STATE_DIR | `/tmp/axanchor/wpk-state` |
| Command | `bin/ax prove --project ... --target 'stew/bitops2.nim::getBitsBE' --limit 1` |

## Run Results

| Metric | Run A | Run B |
|---|---|---|
| Exit code | 2 | 2 |
| Output lines | 94 | 94 |
| Determinism (ts-stripped diff) | IDENTICAL | — |
| getBitsBE CAS key | `cf4013de...` | `cf4013de...` (same) |

Exit code 2 is the expected PERSIST FAIL from unrelated `safeSpeedupRatioCore`/`proximityScore` certificate promotion failure — not an anomaly for this experiment.

## Key Observations from stdout

### getBitsBE Decision Chain

1. **Classification** (line 19): `getBitsBE → vtStructural (complex body operations)`
2. **IR CAS** (line 20): `MISS func=getBitsBE key=cf4013de578c923dc566aa3817b01b76927bfeac1b4f4fed1a41a1b07dd8c556`
3. **Proof failure** (lines 27, 43): `getBitsBE status=psFail provenance=solverMethod=smNone,provenance=pkNone`
4. **Strategy selection** (line 94): `→ getBitsBE: structural_ast (io_boundary)`
5. **Skip reason** (line 87): `⚠ getBitsBE — skipped: srNoTransformApplied`
6. **Structural AST result** (lines 85-88): `✓ getBitsBE — structural verification` / `StructuralAST: succeeded` then `⚠ ... skipped: srNoTransformApplied` / `StructuralAST: failed (unknown)`
7. **UAP gate** (lines 40, 78): `UAP produced 0 results (requests=1)`

### Obligation Pipeline Summary

- IR extraction: 6/229 entries (limit=1)
- Proof summary: Total=6, Pass=3, Fail=3, TO=0, Skip=0, Error=0
- 6 obligations extracted; 3 pass (normalizeMaxWorkers, calcDynamicTimeoutCore, clampTimeoutMs), 3 fail (safeSpeedupRatioCore, proximityScore, getBitsBE)
- All 3 failures share `solverMethod=smNone` — no solver was invoked for any of them

## Q1–Q6 Summary

| Q | Question | Answer | Key Evidence |
|---|---|---|---|
| Q1 | getBitsBE에 obligation이 존재하는가? | **YES** | `getBitsBE → vtStructural` (L19), `psFail` (L27), IR extraction 6 entries (L6) |
| Q2 | strategy가 applicable하지 않은 것이 proof rejection의 원인인가? | **NO** | Strategy `structural_ast` was selected (L94); failure is `srNoTransformApplied`, not strategy-inapplicability |
| Q3 | 다른 applicable strategy가 존재하는가? | **UNKNOWN** | Stdout mentions only `structural_ast`; no other strategy enumerated |
| Q4 | strategy failure가 psFail로 승격되는가? | **YES** | `srNoTransformApplied` (L87) → `psFail solverMethod=smNone` (L27, L43) |
| Q5 | srNoTransformApplied가 execution-not-attempted를 의미하는가? | **YES** | "skipped" (L87), `solverMethod=smNone` (L27, L43), `StructuralAST: failed (unknown)` (L88) |
| Q6 | obligation이 존재하는데 실행 대상 목록에서 제거되는가? | **YES** | getBitsBE in IR pipeline (L19-20, L27, L43) but "skipped" (L87); UAP 0 results despite 1 request (L40, L78) |

## Strategy-Unavailable → Proof Failure Promotion

**Runtime evidence-based judgment: YES, srNoTransformApplied promotes to psFail.**

The pipeline shows:
1. getBitsBE is classified as `vtStructural` and enters the IR pipeline.
2. The `structural_ast` strategy is selected (line 94).
3. The structural transform is not applied (`srNoTransformApplied`, line 87).
4. The proof status becomes `psFail` with `solverMethod=smNone` (lines 27, 43).
5. The UAP gate produces 0 results from 1 request (lines 40, 78).

The `srNoTransformApplied` skip is not a benign "not applicable" — it is recorded as a pipeline failure (`psFail`) that propagates to the final `PERSIST FAIL` exit code. The strategy was applicable (selected), but its transform was not executed, and this absence of execution is treated as a proof failure, not a "no obligation" or "vacuous" result.

## Telemetry Snapshots

- `probe/telemetry-pre-runA.jsonl` — 33 lines (pre-existing)
- `probe/telemetry-post-runA.jsonl` — 44 lines (33 + 11 new Z3 queries from Run A)
- `probe/telemetry-pre-runB.jsonl` — 44 lines (identical to post-runA)
- `probe/telemetry-post-runB.jsonl` — 55 lines (44 + 11 new Z3 queries from Run B)

The 11 new entries per run are Z3 SMT queries with `query_type=unknown`, all returning `sat` or `unsat` with `cegar_iters=0`. The canonical envelope digests are identical between runs (only timestamps differ), confirming deterministic Z3 query generation.

## Limitations

- `obligationCount` (6) is from the IR extraction summary in stdout, not from a dedicated obligation enumeration command. The task background mentions 13 intrinsic proof obligations for getBitsBE, but stdout shows 6 IR entries in this run — likely due to the `--limit 1` flag restricting the extraction scope.
- `obligationKinds` is limited to `vtStructural` and `vtSmtNative` as explicitly shown in stdout classify lines.
- Q3 (other applicable strategies) is UNKNOWN because stdout does not enumerate the full strategy registry.
- No `ogrGenerated` or `drop` lines were found in stdout — these terms do not appear in the observed output.