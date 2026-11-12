# GitHub Ruleset API Quirks (REST 쓰기 경로 404 / GraphQL mutation 표면)

> AGENTS.md §0.5 Quirk Mandate — 발견 시각 2026-10-10, 발견 위치:
> merge queue 필수 저장소에서 회전성 PR(trust-surface/정책 자기편집)의
> 비상 창 절차(3-ruleset 동시 비활성 → 병합 → 복원) 실측. 본 문서는 관측된
> GitHub API 행동의 기록이며, 극장 아님: 모든 항목에 실측 명령과 공식 문서
> 근거를 병기한다. 형식 선행 사례: `docs/spec/gh_org_required_workflow_run_quirks.md`.

**Discovered**: 2026-10-10 (ruleset 비상 창 절차 실측)
**Class**: external service (GitHub REST/GraphQL API) — ruleset 쓰기 계열
**인증 실측 조건**: `gh` CLI, classic PAT(scopes: `admin:enterprise, admin:org,
gist, repo, workflow`), 호출자는 대상 repository와 organization의 admin.

## Q1: REST ruleset 갱신 PATCH → HTTP 404 (동일 토큰의 GET은 200)

### Symptom

동일 토큰에서 ruleset **조회(GET)는 정상**이고 **쓰기(PATCH)는 404**로
차단된다. 레이블 생성 등 일반 쓰기는 같은 토큰으로 정상 → 자격 증명·권한
문제가 아니라 ruleset 쓰기 계열(메서드/경로)만의 행동이다.

```
$ gh api repos/Archright/Axiom/rulesets/20303214            → 200 (정상 응답)
$ gh api orgs/Archright/rulesets/24233738                   → 200 (정상 응답)
$ gh api -X PATCH repos/Archright/Axiom/rulesets/20303214 \
    -f enforcement=disabled                                 → HTTP 404 Not Found
```

- 404는 전송 방식과 무관하게 재현: `-f`(form 필드), `--input`(JSON 본문),
  `X-GitHub-Api-Version` 헤더 명시 모두 동일한 404.
- 무해 필드(`description`)만 고치는 PATCH도 404 — 본문 내용과 무관.
- `GET …/rulesets/{id}/versions` 서브리소스도 404.

### Cause (공식 문서가 말하는 것 vs 실측)

- **문서화된 갱신 동사는 PATCH가 아니라 PUT이다.** REST 레퍼런스는
  repository ruleset 갱신을 `PUT /repos/{owner}/{repo}/rulesets/{ruleset_id}`
  ("Update a repository ruleset"), organization ruleset 갱신을
  `PUT /orgs/{org}/rulesets/{ruleset_id}`로 문서화하며, PATCH는 어디에도
  ruleset 경로의 메서드로 등장하지 않는다. 즉 PATCH 404는 문서와 모순되는
  관측이 아니라 **미문서화 메서드의 미라우팅**으로 정합적이다 — "REST 쓰기가
  막혔다"가 아니라 "PATCH는 ruleset의 문서화된 동사가 아니다"가 정확한 서술이다.
- **GitHub는 권한 부족을 403이 아니라 404로 응답할 수 있다**(troubleshooting
  문서: 존재를 부인하기 위해 404 사용, `X-Accepted-GitHub-Permissions` 응답
  헤더로 요구 권한 확인 가능). 따라서 404 단독으로는 원인을 특정할 수 없다.
  그러나 본 실측은 **동일 토큰에서 GET 200 + GraphQL mutation 성공**을 함께
  관측했으므로, 이 404는 자격 증명/권한 실패가 아니다(권한 실패라면 GraphQL
  쓰기도 실패해야 한다).
- `…/versions` 404는 quirk가 아니다: REST 레퍼런스가 문서화하는 이력
  서브리소스는 `/history`(repo: `GET /repos/{owner}/{repo}/rulesets/{ruleset_id}/history`,
  org 동형)이며 `/versions`는 등재되어 있지 않다.

### 측정 경계 (fail-closed)

REST **PUT** 갱신 경로는 이 세션에서 실측하지 않았다(ruleset 실제 조작은
문서화 작업 범위 밖 금지). 문서화된 동사이므로 동작 가능성이 있으나,
**실측 없이 동작을 단정하지 않는다** — §0.9 검증 불가 주장 금지. 실측으로
확인된 쓰기 경로는 아래 Q2의 GraphQL뿐이다.

## Q2: GraphQL `updateRepositoryRuleset` — repo·org ruleset 공용 쓰기 경로 (실측)

### Symptom (동작한다)

같은 토큰으로 GraphQL mutation은 성공한다. 정확한 실측 형태:

```graphql
mutation {
  updateRepositoryRuleset(input: {
    repositoryRulesetId: "<node_id>"
    enforcement: DISABLED   # 또는 ACTIVE
  }) {
    ruleset { id enforcement }
  }
}
```

- repo ruleset node_id(`RRS_…`)뿐 아니라 **org ruleset node_id도 같은
  mutation으로 처리된다.**
- **`updateOrganizationRuleset` mutation은 스키마에 존재하지 않는다**
  (introspection으로 확인). org ruleset 갱신의 유일한 GraphQL 표면이 이
  mutation이다 — 이름에서 org 전용 mutation을 찾으면 실패한다.
- 실측 절차: 3-ruleset(저장소 2 + 조직 1) 동시 `DISABLED` → 병합 → `ACTIVE`
  복원. 감사는 ruleset history(REST `…/rulesets/{id}/history`, 공식 문서화
  엔드포인트)로 수행.

### 공식 문서 근거

GraphQL 레퍼런스는 `updateRepositoryRuleset`를 문서화한다: 입력
`RepositoryRulesetUpdateInput`의 필수 필드는 `repositoryRulesetId: ID!`
("The global relay id of the repository ruleset to be updated"), 선택 필드에
`enforcement`(RuleEnforcement), `name`, `conditions`, `bypassActors`, `rules`,
`target` — 부분 갱신(입력에 준 필드만 변경)이 계약이다. REST PUT은 전체
본문 교체인 것과 대비된다.

## 차이 요약 (문서 vs 실측)

| 항목 | 공식 문서 | 실측 (2026-10-10) |
|---|---|---|
| repo ruleset 조회 | `GET /repos/{owner}/{repo}/rulesets/{ruleset_id}` | `gh api repos/.../rulesets/20303214` → 200 |
| org ruleset 조회 | `GET /orgs/{org}/rulesets/{ruleset_id}` | `gh api orgs/Archright/rulesets/24233738` → 200 |
| repo ruleset 갱신 | `PUT /repos/{owner}/{repo}/rulesets/{ruleset_id}` (전체 본문) | **미실측** — 실측 없이 단정 금지 |
| org ruleset 갱신 | `PUT /orgs/{org}/rulesets/{ruleset_id}` (전체 본문) | **미실측** |
| PATCH 갱신 | 미문서화 (ruleset 경로에 PATCH 없음) | 404 (`-f`/`--input`/api-version 모두, 무해 필드 PATCH 포함) |
| 이력 | `…/rulesets/{id}/history` 문서화 | `/versions` → 404 (미문서화 경로라 정합) |
| GraphQL 갱신 | `updateRepositoryRuleset`(`repositoryRulesetId: ID!`) | 성공 — repo·org node_id 모두 |
| org 전용 GraphQL mutation | (레퍼런스에 없음) | `updateOrganizationRuleset` 스키마 부재 (introspection) |

## Deterministic rule (sanctioned 경로)

1. ruleset **쓰기**가 필요하면 GraphQL `updateRepositoryRuleset`(실측 경로)를
   쓴다. org ruleset도 동일 mutation이다 — `updateOrganizationRuleset`를
   찾지 않는다. REST PATCH는 쓰기 경로가 아니다(미문서화 메서드, 실측 404).
2. REST 갱신이 필요하면 PATCH가 아니라 **문서화된 PUT**(전체 본문)으로
   시도하되, 실측 전에는 결과를 단정하지 않는다(위 측정 경계).
3. ruleset 이력·감사 조회는 REST `…/rulesets/{id}/history`다. `/versions`는
   존재하지 않는다.

## 비상 창 절차 사용 시 의무 (HARD RULE)

merge queue 필수 저장소에서 회전성 PR(trust-surface/정책 자기편집)이 큐 판정으로
구조적으로 착지 불가할 때 ruleset 비활성 창을 쓰는 절차는 다음을 준수한다:

- **감사 기록 의무**: 비활성·복원 각각에 대해 수행 시각·ruleset id·node_id·
  변경 전후 enforcement·수행 사유를 실행 증거(`docs/evidence/`)에 기록한다.
  GitHub 자체 감사 추적(ruleset history)도 함께 확인한다.
- **기한(창 종료 시점)**: 위 기록은 **창을 닫는 절차 안에서** 만들어진다 —
  복원 readback과 동시에 `docs/evidence/` 파일을 작성한다. 사후에 "기억나서"
  남기는 기록은 의무 이행이 아니다. **로컬 세션 트랜스크립트는 내구 기록이
  아니다**(저장소 밖·미공개) — 1차 원천이 그것뿐이었다면, 복구 시점에 그
  사실을 **관측 공백**으로 그대로 적어야 하고, 그 공백은 이행이 아니다.
  선례: 2026-10-20 24초 창 — 복원은 관측되었으나 기록이 약 1일 뒤에야
  생성되었다: [incident_emergency_disable_window_2026-10-20.md](../evidence/incident_emergency_disable_window_2026-10-20.md).
- **복원 검증 의무**: 병합 후 모든 ruleset을 원래 enforcement로 복원하고,
  GET(또는 history)으로 **관측된** 복원 결과를 증거로 남긴다. "복원했다"는
  주장이 아니라 복원 상태의 관측 기록이 완료 조건이다.
- **창 최소화**: 창은 병합에 필요한 최소 시간만 유지하고, 대상 ruleset 외에
  건드리지 않는다(§0.12 최소 변경).

## References (공식 문서)

- REST — Update a repository ruleset (PUT, 전체 본문; enforcement: disabled/active/evaluate):
  https://docs.github.com/en/rest/repos/rules
- REST — Update an organization repository ruleset (PUT):
  https://docs.github.com/en/rest/orgs/rules
- REST — Get repository ruleset history (문서화된 이력 서브리소스):
  https://docs.github.com/en/rest/repos/rules
- REST — Troubleshooting: 404 Not Found의 의미(권한 부족 시 403 대신 404,
  `X-Accepted-GitHub-Permissions` 헤더):
  https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api
- GraphQL — `updateRepositoryRuleset` 입력 계약(`repositoryRulesetId: ID!`,
  `enforcement` 등 부분 갱신 필드):
  https://docs.github.com/en/graphql/reference/mutations
- Ruleset enforcement statuses (Active/Disabled 개념):
  https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets

## 수정 (2026-10-15) — 정본 쓰기 경로 확정과 관측 이력 정리

> 위 원문(2026-10-10 실측)은 관측 기록으로 그대로 유지된다. 본 절은 이후 확정된
> 사실과 정책을 덧붙이는 것이며 원문을 개정하지 않는다. 배경 계약:
> [admission-generation.md](admission-generation.md) §5(Slice A ruleset SHA pinning).

1. **정본(정책) 쓰기 경로는 문서화된 REST `PUT /orgs/{org}/rulesets/{ruleset_id}`다** —
   workflows 규칙의 `WorkflowFileReference {path, repository_id, sha}`에 **`sha` 결속**
   (`ref` 제거)을 넣는 형태. admission 세대 전환(S4)의 정본 페이로드는
   `admission-generation.md` §5.3이 규정하며, 실측 불성립 시 폴백은 Q2의 GraphQL
   `updateRepositoryRuleset`(repo·org node_id 공용 — 변화 없음)이다.
2. **위 Q1 "측정 경계"(REST PUT 미실측 — 단정 금지)는 유지된다.** 관측 이력은 세 시기로
   나뉜다: (i) 2026-09-30 — sha 포함 PUT 재핀이 **성공**한 실측
   (`docs/evidence/ci_toolchain_scope_2026-09-30.md` §6 재핀 행);
   (ii) 2026-09-30/10-01 — 동일 경로가 **HTTP 500**으로 실패한 실측(7페이로드 변형 —
   `docs/evidence/epoch_record_oracle_select_2026-09-30.md` §8.3) → sha-less `ref: main`
   재등록(ruleset 24233738)으로 대체; (iii) 2026-10-15 현재 — 양 org ruleset(24233738·
   23943917)은 `sha` 부재 `ref: main` 상태
   (`docs/evidence/admission_generation_freeze_2026-10-15.md` §3 verbatim).
   즉 sha-bearing PUT은 시기에 따라 성공·실패가 **엇갈려 관측된 채널**이다 — 현재 era에서
  의 동작은 S4의 PUT+readback 관측이 첫 실측이며, 그 전까지 본 문서의 fail-closed 원칙
   (§0.9 검증 불가 주장 금지)은 그대로 적용된다.
3. **PATCH 404 서술의 정확한 지위(원문 Cause 절 확인)**: 원문은 이미 "PATCH는 ruleset의
   문서화된 동사가 아니다"로 서술되어 있어 본 수정으로의 이동 대상이 아니다 — 본 절은
   이 서술을 **확인**만 한다. `/versions` 404·GraphQL 표면 관측도 원문 그대로 유효하다.
4. **ref: main 핀 자체가 결함으로 판정**되었다(컨트롤러 main 전진이 강제 경계를 무음으로
   변경 — `admission-generation.md` §7 폐기된 등식 2). ref: main으로의 복원·재진입은
   `admission-generation.md` §5.7 롤백 행렬에서 **금지**된다. S4 이후 ruleset readback
   결과의 실측 반영은 본 문서의 후속 개정으로 수행한다.

