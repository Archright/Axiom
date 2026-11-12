# effect_violations DRIFT adjudication — projection 89 vs ledger 90 (pre-existing, reconciled upstream)

- **Date**: 2026-10-08
- **Branch**: `chore/effect-drift-resync` (worktree off `origin/main` @ `de4d587a4`)
- **Question**: the long-reported `bin/debt_engine` DRIFT — `effect_violations` projection **89** vs ledger **90** — flagged "pre-existing, unrelated" by multiple verification records. Which side is true, and does anything remain to reconcile?
- **Disposition**: NO-OP — drift was real and of type (a) (code changed, ledger lagged), and was **already reconciled upstream** by `1a3ea234d` via the sanctioned tool path. This record is verification-only evidence; it changes no code or data (0 diff beyond this document).

## 1. Mechanism (where each number comes from)

- **projection** = `bin/effect_contract_projection` stdout JSON `violations` field (deterministic AST-semantic scan of `src/core/` declarations). `debt_engine` consumes it via subprocess (`evalEffectViolations`, `tools/debt_engine.nim:1694`).
- **ledger** = `data/debt_ledger.json` record `BUDGET#003` (`metric: effect_violations`) `current` field.
- Comparison surface: `debt_engine --validate` Part D / `--sync-budget` metric evaluation — `DRIFT (projection=X vs ledger Y)`.

Projection tool source is **byte-identical from `c0d1a80d3` (2026-10-07) through `origin/main`** (`git diff --stat c0d1a80d3 origin/main -- src/verification/projections/effect_contract_projection.nim` = empty), so the current binary measures historical commits validly (it scans the CWD tree).

## 2. Historical projection measurements (decisive)

Measured by running `bin/effect_contract_projection` inside detached worktrees at each commit:

| commit | tree state | projection (`declarations`/`violations`) | ledger `BUDGET#003.current` | relation |
|---|---|---|---|---|
| `c0d1a80d3` (ledger 90 sealed, PR #539-era) | pre-DEBT#478 | 4136 / **90** | 90 | in sync at seal time |
| `8ffc94d89` (last ledger=90 state on main) | post-DEBT#478 | 4131 / **89** | 90 | **DRIFT — real, type (a)** |
| `1a3ea234d` (2026-10-07 17:05) | ledger regenerated | — | **89** | reconciled here |
| `de4d587a4` (= `origin/main` at adjudication) | current | 4137 / **89** | 89 | **in sync** |

- The only `src/core` commit in `c0d1a80d3..8ffc94d89` is `f878f61aa` — **DEBT#478 ambient severity authority closure** (AXIOM_UPDATE_BASELINE reader removal; evidence: `docs/evidence/debt478_ambient_severity_closure_2026-10-07.md`). That real code change moved the projection 90 → 89; the ledger legitimately lagged at 90 until the next canonical sync.
- `1a3ea234d` commit message documents the sanctioned path used: *"data: nimtry baseline + debt ledger regenerated via canonical commands (… `debt_engine --codegen/--sync-budget/--validate` all PASS — 1418 checks, 0 DRIFT)"*.
- Verdict on the reported ambiguity: **not** a projection calculation defect, and **not** a frozen-wrong ledger — the ledger value 90 was correct when sealed, became stale via a real code change, and was later refreshed to the true measured value 89.

## 3. Current-state verification at `de4d587a4` (all commands from worktree root)

1. Projection live measurement: `./bin/effect_contract_projection` → `{"declarations": 4137, "violations": 89, …}` (earlier evidence citing `{4135, 90}` and `{4135, 89}` predates the DEBT#478 closure / PR #567 declaration changes respectively).
2. Ledger: `BUDGET#003` → `current: 89`, `status: open`, `resolution: WONT_FIX` (deliberate budget record, not an error state).
3. `./bin/debt_engine --sync-budget --dry-run` → `Records processed: 6 / Updates applied: 0 / [DRY-RUN] No changes detected — fully synced.`
4. `./bin/debt_engine --sync-budget` (real) → `Done. 0 record(s) updated.` — rewrite left `git status` completely clean (byte-identical write; idempotent).
5. `./bin/debt_engine --codegen` → `Generating src/generated/debt_constants.nim... [skip] unchanged` and `Generating docs/DEBT_REGISTRY.md... [skip] unchanged` → both projections byte-identical.
6. `./bin/debt_engine --validate` → `✅ effect_violations PASS (projection=89 == ledger 89)`; `Checks: 1423 total, 1423 passed, 0 failed`; `Metric evaluation: 6 PASS, 0 DRIFT`; exit 0.

## 4. Conclusion

- The reported DRIFT (projection 89 vs ledger 90) **existed** during the window `f878f61aa` → `1a3ea234d` (2026-10-07) and the verification records that noted it as "pre-existing, unrelated" were accurate at their observation time.
- It was **reconciled by the sanctioned tool path** in `1a3ea234d`; nothing was left to resync at adjudication time (`--sync-budget`: 0 updates; `--codegen`: unchanged; `--validate`: 0 DRIFT).
- No manual numeric edit was performed anywhere in this adjudication; the ledger was never touched by this work (worktree clean apart from this evidence document).

## 5. Reproduction

```sh
git worktree add --detach /tmp/ax-c0d1 c0d1a80d3 && git worktree add --detach /tmp/ax-8ffc 8ffc94d89
cp bin/effect_contract_projection /tmp/ax-c0d1/bin/ && cp bin/effect_contract_projection /tmp/ax-8ffc/bin/
( cd /tmp/ax-c0d1 && ./bin/effect_contract_projection | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["declarations"],d["violations"])' )  # 4136 90
( cd /tmp/ax-8ffc && ./bin/effect_contract_projection | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["declarations"],d["violations"])' )  # 4131 89
git show 8ffc94d89:data/debt_ledger.json | python3 -c 'import json,sys;print([r["current"] for r in json.load(sys.stdin)["records"] if r["metric"]=="effect_violations"])'  # [90]
./bin/debt_engine --sync-budget --dry-run && ./bin/debt_engine --codegen && ./bin/debt_engine --validate
```
