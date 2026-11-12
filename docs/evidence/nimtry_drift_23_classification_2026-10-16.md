# nimtry drift classification — BUDGET#004 (ledger "0→23 closed→open") — 2026-10-16

Investigator: registry-hygiene-t2 workstream (chore/registry-hygiene-t2)
Investigation id: BUDGET#004 (`data/debt_ledger.json` metric `nimtry_violations`, current=23, status=open — drift recorded by agent N2 as pre-existing)
Verdict: **class (ii) present → DO NOT absorb. Baseline NOT updated, budget NOT synced, ledger left untouched (open). Production fixes are out of scope of this slice.**

## Method (READ-ONLY investigation, documented tooling only)

- Tree: dedicated worktree off fresh origin/main `c606c4373` (branch `chore/registry-hygiene-t2`), 2026-10-16.
- Tool: `bin/nimtry` built from current worktree source (`make bin/nimtry` → `src/gate/nimtry.nim`).
- Baseline: `data/nimtry_baseline.json` v2 protocol (created 2026-10-14T13:12:06+09:00, `total_violations` 4163, fingerprint-anchored violations[]).
- Report mode (the CLI's documented diff mode, `src/gate/nimtry/nimtry_cli.nim` `--diff-baseline`):

```
./bin/nimtry src/ --diff-baseline --list
# === Baseline Diff ===
# New: 19
# Resolved: 7
# Stable: 4156
#   NEW: ... (19 rows below)
```

- Gate reproduction (the evaluator command used by `bin/debt_engine --sync-budget` → `evalNimtryViolations` and `make check-arch`):

```
./bin/nimtry src/        # EXIT=1 — "[nimtry] FAIL: 7 new ERROR violations not in baseline (debt anchoring)"
```

- Count reconciliation: the ledger's `current: 23` is the recorded snapshot from the N2 measurement generation; the LIVE enumeration at this verification moment is **19 NEW** (fingerprint diff). The gate's fail-closed surface is the 7 new ERROR-severity items only (warnings are anchoring-neutral). Between the ledger snapshot and now, the baseline was regenerated (commits `8b3622c19`, `a74b7c01b` — "post-freeze 신규 위반 17건" anchoring), which re-based the diff; the numbers above are the current, tool-reported facts.

## Classification of the NEW violations (19 = 7 + 12 + 0)

### Class (i) — legitimate fixture/test extensions (approved absorb pattern): 7

All `SAFETY-language-ban` **error**-severity, all under `tests/fixtures/` (test data consumed by workflow-lane lint fixtures — the exact pattern previously absorbed via the official `--update-baseline` path in commit `02017aa03` "+2 fixture extensions via --update-baseline"):

| # | Severity | Rule | File | Landed by |
|---|----------|------|------|-----------|
| 1 | error | SAFETY-language-ban | tests/fixtures/workflow_lane_guard/lane_with_emission.yml | 3fb37fd12 (2026-10-15, PR #851 content — P1 lane-stderr mechanical gate fixtures) |
| 2 | error | SAFETY-language-ban | tests/fixtures/workflow_lane_guard/lane_without_emission.yml | 3fb37fd12 (2026-10-15, PR #851 content) |
| 3 | error | SAFETY-language-ban | tests/fixtures/workflow_poison/boundary_20999_tokenized.yml | a35708fb5 (2026-10-14, parse-poison lint boundary fixtures) |
| 4 | error | SAFETY-language-ban | tests/fixtures/workflow_poison/control_30000_token_free.yml | a35708fb5 |
| 5 | error | SAFETY-language-ban | tests/fixtures/workflow_poison/boundary_21000_tokenized.yml | a35708fb5 |
| 6 | error | SAFETY-language-ban | tests/fixtures/workflow_poison/poison_21001_tokenized.yml | a35708fb5 |
| 7 | error | SAFETY-language-ban | tests/fixtures/workflow_poison/poison_regression_25954.yml | a35708fb5 |

### Class (ii) — production-code violations (REAL — must NOT be absorbed): 12

All in `src/` production modules; every carrying file was modified **after** the 2026-10-14 baseline snapshot (post-baseline landing drift). These are genuine current-code violations of the SoC surface-area / SOLID-OCP / purity rules:

| # | Severity | Rule | File | Detail | Last touch (drift source) |
|---|----------|------|------|--------|---------------------------|
| 1 | warning | SOLID (soc-surface-area) | src/cli/merge_cli.nim | has 60 exported functions (layer cli max 20) — baseline anchored 58 | baad02b2a (2026-10-14) |
| 2 | warning | SOLID (soc-surface-area) | src/cli/merge_cli.nim | collectAdmissionFacts spans 84 effective SLOC (max 50) — baseline anchored 79 | baad02b2a (2026-10-14) |
| 3 | warning | SOLID (soc-surface-area) | src/infrastructure/external_ir_materializer.nim | materializeExternalIR spans 61 effective SLOC (max 50) | 6d016b5be (2026-10-15) |
| 4 | warning | SOLID (solid-ocp) | src/infrastructure/external_ir_materializer.nim | 7 case branches but 0 calls to registry functions [register, registerImpl] | 6d016b5be (2026-10-15) |
| 5 | warning | SOLID (soc-surface-area) | src/verification/batch_uap/loop_depth_scheduler.nim | processOneNodeParallelBody spans 200 effective SLOC (max 50) — baseline anchored 196 | b3b78110e (2026-10-15) |
| 6 | warning | SOLID (soc-surface-area) | src/verification/batch_uap/loop_depth_scheduler.nim | runParallelDepthBatchUap spans 196 effective SLOC (max 50) — baseline anchored 194 | b3b78110e (2026-10-15) |
| 7 | warning | SoC (soc-surface-area) | src/verification/batch_uap/loop_driver.nim | has 59 imports (layer verification max 30) — baseline anchored 58 | b3b78110e (2026-10-15) |
| 8 | warning | SOLID (soc-surface-area) | src/verification/batch_uap/loop_driver.nim | stage2Budget spans 267 effective SLOC (max 50) — baseline anchored 252 | b3b78110e (2026-10-15) |
| 9 | warning | SOLID (soc-surface-area) | src/verification/batch_uap/loop_driver.nim | runBatchUapOrchestration spans 588 effective SLOC (max 50) — baseline anchored 566 | b3b78110e (2026-10-15) |
| 10 | warning | PURITY-new-code-must-be-func | src/engine/profiler.nim:26 | new proc declaration in non-I/O module (AGENTS.md §0.6) | 297128b82 (2026-10-15) — module has ZERO baseline entries (entirely new since the snapshot) |
| 11 | warning | PURITY-new-code-must-be-func | src/engine/profiler.nim:36 | new proc declaration in non-I/O module | 297128b82 (2026-10-15) |
| 12 | warning | PURITY-new-code-must-be-func | src/engine/profiler.nim:47 | new proc declaration in non-I/O module | 297128b82 (2026-10-15) |

### Class (iii) — stale baseline entries: 0

`Resolved: 7` baseline fingerprints are **superseded same-file growth fingerprints**, not stale entries: verified against `data/nimtry_baseline.json`, the retired anchors are the predecessor readings of exactly the files above (merge_cli "has 58 exported functions", collectAdmissionFacts 79 SLOC, loop_driver 58 imports / stage2Budget 252 / runBatchUapOrchestration 566, loop_depth_scheduler 196/194 SLOC, and 1 further superseded fp) — each replaced by its grown successor in the NEW list. Nothing in the baseline references code that disappeared; no stale entry requires baseline-side cleanup.

## Decision (per the slice's decision rule)

The rule: absorb via `nimtry --update-baseline` **only if** all drift items are class (i) (+ optional class (iii)); if ANY class (ii) exists, leave the drift open and report.

- **12 × class (ii) present → NO baseline update, NO `debt_engine --sync-budget`, NO codegen-side budget change.** The ledger record BUDGET#004 stays exactly as found (current=23, status=open) — its number is now understood to be a superseded-generation snapshot, but reconciling it is a metric-sync action reserved for the branch where the live measurement is legitimately absorbable.
- Note the trap avoided: the gate's fail surface is the 7 class-(i) ERRORs, so a full `--update-baseline` would have passed the gate while silently anchoring the 12 class-(ii) production warnings as accepted debt — exactly the absorption this slice forbids.
- The 7 class-(i) fixture items are recorded here with their landing commits so a follow-up slice (with the class-(ii) items independently dispositioned — fix, refactor, or separately anchored with registry entries per the DEBT#505 pattern) can absorb them via the official `--update-baseline` path.
- Production fixes (splitting oversized functions, registry-dispatch for OCP, proc→func conversion in `src/engine/profiler.nim`) are **out of scope** of this slice.

## Reproduction commands

```
make bin/nimtry
./bin/nimtry src/ --diff-baseline --list   # New: 19 / Resolved: 7 / Stable: 4156
./bin/nimtry src/                          # EXIT=1, 7 new ERROR violations (all class i)
```

Cross-refs: `data/debt_ledger.json` BUDGET#004 · `data/debt_budgets.json` metrics/nimtry_violations · `data/nimtry_baseline.json` · precedent commits `02017aa03` (approved fixture absorb), `8b3622c19`/`a74b7c01b` (baseline regenerations), `src/gate/nimtry/nimtry_cli.nim` (--diff-baseline/--update-baseline, v2 fingerprint protocol) · `tools/debt_engine.nim` evalNimtryViolations.
