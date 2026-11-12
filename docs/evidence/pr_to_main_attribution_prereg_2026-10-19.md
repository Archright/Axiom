# PR-to-main Latency Attribution 사전등록 — 측정 계약 v2 (2026-10-19)

> **종류**: 사전등록 문서 (pre-registration). 도구 `tools/ci/pr_latency_attribution.py`의 첫 full-window 측정 **이전에** cohort·window·segment·incident taxonomy·cost contract·decision rule을 전부 고정한다. 관측을 본 뒤의 기준 변경은 어떤 형태로도 허용하지 않으며, 변경은 새 날짜의 사전등록 문서로만 한다.
> **규율 원천**: `docs/evidence/e3_measurement_contract_2026-10-11.md` §7.1(wall = `updated_at − run_started_at`, `/timing` 금지, API second granularity) · `docs/evidence/merge_latency_decision_prereg_2026-10-13.md` §5.2(TOT/S1/S2, TOT(push) 민감도, 재진입은 상태 전이로만 기록) · `docs/evidence/go_matrix_parallelization_prereg_2026-10-16.md` §4.1(D1–D4, Hyndman–Fan R-7) · `data/ci_optimization/p95_attribution_2026-10-16.json`(`RECURRING_COST_DOMINANT`, `INCIDENT_TAIL_OWNS_ABOVE_1H`, `sloReachableWithRegisteredLevers: false`).
> **권위**: 본 문서와 도구는 **Reporter**다 — GitHub merge authority(ruleset·required checks·merge queue·MERGE commit)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 도구 출력은 admission 판정 입력이 아니며, 어떤 gate도 이 값을 소비하지 않는다. 도구는 read-only GET/GraphQL query만 수행하고 `gh` 네이티브 인증만 사용한다(AGENTS.md §2.4).
> **소유자 승인**: 2026-10-19 사용자 전면 허가(구현·검증·PR·merge queue·canonical 실행·acceptance).

---

## 1. 목적 / 범위 / 비목적

### 1.1 목적

PR 생성부터 main 착지까지의 시간을 **겹침 없이 분해**하고, (a) merge-group 검증의 반복 비용, (b) end-to-end p95 기여 구간, (c) 다음 lever의 운영 실행 가능성을 **별도로** 판정한다. 성공 지표는 full-cohort `SLO-PR` p95이며, incident-excluded/clean cohort는 진단용이다.

### 1.2 범위

- Archright/Axiom의 merged PR cohort(전체 window pagination) + closed-unmerged incident census.
- PR-head CI, merge-group CI, queue dwell, dequeue/rearm, merge tail, author/pre-CI, review overlay.
- 공유 merge-group run의 비용을 1회 기록하고, PR별 값은 명시적 추정치로만 제공.
- `SLO-MG`(기존)와 `SLO-PR`(신규 policy metric) 병기.

### 1.3 비목적

- workflow·ruleset·required-check·trustSurface 변경.
- larger runner·s1a split·merge queue 파라미터 변경(다음 slice 후보).
- human review 정책 변경.
- queue 내부 상태 전이(AWAITING_CHECKS/MATCHING/VERIFYING)의 역사 복원 — 플랫폼이 보존하지 않는다.
- `actions/runs/{id}/timing` 사용 — E3 §7.1이 금지한다.
- PR별 실제 청구 비용의 확정 — GitHub는 per-run/per-PR billed cost를 제공하지 않는다.

---

## 2. 두 측정 계층

### 2.1 `wall_partition` — 비겹침, 합산 검증

`[createdAt, mergedAt]` 전체를 겹침 없이 덮는다. **`sum(partition) + unattributed == TOT` (±2초)** 를 기계 검증한다. half-open interval `[start, end)`을 사용하고, interval normalization 후 이중 계산하지 않는다.

| segment | 정의 |
|---|---|
| `pre_ci` | createdAt → first PR-head CI start (PR-head CI가 없으면 first `added_to_merge_queue`) |
| `pr_head_ci` | PR-head required workflow run interval의 union (모든 commit SHA·attempt) |
| `pr_head_idle` | first→last PR-head CI 사이의 비-CI gap |
| `pre_enqueue_gap` | last PR-head CI end → first `added_to_merge_queue` |
| `queue_wait` | `added_to_merge_queue` → first merge_group run start (cycle별) |
| `mg_ci` | merge_group run interval의 union (cycle별) |
| `between_cycle_gap` | MG CI end → next `added_to_merge_queue` (dequeue/rearm recovery; author fix time 포함 가능) |
| `merge_tail` | last MG CI end → mergedAt |
| `unattributed` | 남은 시간 + `unknown_reason` |

규칙:
- 모든 interval은 `[createdAt, mergedAt]`로 clip한다.
- timestamp 누락·역전 시 추정하지 않는다. 해당 구간은 `unattributed`에 넣고 `unknown_reason`을 기록한다.
- `pr_head_ci`/`mg_ci`는 **union**이며, 동시에 실행된 job/run을 중복 계산하지 않는다.
- `queue_wait`는 queue dwell의 일부이고, queue 내부 상태 전이 시간은 `mg_ci`/`queue_wait`로 설명되지 않는 잔여분으로만 남는다.
- **data completeness**: `data_complete=true`는 (i) PR-head CI run이 존재하고, (ii) queue-era PR이면 merge_group `admission-gate` run이 존재할 때만 성립한다. 그렇지 않은 PR은 `data_complete=false`, `unknown_reason`(no_ci_or_queue_events / pr_head_ci_run_missing / admission_gate_run_missing)으로 기록하고 `unattributed` 처리한다. full-cohort TOT는 audit용으로 병기하되, **lever 선택과 `SLO-PR` 판정은 data-complete cohort**를 기준으로 한다.

### 2.2 `diagnostic_overlays` — 겹침 가능, 합산 금지

아래 값은 다른 구간과 겹칠 수 있으므로 **TOT 합산에 포함하지 않는다.** 각 overlay는 `overlap_possible=true`를 가진다.

| overlay | 정의 | 주의 |
|---|---|---|
| `review_wait` | ready-for-review/first CI start → first review submitted/approval | 0-approval ruleset에서는 `advisory=true`, `blocking=false` |
| `ci_coverage_union` | PR lifetime 전체의 모든 CI run interval union | partition의 CI와 별도 |
| `incident_overlay` | incident로 분류된 interval | taxonomy와 1:1 |
| `author_after_ci` | CI end → next commit date | `committedDate` 기반이면 `estimate=true` |

---

## 3. Metric definitions

- `TOT` = PR `createdAt` → `mergedAt` (primary).
- `TOT(commit-date)` = last PR commit `committer.date` → `mergedAt`. **ESTIMATE**이며 push 시각이 아니다. rebase/amend로 실제 push와 어긋날 수 있다. `push_time_basis="committed_date"`.
- `TOT(push)` = 신뢰 가능한 push timestamp가 있을 때만 산출한다. REST events feed의 `PushEvent.created_at`은 **최대 300 events / 30일**이라 90일 cohort에 사용할 수 없다. GraphQL에는 ordinary push timeline item이 없고 `HeadRefForcePushedEvent`만 있다. 따라서 기본값은 `null`, `push_time_basis="unknown"`; force-push는 `HeadRefForcePushedEvent.createdAt`로 보정하고 `push_time_basis="force_push_event"`로 표기한다.
- `TOT(ready)` = `ReadyForReviewEvent.createdAt`(없으면 first commit) → `mergedAt`.
- `SLO-MG`는 세 값을 **분리**한다:
  - `latest_attempt_wall` = run `updated_at − run_started_at` (기존 E3 §7.1 정의; `run_started_at`은 rerun 시 reset됨).
  - `attempt_wall` = `/runs/{id}/attempts/{n}/jobs`의 job interval union (attempt-scoped).
  - `total_elapsed_with_retries` = attempt 1 `created_at` → final attempt `updated_at` (attempts 1..`run_attempt` 순회).
  - 모든 값에 `run_attempt`를 병기한다.
- `SLO-PR` = `TOT` p50/p95 (신규 policy metric). target은 baseline 관측 후 architect가 선언하며, 이 문서는 target을 선언하지 않는다.
- timestamp는 API second granularity(±1초). P95는 Hyndman–Fan R-7.

---

## 4. Cohort

- window: `[since, until]` (inclusive). full-window pagination.
- 수집: REST `GET /repos/{owner}/{repo}/pulls?state=closed&sort=updated&direction=desc&per_page=100&page=N`.
  - `merged_at`이 window 안인 PR = merged cohort (primary).
  - `closed_at`이 window 안이고 `merged_at=null`인 PR = closed-unmerged incident census.
  - **정렬 주의**: REST pulls는 `updated`/`created` 정렬이며 `merged_at` 정렬이 아니다. page의 최소 timestamp가 `since`보다 확실히 이전인 page를 만난 뒤 **한 page 더** 읽어 margin을 확보한다.
  - search API는 최대 1,000 results라 cohort의 단독 소스로 사용할 수 없다.
  - GraphQL pagination은 `first ≤ 100`; `hasNextPage`/`endCursor`를 사용한다.
- `cohort_complete=true`는 다음을 모두 만족할 때만:
  1. closed PR enumeration이 소진되었고(empty/short page),
  2. `--max-prs` safety cap에 도달하지 않았으며,
  3. page safety cap에 도달하지 않았다.
  그렇지 않으면 `cohort_complete=false` + `partial_reason`.
- `sample_sufficient=true`는 **data-complete** n ≥ 60일 때만. 미달이면 p95 기반 lever 선택을 `limited`로 표시한다.
- `data_complete`/`data_incomplete` 수를 공개한다. data-incomplete는 `unknown_reason`과 함께 `unknown`으로 기록하며, full-cohort p95는 audit용으로만 병기한다.
- censored/unmerged는 `M_RIGHT_CENSORED`/`closed_unmerged`로 기록하되 latency p95에는 불가산. 분모와 censored 수를 공개한다.
- 어떤 PR도 조용히 drop하지 않는다. 실패·누락은 `unknowns[]`에 기록한다.

### 4.1 Actions run enumeration — undocumented caps (2026-10-20 verification)

- `GET /repos/{owner}/{repo}/actions/runs`의 paginated retrieval은 **1,000건에서 멈춘다**(공식 문서에 미기재; 실측: `created>=2026-07-21` 90일 query의 `total_count=2500`, `--paginate` 반환 1,000, page 11은 `200` + empty).
- `created`-filtered range의 `total_count`는 **2,500에서 cap**된다(실측). 따라서 slice의 `total_count`가 2,500이거나 10 page를 채우면 더 작은 slice로 재분할해야 한다.
- 도구는 run enumeration을 **일 단위 `created=start..end` slice**로 수행하고, slice의 `total_count > returned`이면 12시간/6시간으로 **재귀 분할**한다. run id로 dedupe한다.
- `data_complete`는 PR-head CI run + (queue-era이면) merge_group `admission-gate` run이 모두 있어야 true다. 아니면 `outside_run_history` / `no_run_for_head_sha` / `pr_head_ci_run_missing` / `admission_gate_run_missing` 중 하나로 기록한다.
- `Commit.pushedDate`는 deprecated/null이고 ordinary push timeline item이 없으므로 `TOT(push)`는 산출하지 않는다(`TOT(commit-date)` estimate/UNKNOWN).

---

## 5. Incident taxonomy (closed set)

`merged_normal`, `dequeued_failed_checks`, `dequeued_invalidated`, `stale_base`, `venue_red`, `review_blocked`, `runner_infra`, `red_retry`, `human_idle`, `closed_unmerged`, `unknown`.

근거:
- Dequeue reason: GraphQL `RemovedFromMergeQueueEvent.reason`만 사용한다. REST issue timeline의 `removed_from_merge_queue`에는 reason이 없다. reason은 공식 문서화된 enum이 아니므로 **opaque string**으로 취급하고, null/미상은 `reason_unavailable`.
- `venue_red`: removal 직전에 실패한 merge_group `admission-gate` run이 존재. run id·conclusion·annotation을 기록.
- `stale_base`: `BaseRefChangedEvent`/`beforeCommit`/base SHA 이동. reason과 ordering으로만 추론하고, 불확실하면 `unknown`.
- `red_retry`: `run_attempt > 1` 또는 failed required check 후 rerun.
- `human_idle`: 장시간(기본 30분) CI/queue/review event가 없는 구간. #910 유형.
- `review_blocked`: `CHANGES_REQUESTED`/required review 미충족. 0-approval ruleset에서는 발생하지 않음.
- `runner_infra`: runner failure/timeout/0-step failure.
- `unknown`: 근거 없음. 추측 금지.

복수 class가 가능하면 `all_classes`에 모두 기록하고, primary는 가장 긴 incident interval로 정한다.

---

## 6. Cost contract

- `shared_ci_run`: run_id, event, head_branch, group_members(`gh-readonly-queue/<base>/pr-N-...` 파싱), runner labels, job minutes를 **run 단위로 한 번만** 기록한다.
- `actual_billed_cost`: `GET /orgs/{org}/settings/billing/usage?year=YYYY&month=M`의 **repo×SKU×day aggregate**만 존재한다. per-run/per-PR actual은 `UNKNOWN`. billing aggregate는 `billing_basis="org_billing_usage_aggregate"`로 별도 보고한다.
- `pr_cost_estimate`: job minutes × SKU rate의 추정치. 공유 MG run은 group members에 **equal split**(명시적 allocation rule)하고 `estimate=true`. group 미상이면 `UNKNOWN`.
- `cost_basis ∈ {measured_free, estimate, unknown}`:
  - `measured_free`는 billable이 실제로 0으로 측정된 경우(예: public repo)에만.
  - included minutes/discount로 `netAmount=0`인 경우는 `included_minutes`로 표기하며 `measured_free`가 아니다.
  - `UNKNOWN`을 0으로 기록하지 않는다.
- `actions/runs/{id}/timing`은 사용하지 않는다(E3 §7.1 계약). job `started_at`/`completed_at`을 사용한다.
- rate reference(공식): Actions Linux $0.006/min, Linux ARM $0.005/min, Windows $0.010/min, macOS $0.062/min; GHEC included 50,000 min/month. rate가 불명한 runner는 `UNKNOWN`.

---

## 7. Retention / API limits

- 2026-10-01부터 checks·workflow runs·commit statuses의 기본 retention은 **90일**이다. public repo는 1–90일, private/internal은 1–400일 설정 가능. **설정 변경은 prospective only**이며 과거 데이터에 소급되지 않는다.
- 90일 window는 retention 경계에 닿는다. 400일 상향은 owner 승인 시 향후 window 보존 수단으로만 사용한다.
- REST core 5,000 req/h, ≤100 concurrent, ≤900 pts/min; GraphQL 5,000 pts/h, ≤2,000 pts/min. Search는 1,000 results/30 req/min.
- raw API response는 `--cache-dir`에 캐시해 재실행 비용을 줄인다. cache는 증거가 아니다(J3).

---

## 8. 세 가지 판정 (독립)

1. `slo_mg`: merge-group 검증의 **반복 비용**을 어느 구간에서 줄일 수 있는가? `mg_ci` p50/p95, GO/lane, bootstrap, non-GO tail을 순위화한다. 기존 SLO(p95 ≤ 480s) 대비 위치를 명시한다.
2. `slo_pr`: full-cohort `TOT` p95에 어떤 segment가 가장 크게 기여하는가? top 5% PR의 partition과 counterfactual(해당 segment를 cohort p50으로 cap했을 때 p95 변화)로 판정한다.
3. `operational_executability`: 선택한 다음 lever를 기존 신뢰 계약·정책 아래에서 실행할 수 있는가? authority(누가 승인/실행), budget, required gates, epoch cutover 필요 여부를 `executable`/`requires_policy`/`requires_budget`/`blocked`/`unknown`으로 판정한다.

세 판정이 서로 다른 lever를 선택해도 오류가 아니다. 한 axis의 개선을 다른 axis의 성공으로 주장하지 않는다.

---

## 9. Decision rule

- **성공 지표**: full-cohort `SLO-PR` p95. incident-excluded/clean cohort는 diagnostic only.
- **Axis A (MG recurring cost)**: `mg_ci`가 지배적이면 GO/lane/bootstrap/non-GO tail 중 p95 기여가 가장 큰 레버를 선택.
- **Axis B (end-to-end tail)**: incident overlay가 `TOT` p95의 >1h 꼬리를 지배하면 dequeue/rearm/stale-base workstream을 선택.
- **Human/author wait**: `pre_ci`/`author_after_ci`/`review_wait`가 크면 review/author workflow 개선(정책 결정 필요). human time은 제거하지 않고 별도 표시한다.
- `cohort_complete=false` 또는 `sample_sufficient=false`이면 p95 기반 lever 선택을 `limited`로 표시하고, full-cohort 성공을 주장하지 않는다.
- cost가 `UNKNOWN`이면 비용 절감을 주장하지 않는다.

---

## 10. Acceptance (canonical)

- 도구: `tools/ci/pr_latency_attribution.py` — stdlib + `gh`, GET-only, no mutation, no polling, no `/timing`.
- canonical outputs:
  - `data/ci_optimization/pr_to_main_attribution_2026-10-19.json`
  - `docs/evidence/pr_to_main_attribution_2026-10-19.md`
  - raw JSONL: `data/ci_optimization/pr_to_main_attribution_2026-10-19.prs.jsonl`(또는 임시 경로; canonical acceptance는 JSON/MD).
- PR1(tool + 본 문서) → required checks(`admission-check`, `bsec-integrity`) → merge queue → canonical main에서 도구 존재 확인.
- canonical run → PR 951/862/895 교차검증 → partition sum/TOT ±2s, overlay 비합산, GraphQL dequeue reason, cohort completeness, UNKNOWN/cost 공개.
- PR2(JSON + evidence MD + decision memo) → merge queue → main에서 `git show` 확인.
- 세 판정(`slo_mg`, `slo_pr`, `operational_executability`)이 기계 판독 가능한 필드로 존재.

---

## 11. Limitations / UNKNOWN

- **Push timestamp**: 임의 merged PR의 실제 push 시각은 90일 cohort에서 신뢰 가능하게 얻을 수 없다. `TOT(commit-date)`는 ESTIMATE다.
- **Queue internal state**: AWAITING_CHECKS/MATCHING/VERIFYING의 historical duration은 플랫폼에 없다. `queue_dwell − queue_wait − mg_ci`로 bound만 보고한다.
- **Group composition**: surviving MG run의 `head_branch` 토큰으로만 복원한다. never-built group은 흔적이 없을 수 있다.
- **Human review**: event는 있으나 "reviewer 대기 vs author 대기"의 상태 머신은 없다. 0-approval ruleset에서 review wait는 advisory다.
- **Cost**: actual per-PR billed cost는 없다. estimate/UNKNOWN만 가능하다.
- **Retention**: 90일 이전 데이터는 소실될 수 있다. 400일 상향은 prospective only.
- **Incident reason**: dequeue reason은 opaque string이며 공식 enum이 아니다. 미상은 `unknown`.

---

## 12. Amendments / rollback

- 기준 변경은 새 날짜의 사전등록 문서로만 한다. 본 문서의 body는 append-only로 보존한다.
- 도구가 admission 판정에 연결되거나 CI generation을 변경하면 AGENTS.md §2.5 CI Epoch Cutover가 재발동한다. 현재 도구는 Reporter-only이므로 해당하지 않는다.
- 보고서가 잘못된 것으로 판명되면 canonical report를 revert하고, `unknowns[]`/`caveats[]`에 사유를 기록한 새 날짜 보고서로 대체한다.
