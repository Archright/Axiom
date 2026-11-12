# PR-to-main Attribution — Remaining Issues and Plan-Required Work (2026-10-20)

> **권위**: Reporter only. 본 문서는 GitHub merge authority(ruleset·required checks·merge queue·MERGE)를 대체하지 않는다. 어떤 admission gate도 이 문서를 소비하지 않는다.
> **계약**: `docs/evidence/pr_to_main_attribution_prereg_2026-10-19.md` (measurement contract v2 + run enumeration amendment).
> **데이터**: `data/ci_optimization/pr_to_main_attribution_2026-10-20.json` (2026-10-06 → 2026-10-20 **14-day operational window**). full 90-day audit는 `data/ci_optimization/pr_to_main_attribution_2026-10-19.json`에 보존한다.
> **방법**: 5개 병렬 read-only 분석 + Context7/공식 문서 + live GitHub API. 모든 mutation은 별도 명시가 없는 한 없음.

---

## 1. 계획 없이 해결한 것 (no-plan, deterministic)

### 1.0 왜 851건 전수가 아니라 14일 window인가

- 2026-10-19 보고서의 **716 data-incomplete는 대부분 1,000-run pagination cap bug의 산물**이었다. run history가 없어서가 아니라, 도구가 최신 1,000건만 보고 오래된 PR-head run을 놓친 것이다. 수정 후 14일 window(423 merged)에서 **419 data-complete / 4 incomplete**로 회복됐다.
- 운영 판단에 필요한 것은 **data-complete cohort**이며, 최근 incident(#817/#828/#838/#895/#910/#919)는 모두 10월이다.
- 30일 window는 744 PR을 GraphQL로 순회하다 5,000/h rate limit과 60초 retry sleep으로 1시간 timeout됐다. 이는 표본 부족이 아니라 **불필요한 PR 순회 비용**이다.
- 따라서 14일(2026-10-06→10-20)은 **최근 incident와 data-complete cohort를 포함하는 최소 결정론적 operational window**다. 90일 full audit는 fixed tool로 별도 재생성할 수 있지만, 운영 결정에는 필요하지 않다.
- **prefilter**: REST PR list의 `head.sha`가 run index에 없고 merge_group run도 없으면, GraphQL/timeline/jobs 호출을 생략하고 `created_at`/`merged_at`만으로 minimal `unknown` record를 만든다. audit cohort 수는 유지하면서 API 비용을 제거한다.

### 1.1 Actions runs 1,000건 pagination cap 제거

**문제**: `GET /repos/{owner}/{repo}/actions/runs`의 paginated retrieval은 **1,000건에서 멈춘다**(공식 문서 미기재; 실측). 90일 `created>=` query는 `total_count=2500`을 보고하지만 `--paginate`는 정확히 1,000건만 반환하고, page 11은 `200` + empty를 반환한다. 그 결과 PR #627(실제 run 3건) 같은 PR이 `pr_head_ci=[]`로 오분류됐다.

**수정**: run enumeration을 **일 단위 `created=start..end` slice**로 수행하고, slice의 `total_count > returned`이면 12시간/6시간으로 재귀 분할한다. run id로 dedupe한다. `total_count` 자체도 created-filtered range에서 2,500에서 cap되므로, 2,500 또는 10 page를 채우면 더 작은 slice로 분할한다.

**검증** (독립 에이전트):
- 2026-10-09 slice: API `total_count=338` (event=pull_request filter), returned 338, target run `37908813804` present, duplicates 0.
- PR #627/#7/#3: 모든 head SHA가 `index_runs(list_runs(...))["by_sha"]`에 인덱싱됨.
- 동일 window 2회 실행: sorted id list 동일 (determinism).
- 잔여 day-level deficit 0.
- 주의: `total_count`를 읽을 때 **`event=pull_request` filter를 반드시 포함**해야 한다. 필터 없이는 all-event count(예: Oct 9 = 811)가 나와 false deficit처럼 보인다.

**코드**: `tools/ci/pr_latency_attribution.py` — `GhClient.list_runs` date slicing + recursive halving.

### 1.2 Data-complete / unknown_reason 정밀화

- `data_complete=true`는 PR-head CI run + (queue-era PR이면) merge_group `admission-gate` run이 모두 있을 때만.
- `unknown_reason`:
  - `outside_run_history` — PR merged before the earliest available run
  - `no_run_for_head_sha` — run history exists but no run for the PR head
  - `pr_head_ci_run_missing` — MG evidence exists but PR-head CI missing
  - `admission_gate_run_missing` — queue events exist but no admission-gate run
- `cohort.run_history_start/end`를 보고서에 기록.
- full cohort p95는 audit-only; lever 선택과 SLO-PR 판정은 data-complete cohort 기준.

### 1.3 Dequeue taxonomy 정확화

기존 `dequeued_failed_checks`는 실제로 `merge_conflict`/`manual`을 포함하는 misnomer였다. 수정:
- `dequeued_failed_checks` — actual `failed_checks`
- `dequeued_merge_conflict` — `merge_conflict`
- `dequeued_manual` — `manual`
- `dequeued_invalidated` — `invalidated`
- `dequeued_other` — 그 외 opaque reason
- 중복 `RemovedFromMergeQueueEvent`(같은 timestamp+reason)는 dedupe; class interval은 union.
- `venue_red` evidence에 `NOT_ADMIT_*` **reason_code**를 기록(check-run annotations에서 추출). 2026-10-13→19 cohort에서 확인된 코드: `ROT_NEW_PIN` 6, `NO_CERT` 4, `ROT_ALLOWLIST` 1, `UNPARSED` 1.

### 1.4 Incident contribution 및 per-job percentiles

- `incidents.contribution`: class별 count, TOT sum/p50/p95, data-complete TOT 대비 share, affected PR list.
- `judgments.slo_mg.job_ranking`: job별 sum/count/mean/p50/p95.
- 2026-10-13→19 data-complete incident 10 PR이 전체 TOT의 **44.5%**를 차지; venue_red 5 PR이 27,715s, human_idle 3 PR이 52,769s(그중 #910 41,144s = 78%).

### 1.5 Platform facts (공식 문서 + live 검증)

| 사실 | 결론 |
|---|---|
| Actions retention | repo/org live `{"days":90,"maximum_allowed_days":90}`. private/internal의 문서상 1–400일은 **org/enterprise cap**에 종속; 90 초과는 enterprise-admin action이며 repo/org owner API로 불가. 2026-10-01부터 checks/runs/statuses 포함, **prospective only**. |
| `TOT(push)` | `Commit.pushedDate`는 **deprecated (removal 2023-07-01)**, 모든 commit에서 null. ordinary push timeline item 없음. Events feed ≤300/30일. **per-commit push timestamp API는 존재하지 않는다** → `TOT(commit-date)` estimate/UNKNOWN. |
| Per-PR billed cost | billing usage는 repo×SKU×day aggregate만; run/job/PR ID 없음. job minutes는 **job별로 분 올림**. per-PR actual cost API 없음 → estimate/UNKNOWN만. |
| Queue history | GraphQL add/remove event와 current `MergeQueueEntry`만; position/state transition history 없음. `merge_group.destroyed` webhook은 prospective. |
| Actions metrics | Usage/Performance metrics는 UI/CSV only; REST/GraphQL endpoint 없음; per-PR attribution 없음. |
| Required check semantics | **정정**: GitHub는 `success`/`skipped`/`neutral`을 성공으로 간주. **job-level skip은 required check를 통과**하고, **workflow-level skip(path/branch filter)만 pending으로 차단**한다. Axiom의 `acceptableConclusion: "success"`는 GitHub ruleset보다 **엄격한 정책**이지 플랫폼 강제가 아니다. |

### 1.6 Rearm 동작 (no-plan observation)

- `merge-queue-rearm`은 2026-10-14 이후 모든 dequeue에서 **2–6초 내 발화**했지만 **arm 성공 0회**. `GITHUB_TOKEN`으로 `enablePullRequestAutoMerge`가 불가능(Q14)해 모든 재진입은 manual `wintrover` act였다.
- 16개 removal→re-add gap 35,217s(9.8h)은 **100% human** (author push 8, same-head manual add 7, conflict force-push 1).
- condition 6이 `runs?event=merge_group&per_page=20` repo-wide라 #851의 admission run을 놓쳐 UNKNOWN → no-arm.
- `NOT_ADMIT_ROT_NEW_PIN`(#919)은 allowlist 밖이라 UNKNOWN → no-arm; manual re-entry는 green으로 merge됨(잘못된 negative).
- **하지 말 것**: `ROT_*`/`NO_CERT`를 TRANSIENT로 확대해 auto-arm하는 것 — deterministic admission-policy failure를 재실행하는 theater(§0.9).

### 1.7 CI 반복 비용 (no-plan observation)

- 14일 window: **2,674 shared MG runs, 12,811.7 job-min ≈ $76.87 estimate**.
- workflow share: admission-gate **9,913.4 min / 77.4%** (564 runs, mean 17.6 min), observer 1,748.6 min / 13.6% (452 runs), bsec 527.3 min / 4.1% (338), landing 454.3 min / 3.5% (660), probe 168.0 min / 1.3% (660).
- critical path: `build-base 230.9s → go-critical-lane-0 361.2s → attest admission-check 341.1s` ≈ mg_ci p50 917.5s.
- serial tail: mint-prepare 38.4s + mint-publish 49.8s + verdict 59.1s ≈ 147s.
- duplication: deriver 3중 컴파일(주로 off critical path), 8× nimble install(SL-09 미발화로 dormant), slice-engine verbatim copies, B checkout/toolchain ≥10 firing jobs, artifact churn.
- no-plan: CAS v4 reuse 이미 착지(REUSED 401–550s band), per-job percentiles/기여도 보고, SL-09 firing tracker.

---

## 2. 계획이 필요한 항목 — 왜 계획이 필요한가

아래 항목은 **코드 한 줄 수정으로 끝나지 않는다**. 공통 이유는 (a) 실행 경계/trust surface 변경, (b) 외부 authority(org/enterprise/budget), (c) 제품 계약/측정 의미 변경, (d) 플랫폼이 보존하지 않는 데이터의 신규 수집, (e) 되돌림·사전등록 없는 변경 금지다.

### 2.1 MG attest-chain / critical path 변경

대상: `build-base-artifacts → go-critical-lane → attest admission-check`의 needs/parallelism, toolchain handoff, deriver single-mint, mint/verdict tail fusion.

**왜 계획이 필요한가**:
- `admission-check.yml`은 `config/policy/merge_admission.json` trustSurface에 포함된다. 변경은 auto-merge deny 대상이며, org required workflow의 callee SHA pin과 ruleset `workflows` sha를 **원자적으로** 갱신해야 한다(§2.5 Atomic Binding Update).
- Gate A(B-built verifier, H data-only), GO-critical 4 tests, Judgment CAS, fail-closed semantics를 보존해야 한다. 단순 “jobs를 합친다”는 변경은 evidence identity/trust를 깨뜨릴 수 있다.
- 성능 판정은 **총 MG wall p50/p95 + cost**로 사전등록되어야 하며, 변화가 variance인지 개선인지 구분할 표본·중지 규칙이 필요하다.
- rollback은 frozen previous epoch + org pin 재회전을 포함해야 한다.

**계획에 반드시 포함**: baseline/target(총 MG wall, cost), 변경할 job/needs, trust invariant 보존 증명, pre-registration, local/targeted verification, short CI validation, canonical cutover, production acceptance, rollback reference.

### 2.2 s1a lane split (ContractRevision)

**왜 계획이 필요한가**:
- `tests/unit/test_s1a_lean_golden.nim`은 `JudgmentClosure` count-bound(17 accepts/14 probes, single flush)이며, DEBT#432/frozen Makefile surface/test contract가 얽혀 있다. split은 **contract revision**이지 mechanical change가 아니다.
- admission evidence semantics(무엇이 하나의 judgment unit인가)을 바꾸므로 architect approval + `docs/spec/test_judgment_cas_contract.md` 개정이 필요하다.
- workflow 변경은 §2.5 cutover + pin rotation을 동반한다.
- 기대효과는 median ~½ H-band이지 variance 감소가 아니다. pre-registered measurement가 필요하다.

### 2.3 Queue/rearm automation 변경

대상: condition 6 pagination, `NOT_ADMIT_ROT_NEW_PIN` classification amendment, arm credential(PAT/App), auto-arm-on-ready trigger.

**왜 계획이 필요한가**:
- `merge-queue-rearm.yml`은 live execution boundary다. 조건/retry budget/concurrency 변경은 CI 변경이며 coherent generation cutover가 필요하다.
- **arm credential**은 `GITHUB_TOKEN`으로 불가능하다. PAT/App secret 도입은 credential boundary·보안·rotation 정책 변경이며 operator/architect 결정이다.
- classification allowlist는 closed enumeration이며, in-place 확장은 금지된다(header의 amendment rule). `ROT_*`/`NO_CERT`를 auto-arm으로 확대하면 deterministic red venue를 재실행하는 theater다.
- auto-arm-on-ready는 **새 trigger surface**이므로 `§0.12` product contract가 먼저 필요하다.
- 성공 판정은 “자동 재진입률”이 아니라 **data-complete TOT p95 + incident rate + no-masking invariant**로 사전등록해야 한다.

### 2.4 Runner determinism / larger runners

**왜 계획이 필요한가**:
- `data/ci_pareto_baseline.json`의 **SCOPE AMENDMENT v11**이 larger runners를 금지한다. 이는 플랫폼 제약이 아니라 **정책/예산 결정**이다.
- `axiom-ci` runner group은 존재하지만 runner 0대다. larger/self-hosted runner 프로비저닝은 org admin + 비용 승인 + security/trust 검토가 필요하다.
- lane-specific 적용은 `admission-check.yml` 변경 → §2.5 cutover + org pin rotation을 동반한다.
- `s1a`의 VM regime variance는 larger runner로 줄어들 수 있지만, **총 MG wall + cost dual-metric**으로 판정해야 하며, a_fp/image drift로 cold cache가 될 수 있다.

### 2.5 Forward-looking observability (push timestamp, queue state, per-PR cost, metrics)

**왜 계획이 필요한가**:
- 플랫폼은 ordinary push timestamp, queue 내부 state transition history, per-PR billed cost, Actions metrics API를 **제공하지 않는다**. 과거 데이터는 backfill 불가다.
- 이를 얻으려면 push 시점 timestamp를 기록하는 workflow, merge_group webhook/queue snapshot 수집기, run+timing 수집 파이프라인, 외부 storage가 필요하다. 이는 **새 CI generation/architecture layer**이며 retention/cost/authority 정책을 수반한다.
- per-PR cost는 estimate만 가능하며, allocation rule(equal split vs other)을 제품/재무 정책으로 고정해야 한다.

### 2.6 Metric/cohort policy

**왜 계획이 필요한가**:
- `SLO-PR` target(예: p95 ≤ X)은 아직 선언되지 않았다. target 설정은 product contract/architect decision이다.
- data-incomplete PR(14일 window에서 4건; 2026-10-19 보고서의 716은 1,000-run cap bug의 산물)을 cohort에서 제외할지, 별도 stratum으로 둘지, full-cohort p95를 audit-only로 유지할지의 **metric population policy**가 필요하다.
- retention 90-day cap은 org/enterprise policy이며, pre-2026-10-01 data는 소급 복구 불가다. “과거를 복원”하는 계획은 불가능하며, “향후 export/archive”만 계획 가능하다.

### 2.7 CI duplication / org-owned workflows

**왜 계획이 필요한가**:
- deriver single-mint, artifact churn, toolchain handoff, mint/verdict fusion은 workflow/topology 변경 → §2.5 cutover + pin rotation.
- `observer-manifest-consistency`(15% cost, p50 4.9 min)는 **Archright/.github org workflow**다. Axiom repo만으로 변경할 수 없고 org-side authority/plan이 필요하다.
- SL-09 promotion 시 8× nimble install이 발화한다. scope promotion + workflow change + measurement prereg가 필요하다.
- `Makefile`/`ci/checker.mk`는 frozen surface이며 ADD/MODIFY/DELETE에 정책 PR이 필요하다.

### 2.8 Required-check semantics / policy

**왜 계획이 필요한가**:
- GitHub는 `success`/`skipped`/`neutral`을 성공으로 간주한다. Axiom의 `acceptableConclusion: "success"`는 **더 엄격한 정책**이며, 이를 바꾸는 것은 trust-policy 결정이다.
- workflow-level skip은 pending으로 차단되고, job-level skip은 통과한다. required gate를 “structurally unskippable”로 만들려면 workflow trigger/path filter 설계를 바꿔야 하며, 이는 CI topology change다.
- required checks/rulesets/queue params 변경은 merge authority 자체를 바꾸는 작업이므로 ADR/architect approval이 필요하다.

### 2.9 Remaining data-incomplete / historical audit

**왜 계획이 필요한가**:
- 수정 후 14일 window의 data-incomplete는 **4건**(`pr_head_ci_run_missing`)뿐이다. 2026-10-19 보고서의 716 unknown은 대부분 **1,000-run cap bug**였으며 retention 탓이 아니었다.
- 90일 full audit를 fixed tool로 재생성하려면 30–60분 + rate-limit 관리가 필요하다. 이는 운영 결정에 필수는 아니며, 별도 실행 계획(시간/비용)으로 분리한다.
- retention 90일 cap 때문에 2026-07 이전 run은 여전히 없을 수 있다. 이는 **audit-only 한계**이며, “full 90-day p95”를 운영 지표로 쓰지 않는 population policy가 필요하다.

---

## 3. No-plan follow-ups (계획 불필요, 후속 관측 개선)

1. **Rearm verdict JSON ingestion**: `merge-queue-rearm` job log의 `{"rearm":...}` verdict와 arm→enqueue latency를 attribution report에 필드로 추가. 데이터 측 개선; workflow 변경 없음.
2. **Dependabot merge trigger**: #910(11.4h)은 dependabot PR에 merge trigger가 없어서 발생. repo setting 또는 dependabot automation으로 해결 가능한지 확인. workflow 추가가 필요하면 plan-required로 재분류.
3. **ROT_NEW_PIN surfacing**: trust-surface 변경 PR에 pin-sync 필요 label/comment를 PR-head 시점에 표시. observability only.
4. **Historical-mode forensic validation**: `merge-queue-rearm`의 `workflow_dispatch + historical + dry_run`으로 기록된 failed run을 검증(arm하지 않음).
5. **Quirk 문서화**: `NOT_ADMIT_ROT_NEW_PIN` re-entry-success, arm→enqueue 6–60 min, required-check skip semantics를 `docs/spec/`에 기록(§0.5b).

---

## 4. Decision

- **End-to-end p95**: data-complete cohort의 최대 기여는 `between_cycle_gap`(dequeue/rearm recovery)과 `human_idle`이다. no-plan operator fix(dependabot trigger, label/yield protocol)를 먼저 적용하고, workflow/credential 변경(condition 6, arm credential, classification)은 plan-required로 분리한다.
- **SLO-MG**: recurring cost dominant. attest chain(build-base → go-critical-lane → admission-check)을 대상으로 하는 runner/lane/topology 변경은 policy/budget + §2.5 cutover가 필요하다.
- **No p95 reduction is claimed in this document.** Baseline/lever selection only; the next slice must measure before/after on the same contract.

---

## 5. Evidence

- Run slicing: `988de55eb` + independent verification (PR #627/#7/#3 indexed; counts match; deterministic; 0 deficit).
- Platform docs: Context7 `/github/docs` + docs.github.com paths in the official-docs memo; live `gh api` probes.
- Incident/rearm: PR #827/#828/#838/#895/#910/#919 run ids and `NOT_ADMIT_*` annotations in the incident memo.
- CI cost: `data/ci_optimization/pr_to_main_attribution_2026-10-19.json` + `docs/evidence/attest_job_decomposition_2026-10-12.md`.
- Canonical report: `data/ci_optimization/pr_to_main_attribution_2026-10-20.json` + `docs/evidence/pr_to_main_attribution_2026-10-20.md`.
