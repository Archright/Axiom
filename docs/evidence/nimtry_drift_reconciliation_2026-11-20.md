# nimtry metric drift reconciliation — 2026-11-20

**Status**: Applied (measurement reconciliation, not a debt reduction)
**Branch**: `workstream/nimtry-reconcile` (dedicated worktree)
**Base**: `origin/main` = `f8959445363874bf4fa6f94d9f0ca9bea1b43e8d` (Merge PR #262)
**Toolchain**: Nim 2.2.10 (`~/.choosenim/toolchains/nim-2.2.10`), binaries built from this worktree
**Measurement window**: 2026-11-20T23:03 KST → 2026-11-21T07:56 KST (tool timestamps quoted verbatim below)

---

## 1. Conclusion first

| Item | Before | After | Verdict |
|---|---|---|---|
| `data/nimtry_baseline.json` `total_violations` | **4272** (created 2026-11-19T13:53:56+09:00, commit `42d1493`) | **4374** (created 2026-11-20T23:06:30+09:00) | stale anchor vs. a landed subsystem |
| live `bin/nimtry src/ --diff-baseline` | **New: 106, Resolved: 4, Stable: 4268** (live total 4374) | **New: 0, Resolved: 0, Stable: 4374** | drift resolved |
| `bin/nimtry src/` | exit 1 — `FAIL: 2 new ERROR violations not in baseline` | exit 0 — `PASS — 4374 violations (debt anchored)` | `make check-arch` green |
| `data/debt_ledger.json` `BUDGET#004.current` | 0 (last verified 2026-11-14T08:31:42+09:00) | 0 (unchanged; evaluator now returns 0) | ledger was not wrong — its snapshot predates the landing |
| `bin/debt_engine --validate` | `nimtry_violations DRIFT (projection=1 vs ledger 0)` — 1826/1826 checks, 3 PASS / 1 DRIFT, exit 0 | `nimtry_violations PASS (projection=0 == ledger 0)` — 1826/1826 checks, 4 PASS / 0 DRIFT, exit 0 | drift resolved |
| `data/debt_reduction_baseline.json` cap | `nimtry_violation_count` / `nimtry_active_violations` = **4275** | **4374** | historical cap synced to the measured anchor |
| `bin/debt_integrity_gate` | `FAIL: nimtry_active_violations increased (4374 > 4275)` (live sidecar present) | `Active Violations: 4374 / Historical Baseline Cap: 4374` … `PASS` | required `debt-registry-gate` stays green |

**Diagnosis**: stale baseline + a real increase from a landing, not a ledger accounting
error and not a source regression in previously anchored code. The 106 new rows are the
Evidence Bundle v2 landing (`bb31dae`, `95b871e`, `687240b`, all 2026-11-20); 100 of the
106 are in nine files that did not exist at the baseline commit. The `projection=1` in
the DRIFT message is **not a violation count** — see §3.3.

---

## 2. Where the numbers come from (file:line)

### 2.1 The `nimtry_violations` projection

- `tools/debt_engine.nim:1697-1713` — `evalNimtryViolations()` runs `bin/nimtry src/`
  (same call as `make check-arch`). Exit 0 → `0`. Otherwise it counts output lines
  containing `[soc-` or `violation`, and returns `1` when no line matches (fail-closed
  floor). It never reads `data/nimtry_baseline.json`; the doc comment at
  `tools/debt_engine.nim:1702-1703` says the baseline is an archived anchor, not the
  live measurement.
- `tools/debt_engine.nim:1470` — Part D prints `DRIFT (projection=… vs ledger …)` when the
  values differ.
- `data/debt_ledger.json:55-67` — `BUDGET#004` (`metric: nimtry_violations`):
  `baseline: 704`, `target: 0`, `current: 0`, `status: closed`, `resolution: FIXED`,
  `lastVerifiedAt: 2026-11-14T08:31:42+09:00`.
- `data/debt_budgets.json:22-27` — budget policy: `baseline: 704`, `target: 0`.
  This file was **not** changed.

### 2.2 The baseline anchor

- `src/gate/nimtry/nimtry_cli.nim:429-436` — v2 baseline protocol; `--update-baseline`
  writes the current violation set via `saveBaselineV2` (`:152-175`).
- `src/gate/nimtry/nimtry_cli.nim:441-511` — gating: any fingerprint not in the baseline
  fails the run; new **ERROR** rows are reported first and cause exit 1 (`:477-482`).
- `src/gate/nimtry/nimtry_cli.nim:333` — `--update-baseline` flag; `:335` —
  `--diff-baseline`.
- `data/nimtry_baseline.json` — before: `version: 2`, `total_violations: 4272`,
  `by_severity {warning: 3898, error: 374}`, `created: 2026-11-19T13:53:56+09:00`,
  landed by `42d1493` (2026-11-19 13:57 +0900).

### 2.3 The historical cap

- `src/gate/runners/debt_integrity_gate.nim:177-181` — `nimtry_violation_count` =
  `data/nimtry_baseline.json` `total_violations`.
- `src/gate/runners/debt_integrity_gate.nim:183-194` — `nimtry_active_violations` =
  `data/nimtry_live_count.json` sidecar (written by nimtry at
  `src/gate/nimtry/nimtry_cli.nim:411-420`), `-1` when absent.
- `src/gate/runners/debt_integrity_gate.nim:289-305` — `--update-baseline` writes the
  measured metrics; otherwise any `value > base` is a FAIL in release builds.
- `Makefile:191-193` builds the gate with `-d:release` (the ratchet must not downgrade to
  WARN); `.github/workflows/debt-registry-gate.yml:54-56` runs it as the required
  `debt-registry-gate` check. The workflow runs without `bin/nimtry`, so
  `nimtry_active_violations` is `-1` there and only `nimtry_violation_count` (the
  baseline total) is compared.

### 2.4 The sanctioned update path

- `config/repository_surface.json:5` (policy v18 note): “nimtry DRIFT 데트앵커 등록 —
  `data/nimtry_baseline.json` CONTROLLED … **2단계 = nimtry --update-baseline 재앵커 +
  budget ledger 동기화 follow-up**”; path registration at `config/repository_surface.json:69`.
  CONTROLLED is a scrutiny inventory, not a freeze (`docs/spec/repository_surface_contract.md:41`).
- `docs/evidence/preexisting_metric_drift_forensics_2026-10-31.md:121-131` (§5.1) and
  `:146-158` (§6.2): for `nimtry_violations` DRIFT, the canonical prescription is the
  v18 two-phase re-anchor (`--update-baseline` + ledger sync).
- `docs/evidence/nimtry_ratchet_budget_request_2026-11-02.md:16-24` — precedent
  `90604006e`: re-anchor sequence = `bin/nimtry src/ --update-baseline` **and**
  `bin/debt_integrity_gate --update-baseline`; §218-219: “재앵커는 현황 정합화이지
  감축이 아니다.”
- `docs/spec/walkdirrec_ordering_quirk.md:57-61` — baseline updates land in the same
  commit as the source change; `--diff-baseline` must report `New: 0` after re-anchor.

No new mechanism was introduced.

---

## 3. Measurements (verbatim commands and outputs)

Binaries were built from this worktree, not reused from another checkout:

```
$ make bin/nimtry bin/debt_engine bin/debt_integrity_gate
```

### 3.1 Before — baseline 4272 vs live 4374

```
$ ./bin/nimtry src/ --diff-baseline --list
[INFO] logger: === Baseline Diff ===
[INFO] logger: New: 106
[INFO] logger: Resolved: 4
[INFO] logger: Stable: 4268
```

`106 = 104 warning + 2 error`, by rule tag:

| rule tag | severity | rows |
|---|---|---:|
| `purity-new-code-must-be-func` | warning | 42 |
| `effect-transitive-io` | warning | 31 |
| `soc-surface-area` (SOLID) | warning | 17 |
| `effect-triple-annotation` | warning | 8 |
| `solid-ocp` (SOLID) | warning | 5 |
| `safety-proc-purity` | warning | 1 |
| `safety-forbidden-patterns` — `SAFETY-no-main-module-in-src` | **error** | 1 |
| `safety-forbidden-patterns` — `SAFETY-unsafe-parse` | **error** | 1 |

The two errors:

```
[error] SAFETY-no-main-module-in-src — [safety-forbidden-patterns] src/bin/evidence_verify.nim:11 'when isMainModule' in non-I/O boundary module. Only src/cli/, src/mcp/, and src/gate/runners/ may use isMainModule.
[error] SAFETY-unsafe-parse — [safety-forbidden-patterns] src/verification/evidence_bundle/strict_json.nim:185 Direct parseFloat() usage. Use safeParseFloat() from src/core/safe_parsers.nim.
```

Attribution (file existence checked against `42d1493`; row-to-file mapping uses the new
baseline fingerprints, which include the file):

- **100 rows in 9 files absent at `42d1493`**: `src/verification/cert_export.nim` 24,
  `src/verification/evidence_bundle/bundle_verify.nim` 24,
  `bundle_export.nim` 19, `bundle_paths.nim` 15, `bundle_toolchain.nim` 11,
  `strict_json.nim` 3, `src/cli/evidence_bundle_cli.nim` 2,
  `src/bin/evidence_verify.nim` 1, `bundle_schema.nim` 1.
- **6 rows in 4 pre-existing files**:
  - `src/cli/axiom_engine.nim` 2 — exports 68 → 71 and `prepareProofRun` 236 → 240 SLOC
    (file changed by `1d2d269`, 2026-11-20);
  - `src/verification/counterexample_replay.nim` 1 — exports 36 → 37 (file changed by
    `b132a5a`, 2026-11-19);
  - `src/cli/cert_cli.nim` 1 — OCP branches 13 → 12 (an improvement that changes the
    fingerprint; file changed by `bb31dae`);
  - `src/core/trusted/bypass_verify.nim` 2 — `getTreeHash` and `verifyBypassSignature`
    are newly reported by the transitive-I/O analysis although the file has not changed
    since `c021c33` (2026-11-12): effect-graph propagation from the landing, not a source
    edit in that file.

The `Resolved: 4` rows are exactly the superseded predecessors of the first three bullets
above plus the `cert_cli` 13-branch row; net change = 106 − 4 = **+102** (4272 → 4374).

The two failure surfaces:

```
$ make check-arch
=== [2/4] Architecture Violation Check ===
❌ Architecture check FAILED (nimtry exit 1):
[ERROR] nimtry_cli: [nimtry] FAIL: 2 new ERROR violations not in baseline (debt anchoring)
[ERROR] nimtry_cli:   [error] SAFETY-no-main-module-in-src — …
[ERROR] nimtry_cli:   [error] SAFETY-unsafe-parse — …
make: *** [Makefile:247: check-arch] 오류 1
# make exit 2

$ ./bin/debt_engine --validate
  ✅ import_lint_violations PASS (projection=0 == ledger 0)
  [skip] layer_violations: evaluator binary unavailable (bin/layer_enforcement_gate)
  [warn] layer_violations: evaluator error
  [skip] effect_violations: evaluator binary unavailable (bin/effect_contract_projection)
  [warn] effect_violations: evaluator error
  ⚠️  nimtry_violations DRIFT (projection=1 vs ledger 0)
  ✅ debt_registry_open PASS (projection=60 == ledger 60)
  ✅ debt_registry_closed PASS (projection=232 == ledger 232)
  …
  Checks: 1826 total, 1826 passed, 0 failed
  Metric evaluation: 3 PASS, 1 DRIFT
  All debt validation checks passed.   (exit 0)
```

`bin/debt_integrity_gate` (before the baseline change, with the live sidecar present):

```
[ERROR] [debt-integrity-gate]: FAIL: nimtry_active_violations increased (4374 > 4275)
```

In a fresh CI checkout without the sidecar this pre-change state passes, because
`nimtry_violation_count` (baseline 4272) is still ≤ 4275. After re-anchoring, the baseline
total itself would exceed 4275, which is why the cap sync below is part of the same
sanctioned sequence.

### 3.2 Why `projection=1`

`evalNimtryViolations` (`tools/debt_engine.nim:1707-1712`) counts output lines containing
`[soc-` or `violation`. When nimtry fails on new errors it prints one banner line
(`[nimtry] FAIL: N new ERROR violations not in baseline`, `nimtry_cli.nim:477`) plus
per-violation lines of the form `[error] RULE — detail`, which do not contain the literal
`violation`. The count therefore saturates at **1 regardless of N** (or at the number of
banner/`[soc-` lines on the warning branch). `projection=1` is a banner-line artifact, not
a count of the 106 new rows. This is a pre-existing evaluator property; it was not
changed by this reconciliation (see §7).

### 3.3 After — re-anchor and cap sync

```
$ ./bin/nimtry src/ --update-baseline
[INFO] logger: [nimtry] Baseline updated with 4374 violations.        # exit 0
```

Determinism check — a second regeneration from the same tree:

```
created run 1: 2026-11-20T23:03:54+09:00
created run 2: 2026-11-20T23:06:30+09:00
total equal: True 4374 4374
by_severity equal: True {'warning': 3998, 'error': 376}
violations array identical: True
payload sha256 (both runs): b07fcd45bc11e1f4f5033e503ee133841c5b0321e5779b8be4fb9da8f69f7842
```

The violation payload (all rows, order, fingerprints, severities) is byte-identical across
regenerations. The only differing field is `created`, the tool's wall-clock metadata
(`nimtry_cli.nim:154`); it is not consumed by `loadBaselineV2` (which reads only `id`) and
is the same behaviour every prior re-anchor has had. This is the determinism boundary of
the sanctioned tool, not a new nondeterminism.

Post-re-anchor gate calls:

```
$ ./bin/nimtry src/
[ERROR] nimtry_cli: [nimtry] PASS — 4374 violations (debt anchored) (errors: 376, warnings: 3998) (cache: 1340 hits, 0 misses)
# exit 0

$ ./bin/nimtry src/ --diff-baseline
[INFO] logger: New: 0
[INFO] logger: Resolved: 0
[INFO] logger: Stable: 4374

$ ./bin/debt_integrity_gate --update-baseline
[INFO] [debt-integrity-gate]: Baseline updated                          # exit 0

$ cat data/debt_reduction_baseline.json
{"metrics":{"forwarding_stubs":8,"isMainModule_in_core":0,"nimtry_violation_count":4374,"nimtry_active_violations":4374,"stale_generated_pbt_files":0}}

$ ./bin/debt_integrity_gate
[INFO] [debt-integrity-gate]: nimtry — Active Violations: 4374 / Historical Baseline Cap: 4374
[INFO] [debt-integrity-gate]: Registry: 292 entries (43 open, 0 accepted)
[INFO] [debt-integrity-gate]: Open: 18 marker-bound, 25 registry_disposition-bound (rationale verified)
[INFO] [debt-integrity-gate]: Code: 23 {.axiomDebt.} markers found
[INFO] [debt-integrity-gate]: All 43 open debts have code markers. PASS.
# exit 0

$ make check-arch
=== [2/4] Architecture Violation Check ===
✅ No architecture violations
# exit 0

$ ./bin/debt_engine --validate
  ✅ import_lint_violations PASS (projection=0 == ledger 0)
  ✅ nimtry_violations PASS (projection=0 == ledger 0)
  ✅ debt_registry_open PASS (projection=60 == ledger 60)
  ✅ debt_registry_closed PASS (projection=232 == ledger 232)
  …
  Checks: 1826 total, 1826 passed, 0 failed
  Metric evaluation: 4 PASS, 0 DRIFT
  All debt validation checks passed.
# exit 0
```

Re-run on the committed tree after the pre-commit hook built `bin/layer_enforcement_gate`
(hook Part 3): `Metric evaluation: 5 PASS, 0 DRIFT` — `layer_violations` becomes measurable
once that binary exists and passes; `nimtry_violations` remains PASS. The 4 PASS figure above
is the pre-hook measurement, when that binary was absent.

`./bin/debt_engine --sync-budget --dry-run` reports `Updates applied: 0` and
`[DRY-RUN] No changes detected — fully synced.` for the measured records; it exits 1 only
because `bin/effect_contract_projection` (and, at dry-run time, `bin/layer_enforcement_gate`)
was not built in this worktree (`BUDGET#002`/`BUDGET#003` unmeasured). `data/debt_ledger.json`
was not written.

### 3.4 Note on the earlier “live 4296” figure

The 4296 count quoted in the task is **not reproducible at `f895944`**: the live count at
this base is **4374** (measured twice, §3.1/§3.3). The most likely reading is that 4296 was
taken at an earlier head, before the final Evidence Bundle v2 commit `687240b`
(2026-11-20 13:15 +0900) — its nine new source files carry **100** of the 106 new rows, so
any head before that commit would show a materially smaller live count. This document does
not verify that hypothesis: re-measuring a historical head needs a separate checkout and a
second nimtry build, which is outside this slice. The reconciliation is anchored to the
reproducible 4374 at `f895944`.

---

## 4. Classification and mechanism

| Candidate cause | Evidence | Verdict |
|---|---|---|
| Stale baseline | Baseline `created` 2026-11-19T13:53; 100/106 new rows are in files absent at `42d1493`; the landing commits are all 2026-11-20 | **primary cause** |
| Real regression in anchored code | 6 rows in 4 pre-existing files: 4 are post-baseline surface/SLOC/OCP changes from the same landing, 1 is an improvement (13→12 branches), 2 are effect-graph propagation into an unchanged file (`bypass_verify.nim`, last change `c021c33`) | no regression in previously accepted code |
| Ledger accounting error | `BUDGET#004.current=0` was true on 2026-11-14 when nimtry passed; the evaluator's `1` is a banner-line artifact, not a count | no ledger error; the snapshot simply predates the landing |

**Mechanism used**: the documented v18 two-phase reconciliation —
`bin/nimtry src/ --update-baseline` (anchor the measured set) followed by
`bin/debt_integrity_gate --update-baseline` (sync the historical cap). It is sanctioned by
`config/repository_surface.json:5` (v18) and `:69` (CONTROLLED registration), and matches
the `90604006e` precedent in `docs/evidence/nimtry_ratchet_budget_request_2026-11-02.md:16-24`.

**Why this is not a blanket suppression**:

- `data/debt_budgets.json` (the policy budget: baseline 704, target 0) is untouched; no
  target was relaxed.
- No gate check was disabled or downgraded; `make check-arch` and `bin/debt_integrity_gate`
  still enforce the anchor (`New: 0` required for future commits).
- All 106 rows are enumerated above by rule and file, and the 2 error rows are called out
  by file:line. The anchor is the repository's designed “existing violations are accepted
  debt; new ones fail” protocol (`nimtry_cli.nim:441-491`), not a silent patch.
- The cap increase (4275 → 4374, +99) is measurement reconciliation, explicitly not a
  reduction and explicitly not counted as one (`nimtry_ratchet_budget_request_2026-11-02.md`
  §6.2). It is nevertheless a real ratchet increase: the repo now tolerates 99 more rows
  than before, and a reduction plan remains a human decision (that document's D1/D2).

---

## 5. Files changed

| File | Change |
|---|---|
| `data/nimtry_baseline.json` | `bin/nimtry src/ --update-baseline`: 4272 → 4374 rows; warning 3898 → 3998, error 374 → 376; 106 new rows, 4 superseded; `created` 2026-11-20T23:06:30+09:00 |
| `data/debt_reduction_baseline.json` | `bin/debt_integrity_gate --update-baseline`: `nimtry_violation_count` and `nimtry_active_violations` 4275 → 4374 (other metrics unchanged: `forwarding_stubs` 8, `isMainModule_in_core` 0, `stale_generated_pbt_files` 0) |
| `docs/evidence/nimtry_drift_reconciliation_2026-11-20.md` | this document |

Not changed: `data/debt_budgets.json`, `data/debt_ledger.json`, `data/debt_registry.json`,
`docs/DEBT_REGISTRY.md`, any `src/` file.

---

## 6. Proposed registry entry (for the registry owner — not applied here)

`data/debt_registry.json` is owned by a different workstream and was **not** edited. The
next free id at `f895944` is `DEBT#562` (current maximum `DEBT#561`). The entry below
validates against `data/debt_schema.json` `definitions.DebtRegistryEntry`. Adding it raises
`debt_registry_open` from 60 to 61, so the registry owner must re-run
`./bin/debt_engine --sync-budget` (otherwise `BUDGET#005` will report DRIFT).

```json
{
  "id": "DEBT#562",
  "category": "Architecture / nimtry Anchored Debt",
  "title": "Evidence Bundle v2 landing added 106 unanchored nimtry rows (2 error) — anchored via the v18 re-anchor path; remediation deferred",
  "impact": "medium",
  "severity": "medium",
  "description": "Machine measurement 2026-11-20 on base f895944 (branch workstream/nimtry-reconcile): bin/nimtry src/ --diff-baseline reported New: 106 (104 warning, 2 error), Resolved: 4, Stable: 4268 against data/nimtry_baseline.json (4272, created 2026-11-19T13:53:56+09:00). 100 rows are in nine files absent at the baseline commit (src/verification/evidence_bundle/{bundle_export,bundle_paths,bundle_schema,bundle_toolchain,bundle_verify,strict_json}.nim, src/verification/cert_export.nim, src/cli/evidence_bundle_cli.nim, src/bin/evidence_verify.nim — landed by bb31dae/95b871e/687240b on 2026-11-20); 6 rows are in four pre-existing files (src/cli/axiom_engine.nim x2, src/core/trusted/bypass_verify.nim x2, src/cli/cert_cli.nim x1, src/verification/counterexample_replay.nim x1), attributable to post-baseline edits (axiom_engine, cert_cli, counterexample_replay) or effect-graph propagation into an unchanged file (bypass_verify, last changed c021c33). Rule split: purity-new-code-must-be-func 42, effect-transitive-io 31, soc-surface-area 17, effect-triple-annotation 8, solid-ocp 5, safety-proc-purity 1 (warning); safety-forbidden-patterns 2 (error: SAFETY-no-main-module-in-src at src/bin/evidence_verify.nim:11, SAFETY-unsafe-parse at src/verification/evidence_bundle/strict_json.nim:185). Disposition: anchored as accepted debt via the documented v18 two-phase path (bin/nimtry src/ --update-baseline -> 4374; bin/debt_integrity_gate --update-baseline -> cap 4275->4374), not silently patched; this is measurement reconciliation, not reduction. Closing criteria: (1) convert the 42 new procs to func where AGENTS.md 0.6 applies; (2) add {.raises: [].} / {.tags: [AxiomIOEffect].} to the 39 effect rows or justify them; (3) replace the direct parseFloat with safeParseFloat at strict_json.nim:185; (4) resolve the src/bin entry-point rule gap for evidence_verify.nim (src/cli/ relocation or an explicit policy decision); (5) re-anchor and close when the count drops.",
  "files": [
    "src/verification/evidence_bundle/bundle_export.nim",
    "src/verification/evidence_bundle/bundle_paths.nim",
    "src/verification/evidence_bundle/bundle_schema.nim",
    "src/verification/evidence_bundle/bundle_toolchain.nim",
    "src/verification/evidence_bundle/bundle_verify.nim",
    "src/verification/evidence_bundle/strict_json.nim",
    "src/verification/cert_export.nim",
    "src/cli/evidence_bundle_cli.nim",
    "src/bin/evidence_verify.nim",
    "src/cli/axiom_engine.nim",
    "src/core/trusted/bypass_verify.nim",
    "src/cli/cert_cli.nim",
    "src/verification/counterexample_replay.nim"
  ],
  "source": "nimtry",
  "status": "open",
  "resolution": "UNRESOLVED — anchored 2026-11-20 via bin/nimtry src/ --update-baseline (data/nimtry_baseline.json 4272->4374) and bin/debt_integrity_gate --update-baseline (data/debt_reduction_baseline.json 4275->4374). Evidence: docs/evidence/nimtry_drift_reconciliation_2026-11-20.md. Closing criteria are in description.",
  "productTruthImpact": "PRODUCT_SUPPORT",
  "binding": "registry_disposition",
  "bindingRationale": "The 106 anchored nimtry rows are v2 baseline fingerprints, not per-row {.axiomDebt.} code markers, so the registry entry itself is the binding medium (docs/spec/debt_registry_schema.md 10.1). The disposition is the documented v18 re-anchor (config/repository_surface.json v18), and recording it here keeps the anchor from being a silent absorption. Precedent: DEBT#505.",
  "lastVerifiedAt": "2026-11-20T14:06:30Z"
}
```

---

## 7. Residual risks and follow-ups

1. **Ratchet increased by 99 rows** (4275 → 4374). This is honest measurement
   reconciliation, but it raises the tolerated debt. A reduction plan for the Evidence
   Bundle violations (and the 2 error rows in particular) is a human decision; the 2 error
   rows are the highest-value targets because `SAFETY-unsafe-parse` is a one-line
   `safeParseFloat` substitution and `SAFETY-no-main-module-in-src` is an entry-point
   placement decision.
2. **`projection` saturation** (`tools/debt_engine.nim:1707-1712`): any failing nimtry run
   reports 1 (or a banner-line count), never the true number. After this anchor the metric
   is 0, but a future failure will again display a misleading small number. Fixing the
   evaluator to parse `--diff-baseline` output or a JSON sidecar is a separate change
   (out of scope; no new mechanism was introduced).
3. **Effect-graph propagation**: `src/core/trusted/bypass_verify.nim` is unchanged yet 2
   of its functions are now flagged. That is a property of the transitive-I/O analysis
   after the landing, not a source edit; worth a follow-up if the bare-name resolution
   (see `docs/spec/walkdirrec_ordering_quirk.md`) is suspected.
4. **`created` metadata**: regeneration is payload-deterministic but not byte-identical
   because `saveBaselineV2` stamps `now()`. The committed file is one canonical payload;
   re-running `--update-baseline` will produce a one-line `created` diff.
5. **`--sync-budget` completeness**: `--dry-run` reports 0 pending updates for the measured
   records but exits 1 because `bin/effect_contract_projection` was not built in this
   worktree (and `bin/layer_enforcement_gate` was absent at dry-run time; the pre-commit hook
   later built it and `layer_violations` then measured PASS). This is an environment gap, not
   a ledger drift; `data/debt_ledger.json` was not touched.
6. **Registry entry not applied** (§6): if the registry owner adds `DEBT#562`, they must
   run `bin/debt_engine --sync-budget` to keep `BUDGET#005` in sync (60 → 61).

---

## 8. Reproduction summary

```
make bin/nimtry bin/debt_engine bin/debt_integrity_gate
./bin/nimtry src/ --diff-baseline --list        # before: New 106 / Resolved 4 / Stable 4268
make check-arch                                 # before: exit 2, 2 new ERRORs
./bin/debt_engine --validate                    # before: nimtry_violations DRIFT 1 vs 0
./bin/nimtry src/ --update-baseline             # baseline 4272 -> 4374
./bin/nimtry src/                               # PASS 4374 (debt anchored)
./bin/nimtry src/ --diff-baseline               # New 0 / Resolved 0 / Stable 4374
./bin/debt_integrity_gate --update-baseline     # cap 4275 -> 4374
./bin/debt_integrity_gate                       # Active 4374 / Cap 4374, PASS
make check-arch                                 # PASS
./bin/debt_engine --validate                    # 1826/1826, 4 PASS / 0 DRIFT
```