# GitHub Merge-Admission Observation Quirks (landing_observe.sh + gh CLI/API)

> AGENTS.md §0.5 Quirk Mandate — 발견 2026-10-10 (trust-root 슬라이스 측정 활동).
> 본 문서는 merge-admission **관측 계층**(`tools/ci/landing_observe.sh` adapter,
> gh CLI/API)에서 관측된 특이사항의 기록이다. 플랫폼 런 관측 일반 quirks는
> `gh_run_observation_quirks.md`, org 필수 워크플로 run 404의 원기록은
> `gh_org_required_workflow_run_quirks.md`가 담당한다(파일명을 그쪽과 구분되게
> `gh_merge_admission_observation_quirks.md`로 명명 — 관측 대상이 merge-admission
> 계층이기 때문).

## Q1 — landing_observe.sh pr-head 행이 advisory check를 required rollup으로 계수한다

**Symptom**: `tools/ci/landing_observe.sh`의 pr-head 행이 GraphQL
`statusCheckRollup{state}`를 "pr-head required-check rollup"으로 취급한다
(`tools/ci/landing_observe.sh:81` 쿼리, `:189` 판정 문자열). `statusCheckRollup`은
**required 여부를 반영하지 않는 애그리게이트**다(라이브 인트로스펙션 2026-10-10:
"Check and Status rollup information for the PR's head ref" — Status·CheckRun
전체의 rollup). advisory check 하나만 FAILURE여도 GitHub merge queue가 live인
동안에도 `[BLOCKER] pr-head required-check rollup=FAILURE` +
`VERDICT: TERMINAL_FAIL`을 내보낸다.

**Measured evidence (2026-10-10)**: PR #673 — advisory `repository-surface`가
FAIL인데 그 워크플로 헤더는 스스로 advisory임을 명시한다
(`.github/workflows/repository_surface.yml:1` "required check 아님"). 그럼에도
merge queue는 PR을 착지시켰다: `5191eb1ba0eb7ded2aae989017ac1caabd971fe1`
(parents=2, PR mergedAt 2026-10-09T21:15:39Z). 같은 시점의 스크립트 실행은
`TERMINAL_FAIL`과 `[QUEUE] isInMergeQueue=true`를 **같은 출력에서** 발행 —
adapter 판정이 GitHub 병합 권위와 모순된 채 관측된다.

**Cause**: required 집합의 권위는 repo ruleset의 required checks 정의다.
`statusCheckRollup`은 그 필터가 아니다. AGENTS.md §2.3 — merge-admission의
authority는 GitHub이며 adapter·reporter는 authority가 아니다(Authority ≠
Adapter).

**Mitigation (fix 전까지)**: 스크립트의 rollup 행이 `[QUEUE]`/`[RUNS]`/`[GATE]`
행과 모순되면 raw facts + GitHub 큐 상태가 권위다.

**Status**: fix in flight by concurrent workstream (2026-10-10 기준).

## Q2 — merge_group 런의 `gh run view`/`--log` 404 — 로그 본문은 REST jobs 경로로 획득한다

기존 기록(`gh_org_required_workflow_run_quirks.md`): org 필수 워크플로 런의
`workflow_id`를 현 repo workflows 엔드포인트로 재해석 → 404 (runs
`36667874946`, `37428943334`; upstream cli/cli#9228 — 기존 기록의 추적 항목).

**2026-10-10 재측정 + 확장** — run `37975587567`(event=`merge_group`,
`workflow_id=367727531` — 동일 org admission-gate 워크플로, head_branch
`gh-readonly-queue/main/pr-666-…`):

```
$ gh run view 37975587567 -R Archright/Axiom
failed to get run: HTTP 404: Not Found
  (https://api.github.com/repos/Archright/Axiom/actions/workflows/367727531)
```

기존 문서에 없던 확장 사실 두 가지:

- `gh run view <id> --log` 변형도 동일 404다 (요약·로그 모두 workflow-id
  재해석 경로를 공유).
- 로그 **본문** 획득은 REST가 동작한다:
  `GET /repos/{owner}/{repo}/actions/runs/{id}/jobs` → job id 확보 후
  `GET /repos/{owner}/{repo}/actions/jobs/{job_id}/logs`. 기존 문서의 대체
  경로는 run **상태** 폴링(`GET /actions/runs/{id}`)이었으므로, 본 항목은
  본문 획득 경로를 보강한다.

단, jobs logs 경로에는 기존 기록(`gh_run_observation_quirks.md` Q3,
2026-10-08)의 조건이 그대로 적용된다: 로그에 ANSI escape가 포함되면 `gh api`는
출력을 거부하므로 `--allow-escape-sequences`가 필요하다(중복 기록하지 않음 —
해당 문서 참조).

**Status**: 외부 도구 결함 클래스 — 신규 수정 없음, 기록만.

## Q3 — org audit-log API가 `created`/`action`/`phrase` 필터를 조용히 무시한다; `--paginate` 원시 스트림은 단일 jq로 소비할 수 없다

**Symptom**: `GET /orgs/{org}/audit-log`에 `created`·`action`·`phrase` 쿼리
파라미터를 붙여도 오류 없이 필터가 적용되지 않은 스트림이 반환된다(조용한
무시). 또한 `gh api --paginate`의 원시 출력은 연결된 다중 페이지 JSON 배열
스트림인데, 이를 **단일 JSON 문서로 기대하는** 하나의 `jq` 호출에 파이프하면
`Unfinished JSON term`으로 실패한다.

**Measured evidence (2026-10-10)**:

```
$ gh api "/orgs/Archright/audit-log?created=<2015-01-01&per_page=3" \
    --jq '[.[] | .created_at] | {count: length, oldest: min}'
{"count":3,"oldest":1791582406240}   # epoch-ms ≈ 2026-10-10 — <2015 필터가 무시됨
```

참고: audit-log REST 항목의 `created_at`은 epoch-ms **숫자**다 — 클라이언트 측
시간 필터링은 문자열 비교가 아니라 수치 비교로 해야 한다.

**Mitigation**: 서버 측 필터 파라미터에 의존하지 않는다 — pagination +
클라이언트 측 필터링. `gh api --paginate --jq '…'`(per-page jq)는 페이지마다
필터를 실행해 유효한 스트림을 만들며, 원시 다중 페이지 출력을 하나의 jq
프로세스로 소비하는 형태를 피한다.

**Status**: 외부 API/도구 행동 — 기록만.

## Q4 — PR-venue admission 런 진행 구간의 REQCHK exact-name 지연 (2026-10-13 측정)

**Symptom**: PR-venue admission 런이 진행 중인 구간에서
`tools/ci/landing_observe.sh` REQCHK는 `attest / admission-check` 잡이 이미
green인 이후에도 `admission-check=MISSING`을 보고할 수 있다. required-check
이름은 런의 exact-named 애그리게이트 잡 `admission-check`인 반면, 진행 중인
(in-flight) 잡들은 접두사가 붙은 이름(`attest / admission-check`,
`verdict / admission-check`)을 가진다. MISSING 판독값은 애그리게이트 잡이
완료되면 해소된다.

**Measured evidence (2026-10-13)**: 드릴 PR #802(04:11–04:21Z, observer 16
passes) — 관측기의 UNKNOWN 판독값은 드릴 내내 fail-closed로 올바르게
처리되었다.

**Cause**: advisory-surface artifact일 뿐이다 — 관측기는 advisory이며,
authority는 GitHub의 required-check 평가에 그대로 있다(AGENTS.md §2.3,
Authority ≠ Adapter).

**Status**: 관측기 advisory artifact — authority 변경 없음, 기록만.

## Q5 — GraphQL `dequeuePullRequest`: 입력 필드는 `pullRequestId`가 아니라 `id`다; 페이로드에 `pullRequest` 필드는 없다

**증상**: 공개 GraphQL 문서 패턴
`dequeuePullRequest(input:{pullRequestId:...}){pullRequest{...}}`가 본
스키마에서 3중 거절된다 — `DequeuePullRequestInput`은 `id: ID!`만
수용하고(`pullRequestId` → `argumentNotAccepted`),
`DequeuePullRequestPayload`에는 `pullRequest` 필드가 없다
(`undefinedField`).

**측정**(2026-10-14, merge-queue-rearm 음성 제어 캐너리 PR #820 수동
dequeue): `input:{pullRequestId:$id}` 호출 →
`missingRequiredInputObjectAttribute(id)` + `argumentNotAccepted`
+ `undefinedField` 동시 반환. `mutation($id:ID!){dequeuePullRequest(input:{id:$id}){__typename}}`
→ 성공, 직후 조회에서 `isInMergeQueue=false`로 큐 이탈 확인.

**판정 규칙**: 수동 dequeue 자동화는 `input:{id: <PR node ID>}`로
호출하고, 성공 판정은 mutation 페이로드가 아니라 후속
`isInMergeQueue`/`mergeQueueEntry` 조회로 한다.
