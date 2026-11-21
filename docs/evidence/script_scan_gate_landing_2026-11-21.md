# Unicode Script Allowlist Admission — landing and acceptance evidence

- **Status**: acceptance record (fills with live observations)
- **Date**: 2026-11-21
- **ADR**: `docs/adr/0044-unicode-script-allowlist-admission.md`
- **Policy**: `compliance/policy/script-scan-policy.yml`
- **Evaluator**: `tools/ci/publication_script_eval.nim`
- **Dimension**: `script-scan` (sixth dimension of `publication-integrity`)

## 1. Contract actually enforced

A landing diff MUST NOT add a line containing a Unicode code point whose Script
property is outside `{ASCII range, Latin, Greek, Common, Inherited}`, except at the
exact-path product i18n exemption `data/i18n/ko.json`.

This is **not** an English-only guarantee. Declared limitations (shipped in the
policy and in every report): Latin-script non-English prose, Greek prose,
Common/Inherited punctuation, HTML entities, Unicode escapes, images, and
PR/issue/commit messages are not detected.

## 2. Authority preflight

| Item | Value |
|---|---|
| Merge authority | GitHub rulesets `27097366` (7 contexts) and `27525972` (`admission-check`) |
| New required check | none |
| New GitHub App | none |
| New workflow file | none (existing `publication-integrity`) |
| Check identity | `publication-integrity`, unchanged |
| Producer | existing workflow, existing App (`5795152` for `admission-check`, `15368` for the six others) |
| Agent authority | read/modify/execute/push; merge requires delegation + break-glass |

## 3. CI epoch freeze

- Frozen live main: `db0e977f6219d33dcfc91be1f9e238a72f2dd53b`.
- Freeze tag: `ci-frozen-2026-11-21-script-scan`.
- Frozen blobs: workflow `4e343a953700359c4963d2d048045e550d407f13`,
  report `eb278f8fd9025d20539ae2e996e7a91bd7b8726a`,
  merge admission `5c75f451b0e9326e0d692542828478e954652693`.
- Live main advanced during the work (#304, #273, #308); landing is a native
  MERGE on the live tip, not a rebase.

## 4. Implementation and local verification

- Commit `4c4290743089572446d7736179bb9975c95b043f` — dimension, policy, ADR,
  spec v1.5, tests, workflow job, aggregator wiring, trust-surface registration.
- Commit `41c02cf096a934cbe1d7e94b96e8adbb2feb0ae6` — replaced swallowed stderr
  failures with diagnostic capture after the theater gate rejected them.
- `tests/ci/test_publication_gate_tools.nim`: 25/25 pass (six script-scan tests).
- Self-scan of the implementation diff (base `db0e977f`, head `41c02cf0`):
  PASS, added lines 1626, violations 0, unknowns 0.
- `check-workflow-shell-syntax`: 273 run blocks, 0 failures.
- `make check-repository-surface`: FROZEN MODIFY on `config/policy/merge_admission.json`
  and `.github/**` — the designed trust-surface self-reference.

## 5. Trust-surface landing (PR #309)

- Delegation record: PR comment `7059573764`, scoped to PR #309 and head
  `41c02cf096a934cbe1d7e94b96e8adbb2feb0ae6`; yolo mode made the interactive
  prompt unavailable, so the comment records the operator's explicit
  authorization and the executor's non-dual-control status.
- Pre-change ruleset snapshots:
  - `27097366` sha256 `d05fac11e9b8d3563630eef5d930713dc106e18f0f69c27a67f55f6e5cc3b40a`
  - `27525972` sha256 `4d00178406e419337905cb220e245cdb10e1d408c794ce90ca1ddc6d027a6fe0`
- Queue drained before the bypass (`mergeQueue.entries.totalCount = 0` at
  `2026-11-21T07:54:23Z`, after PR #308 merged).
- Bypass: `OrganizationAdmin`, `bypass_mode=pull_request`, on both rulesets.
  PUT A `07:58:16Z`, PUT B `07:58:17Z`.
- Merge: REST native MERGE `858710ae6f590d7dae06646142e79851dda10721` at
  `2026-11-21T07:58:46Z`.
- Restore: PUT A `07:59:23Z`, PUT B `07:59:24Z`. Readback: both rulesets
  `bypass_actors=[]`, contexts 7/1, essential fields byte-identical to the
  pre-change snapshots.
- `admission-check` on the PR failed only at `[SL-20] SURFACE_FORBIDDEN`
  (9 changed files: `config/policy/**`, `.github/**`). The other six required
  contexts passed.

## 6. Negative controls (live)

Fill from merge-queue observations. Each PR is based on live main, armed with
`gh pr merge --auto`, and must be rejected by `publication-integrity` at the
merge-group venue.

| Control | Branch / PR | Mutation | Expected | Observed |
|---|---|---|---|---|
| NEG-1 | `neg1-korean-line` / #311 | new Korean line | FAIL | FAIL — run `44885635430`, head `d9d9d14b`, check-run `136792038460`; report 19 code points; PR removed from queue, auto-merge disabled |
| NEG-2 | `neg2-korean-edit` / #312 | edited line keeps Korean | FAIL | FAIL — run `44886279753`, head `17542649`, check-run `136793550558`; report 18 code points; PR removed from queue, auto-merge disabled |
| NEG-3 | `neg3-invalid-utf8` / #313 | invalid UTF-8 added line | UNKNOWN | UNKNOWN — run `44886843660`, head `f9cb21be`, check-run `136795356889`; aggregator verdict UNKNOWN, blocker `job script-scan result=failure`; PR removed from queue, auto-merge disabled |
| NEG-4 | `neg4-exempt-rename` / #314 | rename out of exempt path | UNKNOWN | see §7 |

Local evaluator results before arming:
- NEG-1: FAIL (19 code points, first `U+C774`).
- NEG-2: FAIL (18 code points, first `U+AC8C`).
- NEG-3: UNKNOWN (`invalid UTF-8: tests/fixtures/script_scan/neg3_invalid_utf8.md:1`).
- NEG-4: UNKNOWN (`exempt path is not tracked: data/i18n/ko.json`; renamedPaths
  records a full destination scan of 132 added lines).

## 7. NEG-4 structural finding (honest limitation of the observation)

`data/i18n/ko.json` is also a closure input of
`.github/actions/setup-axiom-toolchain` (`AXIOM_CACHE_KEYGEN`). Moving it makes
every job that uses the action fail before adjudication
(`AXIOM_CACHE_KEYGEN: FAIL — closure input data/i18n/ko.json absent from tree`),
and `readiness-verdict` / `secret-scan` also fail. Consequently the PR cannot
enter the merge queue, so the exempt-liveness UNKNOWN is verified locally and by
unit tests but is preempted live by an independent fail-closed gate. This is
defense in depth, not a hole: the mutation is blocked either way.

## 8. Clean canary (live)

- Brand: `canary-script-scan-clean`, PR #315, English-only file.
- All seven required contexts succeeded before arming.
- Merge-group run `44887625501`: `publication-integrity` check-run `136797794855`
  success, six dimensions PASS; `script-scan` report PASS (added 13, unknowns 0).
- Landed as native MERGE `075bc10274787ab51f8a5ed6d6085aee6074f787`, the same
  SHA as the queue merge-group head.

## 9. Canonical main landing venue

- `gh workflow run publication-integrity.yml --ref main` on `075bc102`.
- Run `44888458815`: `script-scan` job success; report verdict PASS,
  added 13, unknowns 0; binding base `974f4afd`, head `075bc102`;
  tool ripgrep 14.1.0 musl, binary sha256
  `c2feed7a376d3754958fa6235a6ef88a74bcabc9b0cfccacbd48939b5f87860d`.
- Aggregator report: venue `workflow_dispatch`, verdict **PASS**, all six
  dimensions PASS (secret-scan, license-scan, dependency-scan, provenance,
  sbom, script-scan), no blockers. Check-run `136800227695` on `075bc102`
  (`actions/runs/44888458815/job/136800227695`).

## 10. Language debt inventory

- File: `docs/reports/script_scan_language_debt_inventory_2026-11-21.json`.
- Measured at `075bc102` with the policy pattern and the same exclusions as the
  gate (`vendor/`, `build/`, `.cache/`, `.axiom/`, `data/i18n/ko.json`).
- Totals: **1,025 files**, **1,184,951** disallowed-script code points.
- Largest areas: `docs/evidence` 629,678; `docs/spec` 249,804;
  `docs/adr` 77,888; `docs/history` 24,114; `docs/agents` 19,528.
- The inventory is a measurement baseline, not a translation mandate. Historical
  evidence keeps its original text; the migration workstream decides which
  documents receive English translations or English summaries.

## 11. Preserved invariants

| Invariant | Post-landing state |
|---|---|
| Required contexts | 7 on `27097366`, 1 on `27525972` — unchanged |
| Bypass actors | `[]` on both rulesets |
| Check identity | `publication-integrity` unchanged |
| App identities | `5795152`, `15368` unchanged |
| Merge method | MERGE (native), unchanged |
| Failure semantics | UNKNOWN blocks; missing report is UNKNOWN; skipped dimension never success |

## 12. Post-landing live observations (same day, appended)

These observations were made after this record landed (`647e83c3`). Earlier
sections are kept as written; this section appends what the live queue then
produced.

### 12.1 Real PRs blocked by the gate (not synthetic mutations)

| Control | PR | Mutation | Observed |
|---|---|---|---|
| NEG-5 | #317 | Korean prose added to `docs/adr/0025-gateway-landing-authority.md` (23 lines in the ADR; 131 across the PR) | FAIL — stacked merge-group run `44890395147`, head `446f55f5`, base `647e83c3`; report 2,158 code points, first `docs/adr/0025-gateway-landing-authority.md:1036 U+C2B9`; aggregator FAIL; entry evicted from the queue at 09:44:21Z; PR remains OPEN |
| NEG-6 | #321 | 17 added lines carrying Korean prose in `docs/spec/github_delegation_residuals.md` | FAIL — merge-group run `44891148754`, head `e611416c`, base `48ea64fe`; report 256 code points in `docs/spec/github_delegation_residuals.md:66`; entry evicted; PR remains OPEN |

Both PRs were authored outside this workstream and entered the queue through
the normal path, so the gate blocks genuine contributions, not only fixtures.
Neither PR was closed; each can land after its added prose is translated.

`script-scan` is intentionally not part of `pull_request` admission. PR #321
therefore reported `mergeStateStatus=CLEAN` at the pull-request level while it
could not pass the merge queue. The landing venue remains the sole verdict;
a green PR page is not an admission decision.

### 12.2 Attribution and isolation in a stacked queue

In the same queue cycle, PR #320 (English-only test) landed as `48ea64fe`
while the stacked group `48ea64fe -> e611416c`, which contained #321, failed.
The failure isolated to the PR that added Korean; ordinary English development
continued in the same cycle.

### 12.3 Out-of-band ruleset drift detected and reverted

The final readback found that both rulesets had gained a `User` bypass actor
at `2026-11-21T09:36:23Z`, after the §11 readback:

```
bypass_actors: [{actor_id: 53123826, actor_type: User, bypass_mode: always}]
```

This change was not made by this workstream and contradicted the frozen
pre-change snapshot (both rulesets `[]`). The drifted bodies were snapshotted
and the pre-change bodies restored at `2026-11-21T09:46:14Z` with
`bypass_actors: []`. The final essential-field diff against the pre-change
snapshot is empty for both rulesets (contexts, enforcement, conditions,
merge-queue parameters, bypass actors). An `always` bypass would allow direct
pushes and merges to bypass every required check, including `script-scan`;
restoring the snapshot is part of acceptance, not housekeeping.

### 12.4 Final canonical main state

- main `48ea64fe` (PR #320) contains `647e83c3` (this record and the inventory).
- `gh workflow run publication-integrity.yml --ref main` on `647e83c3`:
  run `44891171515`, check-run `136808808137`, verdict **PASS**, all six
  dimensions PASS including `script-scan` (report PASS, 0 violations,
  0 unknowns; binding `4ea334d4 -> 647e83c3`).
- Ruleset final readback: `27097366` 7 contexts, MERGE/ALLGREEN, bypass `[]`;
  `27525972` 1 context, bypass `[]`.