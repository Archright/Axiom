# GitHub Auto-Merge × Merge-Queue Quirks (gh CLI / GraphQL / Dependabot)

> AGENTS.md §0.5 Quirk Mandate — 발견 2026-10-22 (dependabot 무인 병합 슬라이스:
> PR #1045/#1046/#1047 — 이 저장소 최초의 auto-merge 착지 3연속 실측).
> 본 문서는 **auto-merge + merge-queue 조합의 관측·운영 특이사항** 기록이다.
> PR 게이트 관측 일반은 `gh_run_observation_quirks.md`, merge-admission 관측은
> `gh_merge_admission_observation_quirks.md`, org 필수 워크플로 run 404는
> `gh_org_required_workflow_run_quirks.md`가 담당한다.

## Q1 — `gh pr checks --watch`는 merge-queue 단계를 추적하지 않고 즉시 종료한다

**Symptom**: PR-head checks가 전부 결론 나는 순간 `gh pr checks <n> --watch`는
exit 0으로 종료한다. 이때 PR은 아직 **OPEN**이고 merge-queue(merge-group CI)는
시작조차 안 했을 수 있다. 워크플로 실행 관측 스킬 규정의 "단발 확인 + 5분 상한
슬립 반복" 정책(2026-10-07)이 이 이유로 필수다.

**Measured evidence (2026-10-22)**: PR #1046 — checks-watch exit=0 시점 state=OPEN,
`AddedToMergeQueueEvent`는 그 뒤 16:10:41Z, MERGED 16:19:56Z. PR #1047 — exit=0가
큐 진입 전 2회 관측. `gh pr checks`가 보는 check-run 집합이 PR head sha 기준이고
merge-group 런(`gh-readonly-queue/*` ref)은 이 집합에 속하지 않기 때문이다.

## Q2 — auto-merge의 자동 큐 진입은 "가장 느린 required check" 완료 후에야 발화한다

**Symptom**: arm(`gh pr merge --auto --match-head-commit`) 즉시가 아니라, PR head의
**모든** required checks가 success를 보고한 뒤에 `AddedToMergeQueueEvent`가 발생한다.
이 저장소에서는 `axiom-operational-slice`(~9분)가 마지막에 끝나므로 arm→enqueue에
10분+ 지연이 관측된다. arm 실패가 아니라 정상 지연이다 — arm→enqueue 갭을
"auto-merge 불능"으로 오판하지 말 것.

**Measured evidence (2026-10-22)**: #1046 arm 16:00:57Z → enqueue 16:10:41Z(잔여
pending이 `axiom-operational-slice`·`debt-registry-gate`뿐이던 시점 통과).
#1047 arm 16:23:42Z → checks 0 pending 확인 후 enqueue, position 1, AWAITING_CHECKS.

## Q3 — 큐 진입 후에는 `autoMergeRequest`가 null로 읽힌다 (arm 상태는 timeline에서)

**Symptom**: auto-merge가 활성화돼 큐에 들어간 PR을 GraphQL로 조회하면
`autoMergeRequest: null`이다. arm 사실은 **timeline의 `AutoMergeEnabledEvent`**로만
확인된다. "arm 여부" 판정을 `autoMergeRequest != null`로 하면 큐 진입 PR을
미arm으로 오판한다.

**Measured evidence (2026-10-22)**: #1046 — 16:41Z 조회에서
`autoMergeRequest: null` + `AutoMergeEnabledEvent` 존재 + `mergeQueueEntry{position:1,
state:AWAITING_CHECKS}`가 동시 관측.

## Q4 — `dependabot.yml` 변경이 main에 착지하면 ~20초 내 즉시 업데이트 run이 발화한다

**Symptom**: dependabot 설정 변경 merge는 weekly schedule을 기다리지 않고
곧바로 dependabot-updates run을 트리거한다. 승격/수용 관측 창을 짧게 잡을 수 있고,
반대로 설정 PR 착지 직후의 run은 "변경된 설정의 첫 실측"으로 읽어야 한다(스케줄
run이 아님).

**Measured evidence (2026-10-22)**: #1046 MERGED 16:19:56Z → dependabot run
39813135087 created 16:20:04Z (success, PR 0건 — exclude-paths 착지 직후 차단
클래스 제안 0·오류 0). 참고: Dependabot UI의 "Check for updates"가 유일한 수동
즉시 트리거다(공개 API 없음).

## Q5 — `check-repository-surface` 로컬 실행은 커밋되지 않은 편집을 보지 못한다

**Symptom**: surface 게이트는 `git diff $(git merge-base origin/main HEAD) HEAD`로
판정한다 — **작업 트리의 미커밋 편집은 diff에 없어 로컬 게이트가 PASS**하고,
커밋 후 pre-push OID 스냅샷에서 FAIL로 뒤집힌다. "로컬 게이트 PASS"를
"스냅샷 판정 PASS"로 외삽 금지. 정책 파일(`config/repository_surface.json`)
자기 개정은 BASE 기준 FROZEN MODIFY로 스냅샷 FAIL이 확정되며, 이는 v51
knownBlindSpots가 문서화한 자기승인 차단이다 — 소유자 수용-리스크 경로
(`git push --no-verify`, §Owner 결정 #1)로만 착지한다(v83 telemetry FAIL
선례: 9d096753 FAIL 2회 기록 후 PR #1023 큐 착지).

**Measured evidence (2026-10-22)**: 본 세션 — 미커밋 상태 `make push-admissibility`
전체 PASS → 커밋 후 스냅샷 FAIL(1473e7449, telemetry 기록) → `--no-verify`
push → #1045 큐 통과 MERGE. in-tree `make check-repository-surface` 재실행도
커밋 후에는 동일 FAIL(merge-base..HEAD diff 반영).

## Q6 — org ruleset은 repo 엔드포인트로 읽는다 (admin:org 불필요)

**Symptom**: `GET /orgs/{org}/rulesets`는 `admin:org` 스코프를 요구하지만,
`GET /repos/{owner}/{repo}/rulesets`는 대상 repo에 적용된 org ruleset까지
`source: "<org>"`와 함께 반환한다(read-only). org 측 ruleset 실측이 필요할 때
repo 엔드포인트로 충분하다.

**Measured evidence (2026-10-22)**: `gh api orgs/Archright/rulesets` → 404(admin:org
필요) + `gh api repos/Archright/Axiom/rulesets` → 25218071(axiom-admission-gate)·
23943917(landing-integrity) 포함 6개 전수 반환.

## Q7 — pyyaml은 workflow YAML의 `on:`을 boolean `True`로 파싱한다

**Symptom**: YAML 1.1 스펙상 `on/off/yes/no`가 boolean으로 coercion된다. Python
yaml 도구로 workflow 파일을 파싱하면 키 목록에 `True`가 나타난다 — 버그가 아니라
도구의 스펙 동작. workflow 문법 검증 도구는 `on:`을 문자열 키로 다뤄야 한다면
커스텀 loader가 필요하다.

**Measured evidence (2026-10-22)**: `yaml.safe_load`로
`.github/workflows/dependabot-auto-merge.yml` 파싱 → keys에 `True` 관측
(GitHub 자체 파싱은 정상 — 실측 #1046 착지).

## Q8 — 큐 ref `gh-readonly-queue/main/pr-N-<sha>`의 이름으로는 PR 귀속 판정을 할 수 없다 — sha 접미사는 스페큘레이티브 베이스 tip이며 다른 PR의 merge commit일 수 있다

**Symptom**: merge-queue 착지 창에 fetch되는 큐 ref명 `pr-N-<sha>`에서 `<sha>`를
"이 ref가 검증하는 PR의 head"로 읽으면 오귀속한다. `<sha>`는 그 엔트리가
적층된 **베이스 tip**(관측 시점의 main 기점)이고, 런의 `head_sha`는 PR
head가 아닌 **합성 병합 후보**다. `pr-N`의 N은 관측 창에서 큐에 든 PR 번호와
일치했으나(1125–1152 전 일치), N의 의미는 공식 문서가 정의하지 않는다(문서
예시는 `main/pr-1`, `main/pr-2` 형태 표기뿐).

**Measured evidence (2026-10-31, PR #1149/#1150/#1151 착지 창, REST
`/actions/runs?event=merge_group` 관측)**:

| 시각(UTC) | ref | run head_sha | 귀속 | 결과 |
|---|---|---|---|---|
| 12:46:16Z | `pr-1150-ee87f0a70…` | `6f5b1ef9…` | #1150 1차 엔트리 | admission-gate failure → 탈큐 |
| 12:55:14Z | `pr-1151-6f5b1ef9…` | `f686b282…` | #1151 엔트리(#1150 실패 후보 위 스페큘레이티브 적층) | admission-gate failure |
| 13:02:23Z | `pr-1151-ee87f0a70…` | `1236f33a2…` | #1151 재기점 엔트리 | success → #1151 MERGED 13:16:06Z |
| 13:12:34Z | **`pr-1150-1236f33a2…`** | `66ae494a0…` | #1150 재진입 엔트리 | success → #1150 MERGED 13:23:38Z |

결정적 행: `pr-1150-1236f33a2…`의 sha 부분 `1236f33a2…`는 **PR #1151의
mergeCommit**이다(#1151 mergeCommit `1236f33a23d34f412c675800cfc67d0c192742a5`,
headRefOid `e9559c263…`). 즉 ref명 sha는 다른 PR의 merge commit이 될 수
있고, 이 ref의 run head_sha `66ae494a0…`는 #1150의 mergeCommit다. ref명이나
run head_sha만으로 "#1151의 큐 런"을 찾으면 이 행을 #1151 것으로 오독한다.
또한 당선 런의 head_sha(#1151: `1236f33a2…`)는 PR headRefOid
(`e9559c263…`)와 다르고, 동일 ref명에서 재시도마다 head_sha가 변동된다
(pr-1144: 관측 창 내 3개 후보 `1d94d50…`/`a619cc1…`/`fe4874e…`).

**Official documentation basis** [documented, Managing a merge queue —
fetched 2026-11-01]: 프리픽스와 "다른 sha" 성격만 문서화돼 있다 — *"a branch
that begins with the special prefix `gh-readonly-queue/{base_branch}` …
These are the temporary branches that are created on your behalf by a merge
queue and contain a different sha from the pull request."*
(<https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue>)
N·sha 접미사의 구성 규칙과 재시도별 후보 변동은 문서에 없다 — 관측치로만
기록한다.

**운영 규범**: 병합 판정·귀속의 authority는 ref명이 아니라 GitHub다 —
`gh pr view <n> --json state,mergeCommit`(GitHub 네이티브 MERGE 커밋,
AGENTS.md §2.3). 큐 런을 PR에 귀속해야 할 때는 후보 커밋의 부모 검증
(`head ∈ parents(candidate)`)와 PR 번호 확인을 함께 하고, ref명 문자열
파싱만으로 판정하지 않는다. 관측 근거 캠페인:
`experiments/serde-json-claim-2026-10-31/` +
`docs/evidence/serde_json_claim_adjudication_2026-10-31.md`(PR #1149/#1151).

## Q9 — required-workflow ruleset의 mid-queue 변경 후 all-green 큐 엔트리가 AWAITING_CHECKS로 스톨한다 — 탈큐·재arm으로는 재진입 불가, fresh head가 유일한 회복 경로

**Symptom**: 큐 엔트리의 merge_group 런과 큐 SHA check-run이 **전부 success**인데도
두 엔트리가 state=AWAITING_CHECKS로 68분+ 스톨한다. 선행 이벤트는 04:49:37Z의
org ruleset 2건 updated_at 동시 변경(1.4초 간격)뿐이고, 초기 phrase 검색에서는
ruleset-edit action이 관측되지 않았다(실측 action명 `repository_ruleset.update` —
검색 아티팩트, ROOT-CAUSE 참조). 규칙 변경 **이전**에 생성된 PR-head required-workflow run은 변경
**이후** 규칙을 더 이상 만족하지 못하고, 규칙 변경이 PR-head run을 재트리거하지
않으므로 GitHub의 "required workflow satisfied" 판정이 영구 미충족으로 고정된다
(기계 판독은 아래 enqueuePullRequest 진단). 수동 탈큐 후 같은 head sha로 재arm해도
재진입 불가다. 문서가 열거하는 큐 탈락 사유 4종(CI failure · timeout · user
removal · branch protection failure) 중 어느 것도 발화하지 않았다 — checks는 전부
결론을 보고했으므로 status-check timeout의 발화 조건(결론 미보고)이 아니고, 실측
스톨 68분은 timeout 120분 미만이다. 즉 문서 서술 범주는 **즉시 removal**만 다루고,
관측된 **무기한 스톨** 케이스는 문서에 없다.

**Measured evidence (2026-11-02, Archright/Axiom main merge queue — ruleset
"main" #20303214)**:

큐 설정: `check_response_timeout_minutes=120`, `grouping_strategy=ALLGREEN`,
`max_entries_to_build=2`, `max_entries_to_merge=1`; required_status_checks는
GitHub Actions app id 15368이 보고하는 5 contexts. org ruleset 2건
(axiom-admission-gate #25218071 → `.github/workflows/admission-gate-v2.yml`,
landing-integrity #23943917 → `.github/workflows/landing-integrity.yml`)이
repository_id 1182157951의 sha `0684026f…`를 WorkflowFileReference로 핀 —
두 workflow 파일은 Archright/Axiom 트리에 존재하지 않는다(org-required-workflow
클래스).

| 시각(UTC) | 관측 |
|---|---|
| 04:16:58Z → 04:17:22Z | PR #1206 정상 착지(베이스라인): 엔트리의 admission-gate 완료 24초 후 MERGE |
| 04:36:17Z | #1208의 PR-head required-workflow run 41389395796 생성(변경 이전 규칙 상태로 평가된 run) |
| 04:42:54Z / 04:43:28Z | 큐 엔트리 #1207·#1208 빌드(`gh-readonly-queue/main/pr-N-…`, 엔트리당 merge_group 8개) |
| 04:49:37.357Z / 04:49:38.724Z | org ruleset 2건의 updated_at이 1.4초 간격으로 동시 변경(+09:00 표기 → 04:49:37Z UTC). org audit log 10페이지(`action:protected_branch`·`merge_queue` phrase)에서 ruleset-edit action 부재 |
| 04:55:11Z까지 | merge_group 런 16개 전부 success · 큐 SHA check-run 32개 전부 success/skipped · app 15368이 required 5 contexts 전부 보고 |
| 04:55Z → 06:01Z | 두 엔트리 state=AWAITING_CHECKS 스톨 68분+(GitHub status page 전 항목 operational — 플랫폼 인시던트 아님) |
| 06:01:50Z | #1207 수동 탈큐(audit: `merge_queue.pull_request_dequeued`, actor=wintrover) |
| 06:04:05Z / 06:11:51Z / 06:20:05Z | `merge_queue.pull_request_queue_jump` actor=wintrover(동일 credential을 공유하는 다른 자동화) |
| 06:11:49Z | #1208 RemovedFromMergeQueue — repo의 `merge-queue-rearm` 분류: `UNKNOWN — "latest merge_group run concluded success (green MG + manual dequeue = intentional removal)"` → no-arm |
| 06:20:15Z | 재arm 시도(`gh pr merge --auto --merge --match-head-commit <기존 head sha>`) → **재진입 불가** |
| 진단 | GraphQL `enqueuePullRequest` → **"Pull request Required workflow 'admission-gate' is not satisfied Required workflow 'landing-integrity' is not satisfied"** — 04:36:17Z 생성 PR-head run이 04:49:37Z 규칙 변경을 만족하지 못함이 기계 판독으로 확정 |
| 06:58:02Z | 회복: fresh head `0aebf9683…` push → 1개 workflow fail-closed 실패(mint-prepare A0: "PR #1208 base.sha 'ed9cab36d5ad' != baseSha input '36576a9567de'" — main이 진행됨) → `gh pr update-branch 1208` → head `d87cf93fe…`, 11/11 green → 큐 재진입 |
| 07:06:56Z | #1208 MERGED(merge commit `6ac29b915…`, parents=2) — bypass 없이 표준 경로만 사용 |
| 대조군 | #1210·#1211(규칙 변경 **이후** 06:11:53Z 빌드) → 06:20:05Z / 06:20:45Z 정상 MERGE — 변경 이후 규칙으로 평가된 엔트리는 무증상 |
| 교차 검증 | 병렬 PR #1207 작성자가 독립적으로 동일 회복(커밋 메시지: "chore(ci-cost): re-arm merge queue entry — post-dequeue required-workflow state reset") |

**ROOT-CAUSE** (병렬 조사, 2026-11-02, read-only `gh api` GET만 사용): GitHub 자동
re-pin이 **아니다** — 운영자(wintrover, user id 53123826)의 **gh CLI 2.102.0 수동
PUT**이다. org ruleset 2건은 04:49:37.517Z / 04:49:38.902Z에
`PUT /orgs/Archright/rulesets/{id}`로 갱신됐다(감사 로그 서명: `actor_is_bot=false`,
location KR, `programmatic_access_type="OAuth access token"`,
`oauth_application_id=1157143`, token_scopes `admin:org,gist,repo,workflow`). 핀은
`d76caf95…` → `0684026f…`로 교체됐고 `0684026f1b…`는 **Archright/.github
(repository_id 1182157951) main tip의 PR #252 merge commit**(04:47:57Z, merged_by
wintrover)과 정확히 일치 — 병합 **100초 후** 재고정. "1.4초 간격 동시 변경"의
정체는 두 PUT의 순차 실행 간격(1.385s)이다. 이는 조직의 정례 절차다: 소스 브랜치
커밋 메시지가 "RESID-23 operator re-pin"으로 절차를 명명하고, 2026-10-16~11-02
사이 동일 서명의 ruleset 갱신 약 150건(대부분 `.github` main 병합 후 48초~17분
내)이 관측된다. 핀은 파일 blob이 아니라 main tip commit sha다
(landing-integrity.yml blob은 2026-10-23 이후 불변인데도 핀이 lockstep으로 이동).
"audit log에 ruleset-edit action 부재"는 검색 아티팩트다 — 실제 action명은
`repository_ruleset.update`이며 `action:protected_branch`·`action:merge_queue`
phrase로는 미검출된다. 규칙 **갱신**(sha pin 교체)이 기존 PR-head
required-workflow run을 재트리거하는가: 문서 미서술(위 6은 rule **생성**만 다룬다)
— 관측 거동은 **재트리거 없음**(스톨 유지), 회복은 문서화 트리거(fresh head +
update-branch)로만 가능했다. 판정 프루브는 ruleset history가 결정적이다:
`gh api orgs/Archright/rulesets/{id}/history`가 버전·타임스탬프·actor·핀 diff를
반환한다(repo 엔드포인트 경로는 404 — §Q6와 동일 계층 quirk). 한계: gh CLI
서명은 "사람 직접 입력"과 "운영자 토큰으로 도는 로컬 스크립트"를 구분하지
못한다(어느 쪽이든 operator-driven이며 GitHub-automatic은 기각됨).

**Official documentation basis** [fetched 2026-11-02, Context7 `/github/docs` +
docs.github.com 실페치]:

1. **WorkflowFileReference**(ruleset의 required workflow 참조) — REST 스키마:
   `path`·`repository_id` 필수, `ref`(branch/tag) 선택, `sha` = *"The commit SHA
   of the workflow file to use"* → **sha는 커밋 고정 핀**이다. GraphQL 대응
   `WorkflowFileReferenceInput`도 동일 4필드. 소스: `src/rest/data/fpt-2026-03-10/repos.json`,
   `src/graphql/data/fpt/schema-actions.json`
   (<https://docs.github.com/en/rest/repos/rules>,
   <https://docs.github.com/en/graphql/reference/input-objects#workflowfilereferenceinput>).
   GitHub이 이 sha pin을 **자동 갱신**하는 문서화된 동작: **UNKNOWN** — 전수
   검색에서 미발견. 따라서 ruleset updated_at 동시 변경의 원인은 문서로 판정 불가.
2. **Mid-flight 규칙 변경 시 큐 엔트리 동작**: 문서는 removal 사유 4종만 열거한다 —
   *"Configured CI service is reporting test failures for a merge group / Timed
   out awaiting a successful CI result based off the configured timeout setting /
   User requesting a removal via the API or merge queue interface / Branch
   protection failure that could not automatically be resolved"* (reusable
   `data/reusables/pull_requests/merge-queue-removal-reasons.md`;
   <https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-a-pull-request-with-a-merge-queue>).
   관측된 **스톨 케이스(AWAITING_CHECKS 유지)는 문서에 미서술**다. "Branch
   protection failure that could not automatically be resolved"가 개념상 가장
   근접하지만 문서는 이를 removal 사유로만 서술한다 — 실측에서는 removal이 아닌
   스톨이었고, 탈큐는 사용자·자동화 수동 행동이었다.
3. **`check_response_timeout_minutes`(Status check timeout) 의미**: *"Maximum time
   for a required status check to report a conclusion. After this much time has
   elapsed, checks that have not reported a conclusion will be assumed to have
   failed"*
   (<https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets>),
   *"Choose how long the queue should wait for a response from CI before assuming
   that checks have failed"*
   (<https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue>).
   → **결론 미보고 check의 실패 간주 임계**다. 본 실측 스톨과 무관: 모든 check가
   결론을 보고했고 68분 < 120분이었다.
4. **AWAITING_CHECKS 값별 의미**: **UNKNOWN** — `/github/docs` 전수 검색에서
   `MergeQueueState` 열거값 서술을 찾지 못했다. 문서에 있는 `MergeStateStatus`
   (BEHIND/CLEAN/BLOCKED/…)는 PR 수준 `mergeStateStatus`의 **별개 열거**다.
   AWAITING_CHECKS는 API 관측값으로만 기록한다.
5. **`enqueuePullRequest`**: *"To add a pull request to the queue only if it can be
   added immediately, without enabling auto-merge, use the `enqueuePullRequest`
   GraphQL mutation. If the pull request can't be added, the mutation returns an
   error that explains why."*
   (<https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-a-pull-request-with-a-merge-queue>,
   <https://docs.github.com/en/graphql/reference/pulls#mutation-enqueuepullrequest>).
   문서 서술 그대로, 실측 오류 문자열이 미충족 required workflow를 나열했다 —
   "즉시 추가 불가 사유"의 **기계 판독 채널**로 사용 가능이 실증됐다. 같은 페이지:
   `gh pr merge`는 required checks 통과 시 큐 진입, 미통과 시 auto-merge 활성.
6. **Ruleset(required) workflow의 (재)실행 시점**: 지원 이벤트는 `pull_request`,
   `pull_request_target`, `merge_group`뿐이고 필터(`branches`·`types`·`paths` 등)는
   무시되며 기본 activity types(`opened`·`synchronize`·`reopened` /
   `checks_requested`)로 "only triggered, and is always triggered"
   (reusable `data/reusables/repositories/ruleset-workflow-event-triggers.md`).
   PR-head required check로 평가되는 run의 이벤트 제한: `push`, `pull_request`,
   `pull_request_review`, `pull_request_target`, `deployment`, `deployment_status`;
   merge queue는 별도 `merge_group` 이벤트 요구
   (<https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks>).
   규칙 변경의 재트리거: rule **생성** 시점에 PR이 열려 있으면 *"the required
   workflow will not run automatically. To trigger the required workflow, push a
   new commit, update your branch, or close and re-open the pull request"*
   (<https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/troubleshooting-rules>).
   실측 회복 절차(fresh head push → `gh pr update-branch`)는 이 문서화 트리거와
   정확히 일치한다. 단, live 페이지의 해당 절은 `repo-rules-required-workflows`
   feature flag 뒤라 docs.github.com 실렌더링에 없을 수 있다 — 검증은 github/docs
   소스(`content/repositories/.../managing-rulesets/troubleshooting-rules.md`)로
   수행(fetched 2026-11-02). 기존 rule의 **갱신**(예: sha pin 변동) 시 PR-head run
   재트리거 여부: **UNKNOWN** — 문서는 생성 케이스만 서술한다.

**운영 규범**:

- **진단**: all-green 스톨의 판정 authority는 GitHub다 — 추측 대신
  `enqueuePullRequest` mutation을 **기계 판독 프루브**로 사용한다(재진입 시도 ==
  진단; 오류가 미충족 required workflow를 나열한다). 착지 관측은
  `landing_observe.sh` ≥30s + `gh pr view <n> --json state,mergeQueueEntry,mergeCommit`.
- merge_group 런 전부 success여도 "required workflow satisfied"와 동치가 아니다 —
  큐 SHA의 green은 `merge_group` 이벤트 run이고, PR-head required-workflow run의
  **규칙 시점 적합성**은 별개 판정이다. "check-run 32개 green → 스톨 원인 없음"으로
  읽지 말 것. 첫 진단 변수: ruleset `updated_at`과 PR-head run `created_at`의
  선후 관계(실측 경계: 04:36:17Z run vs 04:49:37Z 규칙 변경).
- **회복**(표준 경로만, bypass 없음): fresh head commit push → base 진행으로
  fail-closed 실패 시 `gh pr update-branch <n>` → 전부 green 확인 → **새 head
  sha**로 `gh pr merge --auto --merge --match-head-commit <new-sha>` 재arm. 기존
  head sha의 재arm은 성공하지 않는다(실측). 이 순서는 문서화 트리거("push a new
  commit, update your branch")와 일치한다.
- **금지**: 큐 bypass("Merge without waiting for requirements to be met" /
  bypass branch protections) 사용 금지; merge authority는 GitHub다(AGENTS.md §2.3,
  GitHub 네이티브 MERGE 커밋). re-arm 자동화의 `UNKNOWN` 분류(no-arm)를 반복
  재arm 시도로 덮어쓰지 말 것 — PR-head run이 규칙 미충족인 동안 재arm은
  기계적으로 실패한다.

## 운영 규범 요약 (이 저장소 한정)

- 큐 진입한 PR의 착지 확인: `gh pr checks --watch`에 의존하지 말고 단발
  `gh pr view <n> --json state,mergedAt` + 5분 상한 슬립 반복.
- arm 상태 확인: timeline `AutoMergeEnabledEvent`(`autoMergeRequest` 아님).
- arm→enqueue 지연(최장 required check 소요 + α)은 정상 — 실패로 판정 금지.
