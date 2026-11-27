# PR #517 trust-surface break-glass landing record — closure-deriver provisioning 62 s → 10 s

> **Status**: landing record. This document **records, after the fact, a manual landing that has already
> happened**; it changes no policy, workflow, or ruleset. The one exception: the same PR appends a single
> row for this bypass event to `data/ci_optimization/rule_suite_bypass_ledger/ledger.jsonl` (the ledger is
> the permanent record whose own header says the platform destroys the evidence after 30 days unless it is
> copied in, so it is closed in the same PR as the landing).
> **Created**: 2026-11-27
> **Landing**: PR #517 → native MERGE `e44acaf0f25d0f82b49ad130db5b5c2214cbdc37`

## §0. What this document records

PR #517 changed `.github/workflows/admission-gate-v2.yml`, one of the 18 trust-surface paths, so App
`5795152`'s `admission-check` refused it by design and the normal merge-queue route was structurally
unavailable. The MUST-T2a delegation was registered as a PR comment **before** the merge command; a
temporary bypass was then granted on the **two** rulesets that carry required checks and the landing was
performed through the REST merge endpoint. This document fixes those facts and the invariant preservation.

## §1. Authority chain

| Item | Value |
|---|---|
| Operator (human architect) | `wintrover` — org role `admin` (measured: `orgs/Archright/memberships/wintrover`) |
| Operator instruction (originally in Korean; rendered in English) | "Everything that requires permission is fully approved." / "Everything that requires permission is fully permitted." / "Carry it through to the end." / "Optimize trust surface and frozen too. They must not be sacred ground." — 2026-11-27 |
| Delegation record | `issuecomment-7209034456` (registered **before** the merge command) |
| Executor | agent (per-PR explicit delegation). Not recorded as human key input (§0.9 honest-executor). |

## §2. Refusal evidence and the rotation steps (command → response)

- **Refusal**: at PR #517 head `b0030664`, App `admission-check` = `FAILURE`.
  Every in-repo check on the same head was green (green 23 / skipped 12 / failure 1 — the single failure is the App).
- **Mid-queue mutation ban honored**: at the moment of ruleset manipulation `mergeQueue(branch:"main").entries.totalCount = 0` (GraphQL, measured twice).
- **Observation purity honored**: observation used GET only. `current_user_can_bypass: never` was also read via GET only.

### §2.1 Snapshots (before manipulation)

| ruleset | sha256 | required contexts |
|---|---|---|
| `27097366` main | `4984d5fafb9a4db114a28948b736bd3682c7e76131fd9149e2ae192037519b29` | 7: `admission-check`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`, `publication-integrity`, `readiness-verdict` |
| `27525972` main-admission | `17ba52e51d0dbfa4bf0c225f3e0c0698e8af87e341d0a2978c4d67f466f26e45` | 1: `admission-check` |

Both rulesets had `bypass_actors = []` before manipulation.

### §2.2 Three-step rotation

1. `PUT /repos/Archright/Axiom/rulesets/27097366` ← `bypass_actors:[{actor_type:"OrganizationAdmin", bypass_mode:"pull_request"}]`
   → response `updated_at=2026-11-27T12:30:35+09:00`
2. `PUT .../rulesets/27525972` (same bypass) → response `updated_at=2026-11-27T12:30:36+09:00`
3. `PUT /repos/Archright/Axiom/pulls/517/merge` `{merge_method:"merge", sha:"b0030664…"}`
   → response `{"merged":true,"message":"Pull Request successfully merged","sha":"e44acaf0f25d0f82b49ad130db5b5c2214cbdc37"}`
4. Restore, two `PUT`s (bypass removed) → `updated_at=2026-11-27T12:30:53+09:00` / `…54+09:00`

`--auto` was not armed (MUST-T1). `gh pr merge --merge` cannot get past the merge_queue rule
(VS-I §2.2(ii), measured), so the REST merge endpoint was used.

## §3. Invariant preservation, measured after landing

- **Rulesets intact**: after restoration, `{name,target,enforcement,conditions,rules,bypass_actors}` of both
  rulesets were **byte-compared against the pre-manipulation snapshots → identical: true** (both). `bypass_actors = []`.
- **Required contexts unchanged**: 7 / 1, identical to before landing.
- **Canonical main push CI**: `trusted-writer-set` ✔, `fresh-prove-observation` ✔,
  `axiom-operational-slice` ✔ (03:30:49→03:33:17), `readiness-verdict` ✔ (03:33:19→03:35:35).
- **Epoch axis unchanged**: `trustedAdmissionWorkflowSha` / `productionExecutionPin` are the `admission-check.yml`
  axis and this PR does not touch that file → no epoch rotation needed.
- **Cache-key lineage unchanged**: `script_hash` is computed from the workspace `action.yml`, not from the pinned
  remote bytes (`action.yml:224`). Confirmed empirically by `axiom-a-nim-…-cbb80a6a…` `exact-hit=true` on the PR run.

## §4. Measured effect (not an estimate)

| Measurement | baseline | before landing (PR run) | Source |
|---|---|---|---|
| provisioning step | 62 s | **10.0 s** | run 45933688981 / job 140291928327 step 5 (03:21:54→03:22:04) |
| ├ A-layer restore (1,083,675,758 B → 202,171,572 B) | 30 s | 5.0 s | `a-restore duration_ms=5006` |
| └ `Install system deps (libpcre3)` | 31.8 s | 4.0 s | `__run_4 duration_ms=3998` |
| `closure-deriver` job | 85 s | 33 s | job 140291928327 (03:21:39→03:22:12) |

`AXIOM_CACHE_A_RESTORE: exact-hit=true`, `AXIOM_CACHE_A_VERIFY: OK — nim=2.2.10 z3=4.13.3 gccFp=8497f84b2b8334c4 glibcFp=f3590395c77ccf34`,
`a-paths scope=nim: ~/.nimble ~/.choosenim ~/.local/bin`. B-layer is `exact-hit=` (empty) — a miss by design, inert because the deriver does not consume B outputs.

## §5. Ledger entry

`data/ci_optimization/rule_suite_bypass_ledger/ledger.jsonl` 29 → 30 rows.
New row = `{"id":5400971285,"actor_name":"wintrover","before_sha":"750e14cd…","after_sha":"e44acaf0…","result":"bypass"}`.
`rule_suite_bypass_ledger assert` result: 30 landings, range `2026-11-17T01:50:38+09:00 .. 2026-11-27T12:30:43+09:00`,
freshness **FRESH** (age=0d, limit=30d); direct-push / elevation-window are **UNKNOWN** because no inputs were supplied (unperformed ≠ 0).

## §6. Remaining honest limits

- This landing **consumed one rotation**. The fact that touching a trust-surface path costs this ceremony every
  time is itself a structural cost to development speed, and that cost exceeds the 52 seconds this PR saved. The
  remedies are App semantics (DEBT#558) or a smaller trust-surface path set; neither is reachable by an in-repo change alone.
- `runner-pool-acceptance.yml@c021c338` at `admission-gate-v2.yml:641` carries the same 12-day-old pin. It is
  outside this PR's scope (found ≠ authorized) and is left as a follow-up.
