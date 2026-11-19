# GitHub Free parity — live merge-authority observation (2026-11-19)

> **Status**: 관측 증거 동결(freeze). 본 문서는 코드·정책·워크플로를 변경하지 않는다 — 실측값만 기록한다.
> **Created**: 2026-11-19
> **Measured at**: 2026-11-19T08:18Z (UTC). `gh` 2.102.0 (2026-09-30).
> **Base**: `7b1c0c35351be04416066fbdf35a1f517de4151e` (origin/main, 2026-11-19T07:40:59Z)
> **재실행 주의**: 본 문서의 값은 시점 스냅샷이다. ruleset `updated_at`, run 타임스탬프는 재조회 시 달라질 수 있다.

## §0. 결론

조직 `Archright`는 **이미 Free 플랜**이다. Team 해지 절차, 재결제, 롤백 대상은 존재하지 않는다 — 전환은 완료된 상태이며, 본 문서는 그 상태의 강제 체인을 실측으로 동결한다. Free 아키텍처는 문서 서술이 아니라 **실제 merge_queue admission**으로 입증된다: PR #204는 merge queue에 등록되어(`added_to_merge_queue` 07:40:59Z) 착지했고(`merged` 07:53:18Z), 그 큐 커밋에서 `merge_group` run `44481531363`이 실행되어 `success`로 끝났으며, merge commit의 `admission-check`는 Actions가 아니라 App `5795152`(`axiom-admission-verifier`)가 발행했다.

강제 체인은 **저장소 ruleset 2건**(`27097366` main, `27525972` main-admission)뿐이다. 조직 ruleset 엔드포인트는 Free에서 403이며, 이는 예상된 플랜 경계다.

## §1. 조직 플랜 · 저장소

| 항목 | 실측값 | 명령 |
|---|---|---|
| org login / type | `Archright` / `Organization` | `gh api orgs/Archright` |
| org plan | `free` (`space: 976562499`, `private_repos: 10000`, `filled_seats: 1`, `seats: 0`) | 동일 |
| org created_at | `2026-03-15T03:14:00Z` | 동일 |
| org public_repos / is_verified | `4` / `false` | 동일 |
| repo | `Archright/Axiom`, `visibility: public`, `private: false` | `gh api repos/Archright/Axiom` |
| repo id | `1454952493` (`node_id R_kgDOVrjQLQ`) | 동일 |
| default_branch | `main` | 동일 |
| owner | id `268288440`, login `Archright` | 동일 |

`gh api orgs/Archright` 응답의 `plan` 블록 원문:

```json
{
  "name": "free",
  "space": 976562499,
  "private_repos": 10000,
  "filled_seats": 1,
  "seats": 0
}
```

플랜 이름이 `free`이므로 Team 구독은 활성 상태가 아니다. 본 문서는 "해지 예정" 또는 "재결제 예정"인 어떤 상태도 관측하지 않았다 — 그런 상태는 API에 존재하지 않는다.

## §2. 조직 ruleset 엔드포인트 — 403 (플랜 경계, 예상됨)

```console
$ gh api orgs/Archright/rulesets
{"message":"Upgrade to GitHub Team to enable this feature.","documentation_url":"https://docs.github.com/rest/orgs/rules#get-all-organization-repository-rulesets","status":"403"}
gh: Upgrade to GitHub Team to enable this feature. (HTTP 403)
$ echo $?
1
```

- `message`: `Upgrade to GitHub Team to enable this feature.`
- `documentation_url`: `https://docs.github.com/rest/orgs/rules#get-all-organization-repository-rulesets`
- HTTP `403`, CLI exit `1`

해석: Free 조직에서는 조직 범위 ruleset API 자체가 제공되지 않는다. 강제 체인은 `main` 브랜치에 실제 적용되는 규칙 목록으로 교차 검증했다 — `GET repos/Archright/Axiom/rules/branches/main`은 `ruleset_id`가 `27097366`과 `27525972`인 규칙만 반환하며(§3), 조직 ruleset 기여분은 0건이다. 따라서 저장소 ruleset만이 merge authority다. 이 403은 장애가 아니라 플랜 경계의 정상 응답이며, 조직 ruleset이 "삭제되었다"는 주장도 본 문서는 하지 않는다 — **API로 관측 불가**일 뿐이다.

## §3. 저장소 ruleset 목록

```console
$ gh api repos/Archright/Axiom/rulesets | jq '[.[] | {id,name,target,source_type,enforcement}]'
```

| id | name | target | source_type | enforcement |
|---|---|---|---|---|
| `27097391` | `artifact-hygiene` | `push` | Repository | `disabled` |
| `27097369` | `cas-probe-scratch` | `branch` | Repository | `active` |
| `27097390` | `execution-surface-create` | `push` | Repository | `disabled` |
| `27466866` | `ledger-no-destroy` | `branch` | Repository | `active` |
| `27097366` | `main` | `branch` | Repository | `active` |
| `27525972` | `main-admission` | `branch` | Repository | `active` |

6건 모두 `source`가 `Archright/Axiom`(저장소 수준)이다. `?includes_parents=true&per_page=100`로 재조회해도 동일한 6건이 반환되며 `source_type: "Organization"` 항목은 0건이다 — 부모(조직) ruleset이 목록에 존재하지 않음을 교차 확인했다.

`main` 브랜치에 실제 적용되는 규칙은 `GET repos/Archright/Axiom/rules/branches/main`으로 교차 검증했다:

| ruleset_id | type |
|---|---|
| `27097366` | `deletion` |
| `27097366` | `non_fast_forward` |
| `27097366` | `pull_request` |
| `27097366` | `required_status_checks` |
| `27097366` | `merge_queue` |
| `27525972` | `required_status_checks` |

## §4. ruleset `27097366` ("main") — merge authority

```console
$ gh api repos/Archright/Axiom/rulesets/27097366
```

| 필드 | 값 |
|---|---|
| `id` / `name` | `27097366` / `main` |
| `target` / `source_type` / `source` | `branch` / `Repository` / `Archright/Axiom` |
| `enforcement` | `active` |
| `bypass_actors` | `[]` |
| `conditions.ref_name` | `include: ["~DEFAULT_BRANCH"]`, `exclude: []` |
| `current_user_can_bypass` | `never` (인증 주체 기준 응답 필드 — §9 C9 참조) |
| `created_at` / `updated_at` | `2026-11-12T16:10:00.467+09:00` / `2026-11-19T16:12:25.115+09:00` |

규칙 5종: `deletion`, `non_fast_forward`, `pull_request`, `required_status_checks`, `merge_queue`.

### §4.1 `pull_request` 파라미터

```json
{
  "required_approving_review_count": 0,
  "dismiss_stale_reviews_on_push": false,
  "required_reviewers": [],
  "require_code_owner_review": false,
  "dismissal_restriction": { "enabled": false, "allowed_actors": [] },
  "require_last_push_approval": false,
  "required_review_thread_resolution": false,
  "require_extra_approval_for_unattributed_changes": true,
  "allowed_merge_methods": ["merge"]
}
```

### §4.2 `required_status_checks` — 7개 context와 producer App

```json
{
  "strict_required_status_checks_policy": false,
  "do_not_enforce_on_create": false,
  "required_status_checks": [
    { "context": "admission-check",        "integration_id": 5795152 },
    { "context": "bsec-integrity",         "integration_id": 15368 },
    { "context": "debt-registry-gate",     "integration_id": 15368 },
    { "context": "generation-acceptance",  "integration_id": 15368 },
    { "context": "axiom-operational-slice","integration_id": 15368 },
    { "context": "publication-integrity",  "integration_id": 15368 },
    { "context": "readiness-verdict",      "integration_id": 15368 }
  ]
}
```

Producer 신원은 플랫폼 API로 별도 확인했다:

```console
$ gh api /apps/axiom-admission-verifier | jq '{id,slug,name,owner:.owner.login,permissions,events}'
{
  "id": 5795152,
  "slug": "axiom-admission-verifier",
  "name": "axiom-admission-verifier",
  "owner": "Archright",
  "permissions": {
    "actions": "read",
    "checks": "write",
    "contents": "write",
    "merge_queues": "read",
    "metadata": "read",
    "statuses": "write"
  },
  "events": ["merge_group", "workflow_run"]
}
```

`15368`는 GitHub Actions 앱(`app_slug: github-actions`)이다 — §7 check-run 실측에서 같은 값을 확인한다.

### §4.3 `merge_queue` 파라미터

| 파라미터 | 값 |
|---|---|
| `merge_method` | `MERGE` |
| `grouping_strategy` | `ALLGREEN` |
| `max_entries_to_build` | `2` |
| `min_entries_to_merge` | `1` |
| `max_entries_to_merge` | `1` |
| `min_entries_to_merge_wait_minutes` | `0` |
| `check_response_timeout_minutes` | `120` |

## §5. ruleset `27525972` ("main-admission")

```console
$ gh api repos/Archright/Axiom/rulesets/27525972
```

| 필드 | 값 |
|---|---|
| `id` / `name` | `27525972` / `main-admission` |
| `target` / `source_type` / `source` | `branch` / `Repository` / `Archright/Axiom` |
| `enforcement` / `bypass_actors` | `active` / `[]` |
| `conditions.ref_name` | `include: ["~DEFAULT_BRANCH"]`, `exclude: []` |
| `current_user_can_bypass` | `never` |
| `created_at` / `updated_at` | `2026-11-18T15:18:43.069+09:00` / `2026-11-19T16:12:25.993+09:00` |

규칙은 **1건**뿐이다:

```json
{
  "type": "required_status_checks",
  "parameters": {
    "strict_required_status_checks_policy": false,
    "do_not_enforce_on_create": false,
    "required_status_checks": [
      { "context": "admission-check", "integration_id": 5795152 }
    ]
  }
}
```

**명시**: `main-admission`에는 `merge_queue` 규칙이 **없다**. merge queue 파라미터(§4.3)는 `27097366`에만 존재한다. 두 ruleset은 같은 시각(`2026-11-19T16:12:25+09:00`)에 갱신되었고, `main-admission`은 `admission-check`를 App `5795152`로 고정하는 단일 목적 ruleset이다. `main`의 동일 context 항목과 중복 정의되며, 규칙 계층화로 둘 다 적용된다(`rules/branches/main` 교차 검증 §3).

## §6. `admission-gate` 워크플로 트리거

`.github/workflows/admission-gate-v2.yml`:

```yaml
111: name: admission-gate
113: on:
114:   pull_request:
115:   merge_group:
116:     types:
117:       - checks_requested
119: permissions:
120:   contents: read
```

- `.github/workflows/admission-gate-v2.yml:113-117` — `pull_request`(모든 타입)와 `merge_group`의 `checks_requested` 타입에서 실행된다. merge queue가 큐 커밋에 대해 이 워크플로를 발화시키는 지점이 `merge_group` 트리거다.
- `.github/workflows/admission-gate-v2.yml:119-120` — 상위 권한은 `contents: read`뿐이다.

## §7. 실 merge_group 증거

### §7.1 PR #204의 큐 진입·착지

```console
$ gh api repos/Archright/Axiom/pulls/204 | jq '{number,state,merged,merged_at,base:.base.ref,base_sha:.base.sha,head:.head.ref,head_sha:.head.sha,merge_commit_sha}'
{
  "number": 204, "state": "closed", "merged": true,
  "merged_at": "2026-11-19T07:53:18Z",
  "base": "main", "base_sha": "a3e4418942e342f70d405e96a1338b68cb5513cd",
  "head": "docs/readiness-verdict-lane-contract",
  "head_sha": "0517c0efe857267234e8aa9fbc83a3e05b4f544e",
  "merge_commit_sha": "7b1c0c35351be04416066fbdf35a1f517de4151e"
}
```

타임라인은 큐 경로를 직접 보여준다:

| event | created_at | actor |
|---|---|---|
| `added_to_merge_queue` | `2026-11-19T07:40:59Z` | `wintrover` |
| `merged` | `2026-11-19T07:53:18Z` | `wintrover` |
| `removed_from_merge_queue` | `2026-11-19T07:53:18Z` | `github-merge-queue[bot]` |

merge commit의 부모는 base/head 쌍과 정확히 일치한다:

```console
$ gh api repos/Archright/Axiom/commits/7b1c0c35351be04416066fbdf35a1f517de4151e | jq '{sha,parents:[.parents[].sha]}'
{ "sha": "7b1c0c35351be04416066fbdf35a1f517de4151e",
  "parents": ["a3e4418942e342f70d405e96a1338b68cb5513cd",
              "0517c0efe857267234e8aa9fbc83a3e05b4f544e"] }
```

즉 merge_group의 `base` context는 `a3e4418942e342f70d405e96a1338b68cb5513cd`(main), `head`는 `0517c0efe857267234e8aa9fbc83a3e05b4f544e`이며, 큐 커밋 `G = 7b1c0c3…`는 두 부모를 가진 merge commit이다.

### §7.2 run `44481531363`

```console
$ gh api repos/Archright/Axiom/actions/runs/44481531363
```

| 필드 | 값 |
|---|---|
| `id` / `name` | `44481531363` / `admission-gate` |
| `event` | `merge_group` |
| `status` / `conclusion` | `completed` / `success` |
| `head_sha` | `7b1c0c35351be04416066fbdf35a1f517de4151e` |
| `head_branch` | `gh-readonly-queue/main/pr-204-a3e4418942e342f70d405e96a1338b68cb5513cd` |
| `created_at` / `run_started_at` | `2026-11-19T07:41:17Z` / `2026-11-19T07:41:17Z` |
| `updated_at` | `2026-11-19T07:52:54Z` |
| `path` / `workflow_id` | `.github/workflows/admission-gate-v2.yml` / `420946486` |
| `run_attempt` | `1` |

같은 큐 커밋(`head_sha = 7b1c0c3…`)에서 **8개 run**이 발화했다(`GET repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100`에서 `head_sha`로 필터, 전부 `run_attempt: 1`):

| run id | path | conclusion | created_at |
|---|---|---|---|
| `44481530815` | `.github/workflows/observation.yml` | `success` | `2026-11-19T07:41:16Z` |
| `44481530835` | `.github/workflows/generation-acceptance.yml` | `success` | `2026-11-19T07:41:16Z` |
| `44481530846` | `.github/workflows/publication-integrity.yml` | `success` | `2026-11-19T07:41:16Z` |
| `44481530898` | `.github/workflows/debt-registry-gate.yml` | `success` | `2026-11-19T07:41:16Z` |
| `44481530931` | `.github/workflows/bsec-integrity.yml` | `success` | `2026-11-19T07:41:16Z` |
| `44481530937` | `.github/workflows/probe-merge-queue.yml` | `success` | `2026-11-19T07:41:17Z` |
| `44481530942` | `.github/workflows/axiom-operational-slice.yml` | `success` | `2026-11-19T07:41:17Z` |
| `44481531363` | `.github/workflows/admission-gate-v2.yml` | `success` | `2026-11-19T07:41:17Z` |

이는 merge queue가 큐 커밋에서 required context producer들을 실제로 발화시켰다는 증거다 — `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `publication-integrity`, `axiom-operational-slice`(+ 그 안의 `readiness-verdict`), `admission-gate`가 모두 같은 head에서 실행되었다.

`44481531363`의 job 중 판정 경로의 종단은 `admission-check`다(`GET …/actions/runs/44481531363/jobs`, 총 26 job):

| job | conclusion | started_at | completed_at |
|---|---|---|---|
| `closure-deriver` | `success` | `07:41:19Z` | `07:42:15Z` |
| `attest / build-base-artifacts` | `success` | `07:41:19Z` | `07:43:35Z` |
| `attest / admission-check` | `success` | `07:46:15Z` | `07:47:39Z` |
| `verdict / admission-check` | `success` | `07:49:19Z` | `07:50:36Z` |
| `admission-check` | `success` | `07:52:49Z` | `07:52:54Z` |

### §7.3 `admission-verdict` 아티팩트

```console
$ gh api repos/Archright/Axiom/actions/artifacts/14509082548/zip > verdict.zip
$ unzip -p verdict.zip admission-verdict.log | head -1
```

아티팩트 메타데이터: `id 14509082548`, `name admission-verdict-7b1c0c35351be04416066fbdf35a1f517de4151e-1`, `size_in_bytes 1126`, `created_at 2026-11-19T07:50:33Z`, `expired false`.

첫 줄(판정 JSON) 원문:

```json
{"prNumber":204,"headSha":"0517c0efe857267234e8aa9fbc83a3e05b4f544e","baseSha":"a3e4418942e342f70d405e96a1338b68cb5513cd","verdict":{"result":"mergeGo","reasonCode":"GO","reason":"admission passes cleared (base provenance bound to main a3e4418942e3; landing freshness enforced by merge-queue invalidation — ADR-0027 P5)"},"qualification":"NORMAL","rotationCheck":{"closureChange":false,"changed":["docs/spec/readiness_verdict_check.md"],"allowlistOk":true,"subjectDeltaZero":true,"genesis":false,"oldAnchorOk":true,"newAnchorOk":true,"delegatedToPlatform":true},"rotationNote":"","vaultCert":{"required":true,"targets":null},"judge":{"source":"f784e4a85212ab76b175fc90bc55cb1de6bc1f8aaca1933aa167ab35c9ffaf2f"},"preflight":false,"layerAdmissibility":{"status":"PASS","scannedFiles":0,"approvedPairCount":23,"note":"","violations":[]}}
```

파싱된 핵심 필드: `prNumber = 204`, `verdict.result = mergeGo`, `verdict.reasonCode = GO`, `qualification = NORMAL`, `rotationCheck.closureChange = false`. 아티팩트는 같은 zip 안에 `merge_cli` 단계 로그도 담고 있으며, 마지막 판정 라인은 `[dry-run] mergeGo (GO)`다.

### §7.4 merge commit check-runs — App 신원까지 확인

```console
$ gh api "repos/Archright/Axiom/commits/7b1c0c35351be04416066fbdf35a1f517de4151e/check-runs?per_page=100"
# total_count: 49
```

`admission-check`라는 이름의 check-run은 **2건**이다. 이름이 같으므로 앱 id가 판별자다:

| check-run id | `app.id` / `app.slug` | conclusion | started_at | completed_at | details_url |
|---|---|---|---|---|---|
| `135414650383` | **`5795152` / `axiom-admission-verifier`** | `success` | `07:41:16Z` | `07:53:00Z` | `https://github.com/Archright/Axiom` |
| `135419539200` | `15368` / `github-actions` | `success` | `07:52:49Z` | `07:52:54Z` | `…/actions/runs/44481531363/job/135419539200` |

App `5795152`가 발행한 check-run의 부가 필드:

- `output.title`: `Trusted verification verified`
- `external_id`: `v1|1454952493|7b1c0c35351be04416066fbdf35a1f517de4151e|a3e4418942e342f70d405e96a1338b68cb5513cd|4966e4917eb8e3445c16cddb22181945c4f76884` — 저장소 id(`1454952493`)와 (head, base) 쌍이 결속되어 있다.

15368 쪽 `admission-check`는 게이트 run 내부의 동명 job이며 5초 만에 끝난다. 규칙이 요구하는 context는 `integration_id 5795152`이므로, **동명 job이 존재해도 판정 권위는 앱 id로 갈린다** — 이름이 아니라 신원이 판별자라는 것이 실측으로 드러난다.

## §8. 잔여 org-의존 코드 경로 — 현재 의미는 inert/legacy

아래 경로들은 조직 ruleset 시대의 흔적을 담고 있다. 본 문서는 이들을 **삭제 대상이라고 주장하지 않는다** — 현재 의미가 무엇인지만 기록한다.

### §8.1 `config/policy/merge_admission.json:61-70` — `requiredWorkflowDetection`

```json
61:  "requiredWorkflowDetection": {
62:    "repositoryId": 1454952493,
63:    "workflowPath": ".github/workflows/admission-gate-v2.yml",
64:    "verdictJob": "admission-check",
65:    "verdictCheckSource": {
66:      "appId": 5795152,
67:      "appSlug": "axiom-admission-verifier",
...
```

**주의**: `repositoryId`는 `1454952493`(현 저장소 Axiom 자신)이며, 조직 저장소 `Archright/.github`의 옛 id `1182157951`이 아니다. 정책 설명(`config/policy/merge_admission.json:4`, v1.24.0 절)이 그 이동을 기록한다: "requiredWorkflowDetection.repositoryId moves 1182157951 -> 1454952493 (the orchestrator … is repository-native since PR #134)".

현재 의미: 이 블록은 **정책 기대 집합의 원천**이지 조직 ruleset 조회기가 아니다. 소비자는 세 곳이며 모두 "기대 context 이름"을 유도하는 데만 쓴다:

- `.github/workflows/admission-check.yml:1304-1324` — `requiredValidations[]` + `requiredWorkflowDetection`의 (path, job) 튜플을 기대 집합으로 열거.
- `tools/merge_ruleset_drift_monitor.nim:395-430` — `requiredValidations[].job ∪ requiredWorkflowDetection.verdictJob`로 기대 context 집합 유도.
- `tools/ci/landing_observe.sh:408-415` — 같은 union + `requiredCheckSources` 기반 기대 producer.

### §8.2 `src/cli/merge_cli.nim:143-196` — identity mirror

- `:143-151` `RequiredChecks` = 7개 context 이름.
- `:180-196` `RequiredWorkflowIds` = (job, workflowPath) 튜플 6건. `admission-check`는 여기 없다 — 그 producer는 저장소 워크플로가 아니라 App이기 때문이다.
- `:162-165` 주석: "Historically the workflow was ORG-INJECTED at Archright/.github (repository_id 1182157951, sha-pinned by org ruleset 25218071) — the org rulesets are retired (2026-11-17, ADR-0041: 403 under the free org plan)."

현재 의미: 이 블록은 **기록된 신원 mirror**이며 merge-time 재검증이 아니다(`src/cli/merge_cli.nim:153-156`: "NOT a merge-time re-verification: the predicate deliberately does not collect check-runs nor re-verify producer identity"). 파일 내 `ruleset` 문자열은 주석과 trust-surface 경로 목록(`:313`, `:316`)뿐이고 ruleset API 호출 코드는 없다 — `merge_cli`는 조직/저장소 ruleset을 조회하지 않는다.

### §8.3 `tools/merge_ruleset_drift_monitor.nim` — post-hoc 모니터

- `:128-133`: "DRIFT DETECTION IS NOT MERGE-TIME ENFORCEMENT … Merge-time enforcement stays with the platform (the repository ruleset's required status checks; the org ruleset's sha-pinned workflows rule is retired with the org rulesets — deleted 2026-11-17, ADR-0041). The monitor never blocks a merge and never mutates any GitHub state — it only GETs and judges."
- `:21-26`: 선택 조건이 `source is REPOSITORY level (== the repo's own full name — org rulesets excluded)`이므로 조직 ruleset이 목록에 있어도 후보에서 배제된다.

현재 의미: 조직 ruleset의 sha-pinned workflows 규칙은 **모니터 기대값에서 이미 퇴역**했고, 모니터는 저장소 ruleset `main` 하나만 이름으로 해석한다. 병합을 막지 않는다.

### §8.4 `.github/workflows/generation-acceptance.yml` — GPA L2 조회

- `:41-47` 헤더: 현행 강제는 저장소 ruleset `27097366`(`main`, `bypass_actors []`)이며 "repo 범위 관리라 org write가 불필요하다(Free 플랜). org ruleset·bypass actor 관리는 Administration org write가 필요해 GPA의 조회 범위 밖이다 → operator-adapter 티어(ADR-0036 §4)."
- `:415` 목록 조회는 여전히 `repos/$REPO/rulesets?includes_parents=true&per_page=100`를 쓴다.
- `:400-410` 이름 해석(`name=="main" ∧ enforcement=="active" ∧ target=="branch"` + `required_status_checks` 기대 일치)으로 ruleset을 찾는다.

현재 의미: `includes_parents=true`는 부모 ruleset이 존재하던 시절의 조회 형태다. 현재 부모가 0건이므로 결과는 저장소 ruleset만이며, 해석은 이름 기반이라 id 재부여에 영향받지 않는다. 이 플래그는 남아 있지만 판정을 바꾸지 않는다(inert).

### §8.5 `tools/ci/landing_observe.sh` — 관측기

- `:25-33`, `:378-391`: 규칙 집합을 이름 `"main"`으로 해석하고, 불완전 페이지/0건/2건 이상은 `UNDETERMINED`(fail-closed)로 표기.
- `:401-462`: 해석 실패 시 `REQ_DECL`에 "ruleset(\"main\") 해석 불가: … → required set UNDETERMINED (fail-closed)"를 기록.
- `:5-6`, `:38-42`: 출력은 **ADVISORY EVIDENCE**이며 이 도구는 authority가 아니다. read-only(GET/GraphQL만)이고 write/rerun 경로가 없다.

현재 의미: 조직 ruleset을 전제하지 않는다. 이름 해석은 저장소 ruleset을 찾으며, 해석 불가는 fail-closed로 표기된다.

## §9. 본 문서가 입증하는 것 / 입증하지 않는 것

**입증됨 (실측)**

1. 조직은 Free이며 조직 ruleset API는 403이다(§1, §2).
2. merge authority는 저장소 ruleset `27097366`이며, `bypass_actors`는 비어 있고 7개 required context 중 `admission-check`만 App `5795152`, 나머지 6개는 Actions `15368`이다(§4.2).
3. merge queue는 `MERGE`/`ALLGREEN`/build 2/merge 1/merge-wait 0/timeout 120으로 실제 동작했다 — PR #204가 큐에 등록되어 착지했고, 큐 커밋에서 `merge_group` run이 `success`했다(§7.1-§7.2).
4. 판정 산출물은 `mergeGo`/`GO`/`NORMAL`이며, merge commit에는 App `5795152`가 발행한 `admission-check: success`가 존재한다(§7.3-§7.4).

**입증되지 않음 (C9)**

5. 빈 `bypass_actors`가 **저장소 관리자의 override를 구조적으로 차단**한다는 주장. 아래 §9.1 참조 — 공식 문서로 확립되지 않는다.

### §9.1 C9 — 알려진 한계 (UNVERIFIABLE)

확인한 공식 문서 2건:

- <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets>
  - "People with admin access to a repository, or a custom role with the "edit repository rules" permission, can create, edit, and delete rulesets for a repository."
  - "When you create a ruleset, you can allow certain users to bypass the rules in the ruleset. This can be users with a certain role, such as repository administrator, or it can be specific teams or GitHub Apps."
- <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository>
  - "You can grant certain roles, teams, or apps bypass permissions for your ruleset. The following are eligible for bypass access: Repository admins, organization owners, and enterprise owners …"

**판정: UNVERIFIABLE.** 두 문서는 bypass가 "명시적으로 부여하는 목록"임을 서술하지만, **목록이 빈 경우의 기본값**을 명시하지 않는다. 또한 관리자가 ruleset 자체를 편집·삭제할 수 있다고 서술한다. 따라서 "빈 `bypass_actors`이면 관리자도 우회할 수 없다"는 것은 문서로 확립되지 않는다. 본 문서는 관리자가 구조적으로 차단된다고 주장하지 않는다.

참고 관측: 두 ruleset 응답의 `current_user_can_bypass`는 `never`다. 이는 **현재 인증 주체에 대한 응답 필드**일 뿐이며, 관리자 override 가능성에 대한 증명이 아니다. 우회 시도를 실제로 수행하는 것은 파괴적이므로 본 관측 범위 밖이다.

## §10. 재현 명령

```console
gh api orgs/Archright
gh api repos/Archright/Axiom
gh api orgs/Archright/rulesets                      # 403 expected under Free
gh api repos/Archright/Axiom/rulesets
gh api "repos/Archright/Axiom/rulesets?includes_parents=true&per_page=100"
gh api repos/Archright/Axiom/rulesets/27097366
gh api repos/Archright/Axiom/rulesets/27525972
gh api repos/Archright/Axiom/rules/branches/main
gh api /apps/axiom-admission-verifier
gh api repos/Archright/Axiom/pulls/204
gh api "repos/Archright/Axiom/issues/204/timeline?per_page=100" -H "Accept: application/vnd.github+json"
gh api repos/Archright/Axiom/actions/runs/44481531363
gh api repos/Archright/Axiom/actions/runs/44481531363/jobs
gh api repos/Archright/Axiom/actions/runs/44481531363/artifacts
gh api repos/Archright/Axiom/actions/artifacts/14509082548/zip
gh api repos/Archright/Axiom/commits/7b1c0c35351be04416066fbdf35a1f517de4151e
gh api "repos/Archright/Axiom/commits/7b1c0c35351be04416066fbdf35a1f517de4151e/check-runs?per_page=100"
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100"
```