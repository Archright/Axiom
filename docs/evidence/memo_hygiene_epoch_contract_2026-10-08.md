# Memo Layer Hygiene — Ghost Epoch Dir + Allowlist Residual + Epoch-Contract Reconciliation

- **Date**: 2026-10-08
- **Branch / PR**: `chore/memo-hygiene`
- **Origin**: DEBT#471 closure report follow-ups
  (`docs/evidence/debt471_memo_closure_identity_2026-10-08.md` §Follow-ups, items 2–3)
- **Scope guard**: memo is an accelerator — no verdict may change. All changes
  are hygiene (cache-shape guard, dead-name removal, test sandboxing).

## 1. Ghost epoch dir `epoch_4745300579805605544` — classification + removal

**Classification (measured, not assumed)**: not corruption, not empty — a
**valid CAS memo entry written by a unit test**:

```
$ cat .../epoch_4745300579805605544/a3/132a84d4…560
{"gateId":"unit-test-depsdirs-1791422799",…,"epoch":4745300579805605544,"expiresAt":0}
```

**Root cause chain** (all source-verified):

1. `tests/unit/gate_memo_depsdirs_test.nim:33` used
   `cast[int](epochTime()).int` — a float→int **bit-pattern reinterpretation**
   (1.7914e9 → `0x41DB…` → ≈4.745e18). Documented as
   [nim_2_2_10_stdlib_quirks.md Q-010](../spec/nim_2_2_10_stdlib_quirks.md).
2. The test ran with the repo cwd, and `GateMemoBaseDir` is cwd-relative, so the
   garbage epoch was written into the **real** repo cache.
3. The test's cleanup removed a legacy flat path (`<gateId>.json`) that
   `saveGateMemo` (CAS layout `epoch_<N>/<h2>/<h62>`) never writes — a no-op,
   so the pollution survived every run.
4. The GC contract (`current - epochNum >= maxRetained`) can never reclaim a
   directory whose epoch is **above** current, and silently ignores
   non-parseable names — the ghost was permanently unreachable garbage.

**Safety of removal**: the `gateId` `unit-test-depsdirs-*` is a one-off test
id that no real gate dispatches with; `loadGateMemo` matches gateId + lock
hash, so the entry was unreachable by any production lookup. Removal is
verdict-neutral.

## 2. Disk state reconciliation (epoch contract: explicit +1 forward, maxRetained=3)

`.epoch` counter authority read at measurement time.

| Location | Before | After |
|---|---|---|
| main clone `.axiom/cache/gate_memo/` (`.epoch` = 27) | 14 epoch dirs: 0, 6, 16–27 → **11 beyond retention** (retain window = 25,26,27) | **3 dirs: 25, 26, 27** — exactly the contract |
| `orca/workspaces/Axiom/memo-closure/.axiom/cache/gate_memo/` (`.epoch` = 0) | `epoch_0` (12 CAS files) + ghost `epoch_4745300579805605544` (1 CAS file) | `epoch_0` only — ghost removed |

Removed dirs hold only old-epoch memo entries; lookups address the current
epoch exclusively, so removal forces live re-judgment at worst (accelerator
loss), never a verdict change.

## 3. Recurrence prevention (source + guard)

| Layer | Change |
|---|---|
| Source | `tests/unit/gate_memo_depsdirs_test.nim` now sandboxed (temp cwd — `makeMemoTmpDir` convention of `gate_memo_test.nim`) at contract-valid epoch 0, with real cleanup |
| GC guard | `garbageCollectOldEpochs` (`src/core/gate/gate_memo.nim`): non-numeric `epoch_*` suffix → **reclaimed** + ERROR log; numeric epoch above current → **kept + ERROR log** (foreign or the documented manual-rollback state; removal would race a concurrent epoch advance) |
| Spec | `docs/spec/cache_policy.md`: GC section documents the guard; legacy `logs/.gate_memo` paths corrected to the DEBT#237 location `.axiom/cache/gate_memo`; `.migrating` → `.migration_lock` |
| Allowlist | `LightGateAllowlist` (`src/gate/utils/gate_safety_macro.nim`): residual `debt-scan-gate` name removed (see §4); feature test assertions updated to the new truth |

## 4. Allowlist residual name `debt-scan-gate` — dead-key removal (verdict-neutral)

Mechanism trace (source-verified):

- `tryDispatchInProcess` (`inprocess_dispatch.nim`) requires
  `isLightGateAllowed(gate.id)` **and** a runner (`findInProcessRunner` →
  `inProcessRegistry`, or the `runGateInProcess` case branches).
- `debt-scan-gate` has **neither**: no `registerInProcessGate("debt-scan-gate")`
  call site, no `runGateInProcess` branch (only `debt-ct-gate`,
  `doc-completeness-gate`, `trust-commit-scope`), and
  `all_gate_runners.nim` (the hook binary's compile-time registry) imports no
  debt-scan runner — its only importers are spec tooling
  (`helper_spec.nim`, generated `helper_registry.nim`).
- The runner merged into `debt-integrity-gate`
  (`src/gate/runners/debt_integrity_gate.nim` header); the DEBT#471 report
  already classifies the allowlist name as stale.

So for every gate dispatched today the allowlist entry is a dead key; removing
it changes no dispatch decision. The stale feature-test assertion
(`array[2] = [debt-scan-gate, doc-completeness-gate]` — already false on main
since trust-commit-scope landed) is updated to assert the new truth and the
residual name's rejection.

## 5. Verification (machine-observed, 2026-10-08)

Environment: worktree `orca/workspaces/Axiom/memo-hygiene` (branch
`chore/memo-hygiene`, base = origin/main `5dc62ebba`), Nim 2.2.10, hooks ACTIVE
(no `--no-verify` anywhere), `make ci-bootstrap` PASS (baseline check OK).

Memo suite preflight — all green after this slice:

| Suite | Result |
|---|---|
| `tests/unit/gate_memo_test.nim` | 37/37 `[OK]`, 0 failed (incl. 3 new GC-guard tests + corrected stale legacy-fallback test, see §6) |
| `tests/unit/gate_memo_depsdirs_test.nim` | ALL PASSED — sandboxed; worktree real cache (`.axiom/cache/gate_memo/`) **not created** by the run: zero pollution (was the ghost producer) |
| `tests/unit/gate_memo_decision_replay_test.nim` | 16 `[OK]`, 0 failed |
| `tests/unit/memo_daemon_identity_roundtrip_test.nim` | `[OK]` |
| `tests/unit/test_gate_memo_fcunknown_regression.nim` | 6 passed, 0 failed |
| `tests/unit/test_gate_memo_tooling_error_regression.nim` | 29 passed, 0 failed |
| `tests/gateway/gate_safety_macro_feature_test.nim` | 5/5 `[OK]` (incl. new residual-name rejection) |

G7 + determinism (memo = accelerator acceptance):

- `make verify-contract-release-e2e-full` → exit 0,
  `INFO: G7 pass (tier=z3-verified status=not_verifiable vaultPath=)`,
  `✅ verify-contract-release-e2e-full PASSED`; binary immutability
  (`sha256(bin/ax)` before/after E2E identical) and report/state consistency
  asserted by the target itself; lean-verify PASS (proofs/ builds cleanly).
- `bin/ax report --canonical-digest` ×2 →
  `ed38cc64c05058079d2f763c208783f148a6cabaccd320ce031059e7401878d6` ×2
  **identical**.

GC guard behavior is directly exercised (from the gate_memo_test run log):

```
[ERROR] hub: [gate_memo] GC: reclaimed non-numeric epoch dir epoch_not_a_number
[ERROR] hub: [gate_memo] GC: epoch dir epoch_4745300579805605544 is above current epoch 0 — foreign or manual-rollback state; kept, not removed
```

## 6. Pre-existing stale test corrected (disclosed, not caused by this slice)

`gate_memo_test.nim` "overload with compositeLockHash falls back to legacy for
wrong hash" was **already failing on pristine main** — machine-observed on the
unmodified main clone at `5dc62ebba` (clean tree) with the identical
`Check failed: fallback.isSome` before any of this slice's edits. Root cause:
the expectation predates Phase B — `saveGateMemo` writes the CAS layout only,
while the legacy fallback reads only the flat `epoch_<N>/<gateId>.json` path,
so a wrong-hash lookup after a CAS save can never hit (fail-closed: live
re-judgment — which is the sound behavior). The test now asserts both current
semantics (CAS miss + no flat file → `isNone`) and the real legacy property
(a hand-written flat entry is surfaced regardless of hash). Product code
untouched for this — verdict-neutral test-alignment only.

## 7. Debt-integrity pin regeneration (canonical flow, machine-verified)

The edit to `src/core/gate/gate_memo.nim` is a **substantive change** under the
debt-integrity binding: `data/architecture_debt.json` entry[104] pins the
file's canonical syntax hash (`nim-pnode-canonical-v2`), so
`bin/debt_engine --validate` failed closed with
`entry[104] substantive change detected (canonical hash changed)` before
regeneration. Resolved through the canonical flow (DEBT#471 evidence
precedent): `bin/debt_engine --regen-arch --codegen --sync-budget --validate`
→ entry hash updated, 1 ledger record updated, **1435/1435 checks passed,
"All debt validation checks passed."** The regenerated
`data/architecture_debt.json` + `data/debt_ledger.json` are part of this
commit — the audit trail of the substantive change.

## 8. Pre-existing landing-infra defect (disclosed, out of scope)

`bin/build_all_gates --release` (the hooks' printed prescription for stale
binaries) currently fails **80/80 gates** on pristine main sources
(`5dc62ebba`): every freshly-built gate binary exits 1 during the
builder's self-run because of **33 pre-existing decision-binding violations**
in files this slice never touched (`src/cli/cert_cli.nim`,
`src/cli/merge_cli.nim`, `src/cli/landing_cli.nim`,
`src/core/types/request_result.nim`, `src/core/types/candidate_identity.nim`,
`src/engine/plan_executor.nim`,
`src/verification/{evidence_cas,attestation_witness}.nim` — all below the
30-day escalation threshold, WARN-level in audit mode but exit-1 for freshly
built gate self-runs). The main clone's stale binaries (built 10-05,
pre-violation) exit 0 — masking the drift. Workaround used here, within the
hooks' own semantics: the stale-binary guards are per-binary freshness
predicates (`bin/X` newer than its sources), and the affected verifier
binaries were rebuilt individually via the standard single-target compile
(`nim c -d:release -o:bin/nim_check_gate src/gate/runners/nim_check_gate.nim`;
`make bin/debt_engine` etc. — the pre-push hook's own alternative
prescription `make <gate>`). Every gate the hooks actually run then executed
and passed (pre-commit battery + pre-push battery). Fixing
`build_all_gates`/the decision-binding backlog is a follow-up for the
mainline owners, not this hygiene slice.

