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
