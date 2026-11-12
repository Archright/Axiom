# gh_app_identity_resolution_quirks — GitHub App 숫자 id → 신원 해석 채널의 판별력 한계

> 기록 계약: AGENTS.md §0.5 Quirk Mandate. 실측: 2026-10-22 (GPA Phase 0
> baseline authorities §1.3·§1.4의 11경로 전수 실패에 대한 A5 재조사).
> 추가 실측: 2026-10-30 (org 설치 App 인벤토리 재관측 — Q3 표류 기록).
> 본 문서는 관측된 GitHub API 행동의 기록이며, 극장 아님: 모든 항목에
> **실측 명령과 기대 출력**을 병기한다. 형식 선행 사례:
> `docs/spec/github_ruleset_api_quirks.md`, `docs/spec/gh_run_observation_quirks.md`.

**Discovered**: 2026-10-22 (bypass integration `29110` 신원 미확정 상태에서
GitHub App id → 신원 해석 경로 전수 조사)
**Class**: external service (GitHub REST/GraphQL API) — App 신원 조회 계열
**인증 실측 조건**: `gh` CLI, classic PAT(scopes: `admin:enterprise, admin:org,
gist, repo, workflow`), 호출자는 대상 repository와 organization의 admin.
**적용 대상**: `Archright/Axiom` — push ruleset `23967915`
(name=`execution-surface-create`)의 bypass actor `Integration 29110`.

---

## Q1 — REST `GET /apps/{app_id}`는 slug 전용이다 (숫자 id를 넣으면 404 — 판별력 0)

### Symptom

GitHub App의 **숫자 app id**로 앱을 조회하려는 자연스러운 시도
(`GET /apps/29110`)는 **404**를 반환한다. 더구나 **공개 앱**(GitHub Actions
`15368`)조차 404를 반환하므로, 이 404는 "비공개/내부 앱"이라는 해석을
**지지 않는다** — 관측값 하나로는 아무것도 판별할 수 없다.

```
$ gh api /apps/29110
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/apps/apps#get-an-app","status":"404"}

$ gh api /apps/dependabot
{"id":29110,"client_id":"Iv1.4f9a6346434f815e","slug":"dependabot",
 "owner":{"login":"github","id":9919,...},"name":"Dependabot",...}
```

### 원인

`GET /apps/{app_slug}`는 **slug 전용** 엔드포인트다. 경로 파라미터가
`app_slug`이며 숫자 id를 넣으면 slug 일치 실패 → 404. 즉 404는
**엔드포인트의 성질이 아니라 호출 방식의 문제**다. (공개 앱은 slug로 정상
동작한다 — 공개 여부는 판별 요인이 아니다.)

### 해법 — GraphQL `Query.node(id:)`로 `App` 오브젝트 해석

GitHub GraphQL에는 `App` 오브젝트 타입이 존재하고, `Query.node(id:)`가
**레거시 전역 ID `base64("03:App<app_id>")`** 로 App을 해석한다. 이 채널은
**숫자 app id를 직접 받아** 신원을 반환하므로 판별력이 있다.

```bash
ID=$(printf '03:App29110' | base64)          # → MDM6QXBwMjkxMTA=
gh api graphql -f query="query { node(id: \"$ID\") { ... on App {
  databaseId name slug clientId url createdAt updatedAt description } } }"
```

실측 출력 (2026-10-22):

```json
{"data":{"node":{"databaseId":29110,"name":"Dependabot","slug":"dependabot",
 "clientId":"Iv1.4f9a6346434f815e","url":"https://dependabot-api.githubapp.com",
 "createdAt":"2019-04-16T22:34:25Z","updatedAt":"2026-04-27T17:22:53Z",
 "description":"GitHub Dependabot"}},
 "extensions":{"warnings":[{"type":"DEPRECATION",
   "message":"The id MDM6QXBwMjkxMTA= is deprecated. Update your cache to use the next_global_id from the data payload.",
   "data":{"legacy_global_id":"MDM6QXBwMjkxMTA=","next_global_id":"A_kwHNJr_NcbY"}}]}}
```

- 레거시 전역 ID는 deprecated 경고를伴는다. 신규 전역 ID(`next_global_id`,
  예: `A_kwHNJr_NcbY`)를 캐시에 보관할 것.
- `App` 타입의 introspection 필드(2026-10-22 실측):
  `clientId, createdAt, databaseId, description, id, ipAllowListEntries,
  logoBackgroundColor, logoUrl, name, slug, updatedAt, url`.
- `Organization.installedApps` 필드는 **존재하지 않는다**
  (`undefinedField`) — org 설치 목록의 대체 경로가 아니다.

### 통제 실험 (판별력 입증 — 3건)

위 채널이 "임의의 숫자를 남의 앱으로 오매칭하는" 경로가 아님을 **양성 대조**로
입증한다. **기지의 정체 3건이 동일 채널로 정확히 재현되어야** 이 채널을
신원 판정 근거로 채택할 수 있다.

```bash
for id in 15368 4879411 5082347; do
  nid=$(printf "03:App%s" "$id" | base64)
  gh api graphql -f query="query { node(id: \"$nid\") { ... on App {
    databaseId name slug clientId } } }"
done
```

기대 출력 (2026-10-22 실측):

| app_id | 기지의 정체 | 기대 출력 |
|---|---|---|
| `15368` | GitHub Actions (공개) | `databaseId=15368 name="GitHub Actions" slug=github-actions` |
| `4879411` | `axiom-ci-elastic` (private, 신원 확정) | `databaseId=4879411 name=axiom-ci-elastic slug=axiom-ci-elastic` |
| `5082347` | `axiom-release-authority` (private, 신원 확정) | `databaseId=5082347 name=axiom-release-authority slug=axiom-release-authority` |
| `29110` | 미상 → **Dependabot** | `databaseId=29110 name=Dependabot slug=dependabot` |
| `2781` | (과거 문서가 "Dependabot"으로 기재) | `{"data":{"node":null},"errors":[{"type":"NOT_FOUND", ...}]}` |

**음성 대조도 함께 돌릴 것.** `2781`은 `NOT_FOUND`를 반환한다 — 즉 과거
`data/promotions/baseline/authorities.md` §1.4의 "`2781` = Dependabot(공개)"은
**오기**였고, Dependabot의 실제 app id는 `29110`이다. 음성 대조가 없으면
"이 채널이 아무 id나 어떻게든 해석해 낸다"는 반론을 배제할 수 없다.

### 부수 주의 — id 공간 충돌 (오판 방지)

App id와 User id는 **같은 전역 id 공간**에서 발급된다. `GET /user/29110` →
`{"login":"wherewegonow","id":29110}` — 즉 `29110`은 동시에 *사용자* id로도
존재한다. ruleset의 `actor_type: "Integration"`은 **App id**를 가리킨다는
점(통제: `4879411`/`5082347`이 App id와 일치)이 해석의 전제다.

---

## Q2 — GitHub 소유(GitHub-owned) 앱은 `GET /orgs/{org}/installations`에 등재되지 않는다

### Symptom

org 설치 목록을 전수 조회하면 `total_count=2`가 나오고, ruleset bypass actor인
`Integration 29110`이 **목록에 없다**. 자연스러운 추론은 "이 org에 설치되지
않았으니 Axiom에서도 권한이 없겠지"다 — **이 추론은 틀렸다.**

```
$ gh api /orgs/Archright/installations --paginate \
    --jq '.total_count, (.installations[] | {app_id, app_slug, repository_selection})'
2
{"app_id":4879411,"app_slug":"axiom-ci-elastic","repository_selection":"all"}
{"app_id":5082347,"app_slug":"axiom-release-authority","repository_selection":"selected"}
```

### 원인

`GET /orgs/{org}/installations`는 **org에 *설치된* App**을 열거한다.
GitHub 소유 앱(Dependabot, GitHub Actions 등)은 org의 설치 레코드를 갖지
**않음**이므로 목록에 나타나지 않는다. 즉 `total_count`는
"이 org에서 동작하는 모든 GitHub App"의 개수가 **아니다**.

### 실측 반증 — 목록에 없지만 실제로는 동작한다

`29110`(Dependabot)은 org 설치 목록에 부재함에도:

- `GET /repos/Archright/Axiom/dependabot/alerts` → **HTTP 200**(활성 — 비활성이면 403)
- `GET /repos/Archright/Axiom/pulls/910` → `merged: true`,
  `user: dependabot[bot]`, head `dependabot/github_actions/actions/create-github-app-token-3.3.0`
- `GET /repos/Archright/Axiom/pulls/910/files` → 수정 파일이
  `.github/workflows/diagnostic-authority.yml`, `.github/workflows/release-ship.yml`
- 이 두 경로는 push ruleset `23967915`의
  `file_path_restriction` restricted 목록(`.github/workflows/**/*`,
  `.github/actions/**/*`)에 **포함**된다 → push가 ruleset에 걸리지 않으려면
  bypass actor로 등록되어 있어야 하고, 실제로 등록되어 있다.

→ **"설치 목록에 없다"는 부재 증거가 아니다.** 더 강하게는, "설치 목록에 없다"는
**우회 권한 부재의 증거가 되지 못한다.**

### 그 밖의 installations 조회는 왜 막히는가 (JWT 경계)

| 경로 | 결과 | 사유 |
|---|---|---|
| `GET /user/installations` | 403 "You must authenticate with an access token authorized to a GitHub App…" | 사용자 PAT은 App installation 토큰이 아니다 |
| `GET /repos/{owner}/{repo}/installation` | 401 "A JSON web token could not be decoded" | App JWT 필요 |
| `GET /orgs/{org}/installations/{id}/repositories` | 404 | **존재하지 않는 경로** (이 404는 판별력 있음 — 경로 자체가 없음) |
| `GET /installation/repositories` | App JWT 필요 | repo 선택 목록의 유일한 정공 경로 |

`repository_selection=selected`인 설치의 **구체적 저장소 목록**은 App JWT가
필요하므로 사용자 PAT로는 조회할 수 없다 → 이 항목은 **운영자(인간) 확인
항목**으로 남겨야 하며, "확인됨"으로 기록해서는 안 된다.

---

## Q3 — 설치 인벤토리 표류(drift): 2026-10-22 기록 2건 → 2026-10-30 실측 5건

### Symptom [measured 2026-10-30]

2026-10-30, Q2와 동일한 채널(`GET /orgs/Archright/installations`)을 재관측하면
`total_count=5`다 — 2026-10-22 실측(Q2)의 2건에서 3건이 늘었다.

```
$ gh api /orgs/Archright/installations --paginate \
    --jq '.total_count, (.installations[] | {id, app_id, app_slug, repository_selection, permissions, created_at})'
5
{"app_id":4879411,"app_slug":"axiom-ci-elastic","created_at":"2026-09-09T09:55:49.000+09:00","id":160192931,"permissions":{"actions":"read","checks":"read","contents":"write","metadata":"read","organization_self_hosted_runners":"write","pull_requests":"read"},"repository_selection":"all"}
{"app_id":5082347,"app_slug":"axiom-release-authority","created_at":"2026-09-26T13:44:11.000+09:00","id":165035395,"permissions":{"contents":"write","metadata":"read"},"repository_selection":"selected"}
{"app_id":387324,"app_slug":"ubicloud-managed-runners","created_at":"2026-10-23T14:11:28.000+09:00","id":174366215,"permissions":{"actions":"write","administration":"write","metadata":"read","organization_self_hosted_runners":"write"},"repository_selection":"all"}
{"app_id":5438756,"app_slug":"axiom-ci-provider-router","created_at":"2026-10-23T17:11:54.000+09:00","id":174407656,"permissions":{"actions_variables":"write","metadata":"read"},"repository_selection":"selected"}
{"app_id":68272,"app_slug":"northflank-cloud-build-run","created_at":"2026-10-26T12:30:50.000+09:00","id":175323502,"permissions":{"administration":"write","checks":"write","contents":"write","deployments":"write","members":"read","metadata":"read","organization_hooks":"write","pull_requests":"write","repository_hooks":"write","statuses":"write"},"repository_selection":"all"}
```

요약 표 (설치일은 `created_at`의 날짜 부분):

| installation id | app_id | app_slug | repository_selection | permissions | 설치일 |
|---|---|---|---|---|---|
| `160192931` | `4879411` | `axiom-ci-elastic` | all | actions:read, checks:read, contents:write, metadata:read, organization_self_hosted_runners:write, pull_requests:read | 2026-09-09 |
| `165035395` | `5082347` | `axiom-release-authority` | selected | contents:write, metadata:read | 2026-09-26 |
| `174366215` | `387324` | `ubicloud-managed-runners` | all | actions:write, administration:write, metadata:read, organization_self_hosted_runners:write | 2026-10-23 |
| `174407656` | `5438756` | `axiom-ci-provider-router` | selected | actions_variables:write, metadata:read | 2026-10-23 |
| `175323502` | `68272` | `northflank-cloud-build-run` | all | administration:write, checks:write, contents:write, deployments:write, members:read, metadata:read, organization_hooks:write, pull_requests:write, repository_hooks:write, statuses:write | 2026-10-26 |

### 표류 판정 — 2026-10-22 기준 기록 대비

- `data/promotions/baseline/authorities.md` **Amendment 1**(2026-10-22)이
  기록한 org 설치는 2건뿐이었다: `4879411`(`axiom-ci-elastic`),
  `5082347`(`axiom-release-authority`) — 본 문서 Q2 실측과 동일하다.
- 그 이후 설치된 3건은 기준 문서에 **기록되지 않은 채** 운영 중이었다.
  본 절이 세 앱의 숫자 app id와 설치일을 기록한다:

  | app_id | app_slug | 설치일 |
  |---|---|---|
  | `387324` | `ubicloud-managed-runners` | 2026-10-23 |
  | `5438756` | `axiom-ci-provider-router` | 2026-10-23 |
  | `68272` | `northflank-cloud-build-run` | 2026-10-26 |

  개별 신원의 독립 확정이 필요하면 Q1의 GraphQL `node(id:)` 채널(숫자 app id
  직접 해석)을 사용한다 — slug 전용 REST 표면(`GET /apps/{app_id}`)으로는
  숫자 id를 판별할 수 없다(Q1).

### 해석 경계 (Q2 원칙의 유지)

- 이 목록은 여전히 **"설치된 App" 표면**이다. GitHub 소유 앱은 등재되지
  않으므로 `total_count=5`는 "이 org에서 동작하는 모든 GitHub App"의 개수가
  **아니다** — `29110`(Dependabot)은 2026-10-30 재관측에서도 목록에 없다.
- `repository_selection=selected` 2건(`axiom-release-authority`,
  `axiom-ci-provider-router`)의 구체적 저장소 목록은 App JWT가 필요하므로
  사용자 PAT로 조회할 수 없다 — 운영자 확인 항목으로 남는다(Q2 표).

---

## 교훈 — "조회 실패"를 "존재하지 않음"으로 읽지 말 것

**원칙.** 조회 경로의 실패는 **그 경로의 성질**에 대한 관측이지, 대상의 부재에
대한 관측이 아니다. 부재를 주장하려면 다음 3단계를 모두 통과해야 한다.

1. **채널의 성질을 먼저 특정한다.** 그 경로가 무엇을 담는 표면인가
   (예: `GET /apps/{slug}` = slug 전용 표면 / `GET /orgs/{org}/installations`
   = *설치된* App 표면). 호출 방식 오류(예: slug 엔드포인트에 숫자 id)를
   부재 증거로 쓰지 않는다.
2. **양성 대조로 판별력을 입증한다.** 판정 대상과 **기지의 정체**를 같은
   채널로 조회해 정확히 재현되는지 확인한다. 재현되지 않으면 그 채널은
   판정 근거가 아니다.
3. **음성 대조로 오매칭·무해석을 배제한다.** 알려진 비대상 id가 실제로
   `NOT_FOUND`(또는 동등한 무해석 신호)를 내는지 확인한다.

**이 원칙이 왜 필요한가 — 실측 사례 3건 (모두 "조회 실패 = 부재" 오독).**

| 잘못된 추론 | 왜 틀렸는가 |
|---|---|
| "`GET /apps/29110` 404 → 비공개/내부 App" | slug 전용 엔드포인트에 숫자 id를 넣었다. slug(`/apps/dependabot`)로 부르면 200. 404는 호출 방식의 산물 |
| "`GET /apps/{id}`가 404 → 공개 앱(15368)도 404 → 이 엔드포인트는 판별력 없다" | 관측(404)은 맞고 **해석**이 틀렸다. 판별력 부재는 엔드포인트가 아니라 호출 방식의 문제였고, GraphQL `node(id:)` 채널은 판별력이 있다 |
| "`GET /orgs/{org}/installations`에 없음 → 우회 권한 없음" | GitHub 소유 앱은 org 설치 목록에 등재되지 않는다. 실제 Dependabot은 목록에 없으면서 우회 권한을 **실사용**했다(PR 910 병합) |

**추가 원칙 — 존재하지 않는 경로의 404는 다른 404와 구분한다.**
`GET /orgs/{org}/installations/{id}/repositories`의 404는 "경로가 존재하지
않는다"는 의미이므로 **재시도해도 결과가 변하지 않는다**(재시도 금지 대상).
반면 "권한/JWT 부족"으로 인한 401/403과 "요청 형식 오류"로 인한 404는
**채널을 바꿔서** 재시도해야 한다. 경로 목록을 전수 시도한 뒤에도 판정이
안 서면, **같은 채널의 다른 표현**(REST → GraphQL, id → slug, id → 전역 ID)을
찾아야 하며 "조회 실패 = 부재"로 닫으면 안 된다.

**기록 위치.** 본 quirk의 구체적 적용(29110 = Dependabot, 5082347 =
axiom-release-authority, 2781 오기 정정, 이전 음성 추론 2건의 무효화)은
`data/promotions/baseline/authorities.md`의 **Amendment 1 부록**에 있다.
본 문서는 채널·판별력의 일반 교훈을 담는다.

---

## 관련 문서

- `docs/spec/github_ruleset_api_quirks.md` — ruleset REST 쓰기/GraphQL 표면의
  quirks (bypass_actors 읽기·쓰기 경로 성격)
- `docs/spec/gh_run_observation_quirks.md` — GitHub Actions 런 관측 계층의
  quirks (readback 경로의 성격 구분 태도)
- `docs/spec/gh_org_required_workflow_run_quirks.md` — org required workflow
  런 관측의 quirks
