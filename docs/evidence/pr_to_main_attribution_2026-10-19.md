# PR-to-main Latency Attribution — 2026-10-19

> **권위**: Reporter only. GitHub merge authority(ruleset·required checks·merge queue·MERGE)를 대체하지 않는다. 이 보고서는 admission 판정 입력이 아니며 어떤 gate도 소비하지 않는다.
> **계약**: `docs/evidence/pr_to_main_attribution_prereg_2026-10-19.md` (measurement contract v2).

## 1. Cohort

| 항목 | 값 |
|---|---|
| repo | `Archright/Axiom` |
| window | 2026-07-20T15:00:00Z → 2026-10-18T15:00:00Z |
| closed PRs collected | 944 |
| merged (primary) | 822 |
| data-complete (CI/queue evidence) | 106 |
| data-incomplete (UNKNOWN attribution) | 716 |
| closed-unmerged (census) | 96 |
| cohort_complete | true |
| sample_sufficient (n>=60) | true |

## 2. Metrics

| metric | p50 | p95 | n |
|---|---:|---:|---:|
| TOT full cohort | 1497.0s (24.9m) | 20574.0s (342.9m) | 822 |
| TOT data-complete cohort | 1491.0s (24.9m) | 7005.8s (116.8m) | 106 |
| TOT(commit-date, ESTIMATE) | 1460.5s (24.3m) | 5537.4s (92.3m) | 822 |
| TOT(ready→merged) | 1490.0s (24.8m) | 19339.3s (322.3m) | 822 |
| SLO-MG latest-attempt wall | 907.0s (15.1m) | 1143.0s (19.1m) | 165 |

Full-cohort TOT includes data-incomplete PRs (no CI/queue events); lever selection uses the data-complete cohort.

`TOT(push)` is unavailable: `events feed limited to 300 events / 30 days; GraphQL has no ordinary-push timeline item`.

## 3. Wall partition (data-complete cohort; non-overlapping; sum == TOT)

| segment | p50 | p95 | total | share of data-complete TOT p50 |
|---|---:|---:|---:|---:|
| `pre_ci` | 4.0s (0.1m) | 7.0s (0.1m) | 30.5s (0.5m) | 0.3% |
| `pr_head_ci` | 377.5s (6.3m) | 677.2s (11.3m) | 454.4s (7.6m) | 25.3% |
| `pr_head_idle` | 0.0s (0.0m) | 188.2s (3.1m) | 136.4s (2.3m) | 0.0% |
| `pre_enqueue_gap` | 15.0s (0.2m) | 280.8s (4.7m) | 438.8s (7.3m) | 1.0% |
| `queue_wait` | 18.0s (0.3m) | 379.5s (6.3m) | 59.8s (1.0m) | 1.2% |
| `mg_ci` | 917.5s (15.3m) | 1218.5s (20.3m) | 961.4s (16.0m) | 61.5% |
| `between_cycle_gap` | 0.0s (0.0m) | 1810.2s (30.2m) | 327.2s (5.5m) | 0.0% |
| `merge_tail` | 25.0s (0.4m) | 27.0s (0.5m) | 21.4s (0.4m) | 1.7% |
| `unattributed` | 0.0s (0.0m) | 0.0s (0.0m) | 0.0s (0.0m) | 0.0% |

Identity: all_ok=`true`, max |delta| = 0.000s, tolerance = 2.0s.

## 4. Diagnostic overlays (may overlap; never summed)

| overlay | p50 | p95 | total |
|---|---:|---:|---:|
| `review_wait` | UNKNOWN | UNKNOWN | UNKNOWN |
| `ci_coverage_union` | 1362.0s (22.7m) | 2201.8s (36.7m) | 1462.7s (24.4m) |
| `incident_overlay` | 0.0s (0.0m) | 4090.0s (68.2m) | 852.6s (14.2m) |
| `author_after_ci` | 0.0s (0.0m) | 1874.2s (31.2m) | 344.2s (5.7m) |

`review_wait` is advisory=true under the 0-approval ruleset; it is not a blocking segment.

## 5. Incidents

| class | count |
|---|---:|
| `unknown` | 702 |
| `merged_normal` | 102 |
| `venue_red` | 13 |
| `dequeued_failed_checks` | 5 |
| `human_idle` | 4 |
| `red_retry` | 1 |

## 6. Top p95 contributors

| PR | TOT | primary incident | pre_ci | pr_head_ci | queue_wait | mg_ci | merge_tail |
|---:|---:|---|---:|---:|---:|---:|---:|
| #910 | 42208.0s (703.5m) | `human_idle` | 6.0s (0.1m) | 338.0s (5.6m) | 6.0s (0.1m) | 692.0s (11.5m) | 22.0s (0.4m) |
| #827 | 18193.0s (303.2m) | `venue_red` | 4.0s (0.1m) | 583.0s (9.7m) | 90.0s (1.5m) | 3134.0s (52.2m) | 26.0s (0.4m) |
| #838 | 13235.0s (220.6m) | `human_idle` | 3.0s (0.1m) | 2232.0s (37.2m) | 55.0s (0.9m) | 2170.0s (36.2m) | 25.0s (0.4m) |
| #828 | 9474.0s (157.9m) | `venue_red` | 4.0s (0.1m) | 563.0s (9.4m) | 98.0s (1.6m) | 4454.0s (74.2m) | 25.0s (0.4m) |
| #919 | 7827.0s (130.4m) | `venue_red` | 3.0s (0.1m) | 482.0s (8.0m) | 37.0s (0.6m) | 1292.0s (21.5m) | 18.0s (0.3m) |
| #862 | 7080.0s (118.0m) | `human_idle` | 3.0s (0.1m) | 1453.0s (24.2m) | 18.0s (0.3m) | 1016.0s (16.9m) | 24.0s (0.4m) |

## 7. Counterfactual (cap each segment at cohort p50)

| segment | cap | p95 before | p95 after | delta |
|---|---:|---:|---:|---:|
| `between_cycle_gap` | 0.0s (0.0m) | 7005.8s (116.8m) | 3454.5s (57.6m) | -3551.2s (-59.2m) |
| `pr_head_idle` | 0.0s (0.0m) | 7005.8s (116.8m) | 5617.8s (93.6m) | -1388.0s (-23.1m) |
| `pre_enqueue_gap` | 15.0s (0.2m) | 7005.8s (116.8m) | 6078.2s (101.3m) | -927.5s (-15.5m) |
| `mg_ci` | 917.5s (15.3m) | 7005.8s (116.8m) | 6404.8s (106.7m) | -601.0s (-10.0m) |
| `pr_head_ci` | 377.5s (6.3m) | 7005.8s (116.8m) | 6588.4s (109.8m) | -417.4s (-7.0m) |
| `pre_ci` | 4.0s (0.1m) | 7005.8s (116.8m) | 6869.5s (114.5m) | -136.2s (-2.3m) |
| `queue_wait` | 18.0s (0.3m) | 7005.8s (116.8m) | 7005.2s (116.8m) | -0.5s (-0.0m) |
| `merge_tail` | 25.0s (0.4m) | 7005.8s (116.8m) | 7005.8s (116.8m) | 0.0s (0.0m) |
| `unattributed` | 0.0s (0.0m) | 7005.8s (116.8m) | 7005.8s (116.8m) | 0.0s (0.0m) |

Counterfactual is a sensitivity analysis, not a causal claim.

## 8. Cost

`actual_billed_cost.per_pr = UNKNOWN` — GitHub billing usage API exposes only repo x SKU x day aggregates; no per-run/per-PR billed cost.

| shared merge_group run | members | job minutes | estimate USD | basis |
|---|---|---:|---:|---|
| 39135473456 | 927 | 0.7 | 0.0039 | estimate |
| 39135473445 | 927 | 0.2 | 0.0015 | estimate |
| 39135473412 | 927 | 1.8 | 0.0109 | estimate |
| 39135473401 | 927 | 10.9 | 0.0657 | estimate |
| 39135473271 | 927 | 1.7 | 0.01 | estimate |
| 39134186961 | 926 | 11.5 | 0.069 | estimate |
| 39134186756 | 926 | 0.3 | 0.0016 | estimate |
| 39134186700 | 926 | 0.8 | 0.0045 | estimate |
| 39134186699 | 926 | 1.8 | 0.0105 | estimate |
| 39134186676 | 926 | 1.2 | 0.0072 | estimate |
| 39132586441 | 925 | 20.3 | 0.1216 | estimate |
| 39132586409 | 925 | 0.6 | 0.0038 | estimate |
| 39132586402 | 925 | 1.8 | 0.0108 | estimate |
| 39132586392 | 925 | 0.2 | 0.0014 | estimate |
| 39132586388 | 925 | 2.1 | 0.0124 | estimate |
| 39130593997 | 924 | 20.0 | 0.12 | estimate |
| 39130593864 | 924 | 1.9 | 0.0113 | estimate |
| 39130593819 | 924 | 1.7 | 0.0103 | estimate |
| 39130593802 | 924 | 0.6 | 0.0037 | estimate |
| 39130593796 | 924 | 0.2 | 0.0015 | estimate |

## 9. Judgments (independent)

### 9.1 SLO-MG — recurring merge-group verification cost

- target p95: 480s; latest-attempt p50/p95: 907.0s (15.1m) / 1143.0s (19.1m)
- status: `recurring_cost_dominant`; selected lever: recurring MG job: attest / admission-check
- top jobs by total duration: attest / admission-check (56280s), attest / build-base-artifacts (38094s), attest / go-critical-lane (0) (23477s), gateway / ci-bootstrap (23106s), attest / go-critical-lane (1) (18249s)

### 9.2 SLO-PR — data-complete TOT p95 contributor

- TOT full cohort p50/p95: 1497.0s (24.9m) / 20574.0s (342.9m)
- TOT data-complete p50/p95: 1491.0s (24.9m) / 7005.8s (116.8m)
- normal-path TOT p50/p95: 1410.0s (23.5m) / 2455.5s (40.9m)
- top segment by p95: `between_cycle_gap` (1810.2s (30.2m))
- best counterfactual: cap `between_cycle_gap` at 0.0s (0.0m) → p95 delta -3551.2s (-59.2m)

### 9.3 Operational executability

- status: `executable`
- queue/incident robustness workstream
- no workflow trust-surface change required for observation

## 10. UNKNOWN / caveats

- TOT is created_at -> merged_at; it includes author/pre-CI time by definition.
- TOT(commit-date) uses the last commit committer date and is an ESTIMATE, not push time.
- TOT(push) is unavailable for arbitrary merged PRs: the events feed is limited to 300 events / 30 days and GraphQL has no ordinary-push timeline item.
- review_wait is advisory under the 0-approval ruleset and is never summed into TOT.
- diagnostic_overlays may overlap wall_partition and are not additive.
- Queue internal state durations are not preserved by GitHub; only bounds are reported.
- Dequeue reason is an opaque GraphQL string; REST timeline omits it.
- Cost is an estimate or UNKNOWN; no per-PR billed cost exists.
- PRs with no CI/queue events are data_complete=false and recorded as unknown/unattributed; full-cohort TOT includes them, data-complete TOT is the lever-selection basis.
- Actions runs/checks/statuses retention defaults to 90 days from 2026-10-01; older data may be unavailable.
