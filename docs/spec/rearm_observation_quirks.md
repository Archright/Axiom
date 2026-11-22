# Merge-Queue Re-Arm Observation Quirks (merge-queue-rearm + gh CLI/API)

> AGENTS.md §0.5 Quirk Mandate — 발견 2026-10-24 (재arm·프리플라이트 관측 계층).
> 본 문서는 `.github/workflows/merge-queue-rearm.yml`(ADR-0027 Amendment C/D/E)과
> 그 verdict 수집기가 GitHub Actions·merge-queue 위에서 **올바르게 관측되기 어렵게
> 만드는 플랫폼 행동**을 기록한다. 문서화 등록 근거:
> `docs/evidence/pr_to_main_attribution_remaining_issues_2026-10-20.md:180`
> (follow-up #5 — Quirk 문서화). auto-merge×merge-queue quirks는
> `gh_automerge_merge_queue_quirks.md`, merge-admission 관측 계층 quirks는
> `gh_merge_admission_observation_quirks.md`, 플랫폼 런 관측 일반은
> `gh_run_observation_quirks.md`가 각각 담당한다 — 본 문서는 그 gap만 다루고
> 중복 기록하지 않는다.

## Q1 — 조건부로 건너뛴 job은 success로 보고되어 required check여도 병합을 차단하지 않는다

**증상**: `if:` 조건이 false로 평가된 job의 conclusion은 `skipped`다. 그런데 이
`skipped`는 required status check로 등록돼 있어도 병합을 차단하지 않는다. 따라서
"비싼 lane을 조건으로 건너뛰게 했다"는 선언만으로는 fail-closed가 성립하지
않는다 — skip은 차단이 아니라 통과로 읽힌다.

**근거 (공식 문서)**:
https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions —
"A job that is skipped will report its status as 'Success'. It will not prevent
a pull request from merging, even if it is a required check." 같은 페이지의
troubleshooting 표(https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)도
"A job is skipped by a conditional → The job reports 'Success'"로 확인하며,
check conclusion 어휘 기준(
https://docs.github.com/en/pull-requests/reference/status-checks)에서 `skipped`는
"treated as a success"다. 단, 워크플로 자체가 path/branch 필터나 커밋 메시지로
**skip된 경우**는 다르다 — associated checks가 "Pending" 상태로 남아 병합을
차단한다(위 troubleshooting 표 1행). 즉 success로 위장되는 것은 **조건부 job
skip**뿐이다.

**대응 규칙**: 이 저장소에서 병합 차단을 담당하는 최종 required check는
"건너뛰었음"이 아니라 **명시적 실패(exit 1)를 기록해야** 한다. lane 비활성을
조건 skip으로 표현하면 그 lane은 required 집합 안에서 영구 green이 된다 —
최종 판정 job의 부재·비실행은 절대 차단 근거가 아니다.

## Q2 — `always()`는 needs 기본 success 게이트를 대체한다

**증상**: `needs:`로 묶인 선행 job이 실패해도, `if: always()`가 붙은 하류 job은
조건이 평가되어 실행된다. 그러므로 lane 게이트가 needs 실패 게이트에 의존한다는
가정이 깨진다 — 게이트 본문이 verdict 문자열(예: admission 판정 JSON)만 검사하면,
선행 job이 실패해서 verdict가 성립 조건을 잃었는데도 lane이 실행될 수 있다.

**근거 (공식 문서)**:
https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-jobs#defining-prerequisite-jobs —
"If a job fails or is skipped, all jobs that need it are skipped unless the
jobs use a conditional expression that causes the job to continue. … If you
would like a job to run even if a job it is dependent on did not succeed, use
the `always()` conditional expression in `jobs.<job_id>.if`." 공식
troubleshooting 표도 실패 의존 job을 가진 required check의 처방으로 "Use
`always()` with `needs`"를 제시한다(
https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).
즉 `always()`는 "선행 실패에도 required check가 **명시적 실패를 기록하도록
실행되게 하는**" 공식 수단이지, 그 자체가 판정이 아니다.

**대응 규칙**: 게이트/lane 조건은
`needs.<job>.result == 'success'`를 명시한다(status check 함수·verdict 문자열
단독 검사 금지 —
https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#status-check-functions).
Q1과 결합하면: 최종 required check는 `always()`로 실행 보장 + 본문에서
`needs.*.result` 명시 검사 + 불충족 시 명시적 실패의 3중 구조여야 fail-closed다.

## Q3 — `needs` 컨텍스트는 직접 의존성만 노출한다

**증상**: 중간 job을 거친 간접(전이) 의존 job의 result/outputs를 하류 job에서
`needs.<job_id>`로 참조하면 평가 시점에 존재하지 않는다(빈 값). 이를 어둠 속에
의존하면 최종 판정 job이 자신이 못 보는 상류 결과를 본 것처럼 판정한다 —
실제로는 미정의 값이다.

**근거 (공식 문서)**:
https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#needs-context —
"The `needs` context contains outputs from all jobs that are defined as a
**direct dependency** of the current job. Note that this doesn't include
implicitly dependent jobs (for example, dependent jobs of a dependent job)."

**대응 규칙**: 최종 판정 job이 참조하려는 모든 job은 자신의 `needs:`에 직접
나열한다. DAG 중간 단계의 result/outputs가 필요하면 그 중간 job을 needs에
추가하거나, 중간 job이 outputs를 재노출(단일 재투영)하도록 한다 — 간접 참조로
"알 수 없는 값 = success"로 평가되는 구조를 만들지 않는다.

## Q4 — rearm verdict는 job log에서만 안정적으로 얻어진다

**증상**: `merge-queue-rearm.yml`의 유일한 구조화 산출은 job log에 남는 한 줄
JSON `{"rearm":{pr,head,class,reason,budget,action,evidence{...}}}`다
(`.github/workflows/merge-queue-rearm.yml:80-82` 계약, `emit()` 투영
`:169-175` — `$GITHUB_STEP_SUMMARY`에도 동일 라인이 출력된다). run 단위
REST(`GET /repos/{owner}/{repo}/actions/runs/{id}`)·GraphQL 응답에는 이
구조화 필드가 없고, step summary 본문은 API로 조회할 수 없다(저장소 관측 —
run 오브젝트는 status/conclusion 등 메타만 노출). 로그 보존 기한이 지나거나
run별 로그 획득이 실패하면 verdict 소비자는 손을 쓸 수 없다.

**근거 (저장소 관측)**: 위 워크플로 파일의 구조화 요약 계약(주석 블록 + 모든
terminal path의 `emit` 호출). 참고로 org 필수 워크플로 run의 `gh run view
--log`는 404로 실패하며 로그 본문은 REST jobs 경로로 획득한다 —
`gh_merge_admission_observation_quirks.md` Q2 (ANSI escape 시
`--allow-escape-sequences` 요건은 `gh_run_observation_quirks.md` Q3).

**대응 규칙**: 수집기는 `gh run view <id> --log` 출력에서 `^\{"rearm":` 라인만
파싱한다(404 시 위 대체 경로). 로그 만료·누락·비JSON·라인 중복은 "arm 없음"이
아니라 **unknown으로 기록**한다 — verdict 부재는 분류 불가 상태지 부정 판정이
아니다(DEFAULT-NO-ARM 워크플로의 fail-closed 의미론과 동일 축).

## Q5 — dequeue 사유 ≠ 재진입 실패

**증상**: merge_group dequeue 이벤트에 `NOT_ADMIT_ROT_NEW_PIN` 같은 결정론적
거부 코드가 기록돼 있어도, PR-head 게이트가 **이미 같은 조건을 통과시킨 뒤**라면
그 PR의 재진입(재arm→재큐→착지)은 실패가 아니라 성공한 것이다. dequeue 사유는
그 사이클의 큐 단계 판정이지 재진입 시도의 결과가 아니다 — 재진입 성공률을
dequeue 사유로 집계하면 과소집계된다.

**근거 (저장소 관측)**: VS-1 PR-head rotation-pin 프리플라이트가
`af579664c`(2026-10-20 착지, `feat(admission): VS-1 PR-head rotation-pin
preflight`)로 착지하면서 같은 H2 판정이 PR-head 시점에 선행 평가된다
(`docs/evidence/rotation_allowlist_vs1_preflight_prereg_2026-10-20.md`).
실측(2026-10-24, 본 문서 작성 세션): 착지 시점(2026-10-20T08:30Z) 이후 실패로
끝난 merge_group admission-gate run **125건 전수**의 verdict check-run
annotation 타이틀에서 `NOT_ADMIT_ROT_NEW_PIN`은 **0건**(비고: NO_CERT 9·
UNPARSED 2·PR_CONTEXT_UNRESOLVED 2·verdict check-run 부재 19·타이틀 빈 값 93).
반면 프리플라이트 이전 2026-10-13→19 코호트에서는 `NOT_ADMIT_ROT_NEW_PIN` 6건이
관측됐다(`docs/evidence/pr_to_main_attribution_decision_2026-10-20.md:67`,
`docs/evidence/pr_to_main_attribution_remaining_issues_2026-10-20.md:55`).
수동 재진입 사례: #919 dequeue(`NOT_ADMIT_ROT_NEW_PIN`) 후 manual re-entry가
green으로 병합 — "잘못된 negative"
(`docs/evidence/pr_to_main_attribution_remaining_issues_2026-10-20.md:79`).

**대응 규칙**: dequeue 레코드의 거부 코드를 재진입 실패로 세지 않는다. 재진입
판정은 이후 관측(재큐 진입·required checks·MERGE)로만 한다. 거부 코드·unknown·
재진입 성공은 서로 다른 상태로 구분 기록한다(Q4의 unknown과 동일 축).

## Q6 — arm→enqueue 지연은 6–60분 규모다

**증상**: auto-merge arm 시점과 실제 큐 진입(`AddedToMergeQueueEvent`) 시점
사이에 PR head의 **가장 느린 required check 완료를 기다리는 구간**이 있다 —
메커니즘은 `gh_automerge_merge_queue_quirks.md` Q2가 담당한다(중복 기록하지
않음). 이 저장소의 등록 규모는 6–60분이다
(`docs/evidence/pr_to_main_attribution_remaining_issues_2026-10-20.md:180`;
동 문서 Q2 실측은 10분+). 따라서 "arm했는데 큐에 없다"를 즉시 실패로 판정하면
정상 지연을 고장으로 오판한다.

**근거 (저장소 관측)**: 위 등록 문서 + `gh_automerge_merge_queue_quirks.md` Q2
실측(arm 16:00:57Z → enqueue 16:10:41Z; 마지막 required인
`axiom-operational-slice` ~9분). 큐 진입 여부 자체는 `isInMergeQueue`/
`mergeQueueEntry` GraphQL로만 확인된다(arm 직후 null/false는 비동기 창 —
`merge-queue-rearm.yml` condition 10도 이를 log-only로 처리).

**대응 규칙**: arm→enqueue 관측에는 **명시적 관측 창**(분 단위 하한)을 둔다 —
창 만료까지는 "pending", 만료 후에도 큐 부재면 unknown이다. 즉시 실패 판정 금지.

## Q7 — `gh pr checks`는 큐 단계를 추적하지 않는다

PR-head check-run 집합만 보므로 큐 진입 후 즉시 종료한다 — 큐 진행 관측은 PR
timeline/queue GraphQL로 해야 한다(`gh_automerge_merge_queue_quirks.md` Q1
참조). 공식 근거 한 줄: PR checks 섹션에 나타나 required check를 충족하려면 run이
push/pull_request/pull_request_review/pull_request_target/deployment/
deployment_status 중 하나로 트리거돼야 하고, "Merge queues require the separate
`merge_group` event"다 —
https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks.

## Q8 — The `workflow_run` payload is not subject identity

For a run started by the `workflow_run` event:

- `github.event.workflow_run.head_sha` is the **merge-group SHA**, not the PR head.
- Per the documentation, `github.event.workflow_run.pull_requests[]` lists
  **open** PRs whose head_sha or head_branch matches; it **does not guarantee
  the triggering PR** (there may be zero or several).
- That run's `GITHUB_SHA` is the **last commit on the default branch**.
- `workflow_run` can access **higher privileges and secrets** than the workflow
  that triggered it — checking out PR code or treating an earlier run's artifact
  as verified executable code becomes a privilege-escalation path.

**Response rule**: parse the PR number only from the **single-PR queue-branch
shape** of `head_branch` (`^gh-readonly-queue/[^/]+/pr-([0-9]+)-[0-9a-f]{40}$`),
and **re-read** the PR head via `GET /repos/{owner}/{repo}/pulls/{N}`. If the
shape does not match (including multi-PR groups), the result is `UNKNOWN`/no-arm.
Completion must be bound to
`run_id × run_attempt × (event=merge_group, workflow name/path)` + run `head_sha` + the expected MG SHA.

## Q9 — A required check's publisher and a same-named Actions job are different objects

An **Actions job check** named `admission-check` (the job in `admission-gate-v2.yml`)
and the **required status check** the ruleset demands (published by an App) share the
**same name but different publishers**. Selecting by name alone misattributes pass/fail authority.

**Response rule**: the required check selector is `name == <ctx>` **AND**
`app.id == <base policy's requiredCheckSources.byContext[ctx]>`. Read the expected
App ID from the **base branch policy** (never the PR copy). If the publisher check
is absent, the result is `required-check=absent` / `UNKNOWN`, and a same-named Actions check must not be substituted.

## Q10 — The publisher App check carries no annotations (measured 2026-11-22)

All three failed `admission-check` check-runs had **zero annotations** (`text_len=0`).
That is, the reason code cannot be read from the publisher check's `output.annotations`.

**Response rule**: read the reason code from the check-run annotations of the
**failed Actions legs on the same merge-group SHA `G`** (`admission-check`, `attest / *`,
`verdict / *`); if absent, fall back to job log anchors. The publisher check's
`output.summary` is consumed only as a **rejection signal** such as `trust_surface=FAIL`.

## Q11 — The label budget must confirm "write success" by re-reading

The budget labels (`rearm-intent@<head12>`, `rearmed@<head12>`) cannot be
confirmed by a single successful GitHub API response. The arm request and the
label write are **not an atomic transaction**; if the label write fails, a gap
opens where the budget was consumed but no record exists.

**Response rule**: write the intent label **before** arming, and arm **only after
confirming its existence by re-reading**. If the arm result is unclear, **do not delete**
the intent — the intent's existence is itself durable evidence that the budget was
consumed. Budget exhaustion is expressed not as a red check but as the `rearm-exhausted` marker + `exit 0`.

## Q12 — The add-issue-labels API **auto-creates missing labels** (measured 2026-11-22)

Sending a label name that **does not exist** in the repository to
`POST /repos/{owner}/{repo}/issues/{issue_number}/labels` returns **200** rather than 422;
the response contains the new label object (new `id`, `color: "ededed"`, `default: false`)
and the label is attached to the issue. In other words, labels **need no pre-registration**.

Measured: POSTed `probe-intent-<epoch>` to PR #369 → 200 + new label id
`13177306671` → confirmed by re-reading the issue and repository label lists → deleted both.

**Response rule**: the budget labels (`rearm-intent@<head12>`, `rearmed@<head12>`,
`rearm-exhausted`) work without pre-registration. However, **auto-creation is a side effect**,
so the judgment "the label already exists, hence the budget was consumed" must always be
made by **re-reading the issue label list** (do not trust the write response alone — Q11).
To reduce repository label pollution, operators must treat `rearm-intent@*`/`rearmed@*` as cleanup targets.

## Q13 — `gh api --paginate` merges ARRAY pages but keeps only ONE page of an OBJECT response

Measured 2026-11-22 with `gh 2.102.0` against this repository.

| Response shape | `--paginate` alone | Correct idiom |
|---|---|---|
| JSON array (labels, annotations, PR files, issues) | one merged array containing **all** items | `--paginate` (or `--paginate` + `--jq`, which applies the filter per page and concatenates) |
| JSON object (actions runs, run jobs, workflows) | **one object holding only one page** — `total_count: 28` with a 5-item page yielded five `.workflows` items | `--paginate --slurp` (array of page objects) and flatten in the consumer, or `--paginate --jq '<per-page filter>'` |

Two consequences that are easy to get wrong:

- **Silent truncation on object endpoints.** `gh api --paginate "repos/$REPO/actions/runs/$ID/jobs?per_page=100"`
  looks paginated and is not: the last page overwrites the earlier ones. The observed
  shape is a single object, so no error is raised and the caller sees a plausible subset.
  Use `--slurp` and project with `.[] | .jobs[]?`.
- **`--slurp` cannot be combined with `--jq`.** `gh` rejects the pair with
  ``the `--slurp` option is not supported with `--jq` or `--template` ``. Choose one.

Measured page-shape evidence: `actions/workflows?per_page=5` (28 total, 6 pages) under
`--paginate --slurp` yields `[6, "object", 5]` (6 page objects, 5 workflows each);
the same endpoint under plain `--paginate` yields `.workflows | length == 5`.
A single-page array endpoint (`labels?per_page=100`, 12 items) stays a valid `ARRAY` of 12.

**Response rule**: a list read in this repository must either return the complete set or
fail closed. Adding `--paginate` to an array endpoint is safe and shape-preserving; adding
it to an object endpoint is a correctness bug unless `--slurp` (or `--jq`) is used.

## Q14 — the `workflow_run` wake-up is idempotent under both rerun semantics, and this repository has no rerun instance

`workflow_run: workflows: ["admission-gate"]` matches by workflow **name**, and
`types: [completed]` fires when a watched run reaches a terminal state. A re-run
(`gh run rerun <id>`) creates a new `run_attempt` on the **same** `run_id`.

Measured 2026-11-22: of the latest 100 workflow runs of **any** event, and of the latest
100 `merge_group` runs, **zero** carry `run_attempt > 1`; every observed run is attempt 1.
The "does a rerun emit a second `completed` event?" question therefore has **no local
instance** and is recorded as UNKNOWN rather than asserted.

The design does not depend on the answer:

- If a rerun **does** emit, the decision function binds `run_id`, `run_attempt`,
  `workflow_id`, `event`, and `head_sha` before acting, so the duplicate event resolves to
  the same facts and cannot produce a second arm (the `rearm-intent@` claim already blocks it).
- If a rerun **does not** emit, the PR remains `UNKNOWN`/no-arm until a `dequeued` event or
  an explicit `workflow_dispatch` re-evaluation. That is fail-closed, not a false arm.

**Response rule**: treat events as wake-ups, never as state. Any future claim about
rerun-emission must be backed by an observed attempt-2 run, not by inference.

## Q15 — public repositories lose `pull_request_target` by default on 2026-12-02 unless an Actions event policy allows it

GitHub changelog (2026-11-02): "Starting December 2, 2026, GitHub Actions will block
`pull_request_target` events by default in all public repositories, unless an applicable
Actions event policy explicitly allows them." Brownouts already ran on 2026-11-09 and
2026-11-16 (16:00-18:00 UTC). Private and internal repositories are not affected; the
change applies to Free, Team, and Enterprise Cloud.

Axiom is public and had **no applicable policy** (measured 2026-11-22):
`GET /repos/Archright/Axiom/actions/policies` returned `total_count: 0`; the five
organization policies named `authority-first-P-*` are scoped to `repository_id 1182104685`,
while Axiom is `1454952493`. `.github/workflows/merge-queue-rearm.yml` is the only workflow
in the repository with a real `pull_request_target` trigger, so the blast radius of the
mitigation is exactly one file.

Mitigation in force: repository policy **id 16826** (`allow-merge-queue-rearm-events`),
`enforcement: active`, conditions `workflow_path.include = [".github/workflows/merge-queue-rearm.yml"]`,
rule `restrict_action_events` with
`allowed_events = ["pull_request_target", "workflow_run", "workflow_dispatch"]`.

`allowed_events` is an **allowlist**. The policy must list every trigger of the matched
workflow: allowing only `pull_request_target` would block the `workflow_run` second wake-up
and the manual `workflow_dispatch` path. A future trigger added to this workflow requires a
matching policy update in the same change.

Verification (read-only):

```
gh api "repos/Archright/Axiom/actions/policies?has_parents=true" \
  --jq '.total_count as $n | "total=\($n)", (.policies[]|"\(.id) \(.source_type) \(.enforcement) \(.name)")'
gh api repos/Archright/Axiom/actions/policies/16826 --jq '{enforcement, conditions, rules}'
```

**Response rule**: the policy is platform enablement, not a safety proof. It restores the
ability to receive `dequeued`; it does not make PR-supplied code trusted. The workflow must
keep running trusted code only and must never check out the candidate's tree.

## Q16 — `workflow_run: completed` fires once per ATTEMPT, so re-runs mint duplicate wake-ups (measured 2026-11-22)

`run_attempt` is not part of the event's identity. A re-run of the watched workflow emits a
**second** `workflow_run: completed` delivery that keeps the same `workflow_run.id` and raises
`workflow_run.run_attempt` (1 → 2). The `requested` activity type is the one that does not
repeat on re-run; `completed` does.

Measured on a third-party repository (`sysown/proxysql`) because Axiom has no re-run of a
watched workflow at the current trusted pin:

| upstream attempt | `completed` delivered | downstream runs | payload `run_attempt` |
|---|---|---|---|
| run `44743813943` attempt 1 | `13:27:04Z` | 62, titled `trigger=44743813943/1` | 1 |
| run `44743813943` attempt 2 | `14:35:03Z` | 62 more, titled `trigger=44743813943/2` | 2 |

The official webhook schema marks `run_attempt`, `previous_attempt_url`, and `run_started_at`
as required members of `workflow_run`, described as "1 for first attempt and higher if the
workflow was re-run". Axiom-side observations: `conclusion=cancelled` is delivered (run
`45009434294` → `ci-cache-publisher` run `45010134738`); `conclusion=startup_failure` is in
the schema enum but has no runtime observation in this repository — treat it as UNKNOWN, not
as absent or as success. A re-run preserves the upstream `event`, so a re-run `merge_group`
still presents `event=merge_group`.

**Response rule**: a duplicate wake-up is a normal input, never an error and never a reason to
arm. The decision function must bind the outcome to `(run_id, run_attempt, workflow path,
event, upstream head_sha, expected merge-group SHA)` and must treat a wake-up whose attempt is
not the latest completed attempt as stale. An attempt still running means UNKNOWN/no-arm: the
older attempt's failure must never be fetched and re-registered while a newer attempt can
still produce a different outcome. Duplicates are contained by the existing `concurrency`
group (`cancel-in-progress: false`), by the `rearm-intent@`/`rearmed@` budget re-read
immediately before arming (Q11), and by the pre-arm attempt comparison — so a duplicate spends
runs, not a second arm.

## 운영 규범 (이 저장소 한정)

재arm·프리플라이트 관측을 새로 만드는 구현자는 다음을 따른다.

- **verdict 부재 = fail-closed**: 로그 만료·누락·비JSON은 unknown이다. unknown을
  deny나 "arm 없음"으로 기록하는 것 금지(Q4).
- **명시적 실패 기록**: 차단을 담당하는 최종 required check는 조건부 skip이
  아니라 명시적 실패를 기록해야 한다 — skipped는 success로 읽힌다(Q1).
- **explicit success 검사**: lane 조건은 `needs.<job>.result == 'success'`를
  명시한다. `always()`는 실행 보장일 뿐 판정이 아니며, verdict 문자열 단독
  검사 금지(Q2).
- **direct needs**: 판정 job이 참조하는 job은 `needs:`에 직접 나열한다 — 간접
  의존 참조 금지(Q3).
- **no inferred arm**: arm 사실은 기록된 행위(job log verdict의 `action`,
  timeline `AutoMergeEnabledEvent`)로만 판정한다 — 상태 추론으로 arm을 단정
  금지(Q4, Q6; `gh_automerge_merge_queue_quirks.md` Q3).
- **unknown/deny/재진입 성공 구분**: dequeue 사유는 재진입 성공률의 척도가
  아니다. 세 상태를 구분 기록하고 서로 대체하지 않는다(Q5).
- **complete listing or fail closed**: every list read must return the complete
  set or emit UNKNOWN/no-arm. Array endpoints take `--paginate`; object
  endpoints take `--paginate --slurp` and flatten in the consumer (Q13). A read
  that stops on a page cap is a truncation, never a "no match" verdict.
- **event-policy parity**: a trigger added to a workflow that an Actions event
  policy covers must be added to that policy's `allowed_events` in the same
  change, or the event is blocked before the workflow runs (Q15).
