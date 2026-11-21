# CI Epoch Record — publication-integrity script-scan sixth landing dimension (epoch script-scan): Freeze / Record / Rollback

> **Nature**: AGENTS.md §2.5 (CI Epoch Cutover Protocol) FREEZE / RECORD / ROLLBACK
> record for the coherent-generation cutover that adds the `script-scan` dimension to
> the `publication-integrity` landing venue. The required context name, workflow path,
> and aggregator job id do not change; the aggregation gains a sixth dimension
> (ADR-0044).
> **Date**: 2026-11-21.
> **Work branch**: `workstream/script-scan-admission` (clone-first — AGENTS.md §2.7).
> **Decision binding**: AGENTS.md §2.5 · §2.6 · ADR-0044 ·
> `docs/spec/publication_integrity_gate.md` v1.5.

---

## 1. FREEZE (AGENTS.md §2.5 step 1)

| Item | Value |
|---|---|
| freeze tag | **`ci-frozen-2026-11-21-script-scan`** — pushed to origin. Remote readback: tag object `85db12f9cec221c685188b2b1c763586242bc96e`, peeled `^{}` → `db0e977f6219d33dcfc91be1f9e238a72f2dd53b` |
| freeze target commit = branch base | **`db0e977f6219d33dcfc91be1f9e238a72f2dd53b`** |
| tag ↔ commit match | `git rev-parse ci-frozen-2026-11-21-script-scan^{commit}` == `db0e977f…` (measured) |
| frozen workflow blob SHA | **`4e343a953700359c4963d2d048045e550d407f13`** — `.github/workflows/publication-integrity.yml` |
| frozen aggregator blob SHA | **`eb278f8fd9025d20539ae2e996e7a91bd7b8726a`** — `tools/ci/publication_report.nim` |
| frozen admission policy blob SHA | **`5c75f451b0e9326e0d692542828478e954652693`** — `config/policy/merge_admission.json` |
| rollback basis | the three blobs above — a rollback restores exactly these contents |

Measured blob readback: `git rev-parse db0e977f:<path>` for each path above. The
admission policy path is `config/policy/merge_admission.json`; there is no
`tools/ci/merge_admission.json` in the tree.

Post-freeze main movement (measured 2026-11-21): `origin/main` advanced to
`ebfc56ff72a69f5f0b3a012ed55ea1c92512f222` (PR #304, `workstream/stale-debt-close`)
after the freeze. `db0e977f` is an ancestor of that commit. The freeze target and the
policy `baselineCommit` remain `db0e977f`. The landed change is a GitHub native MERGE
whose first parent is the live main at merge time; that parent is the base the
post-merge `schedule`/`workflow_dispatch` venue judges (`HEAD~1`), so the landing
run and the post-merge run both judge this generation's own change set. The workflow
passes an explicit base per venue (the merge-queue base on `merge_group`; `HEAD~1` on
`schedule`/`workflow_dispatch`); `baselineCommit` is the evaluator's default base for
standalone runs, never an exemption for intervening commits (each was judged by its
own landing run).

## 2. RECORD (step 2)

### 2.1 Change summary

| Surface | Change |
|---|---|
| `tools/ci/publication_script_eval.nim` | new evaluator: Unicode Script allowlist over added diff lines, PASS/FAIL/UNKNOWN, exit 0/1/2, fail-closed inputs |
| `compliance/policy/script-scan-policy.yml` | new policy SSOT: allowlist, exact-path exemptions, tool contract, claim, declared limitations |
| `tools/ci/publication_report.nim` | aggregator gains the sixth dimension through the existing four points (job result → `--job`, `--report`, `--policy-file`); required context and report semantics unchanged |
| `.github/workflows/publication-integrity.yml` | `script-scan` dimension job and aggregator wiring; the job is gated by the landing venue condition (a preflight `success` would be a BLOCKER, spec §2.1 invariant 4) |
| `config/policy/merge_admission.json` | v1.25.0: the evaluator and the policy join `trustSurface` |
| `docs/adr/0044-unicode-script-allowlist-admission.md`, `docs/spec/publication_integrity_gate.md`, this record | decision and contract |

### 2.2 Authority invariant — what does not change

| Element | State |
|---|---|
| Required context | `publication-integrity` (name invariant) |
| Workflow path / aggregator job id | `.github/workflows/publication-integrity.yml` / `publication-integrity` (invariant) |
| Producer | GitHub Actions app `15368` (the context was already Actions-owned) |
| Required context count | 7 — no context added or removed |
| Required context set | admission-check, bsec-integrity, debt-registry-gate, generation-acceptance, axiom-operational-slice, publication-integrity, readiness-verdict |
| Merge queue configuration | unchanged |
| Preflight dimension set | `{secret-scan}` unchanged; `script-scan` is landing-only |

### 2.3 Ruleset pre-change readback (both admission rulesets)

Ruleset `27097366` (`main`):

| Field | Pre-change value |
|---|---|
| required contexts (7) | admission-check, bsec-integrity, debt-registry-gate, generation-acceptance, axiom-operational-slice, publication-integrity, readiness-verdict |
| rules | 5 |
| `bypass_actors` | `[]` |
| merge queue | `MERGE` / `ALLGREEN` |
| `max_entries_to_build` | 100 |
| `max_entries_to_merge` | 1 |
| `check_response_timeout_minutes` | 120 |

Ruleset `27525972` (`main-admission`, a second ruleset that requires the same
`admission-check` context — bypassing only `27097366` was measured to fail with
HTTP 405 on 2026-11-19):

| Field | Pre-change value |
|---|---|
| required contexts (1) | admission-check |
| `bypass_actors` | `[]` |
| snapshot | `/tmp/ruleset-pre-27525972.json`, sha256 recorded in the landing evidence |

### 2.4 Operational risk — the temporary bypass window (declared)

This change touches the trust surface, so it cannot ride the auto-merge queue. It
lands through a **temporary `OrganizationAdmin` bypass** on both rulesets:
`27097366` and `27525972` are each PUT twice — PUT #1 adds the actor to
`bypass_actors`, PUT #2 restores `bypass_actors: []` — four PUTs in total. During the
window the merge authority is wider than `[]`. This record therefore does **not**
claim "no ruleset change"; both rulesets are changed and restored.

Controls:

1. The pre-change readbacks above are recorded (with full JSON snapshots and sha256)
   before PUT #1.
2. Every PUT is audited (actor, timestamp, request body) and linked from the landing
   evidence `docs/evidence/script_scan_gate_landing.md`.
3. The window closes on the same UTC day; the queue is drained before the first PUT
   and no other PR lands under the bypass.
4. **Final readback** must equal the pre-change values for both rulesets: the same 7
   contexts on `27097366`, the same 1 context on `27525972`, 5 rules, `bypass_actors:
   []`, merge queue `MERGE`/`ALLGREEN`, `max_entries_to_build: 100`,
   `max_entries_to_merge: 1`, `check_response_timeout_minutes: 120`. Any difference is
   an incident, not a residual.

### 2.5 Coherent-generation cutover and single-generation rollback

The workflow, evaluator, policy, aggregator wiring, and trust-surface entry land as
**one generation**. No in-place partial edit of the live execution boundary is made
(AGENTS.md §2.5). Rollback is the generation boundary: restore the three frozen blobs
above (workflow, aggregator, admission policy) and remove the new evaluator and policy.
There is no partial rollback — reverting only the workflow would leave the report
contract and the trust surface out of step with the live generation.

Because the required context and the workflow path are invariant, rollback does not
move merge authority and needs no ruleset PUT beyond restoring `bypass_actors: []`.

## 3. Acceptance observations (status)

Facts recorded in this document are the freeze readbacks above. Post-cutover
observations are appended to `docs/evidence/script_scan_gate_landing.md` from the run
record; they are never assumed here.

| Observation | Status |
|---|---|
| freeze tag pushed and peeled to `db0e977f…` | measured |
| frozen blob SHAs (three) | measured |
| ruleset pre-change readback (both rulesets) | recorded (pre-change) |
| `origin/main` advanced to `ebfc56ff…` after the freeze | measured |
| temporary bypass window (four PUTs, two rulesets) | planned; controls in §2.4 |
| post-cutover ruleset final readback | required to close §2.4; recorded in the landing evidence |
| landing run with `script-scan` verdict | required; appended from the run record |
| negative controls (non-Latin added line FAIL, exempt i18n path PASS, invalid UTF-8 UNKNOWN) | required; appended from the run record |
