# PR-to-main Latency Attribution — 2026-10-20

> **권위**: Reporter only. GitHub merge authority(ruleset·required checks·merge queue·MERGE)를 대체하지 않는다. 이 보고서는 admission 판정 입력이 아니며 어떤 gate도 소비하지 않는다.
> **계약**: `docs/evidence/pr_to_main_attribution_prereg_2026-10-19.md` (measurement contract v2).

## 1. Cohort

| 항목 | 값 |
|---|---|
| repo | `Archright/Axiom` |
| window | 2026-10-05T15:00:00Z → 2026-10-19T15:00:00Z |
| closed PRs collected | 952 |
| merged (primary) | 423 |
| data-complete (CI/queue evidence) | 419 |
| data-incomplete (UNKNOWN attribution) | 4 |
| closed-unmerged (census) | 41 |
| cohort_complete | true |
| sample_sufficient (n>=60) | true |

## 2. Metrics

| metric | p50 | p95 | n |
|---|---:|---:|---:|
| TOT full cohort | 1562.0s (26.0m) | 13253.9s (220.9m) | 423 |
| TOT data-complete cohort | 1556.0s (25.9m) | 13295.4s (221.6m) | 419 |
| TOT(commit-date, ESTIMATE) | 1592.0s (26.5m) | 5945.7s (99.1m) | 423 |
| TOT(ready→merged) | 1562.0s (26.0m) | 13253.9s (220.9m) | 423 |
| SLO-MG latest-attempt wall | 799.0s (13.3m) | 1118.7s (18.6m) | 564 |

Full-cohort TOT includes data-incomplete PRs (no CI/queue events); lever selection uses the data-complete cohort.

`TOT(push)` is unavailable: `events feed limited to 300 events / 30 days; GraphQL has no ordinary-push timeline item; Commit.pushedDate is null`.

## 3. Wall partition (data-complete cohort; non-overlapping; sum == TOT)

| segment | p50 | p95 | total | share of data-complete TOT p50 |
|---|---:|---:|---:|---:|
| `pre_ci` | 4.0s (0.1m) | 891.9s (14.9m) | 271.4s (4.5m) | 0.3% |
| `pr_head_ci` | 434.0s (7.2m) | 982.1s (16.4m) | 505.8s (8.4m) | 27.9% |
| `pr_head_idle` | 0.0s (0.0m) | 971.1s (16.2m) | 236.5s (3.9m) | 0.0% |
| `pre_enqueue_gap` | 26.0s (0.4m) | 335.3s (5.6m) | 400.5s (6.7m) | 1.7% |
| `queue_wait` | 18.0s (0.3m) | 921.8s (15.4m) | 135.4s (2.3m) | 1.2% |
| `mg_ci` | 853.0s (14.2m) | 2847.3s (47.5m) | 1000.9s (16.7m) | 54.8% |
| `between_cycle_gap` | 0.0s (0.0m) | 5743.8s (95.7m) | 1277.4s (21.3m) | 0.0% |
| `merge_tail` | 25.0s (0.4m) | 27.1s (0.5m) | 44.1s (0.7m) | 1.6% |
| `unattributed` | 0.0s (0.0m) | 0.0s (0.0m) | 0.0s (0.0m) | 0.0% |

Identity: all_ok=`true`, max |delta| = 0.000s, tolerance = 2.0s.

## 4. Diagnostic overlays (may overlap; never summed)

| overlay | p50 | p95 | total |
|---|---:|---:|---:|
| `review_wait` | UNKNOWN | UNKNOWN | UNKNOWN |
| `ci_coverage_union` | 1309.0s (21.8m) | 4096.6s (68.3m) | 1558.7s (26.0m) |
| `incident_overlay` | 0.0s (0.0m) | 9236.7s (153.9m) | 2044.7s (34.1m) |
| `author_after_ci` | 0.0s (0.0m) | 3044.4s (50.7m) | 484.2s (8.1m) |

`review_wait` is advisory=true under the 0-approval ruleset; it is not a blocking segment.

## 5. Incidents

| class | count | TOT sum | p50 | p95 | share of data-complete TOT |
|---|---:|---:|---:|---:|---:|
| `merged_normal` | 336 | 1523.6s (25.4m) | 1382.5s (23.0m) | 2913.8s (48.6m) | 31.6% |
| `venue_red` | 46 | 16118.3s (268.6m) | 9516.0s (158.6m) | 52437.8s (874.0m) | 45.7% |
| `human_idle` | 29 | 18558.1s (309.3m) | 10125.0s (168.8m) | 57390.4s (956.5m) | 28.6% |
| `dequeued_merge_conflict` | 10 | 13210.0s (220.2m) | 7849.0s (130.8m) | 42913.7s (715.2m) | 8.1% |
| `red_retry` | 9 | 4914.8s (81.9m) | 2671.0s (44.5m) | 13520.4s (225.3m) | 2.7% |
| `dequeued_failed_checks` | 7 | 34342.3s (572.4m) | 33849.0s (564.1m) | 51230.3s (853.8m) | 14.8% |
| `dequeued_manual` | 6 | 29126.7s (485.4m) | 8015.0s (133.6m) | 85025.8s (1417.1m) | 10.8% |
| `dequeued_other` | 1 | 31799.0s (530.0m) | 31799.0s (530.0m) | 31799.0s (530.0m) | 2.0% |

`mean` is the per-incident mean TOT; the share column is the sum of affected data-complete PR TOT over the cohort TOT.

## 6. Top p95 contributors

| PR | TOT | primary incident | pre_ci | pr_head_ci | queue_wait | mg_ci | merge_tail |
|---:|---:|---|---:|---:|---:|---:|---:|
| #627 | 93876.0s (1564.6m) | `venue_red` | 8407.0s (140.1m) | 402.0s (6.7m) | 1191.0s (19.9m) | 3602.0s (60.0m) | 23.0s (0.4m) |
| #650 | 67179.0s (1119.7m) | `venue_red` | 4.0s (0.1m) | 364.0s (6.1m) | 1898.0s (31.6m) | 4117.0s (68.6m) | 22.0s (0.4m) |
| #657 | 61186.0s (1019.8m) | `human_idle` | 5.0s (0.1m) | 243.0s (4.0m) | 1160.0s (19.3m) | 911.0s (15.2m) | 21.0s (0.3m) |
| #787 | 58475.0s (974.6m) | `venue_red` | 577.0s (9.6m) | 0.0s (0.0m) | 2312.0s (38.5m) | 6030.0s (100.5m) | 26.0s (0.4m) |
| #910 | 42208.0s (703.5m) | `human_idle` | 6.0s (0.1m) | 338.0s (5.6m) | 6.0s (0.1m) | 692.0s (11.5m) | 22.0s (0.4m) |
| #793 | 34326.0s (572.1m) | `dequeued_failed_checks` | 4.0s (0.1m) | 546.0s (9.1m) | 1712.0s (28.5m) | 4739.0s (79.0m) | 24.0s (0.4m) |
| #791 | 33946.0s (565.8m) | `dequeued_failed_checks` | 4.0s (0.1m) | 546.0s (9.1m) | 1123.0s (18.7m) | 3853.0s (64.2m) | 24.0s (0.4m) |
| #786 | 33849.0s (564.1m) | `venue_red` | 4.0s (0.1m) | 361.0s (6.0m) | 1435.0s (23.9m) | 4696.0s (78.3m) | 27.0s (0.5m) |
| #785 | 33334.0s (555.6m) | `dequeued_failed_checks` | 3.0s (0.1m) | 331.0s (5.5m) | 1568.0s (26.1m) | 4745.0s (79.1m) | 25.0s (0.4m) |
| #806 | 31799.0s (530.0m) | `venue_red` | 3.0s (0.1m) | 602.0s (10.0m) | 1312.0s (21.9m) | 5336.0s (88.9m) | 26.0s (0.4m) |
| #788 | 30248.0s (504.1m) | `dequeued_failed_checks` | 104.0s (1.7m) | 501.0s (8.3m) | 2976.0s (49.6m) | 5377.0s (89.6m) | 27.0s (0.5m) |
| #730 | 30231.0s (503.9m) | `human_idle` | 4.0s (0.1m) | 347.0s (5.8m) | 18.0s (0.3m) | 944.0s (15.7m) | 26.0s (0.4m) |
| #812 | 29695.0s (494.9m) | `human_idle` | 13075.0s (217.9m) | 0.0s (0.0m) | 920.0s (15.3m) | 6961.0s (116.0m) | 24.0s (0.4m) |
| #654 | 26557.0s (442.6m) | `venue_red` | 2047.0s (34.1m) | 0.0s (0.0m) | 429.0s (7.2m) | 2510.0s (41.8m) | 15.0s (0.2m) |
| #626 | 25747.0s (429.1m) | `human_idle` | 8442.0s (140.7m) | 416.0s (6.9m) | 972.0s (16.2m) | 723.0s (12.1m) | 26.0s (0.4m) |
| #712 | 19529.0s (325.5m) | `human_idle` | 17888.0s (298.1m) | 329.0s (5.5m) | 349.0s (5.8m) | 930.0s (15.5m) | 24.0s (0.4m) |
| #810 | 18415.0s (306.9m) | `venue_red` | 3.0s (0.1m) | 546.0s (9.1m) | 48.0s (0.8m) | 3472.0s (57.9m) | 25.0s (0.4m) |
| #827 | 18193.0s (303.2m) | `venue_red` | 4.0s (0.1m) | 583.0s (9.7m) | 90.0s (1.5m) | 3134.0s (52.2m) | 26.0s (0.4m) |
| #624 | 16218.0s (270.3m) | `human_idle` | 2316.0s (38.6m) | 3317.0s (55.3m) | 54.0s (0.9m) | 1084.0s (18.1m) | 26.0s (0.4m) |
| #811 | 15904.0s (265.1m) | `venue_red` | 4.0s (0.1m) | 525.0s (8.8m) | 99.0s (1.6m) | 2440.0s (40.7m) | 27.0s (0.5m) |
| #661 | 13650.0s (227.5m) | `venue_red` | 463.0s (7.7m) | 0.0s (0.0m) | 36.0s (0.6m) | 2084.0s (34.7m) | 8454.0s (140.9m) |

## 7. Counterfactual (cap each segment at cohort p50)

| segment | cap | p95 before | p95 after | delta |
|---|---:|---:|---:|---:|
| `between_cycle_gap` | 0.0s (0.0m) | 13295.4s (221.6m) | 6843.5s (114.1m) | -6451.9s (-107.5m) |
| `mg_ci` | 853.0s (14.2m) | 13295.4s (221.6m) | 11968.1s (199.5m) | -1327.3s (-22.1m) |
| `pr_head_idle` | 0.0s (0.0m) | 13295.4s (221.6m) | 12404.5s (206.7m) | -890.9s (-14.8m) |
| `pre_enqueue_gap` | 26.0s (0.4m) | 13295.4s (221.6m) | 12404.5s (206.7m) | -890.9s (-14.8m) |
| `pre_ci` | 4.0s (0.1m) | 13295.4s (221.6m) | 12665.4s (211.1m) | -630.0s (-10.5m) |
| `merge_tail` | 25.0s (0.4m) | 13295.4s (221.6m) | 13236.9s (220.6m) | -58.5s (-1.0m) |
| `queue_wait` | 18.0s (0.3m) | 13295.4s (221.6m) | 13241.4s (220.7m) | -54.0s (-0.9m) |
| `pr_head_ci` | 434.0s (7.2m) | 13295.4s (221.6m) | 13263.9s (221.1m) | -31.5s (-0.5m) |
| `unattributed` | 0.0s (0.0m) | 13295.4s (221.6m) | 13295.4s (221.6m) | 0.0s (0.0m) |

Counterfactual is a sensitivity analysis, not a causal claim.

## 8. Cost

`actual_billed_cost.per_pr = UNKNOWN` — GitHub billing usage API exposes only repo x SKU x day aggregates; no per-run/per-PR billed cost.

| shared merge_group run | members | job minutes | estimate USD | basis |
|---|---|---:|---:|---|
| 39267490831 | 958 | 20.4 | 0.1221 | estimate |
| 39267490247 | 958 | 0.2 | 0.0013 | estimate |
| 39267490110 | 958 | 1.6 | 0.0099 | estimate |
| 39267489736 | 958 | 1.2 | 0.0075 | estimate |
| 39267489516 | 958 | 0.7 | 0.0044 | estimate |
| 39263167118 | 955 | 17.4 | 0.1043 | estimate |
| 39263166479 | 955 | 1.7 | 0.0102 | estimate |
| 39263166476 | 955 | 0.3 | 0.0017 | estimate |
| 39263166429 | 955 | 1.5 | 0.009 | estimate |
| 39263166406 | 955 | 0.8 | 0.005 | estimate |
| 39256715680 | 954 | 22.4 | 0.1342 | estimate |
| 39256715670 | 954 | 1.7 | 0.0103 | estimate |
| 39256715653 | 954 | 0.2 | 0.0015 | estimate |
| 39256715584 | 954 | 1.7 | 0.0104 | estimate |
| 39256715409 | 954 | 0.8 | 0.0045 | estimate |
| 39255745515 | 953 | 21.5 | 0.1288 | estimate |
| 39255745320 | 953 | 0.8 | 0.0046 | estimate |
| 39255745264 | 953 | 1.5 | 0.0088 | estimate |
| 39255745245 | 953 | 0.2 | 0.0015 | estimate |
| 39255745221 | 953 | 1.9 | 0.0113 | estimate |

## 9. Judgments (independent)

### 9.1 SLO-MG — recurring merge-group verification cost

- target p95: 480s; latest-attempt p50/p95: 799.0s (13.3m) / 1118.7s (18.6m)
- status: `recurring_cost_dominant`; selected lever: recurring MG job: attest / admission-check

| job | sum | n | mean | p50 | p95 |
|---|---:|---:|---:|---:|---:|
| `attest / admission-check` | 188672s | 564 | 334.5s (5.6m) | 280.5s (4.7m) | 661.7s (11.0m) |
| `attest / build-base-artifacts` | 123214s | 564 | 218.5s (3.6m) | 254.0s (4.2m) | 310.0s (5.2m) |
| `gateway / ci-bootstrap` | 69419s | 349 | 198.9s (3.3m) | 235.0s (3.9m) | 288.0s (4.8m) |
| `verdict / admission-check` | 38404s | 564 | 68.1s (1.1m) | 46.0s (0.8m) | 203.7s (3.4m) |
| `gateway / select` | 37169s | 557 | 66.7s (1.1m) | 60.0s (1.0m) | 103.0s (1.7m) |
| `attest / go-critical-lane (0)` | 33201s | 96 | 345.8s (5.8m) | 381.5s (6.4m) | 416.0s (6.9m) |
| `closure-deriver` | 32157s | 385 | 83.5s (1.4m) | 79.0s (1.3m) | 110.8s (1.8m) |
| `attest / go-critical-lane (1)` | 25843s | 96 | 269.2s (4.5m) | 299.5s (5.0m) | 324.2s (5.4m) |

### 9.2 SLO-PR — data-complete TOT p95 contributor

- TOT full cohort p50/p95: 1562.0s (26.0m) / 13253.9s (220.9m)
- TOT data-complete p50/p95: 1556.0s (25.9m) / 13295.4s (221.6m)
- normal-path TOT p50/p95: 1382.5s (23.0m) / 2913.8s (48.6m)
- top segment by p95: `between_cycle_gap` (5743.8s (95.7m))
- best counterfactual: cap `between_cycle_gap` at 0.0s (0.0m) → p95 delta -6451.9s (-107.5m)

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
