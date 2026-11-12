# Drift re-anchor — 2026-10-21 (3 measured drifts, one hygiene PR)

Base: `origin/main` `0a05adc76f56ea858b84834f5ef319b3436b3f3d`
Worktree: `/tmp/axiom-drift` (branch `chore/drift-reanchor-20261021`)

Scope: three NON-PRODUCT drifts measured on a detached worktree at the base
commit. No product semantics changed; no policy file under `src/gate/**`,
`config/policy/**`, `.github/**` or `AGENTS.md` was touched.

---

## 1. Stale generated artifact — `src/generated/type_registry_metadata.json`

**Measured (base commit)**: `bin/hermetic_build` rewrites the artifact
(+439/−95; 9834 regenerated entries vs 9810 committed). A second run is
byte-identical → the generator is deterministic, the committed artifact was
simply stale.

**Fix**: committed the regenerated artifact (the generator is the SSOT writer;
`bin/hermetic_build` → `writeTypeRegistryIfChanged`).

**Verification**: `bin/hermetic_build` → `type_registry_metadata.json
unchanged (idempotent)` on the second run; `Type registry validation: OK`;
`All hermetic pre-build checks passed.` (exit 0).

## 2. `bin/nimtry src/` — 3 new violations vs the archived baseline

**Measured (base commit)**: `bin/nimtry src/` → exit 1, `FAIL: 3 new
violations not in baseline (debt anchoring)`:

| # | Rule | Target | Class |
|---|------|--------|-------|
| 1 | `SOLID` `[soc-surface-area]` | `src/verification/judgment_cas.nim has 70 exported functions (layer verification max 20)` | (iii) stale anchor |
| 2 | `SOLID` `[solid-ocp]` | `src/verification/judgment_cas.nim has 72 case branches but 0 calls to registry functions [register, registerImpl]` | (iii) stale anchor |
| 3 | `HYGIENE-when-isMainModule-in-test` | `tests/unit/test_evidence_id_contract_probe.nim:124` | (i) test hygiene |

### 2a. Hygiene violation — FIXED (not anchored)

The probe is a standalone program: it is imported by no module and is executed
by `make test-fast-one T=tests/unit/test_evidence_id_contract_probe.nim`
(`nim c -r`, CI lane `admission-check.yml`) and by the unit-test orchestrator
(which compiles every `tests/unit/*.nim` as its own program). Its sibling from
the same commit (`tests/unit/test_judgment_execution_records.nim`) already uses
the no-`when`-guard shape.

Fix: the `when isMainModule:` guard is replaced by an unconditional
`quit(main())` — same fail-closed exit code, no `when` guard.

Verification: `bin/nimtry src/ --diff-baseline` → `New: 2` (was 3);
the probe compiles and EXECUTES (measured: it reaches the canonical chain and
exits 1 through the fail-closed path — identical to the base commit, which
also exits 1 in this worktree because the Lean reference extractor
`proofs/.lake/build/bin/ircheck` is not built here; the failure is
pre-existing and environment-bound, not caused by this change).

### 2b. The two `judgment_cas.nim` warnings — RE-ANCHORED (not fixed, not new debt)

Why they cannot be fixed in this slice without weakening the CAS contract:

* `[soc-surface-area]` (70 exports vs the verification layer limit 20): the
  module's public surface is the go-critical judgment CAS contract. 43 of the
  70 exported symbols have callers outside the module (tools, tests, CI lane
  scripts); reducing the surface to ≤20 would break the contract's consumers.
  The sanctioned per-module escape is `[module_overrides]` in
  `src/gate/architecture_policy.lock` — a frozen policy file (§-1/§-1.2
  territory) and out of this slice's edit scope.
* `[solid-ocp]` (72 case branches, 0 registry calls): the sanctioned escape is
  `[ocp_overrides]` in the same frozen lock file. Making the module dispatch
  through `src/core/axiom_registry.nim` would add a registry dependency to the
  CAS contract module — an architecture change, not hygiene.

Classification against the repo's own decision rule
(`docs/evidence/nimtry_drift_23_classification_2026-10-16.md` §"Decision"):
both entries are **class (iii) — stale/superseded anchors, NOT class (ii) new
production debt**. They were ALREADY anchored in `data/nimtry_baseline.json`
with older readings of the same file:

```
- "[soc-surface-area] src/verification/judgment_cas.nim has 61 exported functions (layer verification max 20)"
+ "[soc-surface-area] src/verification/judgment_cas.nim has 70 exported functions (layer verification max 20)"
- "[solid-ocp] src/verification/judgment_cas.nim has 54 case branches but 0 calls to registry functions [...]"
+ "[solid-ocp] src/verification/judgment_cas.nim has 72 case branches but 0 calls to registry functions [...]"
```

`total_violations` stays 4219 — the re-anchor REFRESHES two readings, it does
not absorb a new violation. `config/repository_surface.json` v18 registers
`data/nimtry_baseline.json` as CONTROLLED with the 2-phase rule (phase 1 =
re-anchor, phase 2 = budget-ledger sync as a follow-up); this PR is phase 1.

**Verification**: `bin/nimtry --update-baseline src/` → `Baseline updated with
4219 violations`; the baseline diff is 5 insertions / 5 deletions (2 `id`
hashes + 2 `detail` strings + the `created` timestamp). `bin/nimtry src/` →
`PASS — 4219 violations (debt anchored)`, exit 0.

**Follow-up (out of scope)**: either a module split of
`src/verification/judgment_cas.nim` (public surface ≤ 20) or a policy decision
on the verification layer's export limit / an `[ocp_overrides]` entry — both
touch `src/gate/architecture_policy.lock` and need the architect.

## 3. Silently accepted `--no-cert-sync` flag

**Measured**: `runReportCli` (`src/cli/report_cli.nim`) parses only `--json`,
`--state-file` and `--canonical-digest`; `--no-cert-sync` is accepted and
ignored. The flag's parsing was deleted in `677f167ab` (2026-06-01) together
with the report's certificate-convergence path — `buildAsiReportNode` and
`convergeProofStateWithCertificates` are no longer called from the CLI
(`src/verification/proof_state_convergence.nim` is dead from the CLI's
perspective) — so `ax report` has not synchronized certificates for ~5 months,
while `tools/ci/smoke_test.nim`, `tools/ci/cold_replay_acceptance.sh` and
`tests/gateway/productization_start_vertical_slice_feature_test.nim` kept
passing the flag.

**Fix** (option (b) — report semantics unchanged, no `src/` change):

* the flag is removed from every in-repo caller (2 CI scripts, 1 gateway test,
  1 deprecated `.feature` scenario);
* the contract is documented in `docs/spec/productization_contract.md` §7
  ("Report flag surface") and in the §5 Notes: the report NEVER synchronizes
  certificates, no cert-sync flag exists, and the removed flag selects no
  behaviour at all;
* `docs/history/external-cli-smoke-optimization.md` gets a "Superseded" note
  (the historical record is not rewritten);
* contract test: `tests/cli/test_report_cli.nim` suite "report flag contract"
  (2 checks) — the flag is INERT (the report result is byte-identical with
  and without it), and the report is driven by the persisted state document.
  The file is now wired into `make test-unit` so it actually executes (it was
  an orphan test file before).

**Why the CLI was not changed to reject the flag**: `src/cli/report_cli.nim` is
**rotation-pinned** — `config/trusted_writer_set.json` carries it in
`trustedCheckerTreeClosure`, and the VS-1 rotation-pin preflight
(`docs/evidence/rotation_preflight_prereg_2026-10-20.md` §6, F-CTRL-1) REDs
any PR whose closure differs from the pin. Measured: the first push of this PR
failed `verdict / admission-check` with

```
H2 FAIL code=ROT_NEW_PIN reason=pin anchor invalid: line-set(pin@H) != set(derived H) …
missing-from-pin=src/cli/report_cli.nim | pin-only=src/cli/report_cli.nim
```

"일반 PR 경로로는 회전 신규 pin을 착지시킬 수 없다(회전 절차/allowlist 경로가
유일 승격 경로)" — an ordinary PR cannot land a rotation new pin; the rotation
procedure is the only promotion path. Re-pinning the file inside an ordinary
PR would forge that ceremony, so the CLI is left untouched.

**Residual gap (follow-up)**: the report CLI still ignores unknown options
silently (`ax prove` rejects them with `unknown option: …`). Making the report
reject them means editing the rotation-pinned `src/cli/report_cli.nim` — that
belongs to the rotation procedure path, not to an ordinary PR. Recorded in
`docs/spec/productization_contract.md` §7 and §5 Notes.

**Verification**:

```
$ ./bin/ax report --json --state-file <fixture>      # unchanged behaviour
{"summary":{},"runOutcome":{...},"schemaVersion":"axiom.report.v1",...}   # exit 0
```

`tests/cli/test_report_cli.nim` suite "report flag contract" — 2/2 OK (the
flag is inert: identical result with and without it).

## 4. Collateral repair

None in this revision: the first revision of this PR also edited
`src/cli/report_cli.nim` (to reject the removed flag), which invalidated that
file's architecture-debt content hash (`❌ [architecture_debt] entry[27]
substantive change detected (canonical hash changed)`) and — decisively — the
rotation pin (see §3). Both were reverted together with the CLI edit, so
`data/architecture_debt.json` is unchanged in the final diff.

## 5. Final verification (measured on the worktree)

| Command | Result |
|---|---|
| `bin/hermetic_build` (×2) | exit 0; 2nd run `type_registry_metadata.json unchanged (idempotent)`; `All hermetic pre-build checks passed.` |
| `bin/nimtry src/` | exit 0 — `PASS — 4219 violations (debt anchored)` (errors: 362, warnings: 3857) |
| `bin/nimtry src/ --diff-baseline` | `New: 2 / Resolved: 2 / Stable: 4217` (the 2 = the refreshed judgment_cas readings) |
| `bin/debt_engine --validate` | exit 0 — `1490 total, 1490 passed, 0 failed`; `Metric evaluation: 4 PASS, 0 DRIFT` (the pre-existing `nimtry_violations DRIFT (projection=2 vs ledger 0)` is resolved) |
| `tests/cli/test_report_cli.nim` | all suites OK, incl. the new "report flag contract" (2 checks) |
| `tests/unit/test_vkd_determinism.nim` | 3/3 OK (report projection unchanged) |
| `tests/unit/test_evidence_id_contract_probe.nim` | compiles + EXECUTES; exits 1 through the fail-closed path — identical to the base commit (the Lean reference extractor is not built in this worktree) |
| `./bin/ax report --json --state-file <fixture>` | exit 0, `schemaVersion: axiom.report.v1` (unchanged) |

## 6. Out of scope / UNKNOWN

* **Pre-existing**: `bin/hermetic_test_gate` is already red on the base commit
  (179 test files above their baseline counts; total 8724 vs 4880) — the
  ratchet baseline is stale, independent of this change. This PR does not move
  any count (measured: `tests/cli/test_report_cli.nim` 104 → 104,
  `tests/unit/test_evidence_id_contract_probe.nim` 12 → 12,
  `tests/gateway/productization_start_vertical_slice_feature_test.nim` 29 → 29).
* **Follow-up (phase 2)**: `data/debt_budgets.json` / `data/debt_ledger.json`
  budget-ledger sync is deferred by the 2-phase rule of
  `config/repository_surface.json` v18. It is not needed for this slice: with
  `bin/nimtry src/` at exit 0 the projection is 0 and the ledger already says
  0 (`nimtry_violations PASS (projection=0 == ledger 0)`).
* **Follow-up**: the `judgment_cas.nim` surface-area / OCP items need an
  architect-level decision (module split vs policy override) — see §2b.
* **Follow-up (rotation path)**: the report CLI's silent acceptance of unknown
  options can only be closed by editing the rotation-pinned
  `src/cli/report_cli.nim` — the rotation procedure/allowlist path is the
  only promotion path for that file, not an ordinary PR — see §3.
