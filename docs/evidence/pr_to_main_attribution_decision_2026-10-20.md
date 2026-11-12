# PR-to-main Latency Attribution — Decision Memo (2026-10-20, 14-day operational window)

> **권위**: Reporter only. 본 문서와 `tools/ci/pr_latency_attribution.py`는 GitHub merge authority(ruleset·required checks·merge queue·MERGE commit)를 대체하지 않는다. 어떤 admission gate도 이 문서를 소비하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).
> **계약**: `docs/evidence/pr_to_main_attribution_prereg_2026-10-19.md` (measurement contract v2 + run enumeration amendment).
> **데이터**: `data/ci_optimization/pr_to_main_attribution_2026-10-20.json`, window **2026-10-06 → 2026-10-20**, snapshot 2026-10-20T05:07:33Z.
> **window 선택**: full 90-day는 audit-only(2026-10-19 보고서)로 보존하고, 운영 판단은 data-complete 419/423을 포함하는 최소 14일 window로 수행한다. 90일 full audit는 1,000-run cap bug로 undercount된 상태이며, fixed tool로 별도 재생성해야 한다.

---

## 1. Cohort

| 항목 | 값 |
|---|---:|
| closed PRs enumerated | 952 |
| merged (primary) | 423 |
| closed-unmerged (census) | 41 |
| **data-complete** | **419** |
| data-incomplete (`pr_head_ci_run_missing`) | 4 |
| run history start/end | 2026-10-05T15:00:33Z / 2026-10-19T14:58:55Z |
| cohort_complete | **true** |
| sample_sufficient | true |

## 2. Metrics

| metric | n | p50 | p95 |
|---|---:|---:|---:|
| TOT full cohort | 423 | 1,562s (26.0m) | 13,253.9s (220.9m) |
| **TOT data-complete** | **419** | **1,556s (25.9m)** | **13,295.4s (221.6m)** |
| SLO-MG latest-attempt wall | 564 | 799s (13.3m) | 1,118.7s (18.6m) |
| SLO-MG attempt wall | 564 | 778.5s | 1,098.0s |
| SLO-MG total elapsed incl. retries | 564 | 799.5s | 1,119.6s |

- `TOT(push)`는 산출 불가: `Commit.pushedDate` deprecated/null, ordinary push timeline item 없음, events feed ≤300/30일. `TOT(commit-date)`는 ESTIMATE다.
- SLO-MG target p95 480s 대비 **p50 799s = 1.66×, p95 1,119s = 2.33×**.
- Top MG jobs (p50/p95): `attest / admission-check` 280.5/661.7s, `build-base-artifacts` 254/310s, `ci-bootstrap` 235/288s, `verdict / admission-check` 46/203.7s, `select` 60/103s.

## 3. Wall partition (data-complete, identity max |delta| 0.000s)

| segment | p50 | p95 | mean | max |
|---|---:|---:|---:|---:|
| `pre_ci` | 4s | 891.9s | 271.4s | 17,888s |
| `pr_head_ci` | 434s | 982.1s | 505.8s | 3,317s |
| `pr_head_idle` | 0s | 971.1s | 236.5s | 14,903s |
| `pre_enqueue_gap` | 26s | 335.3s | 400.5s | 58,846s |
| `queue_wait` | 18s | 921.8s | 135.4s | 2,976s |
| `mg_ci` | 853s | 2,847.3s | 1,000.9s | 6,961s |
| **`between_cycle_gap`** | **0s** | **5,743.8s** | **1,277.4s** | **65,216s** |
| `merge_tail` | 25s | 27.1s | 44.1s | 8,454s |
| `unattributed` | 0s | 0s | 0s | 0s |

- **Top p95 contributor: `between_cycle_gap`** — dequeue/rearm recovery (failed checks/conflict → next enqueue), including author fix time.
- Counterfactual (cap at p50): `between_cycle_gap` **−6,451.9s** (13,295.4 → 6,843.5), `mg_ci` −1,327.3s, `pr_head_idle` −890.9s. Sensitivity only, not causal.

## 4. Incidents (data-complete)

| class | count | share of data-complete TOT sum | p50 | p95 |
|---|---:|---:|---:|---:|
| `merged_normal` | 336 | 31.55% | 1,382.5s | 2,913.8s |
| **`venue_red`** | **46** | **45.70%** | 9,516s | 52,437.8s |
| `human_idle` | 29 | 28.60% | 10,125s | 57,390.4s |
| `dequeued_failed_checks` | 7 | 14.82% | 33,849s | 51,230.3s |
| `dequeued_manual` | 6 | 10.77% | 8,015s | 85,025.8s |
| `dequeued_merge_conflict` | 10 | 8.14% | 7,849s | 42,913.7s |
| `red_retry` | 9 | 2.73% | 2,671s | 13,520.4s |
| `dequeued_other` | 1 | 1.96% | 31,799s | 31,799s |

Shares are **not additive**: one PR can carry multiple classes. `venue_red` dominates the incident mass; the deterministic reason codes are `NOT_ADMIT_ROT_NEW_PIN` (6), `NO_CERT` (4), `ROT_ALLOWLIST` (1), `UNPARSED` (1) in the 2026-10-13→19 sub-cohort.

Top p95 contributors (data-complete):

| PR | TOT | primary | key partition |
|---:|---:|---|---|
| #627 | 93,876s | `venue_red` | between_cycle_gap 65,216s |
| #650 | 67,179s | `venue_red` | between_cycle_gap 60,767s |
| #657 | 61,186s | `human_idle` | pre_ci 59,094s |
| #787 | 58,475s | `venue_red` | between_cycle_gap 49,530s |
| #910 | 42,208s | `human_idle` | pre_enqueue_gap 41,144s (dependabot, no merge trigger) |

## 5. Reconciliation

| PR | TOT | identity | observation |
|---:|---:|---|---|
| #951 | 1,176s | delta 0.000s | PR-head 477s + MG 656s; normal |
| #862 | 7,080s | delta 0.000s | `pr_head_idle` 4,559s (author iteration); human_idle |
| #895 | 3,964s | delta 0.000s | two queue cycles; `NOT_ADMIT_ROT_NEW_PIN`; venue_red |

## 6. Cost

- Per-PR actual billed cost = **UNKNOWN** (GitHub exposes repo×SKU×day aggregates only; no run/job/PR key).
- Per-PR estimate = job minutes × official rate; shared MG runs recorded once; equal split among known group members; `UNKNOWN` never 0.
- October 2026 repo aggregate: Actions Linux 39,783 min (gross $238.70, net $0.00), Actions Linux Slim (net $0.00), storage 24,102 GB-hours (net $0.00). `net=0` reflects included minutes/discount, not measured-free.
- Sample per-PR estimates remain in `cost.pr_estimates`.

## 7. Three independent judgments

### 7.1 SLO-MG — recurring merge-group cost

**`recurring_cost_dominant`.** p50 799s / p95 1,119s vs 480s target. The attest chain (`build-base 254s → go-critical-lane → attest admission-check 280.5s p50`) plus `ci-bootstrap 235s` is the recurring body. This axis requires workflow/lane/runner changes (policy/budget + §2.5 cutover), not queue robustness.

### 7.2 SLO-PR — data-complete end-to-end p95

**`p95_dominated_by_between_cycle_gap`.** Data-complete p95 is 13,295s. The largest actionable contributor is dequeue/rearm recovery (`between_cycle_gap`), with a counterfactual −6,452s. `venue_red` accounts for 45.7% of the data-complete TOT mass; `human_idle` 28.6% (dominated by #910's missing dependabot merge trigger).

### 7.3 Operational executability

- Queue/incident robustness: **`executable`** — observation, operator label protocol, dependabot trigger, and rearm verdict ingestion require no trust-surface change.
- Workflow/credential changes (condition 6 pagination, `NOT_ADMIT_ROT_NEW_PIN` classification amendment, PAT/App arm credential, auto-arm-on-ready): **`requires_policy_or_budget`** and/or §2.5 cutover. Detail in `pr_to_main_attribution_remaining_issues_2026-10-20.md`.
- No bypass of required checks or rulesets was used; the tool is Reporter-only.

## 8. Decision

1. **First next slice (end-to-end p95)**: dequeue/rearm robustness + human-idle/author workflow. Target the `between_cycle_gap` and `venue_red` mass; measure data-complete TOT p95 before/after on the same 14-day contract.
2. **Separate workstream (SLO-MG)**: recurring attest-chain cost. Candidate levers (runner/lane/topology) require policy/budget + §2.5 cutover.
3. **No p95 reduction is claimed in this memo.** This establishes the baseline and selects the next lever.

## 9. Caveats

- 14-day operational window; full 90-day audit is audit-only and was undercounted by the (now fixed) 1,000-run cap.
- `review_wait` is advisory under the 0-approval ruleset; never summed into TOT.
- Queue internal state durations are not preserved by GitHub; only bounds are reported.
- Dequeue reason is an opaque GraphQL string; REST omits it.
- `TOT(push)` is unavailable; `TOT(commit-date)` is an estimate.
- Per-PR billed cost is impossible; estimates only.
- Required-check semantics: GitHub accepts `success`/`skipped`/`neutral`; Axiom's `acceptableConclusion: "success"` is a stricter policy, not a platform guarantee.
