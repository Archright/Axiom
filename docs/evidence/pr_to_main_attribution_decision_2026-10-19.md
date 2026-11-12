# PR-to-main Latency Attribution — Decision Memo (2026-10-19)

> **권위**: Reporter only. 본 문서와 `pr_latency_attribution.py`는 GitHub merge authority(ruleset·required checks·merge queue·MERGE commit)를 대체하지 않는다. 어떤 admission gate도 이 보고서를 소비하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).
> **계약**: `docs/evidence/pr_to_main_attribution_prereg_2026-10-19.md` (measurement contract v2).
> **도구**: `tools/ci/pr_latency_attribution.py` (read-only; native `gh` GET/query only).
> **데이터**: `data/ci_optimization/pr_to_main_attribution_2026-10-19.json`, window 2026-07-21T00:00Z → 2026-10-19T00:00Z, snapshot 2026-10-19T13:57:44Z.

---

## 1. Cohort and data completeness

| 항목 | 값 |
|---|---:|
| closed PRs enumerated | 944 |
| merged (primary) | 822 |
| closed-unmerged (census) | 96 |
| **data-complete** (PR-head CI + admission-gate evidence) | **106** |
| data-incomplete (`unknown`, retention/older generation) | 716 |
| cohort_complete | true |
| sample_sufficient (data-complete n≥60) | true |

- **full-cohort p95는 audit-only**다. 716건은 PR-head CI run 또는 admission-gate run이 API retention/세대 경계 밖이라 `unknown`으로 기록됐다.
- **lever 선택과 SLO-PR 판정은 data-complete cohort(n=106)** 를 기준으로 한다.
- 30일 diagnostic window(2026-09-19→10-19)도 **동일한 n=106, p95 7,006s**를 산출했다 — operational cohort가 안정적임을 확인.

## 2. Metric results

### 2.1 Full vs data-complete

| metric | n | p50 | p95 |
|---|---:|---:|---:|
| TOT full cohort | 822 | 1,497s (24.9m) | 20,574s (342.9m) |
| **TOT data-complete** | **106** | **1,491s (24.9m)** | **7,006s (116.8m)** |
| TOT(commit-date, ESTIMATE) | 822 | 1,460s | 5,537s |
| TOT(ready→merged) | 822 | 1,490s | 19,339s |

`TOT(push)` is unavailable: events feed is limited to 300 events / 30 days, and GraphQL has no ordinary-push timeline item. `TOT(commit-date)` is an ESTIMATE, not push time.

### 2.2 SLO-MG (merge-group verification recurring cost)

| metric | n | p50 | p95 |
|---|---:|---:|---:|
| latest-attempt wall (`updated_at − run_started_at`) | 165 | 907s (15.1m) | 1,143s (19.1m) |
| attempt wall (attempt-scoped jobs) | 165 | 883s | 1,124s |
| total elapsed incl. retries | 165 | 907s | 1,144s |

- SLO target: **p95 ≤ 480s**. Current p50 alone (907s) is **1.89×** the target; p95 is 2.38×.
- Top jobs by total duration: `attest / admission-check` (56,280s), `attest / build-base-artifacts` (38,094s), `attest / go-critical-lane (0)` (23,477s), `gateway / ci-bootstrap` (23,106s), `attest / go-critical-lane (1)` (18,249s).
- **SLO-MG verdict: `recurring_cost_dominant`.** This axis is independent of the end-to-end tail.

### 2.3 SLO-PR (data-complete cohort)

| segment | p50 | p95 | share of data-complete TOT p50 |
|---|---:|---:|---:|
| `pre_ci` | 520s | 4,322s | 32.5% |
| `pr_head_ci` | 0s | 548s | 0.0% |
| `pre_enqueue_gap` | 0s | 36s | 0.0% |
| `queue_wait` | 0s | 35s | 0.0% |
| `mg_ci` | 0s | 1,122s | 0.0% |
| **`between_cycle_gap`** | **0s** | **7,481s** | **0.0%** |
| `merge_tail` | 516s | 1,288s | 32.3% |
| `unattributed` | 0s | 0s | 0.0% |

- Identity: `sum(partition) + unattributed == TOT` for every PR; max |delta| = **0.000s** (tolerance ±2s).
- **Top p95 contributor: `between_cycle_gap`** — dequeue/rearm recovery interval (failed checks → next enqueue), including author fix time.
- Counterfactual: cap `between_cycle_gap` at cohort p50 (0s) → data-complete p95 **7,006s → 3,454s (−3,551s)**. This is a sensitivity analysis, not a causal claim.

### 2.4 Incident census (data-complete cohort)

| class | count |
|---|---:|
| `merged_normal` | 102 |
| `venue_red` | 13 |
| `dequeued_failed_checks` | 5 |
| `human_idle` | 4 |
| `red_retry` | 1 |
| `unknown` (data-incomplete, not in operational cohort) | 702 |

Top p95 contributors (data-complete):

| PR | TOT | primary | key partition |
|---:|---:|---|---|
| #910 | 42,208s | `human_idle` | pre_enqueue_gap ~11.4h (CI green, no merge trigger) |
| #827 | 18,193s | `venue_red` | between_cycle_gap 14,327s |
| #838 | 13,235s | `human_idle` | pre_ci/mg_ci with long idle |
| #828 | 9,474s | `venue_red` | between_cycle_gap 3,926s |
| #919 | 7,827s | `venue_red` | between_cycle_gap 5,667s |

### 2.5 Reconciliation (required samples)

| PR | TOT | partition identity | result |
|---:|---:|---|---|
| #951 | 1,200s | delta 0.000s | PR-head checks + one queue cycle; merged 13:07:29Z |
| #862 | 7,080s | delta 0.000s | `pr_head_idle` 4,559s (author iteration between CI runs); `human_idle` |
| #895 | 3,964s | delta 0.000s | two queue cycles: `failed_checks` removal → re-enqueue → merged; `venue_red` |

## 3. Cost

- **Actual per-PR billed cost = UNKNOWN.** GitHub billing usage exposes only repo × SKU × day aggregates; there is no per-run/per-PR billed cost.
- Per-PR cost is an **estimate** from job minutes × official runner rate, with shared merge-group runs allocated equally among known group members. `UNKNOWN` is never recorded as 0.
- October 2026 billing aggregate (repo `Archright/Axiom`): Actions Linux **38,619 min** (gross $231.71, discount $231.78, net $0.00), Actions Linux Slim **2,140 min** (gross $4.28, net $0.00), Actions storage 23,105 GB-hours (net $0.00). `net=0` reflects included minutes/discount, not `measured_free`.
- Sample per-PR estimates: #951 ~$0.18, #862 ~$0.54, #895 ~$0.50.

## 4. Three independent judgments

### 4.1 SLO-MG — where can recurring merge-group cost be reduced?

**Status: `recurring_cost_dominant`.** The MG p50 907s / p95 1,143s is far above the 480s target. The largest recurring job is `attest / admission-check`, followed by `build-base-artifacts`, `go-critical-lane (0)/(1)`, and `ci-bootstrap`. Reducing this requires a workflow/lane/runner change (policy/budget or contract revision), not a queue-robustness change.

### 4.2 SLO-PR — what dominates the data-complete end-to-end p95?

**Status: `p95_dominated_by_between_cycle_gap`.** The data-complete p95 is 7,006s. The largest actionable contributor is `between_cycle_gap` (dequeue/rearm recovery), with a counterfactual reduction of **−3,551s**. The extreme tail is incident/human-idle driven (#910, #827, #838, #828, #919), not normal-path CI.

### 4.3 Operational executability — can the next lever run under the existing trust contract?

**Status: `executable` for the queue/incident robustness workstream.**
- No workflow/ruleset/required-check/trustSurface change is required to observe or improve dequeue/rearm handling; `merge-queue-rearm.yml` and `landing_observe.sh` already exist.
- The SLO-MG recurring-cost lever (runner/lane change) is **`requires_policy_or_budget`** and, if it changes `admission-check.yml`, also triggers §2.5 CI epoch cutover and org pin rotation.
- No bypass of required checks or rulesets was used; the tool is Reporter-only.

## 5. Decision

1. **First next slice (end-to-end p95):** dequeue/rearm/stale-base robustness and human-idle/author workflow. Target: reduce `between_cycle_gap` and `human_idle` in the data-complete cohort. Success metric: data-complete `TOT` p95, not job wall time alone.
2. **Separate workstream (SLO-MG):** recurring MG cost. Candidate levers remain the previously identified runner/lane changes; they require policy/budget and a CI epoch cutover. Do not conflate this axis with the end-to-end incident tail.
3. **Do not claim p95 reduction yet.** This memo establishes the baseline and selects the next lever; the next slice must measure before/after on the same contract.

## 6. Caveats

- 716 of 822 merged PRs are data-incomplete because PR-head CI/admission-gate runs are outside the 90-day retention/older generation window. Full-cohort p95 20,574s is audit-only.
- `review_wait` is advisory under the 0-approval ruleset; it is never summed into TOT.
- Queue internal state durations (AWAITING_CHECKS/MATCHING/VERIFYING) are not preserved by GitHub; only bounds are reported.
- Dequeue reason is an opaque GraphQL string; REST timeline omits it.
- `TOT(push)` is unavailable; `TOT(commit-date)` is an estimate.
- Cost is an estimate or UNKNOWN; no per-PR billed cost exists.

## 7. Acceptance evidence

- PR1 (`tools/ci/pr_latency_attribution.py` + prereg) merged at `67c236bf` via merge queue; `admission-check` and `bsec-integrity` success; merge commit parents=2.
- Canonical report generated on main at 2026-10-19T13:57:44Z; all 822 PR partition identities pass with max |delta| 0.000s.
- PR 951/862/895 reconciliation passes; PR 862 author-idle and PR 895 two-cycle dequeue are visible.
- `SLO-MG`/`SLO-PR`/`operational_executability` are separate machine-readable fields.
- No workflow/ruleset/required-check/trustSurface change was made; no bypass was used.
