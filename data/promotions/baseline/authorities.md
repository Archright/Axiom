# 권한·신원 실측 (GPA Phase 0 § authorities) — bypass integration / org ruleset 가독성

- 관측 시각(UTC): **2026-10-21T18:42:35Z** (KST 2026-10-22 03:42:35)
- 관측 수단: `gh api` (read-only) + `gh run view --log` (read-only)
- 저장소 트리 미변경 / 브랜치·워크트리 미생성

---

## 1. bypass integration 29110 / 4879411 신원 식별

### 1.1 결론 표

| actor_id | actor_type | 판정 | 근거 |
|---|---|---|---|
| **4879411** | Integration | **확정 — `axiom-ci-elastic`** | `GET /orgs/Archright/installations` 실측: `app_id=4879411`, `app_slug=axiom-ci-elastic`, installation_id `160192931` |
| **29110** | Integration | **UNRESOLVED / UNREADABLE** | 아래 §1.3의 11개 경로 전부 실패. **추측값 기록 금지 → 확정 불가로 남김** |

### 1.2 4879411 = `axiom-ci-elastic` (확정)

`GET /orgs/Archright/installations?per_page=100` → `total_count=2` (전량):

```json
{
  "id": 160192931, "app_id": 4879411, "app_slug": "axiom-ci-elastic",
  "target": {"login": "Archright", "type": "Organization"},
  "repository_selection": "all",
  "permissions": {"checks":"read","actions":"read","contents":"write",
                  "metadata":"read","pull_requests":"read",
                  "organization_self_hosted_runners":"write"},
  "events": [], "suspended_by": null, "suspended_at": null,
  "created_at": "2026-09-09T09:55:49.000+09:00",
  "updated_at": "2026-09-16T20:05:53.000+09:00",
  "html_url": "https://github.com/organizations/Archright/settings/installations/160192931"
}
{
  "id": 165035395, "app_id": 5082347, "app_slug": "axiom-release-authority",
  "repository_selection": "selected",
  "permissions": {"contents":"write","metadata":"read"},
  "created_at": "2026-09-26T13:44:11.000+09:00"
}
```

**4879411은 app_id이며 installation_id가 아니다**(installation_id는 160192931). 즉 ruleset `bypass_actors[].actor_id`는 **App id**를 담는다 — 실측 사실.

저장소 측 교차 확인(모두 `origin/main` 트리):
- `config/app_landing_binding.json`: `"app_id": "4879411"`, `"installation_id": "160192931"`, `"status": "READY"` — 일치.
- `docs/spec/merge_authority_integrity.md:128-129`: "선언된 Landing App = app id `4879411` (installation_id `160192931`), slug `axiom-ci-elastic`" — 일치.
- `docs/evidence/ghec_ruleset_p1c_bypass_2026-09-24.md:13`: 동일 값 — 일치.

권한 해석: 이 App은 `contents:write` + `organization_self_hosted_runners:write`를 가진다. 즉 **bypass 권한은 "main push 불가"가 아니라 "push ruleset 23967915의 file_path_restriction을 우회할 수 있음"**이며, 동시에 `refs/heads/main` 갱신 권한(landing authority)까지 가진다. → GPA 관점: **잔여 위험 1순위** (§4).

### 1.3 29110 — 시도한 경로와 결과 (모두 실패)

| # | 경로 | 결과 | 해석 |
|---|---|---|---|
| 1 | `GET /orgs/Archright/installations?per_page=100` | 200, `total_count=2` — **29110 없음** | Archright org에 설치된 App은 2개뿐(4879411, 5082347). 29110은 org 설치가 아님 |
| 2 | `GET /apps/29110` | **404** | GitHub App 정보 미반환. **단, 대조 실험에서 이 엔드포인트는 판별력이 없음**(아래 §1.4) |
| 3 | `GET /app?app_id=29110` | **401** "A JSON web token could not be decoded" | `gh`의 사용자 PAT는 App JWT가 아니므로 `/app*` 계열은 JWT가 요구됨 |
| 4 | `GET /users/wintrover/installations` | **404** | 동일 계측(응답 본문 "Not Found") — JWT 요구 경로 |
| 5 | `GET /user/installations` | **403** "You must authenticate with an access token authorized to a GitHub App in order to list installations" | 사용자 토큰으로는 App 설치 목록 조회 불가 |
| 6 | `GET /repos/Archright/Axiom/installation` | **401** "A JSON web token could not be decoded" | repo 단위 설치 조회는 JWT 필요 → **Axiom 저장소 설치 목록 조회 경로로 사용 불가** |
| 7 | `GET /orgs/Archright/installation` | **401** (동일 사유) | 동일 |
| 8 | `GET /orgs/Archright/installations/29110` | **404** | — |
| 9 | `GET /installations/29110` | **404** | — |
| 10 | `GET /orgs/Archright/installations/{160192931}` | **404** | org 수준 단일 installation 상세 엔드포인트는 이 토큰에서 동작 안 함(인증/권한) |
| 11 | `GET /orgs/Archright/installations/{id}/repositories` | **404** (양 installation 모두) | repo 선택 목록 조회 불가 |

**추가 관찰 (부정적 증거)**
- Axiom 저장소의 최근 40개 main 커밋에 대한 **check-suite app id 전수**: 단일 값 `15368 (github-actions)` 694건뿐. → **29110은 이 저장소에서 check을 생산한 적이 없다**(최근 40커밋 구간).
- `GET /user/orgs` → 사용자가 속한 org는 **Archright 하나뿐**. → 다른 org에 설치된 App일 가능성 배제(사용자 계정 설치는 남음).
- `GET /repos/Archright/Axiom/hooks` → **빈 배열**(webhook 없음). `GET /orgs/Archright/hooks` → 404(`admin:org_hook` scope 필요).
- 저장소 문서 내 29110 언급 2곳(둘 다 **신원 미기재**, ID 나열만):
  - `docs/adr/0027-queue-delegation.md:35` — "bypass = OrganizationAdmin + Integration 29110·4879411"
  - `docs/evidence/merge_freeze_spoof_probe_2026-10-12.md:46` — "`Integration 29110`, `Integration 4879411` — API 응답 `current_user_can_bypass: \"always\"`"
  - `git log -S "29110"` 최초 등장 = `c9550c40… @ 2026-04-29` (ID는 오래전부터 문서에 존재했으나 **어떤 App인지 한 번도 특정된 적 없음**).

> **UNREADABLE: bypass integration 29110의 신원(어떤 GitHub App인지).**
> 원인: ① `GET /apps/{app_id}`는 비공개 App에서 404를 반환하며, 대조 실험상 이 환경에서는 공개 App(GitHub Actions 15368)조차 404를 반환 → 판별 불가. ② App 설치 목록 전수 조회는 JWT(Installation/App JWT)가 필요한데, 보유 자격증명은 사용자 PAT뿐(§2.4 자격증명 권한 — 시크릿 발급·복제 금지). ③ org 설치 목록에는 29110이 없음.
> **→ operator(인간 아키텍트)의 App Settings 화면 확인이 필요** (§4 목록 A-1).

### 1.4 대조 실험 — `GET /apps/{app_id}` 의 판별력 부재

| app_id | 알려진 정체 | `GET /apps/{id}` 결과 |
|---|---|---|
| 15368 | GitHub Actions (공개·널리 알려짐) | **404** |
| 2781 | Dependabot (공개) | **404** |
| 4879411 | axiom-ci-elastic (private, **신원 확정**) | **404** |
| 5082347 | axiom-release-authority (private, **신원 확정**) | **404** |
| 29110 | 미상 | **404** |

→ **이 엔드포인트는 어떤 app_id에 대해서도 404를 반환하므로, 29110의 404는 "비공개/내부 App"이라는 의미의 증거가 되지 못한다.** (계획서의 주의사항 "404는 비공개/내부 App일 수 있음"은 사실이나, 이 환경에서는 **404가 유일한 관측값**이어서 판별력이 없다.)

---

## 2. org ruleset을 workflow job GITHUB_TOKEN이 읽을 수 있는가?

### 2.1 결론

| 대상 | 판정 | 증거 강도 |
|---|---|---|
| **repo ruleset 20303214** | **읽을 수 있음 (PASS)** — job GITHUB_TOKEN으로 실측 | **직접 실측 (run 39622835490 로그)** |
| **org ruleset 25218071 / 23943917** | **읽을 수 없음으로 간주 (MUST#8)** — 단 **직접 실측은 없음** | **간접 증거(설계 + 문서)** — 직접 실측 아님 |

### 2.2 직접 실측 — repo ruleset leg 2 PASS

`gh run view 39622835490 -R Archright/Axiom --log` (run id 39622835490, workflow 391703936 `admission-ssot-drift`, created 2026-10-21T15:07:22Z, **conclusion=success**, event=workflow_dispatch, head_sha `011c5127d1ab…`).

**Tier 판정 단계 출력 (원문):**
```
::warning::credential tier: job-token — the diagnostic App is NOT registered (human registration gate,
docs/spec/diagnostic_execution_delegation.md §2). The job's own GITHUB_TOKEN is used instead.
MEASURED 2026-10-21 (run 39603184495): this token CAN read the repository ruleset (ruleset drift 4/4 PASS),
so the ruleset leg IS performed; if that read ever fails, the monitor reports the leg as NOT PERFORMED
(degraded mode) instead of silently skipping it.
```

**Monitor 본체 출력 (원문, 2026-10-21T15:09:35Z):**
```
merge_ruleset_drift_monitor: policy SSOT config/policy/merge_admission.json — expected required-check
  contexts: {admission-check, bsec-integrity, debt-registry-gate}
  OK    constant mirror: RequiredChecks == policy-derived {admission-check, bsec-integrity, debt-registry-gate}
  OK    constant mirror: RequiredWorkflowIds == policy requiredValidations (bsec-integrity@381835906, debt-registry-gate@389486255)
  constant mirror: 2/2 checks hold
merge_ruleset_drift_monitor: credential-source=GH_TOKEN (pre-set in the environment — e.g. the job's own
  GITHUB_TOKEN; NOT a diagnostic credential)
merge_ruleset_drift_monitor: live Archright/Axiom ruleset 20303214
  OK    merge_queue: parameters.merge_method == "MERGE"
  OK    required_status_checks: exactly {admission-check, bsec-integrity, debt-registry-gate}
        (app-level producer control: integration_id 15368 on every entry)
  OK    pull_request: required_approving_review_count == 0
  OK    merge_queue: parameters.grouping_strategy == "ALLGREEN"
  ruleset drift: 4/4 expectations hold
  OK    producer observation: context "admission-check" produced by app id 15368 (github-actions)
  OK    producer observation: context "bsec-integrity" produced by app id 15368 (github-actions)
  OK    producer observation: context "debt-registry-gate" produced by app id 15368 (github-actions)
  producer observation: 3/3 contexts observed
admission-ssot-drift: OK — the policy SSOT, the compiled-in constants and the live platform agree on the
  required-check set.
```

**해석 (정직한 판정):**
- ✅ **leg 2 (policy ↔ ruleset) 실측 PASS**: `credential-source=GH_TOKEN`(= job 자신의 GITHUB_TOKEN) 상태에서 `GET /repos/Archright/Axiom/rulesets/20303214`가 **실제 성공**했고 4/4 기대조건이 충족됨을 출력. 단순히 "우회했다"가 아니라 **실제 원본을 읽어 대조한 결과**가 PASS다.
- ✅ **degraded mode 미발동 확인**: 이 워크플로는 `--allow-unavailable-ruleset` 플래그를 job-token tier에서 **전달한다**(원문: `ARGS="$ARGS --allow-unavailable-ruleset"`). 즉 읽기가 실패하면 monitor는 `NOT PERFORMED`로 명시 보고해야 한다. 그런데 실제 출력에 `NOT PERFORMED`는 **0건**이고 4/4 OK가 출력됨 → **조용한 생략이 아니라 실제 읽기 성공**이 증명된다.
- ✅ **required context 3종이 app 15368로 생산됨을 job token으로 확인** (producer leg 3/3).

→ **GPA의 "T1(직접 조회 가능)" 티어 = repo ruleset 20303214 + epoch/TWS/blob 정합성 + 정책 파일**은 실측 근거가 있다. drift monitor와 동일한 workflow permission 상한(`contents:read / actions:read / checks:read`)이면 GPA도 동일하게 성립한다.

### 2.3 org ruleset은 "직접 실측 없음" — 간접 증거

**직접 시도가 로그에 존재하지 않는다**: run 39622835490 로그 전문(1345줄) 검색 결과 `25218071`·`23943917`·`/orgs/Archright/rulesets` **0건**. monitor는 **repo ruleset만** 조회한다.

**설계상 의도된 배제(워크플로 YAML 원문 주석)** — `.github/workflows/admission-ssot-drift.yml`:
```
#   credential 2단 계약 (fail-closed, 명시적):
#   tier 1 (diagnostic-app): 진단 App 시크릿이 등록된 경우 — job 안에서
#     installation token을 민팅(diagnostic-authority.yml과 동일 패턴)하고
#     rulesets API를 읽는다 → 3개 다 판정.
#   tier 2 (job-token): 진단 App이 아직 등록되지 않은 경우(현행 — 진단 App
#     등록은 인간 게이트, docs/spec/diagnostic_execution_delegation.md §2;
#     GitHub API로 App을 만들 수 없다) — job 자신의 GITHUB_TOKEN을 쓴다.
```
그리고 step 본문:
```
# tier 2: Administration:read credential가 없다 — ruleset leg은
# 통째로 불가하므로, 실패 시 명시적 DEGRADED MODE로 내려간다
```
→ **"Administration:read credential가 없다"는 이 저장소 아키텍처의 명시적 설계 전제**다. org ruleset 읽기(Administration org write 필요)를 job token으로 시도하지 **않는** 것이 의도된 거절(fail-closed by design)이다.

**부수 확인**: 저장소 코드/워크플로 어디에도 org ruleset을 job token으로 읽는 경로가 없다.
```
git grep -n "orgs/Archright/rulesets" origin/main -- .github/ tools/ src/ config/
→ docs/spec/admission-generation.md:126, docs/spec/github_ruleset_api_quirks.md:24,100,102,
  docs/spec/gh_org_required_workflow_run_quirks.md:268   (전부 문서/명령 예시, 실행 코드 아님)
```
`docs/spec/diagnostic_execution_delegation.md:43` — 진단 App 허용 스코프에 "**Administration 불허**"가 명시.

> **UNREADABLE(직접 실측 부재): "job GITHUB_TOKEN이 org ruleset 25218071/23943917을 읽을 수 없다"는 이 Phase 0에서 직접 측정되지 않았다.**
> 현재 근거는 (a) GitHub REST 문서의 Administration org write 요구사항, (b) 저장소의 의도된 배제 설계, (c) job token이 Administration 권한을 갖고 있지 않다는 구조적 사실 — 세 가지 모두 **간접/설계 증거**이며 실측 로그가 아니다.
> **→ operator-adapter(단독 operator가 org-admin 자격으로 readback 수행) 경로가 정본 방식이 되어야 한다.** GPA가 "org ruleset을 못 읽는다"를 매니페스트에 **실측 UNKNOWN이 아니라 검증됨으로** 기록하면 안 된다(계획 POLICY#2).

---

## 3. Axiom 저장소의 GH App 설치 목록

`GET /orgs/Archright/installations`는 org의 **모든 설치**(repo 포함)를 담는다 — `total_count=2`가 완전 목록이며, 둘 다 Axiom에 적용된다:

| installation id | app_id | app_slug | repository_selection | Axiom 포함 | 대상 actor_id와 일치 |
|---|---|---|---|---|---|
| 160192931 | **4879411** | axiom-ci-elastic | `all` | 예 | ✅ **4879411과 일치** |
| 165035395 | 5082347 | axiom-release-authority | `selected` | (선택 목록 조회 실패 — §1.3 #11) | ❌ 29110과 아님 |

- `GET /repos/Archright/Axiom/installation` → **401 (App JWT 필요)** → **저장소 단위 설치 목록 직접 조회는 불가**. 위 org 레벨 목록이 대체 경로이며, 그 목록에 29110은 **없다**.
- Axiom repo의 최근 40 main 커밋의 check-suite app id 전수 = **15368 (github-actions) 694건 단일** → 저장소에서 check을 생산한 App은 GitHub Actions뿐.
- `repository_selection=selected`인 `axiom-release-authority`(app_id 5082347)는 **bypass_actors에 없다**. 즉 ruleset 우회 권한은 axiom-ci-elastic(4879411) 1건 + OrganizationAdmin + (미확인 29110)뿐.

---

## 4. GPA 관점의 권한 매트릭스 (실측 기반)

| 대상 | 읽기 | 근거 | GPA 티어 |
|---|---|---|---|
| repo ruleset 20303214 | ✅ job GITHUB_TOKEN으로 실측 | run 39622835490 (4/4 PASS) | **T1 직접** |
| epoch/TWS/blob 정합성 | ✅ git 로컬 + 정책 파일 | 3중 pin 일치 (§baseline) | **T1 직접** |
| org ruleset 25218071 / 23943917 | ⚠️ **간접 증거만, 직접 실측 없음** | §2.3 | **T2 operator-adapter** |
| org ruleset의 `bypass_actors` | ⚠️ 간접(구조) | `bypass_actors`는 write 접근자에게만 반환(플랫폼 규칙) | **T2 operator-adapter** |
| push ruleset 23967915 / 23916707 | ✅ operator(사용자 PAT)로 실측 | baseline.json | **T2 operator-adapter** (GPA job은 repo ruleset과 달리 push ruleset을 job token으로 볼 수 없음 — job token은 push 규칙 조회 권한 없음) |
| workflow run/check-run 읽기 | ✅ job GITHUB_TOKEN | run 39622835490이 checks:read로 producer 관측 성공 | **T1 직접** |
| bypass integration 29110 신원 | ❌ 미확정 | §1.3 11경로 전 실패 | **UNKNOWN → operator 확인 필요** |

### 잔여 위험 (GPA 리스크 관점, 실측 기반)

1. **R-1 (높음)**: `axiom-ci-elastic`(4879411)이 push ruleset 23967915를 **항상** 우회 가능 + `contents:write` 보유 + `organization_self_hosted_runners:write` 보유. → **우회자는 "CI 권력" 그 자체**. GPA의 required 등록은 이 권력의 약화가 아니라 **감지 창(noise-to-signal)** 축소다. ADR-0036에 명시 필요.
2. **R-2 (중간)**: 29110의 정체가 미상. 미확정 App이 `.github/workflows/**` push를 우회할 수 있는 상태로 **잔존**한다. 이건 "identities unknown"이지 "bypass 없는 것"이 아니다.
3. **R-3 (낮음, 그러나 명시 필요)**: org ruleset 3-leg 검증은 GPA job token으로 불가 → operator-adapter에 의존. operator가 없으면 해당 leg은 **UNKNOWN**이며, UNKNOWN 상태에서 승격 완료를 선언하면 안 된다(정책 #2).
4. **R-4 (관측)**: `axiom-release-authority`(5082347)는 `contents:write` 보유이나 bypass_actors 미등록 → ruleset 우회 불가. 반대로 **App인stitutional write 권한은 ruleset과 무관하게 존재**한다(추가 축, plan 범위 밖).

---

## Amendment 1 (2026-10-22 — material correction, A5 GraphQL App node 조사)

> **부록(append-only) 정정 — 위 §1–§4 본문은 수정·삭제하지 않았다.**
> 본 부록이 정정의 **유일한 정본**이며, 각 항목은 본문의 어떤 서술이
> **무효 / 철회 / 오기**인지 명시한다. 기존 본문은 **원본 그대로** 남아 있다
> (무효라고 명시된 서술을 "이 문서 전체가 무효"가 아니라 **해당 서술만** 무효로
> 판정한다 — §1.2/§2.1/§2.2/§3의 설치 레코드·실측 로그·권한 매트릭스 중
> §A.5에 열거하지 않은 항목은 여전히 유효하다).
>
> **근거 원천**: A5 보고서 `/tmp/gpa_residual/app_identity.md` (2026-10-22 작성,
> read-only `gh api` / `gh api graphql` 25개 경로 전수 조사) + 본 정정의
> **재현 실측**(아래 §A.6의 명령을 그대로 실행해 확인).
> **채널별 한계·교훈**: `docs/spec/gh_app_identity_resolution_quirks.md`
> (신규, 2026-10-22) — GraphQL `App` node 해석과 "조회 실패 ≠ 부재" 원칙.

### A.1 철회 — §3의 "org installations `total_count=2`가 완전 목록" 주장

**철회 대상 (§3 첫 문장):**

> "`GET /orgs/Archright/installations`는 org의 **모든 설치**(repo 포함)를 담는다 —
> `total_count=2`가 완전 목록이며, 둘 다 Axiom에 적용된다"

**철회 사유 (실측):** `GET /orgs/Archright/installations`는 **org에 *설치된* App**만
열거한다. **GitHub 소유(GitHub-owned) 앱은 이 목록에 등재되지 않는다.** 따라서
`total_count=2`는 "Archright org에 설치된 App"의 완전 목록이지, "이 org에서
동작하는 모든 GitHub App"의 완전 목록이 **아니다**.

**반증 증거 (bypass 실사용):** ruleset `23967915`의 bypass actor
`Integration 29110`은 위 설치 목록에 **부재**함에도 불구하고 이 저장소에서
실제로 `.github/workflows/**` 경로를 push하고 PR을 병합했다(§A.4). 따라서
"29110 부재"는 "29110이 이 org에서 동작하지 않는다"의 증거가 될 수 없다.
→ §4 권한 매트릭스의 "bypass integration 29110 신원 = ❌ 미확정" 행과
잔여 위험 **R-2**("29110의 정체가 미상")는 §A.2에 따라 **갱신**된다.
(§4의 R-1·R-3·R-4는 그대로 유효하다. 특히 R-4의 "5082347은 bypass_actors 미등록
→ ruleset 우회 불가"는 §A.3에서 재확인된다.)

**유지되는 것 (철회 범위 밖):** `4879411` / `5082347` 두 건의 **설치 레코드 자체**
(installation id·client_id·permissions·repository_selection·created_at)는 그대로
유효하다. 철회 대상은 "완전 목록"이라는 **주장의 범위**이며 설치 레코드의 사실성은
철회 대상이 아니다.

### A.2 확정 — bypass integration `29110` = `Dependabot` (GitHub 소유)

**확정 판정.** ruleset `23967915`의 bypass actor `Integration 29110`은
GitHub 공식 **`Dependabot`** 앱이다.

| 항목 | 값 | 근거 |
|---|---|---|
| app_id | `29110` | GraphQL `App` node 해석 (`databaseId=29110`) |
| slug | `dependabot` | 동일 |
| client_id | `Iv1.4f9a6346434f815e` | 동일 |
| url | `https://dependabot-api.githubapp.com` | 동일 |
| 소유 | **github** (GitHub 소유 앱) | `GET /apps/dependabot` → `owner.login = "github"` |
| org 설치 레코드 | **없음** (설계) | `/orgs/Archright/installations` 미등재 — GitHub 소유 앱 특성 |

**해석 채널 (REST `GET /apps/{id}`가 실패한 이유).** `GET /apps/{app_id}`는
**slug 전용** 엔드포인트다. 숫자 id를 넣으면 404가 나며 — 공개 앱(GitHub Actions
15368)조차 404이므로 **판별력이 전혀 없다**. 숫자 app_id → 신원의 판별력 있는
공식 채널은 **GraphQL `Query.node(id:)`** 이며, 레거시 전역 ID
`base64("03:App<app_id>")`를 넣으면 `... on App { databaseId name slug clientId url }`
로 해석된다.

**통제 실험 (판별력 입증 — 기지의 정체 3건이 동일 채널로 재현).** 이 채널이
"아무 id나 남의 앱으로 오매칭하는" 경로가 아님을 양성 대조로 입증한다.

| app_id | 기지의 정체 | 동일 채널 해석 결과 | 판정 |
|---|---|---|---|
| `15368` | GitHub Actions (공개) | `GitHub Actions` / `github-actions` | ✅ 정확히 재현 |
| `4879411` | `axiom-ci-elastic` (private, 신원 확정) | `axiom-ci-elastic` / `axiom-ci-elastic` | ✅ 정확히 재현 |
| `5082347` | `axiom-release-authority` (private, 신원 확정) | `axiom-release-authority` / `axiom-release-authority` | ✅ 정확히 재현 |
| `29110` | 미상 → 본 amendment에서 확정 | `Dependabot` / `dependabot` | ✅ **확정** |
| `2781` | §1.4가 "Dependabot(공개)"라고 기재 | `NOT_FOUND` | ❌ **§1.4 오기** (아래 §A.5 #3) |

→ 3건의 양성 대조가 정확히 재현된 이상 이 채널의 **ID→App 매핑 판별력**은
입증된 상태다.

**§1.1 결론표 갱신.** `29110` 행의 `UNRESOLVED / UNREADABLE` 판정은
**무효**이며, 판정은 `확정 — Dependabot`으로 교체된다. §1.3의
"**UNREADABLE**: bypass integration 29110의 신원" 블록(11경로 전 실패)도 **무효**다.
§1.4의 표 제목 "`GET /apps/{id}` 의 판별력 부재"는 **주장의 방향은 맞으나
해석이 틀렸다** — 판별력 부재는 엔드포인트의 성질이 아니라 **호출 방식의 문제**
(slug 전용 엔드포인트에 숫자 id를 넣음)였다. slug로 부르면 공개 앱에 대해 정상
동작한다(`GET /apps/dependabot` → `id: 29110`).

### A.3 확정 — `5082347` = `axiom-release-authority` (우회 권한 없음), `4879411` = `axiom-ci-elastic` (유지)

**5082347 = `axiom-release-authority`** (기존 §1.2에 부분적으로만 기재). 이 App은
ruleset 우회 권한이 **없다**.

| 항목 | 값 | 근거 |
|---|---|---|
| app_id / slug | `5082347` / `axiom-release-authority` | GraphQL `App` node + org 설치 레코드 1:1 일치 |
| client_id | `Iv23lizKflxk2O7OzSiM` | 동일 (org 설치 레코드 `client_id`와 일치) |
| installation_id | `165035395` | `GET /orgs/Archright/installations` |
| permissions | `contents:write` + `metadata:read` **만** | 동일 |
| repository_selection | `selected` | 동일 |
| ruleset 23967915 bypass_actors | **부재** → **우회 권한 없음** | 실측 (§A.6-F) |
| 릴리스 산출물 | **0건** (`GET /repos/Archright/Axiom/releases` → `length == 0`) | 실측 (§A.6-H) |

→ §3 표의 "대조 actor_id와 일치" 열이 `5082347` 행에 대해 "❌ 29110과 아님"으로
기재된 것은 **오기**다 — 이 열의 의미는 "ruleset bypass actor id와 일치하는가"인데,
`5082347`은 **bypass actor로 등록조차 되어 있지 않다**(§A.6-F). 올바른 판정은
"**29110과 동일하지 않다**"가 아니라 "**bypass 목록에 없으므로 우회 권한이
없다**"다. (같은 이유로 §3 표의 "Axiom 포함" 열은 `repository_selection=selected`의
구체 목록 미확인으로 **미확정**이며, "❌"로 확정해서는 안 된다.)
**잔여 UNKNOWN 1건(운영자 확인 항목)**: `repository_selection=selected`의
**구체적 저장소 목록**은 `GET /orgs/Archright/installations/{id}/repositories`(404,
존재하지 않는 경로) 또는 `GET /installation/repositories`(App JWT 필요)로만 조회된다.
→ **App JWT 경로 = 인간 운영자 확인 항목**(비블로커). 본 amendment는 이를
"해결됨"으로 기록하지 않는다.

**4879411 = `axiom-ci-elastic`** (기존 §1.2 판정 **유지**). GraphQL 채널로
재현 확인(`axiom-ci-elastic` / `Iv23liiIrdRvUju6DdOS`). §1.2의 권한 해석
(`contents:write` + `organization_self_hosted_runners:write` → push ruleset
`23967915` 우회 + `refs/heads/main` 갱신 권한)도 **그대로 유효**하다.

### A.4 기능 증거 — 우회가 실제로 사용되었음 (29110 = Dependabot)

**규칙 실측.** ruleset `23967915`(name=`execution-surface-create`, `target=push`,
`enforcement=active`, `conditions=null` = 모든 ref)의 `file_path_restriction`
restricted = `[".github/workflows/**/*", ".github/actions/**/*"]`,
`bypass_actors` = `OrganizationAdmin(always)` + `Integration 29110(always)` +
`Integration 4879411(always)`. → **29110은 이 ruleset 단독에만 등록**되어 있고,
우회 범위는 "`.github/workflows/**`·`.github/actions/**` 경로 push"로 제한된다.

**우회 실사용 (직접 증거).** Dependabot이 생성한 PR 8건이 **전부** 위 restricted
경로만 수정한다 — 우회가 없으면 이 push 자체가 차단된다.

| PR | 상태 | head ref | 수정 파일 |
|---|---|---|---|
| 910 | **merged** | `dependabot/github_actions/actions/create-github-app-token-3.3.0` | `.github/workflows/diagnostic-authority.yml`, `.github/workflows/release-ship.yml` |
| 709 | closed | `dependabot/github_actions/actions/cache/restore-6.1.0` | `.github/workflows/ci-cache-publisher.yml` |
| 708 | closed | `dependabot/github_actions/actions/download-artifact-8.0.2` | `.github/workflows/{admission-check,ci-cache-publisher,h4-routing-measure,runner-pool-acceptance}.yml` |
| 707 | closed | `dependabot/github_actions/actions/upload-artifact-7.0.2` | `.github/workflows/{admission-check,certificate-mint,gateway-jobs-measure,h4-routing-measure,observation,probe-merge-queue}.yml` |
| 283 | closed | `dependabot/github_actions/actions/download-artifact-8.0.1` | 4개 workflow |
| 282 | closed | `dependabot/github_actions/actions/checkout-7.0.1` | 6개 workflow |
| 281 | closed | `dependabot/github_actions/actions/upload-artifact-7.0.1` | 5개 workflow |
| 280 | closed | `dependabot/github_actions/actions/cache/save-6.1.0` | 2개 workflow |

PR 작성자 = `dependabot[bot]` (user id `49699333`). PR 910은 **병합 완료** —
우회 경로의 **실사용**에 대한 직접 증거다.

**설계된 우회 (잔여 권한 아님).** Dependabot version-update는 브랜치
`dependabot/**`에 워크플로 파일을 변경한 채 push한다 → 우회 없이는 그 push가
차단된다. 즉 `Integration 29110: always`는 **version-update를 구조적으로
가능하게 하는 의도된 허용**이며, 그 회전 경로 자체는 승격 절차
(DEBT#473 해소 정의 — `docs/spec/admission-generation.md` §4 "2경로 승격 절차",
pin-promotion-gate)로 통제된다. → §4 R-2("미확정 App이 우회할 수 있는 상태로
잔존")는 **무효**하며, 해당 권한은 잔여 위험이 아니라 **설계된 허용**로
재분류된다.

**타이밍 정합 (인과 3연속).**

| 시각 | 사건 | 근거 |
|---|---|---|
| 2026-09-25T07:54:16.090+09:00 (KST) | ruleset `23967915` **생성** (최초 버전) | `GET /repos/Archright/Axiom/rulesets/23967915/history?per_page=100` → oldest version `updated_at` |
| 2026-09-25T09:40:00+09:00 (KST) | `.github/dependabot.yml` **추가** 커밋 `6065b49b27540ae50531a37a46db1bd55ee52ecc` (생성 +105분) | `git log --diff-filter=A -- .github/dependabot.yml` |
| 2026-09-26T14:12:51Z (UTC) | 첫 Dependabot PR **#280** 생성 | `GET /repos/Archright/Axiom/pulls/280` → `created_at` |

→ 규칙 생성 → 105분 후 Dependabot 설정 → 다음 날 첫 Dependabot PR.
(시각 표기 주의: A5 원보고서는 이 PR 시각을 "14:12:51 KST"로 적었으나, 실측 원문
`created_at`은 **`2026-09-26T14:12:51Z`(UTC)** = KST 23:12:51이다. 표기만
정정하며 인과 순서는 동일하다.)

**Dependabot 활성 증거.** `GET /repos/Archright/Axiom/dependabot/alerts` →
**HTTP 200**(alerts 비활성 시 403이므로 200은 활성의 증거).

### A.5 무효화 명시 — 이전 음성 추론 2건 + 오기 1건

아래 서술은 **무효**다(재사용 금지). 각 항목은 왜 판별력이 없었는지를
함께 기록한다 — 근거: `docs/spec/gh_app_identity_resolution_quirks.md`
(조회 실패 ≠ 부재 원칙, 통제 실험 요건).

| # | 이전 서술 (위치) | 판정 | 무효 사유 |
|---|---|---|---|
| 1 | §1.3 경로 1 해석: "29110은 org 설치가 아님" / §1.3 #11 인용의 연장 — "org 설치 목록에 없다" | **무효(우회 권한 추론으로서)** | 진단적으로는 사실이나, **"설치 목록 부재"는 "우회 권한 부재"의 증거가 아니다.** GitHub 소유 앱은 목록에 등재되지 않는데도 실제 우회 권한·실사용이 성립한다(§A.2·§A.4). 설치 목록 부재 = 부재 증거가 아님. |
| 2 | §1.3 추가 관찰: "29110은 이 저장소에서 check을 생산한 적이 없다" (최근 40 main 커밋 check-suite 전수 = 15368 단일) | **무효(판별 근거로서)** | Dependabot은 **check을 생산하지 않고** 브랜치 push로 동작한다. check-suite 전수 스캔은 이 앱의 존재/부재를 **판별할 수 없다**(비판별 신호). |
| 3 | §1.4 대조표: "`2781` \| Dependabot (공개) \| 404" | **오기** | ① `GET /apps/{id}`는 **slug 전용**이라 404에 판별력이 없다. ② GraphQL `node(id: base64("03:App2781"))` → **`NOT_FOUND`** — 2781은 Dependabot이 **아니다**. Dependabot의 실제 app_id는 `29110`이다. |

**부수 정정.** §1.3 #2의 "`GET /apps/29110` 404 → 비공개 App 시사"는 **무효**(slug
전용 엔드포인트에 숫자 id를 넣은 **사용 오류**). §1.3 #8(`GET /orgs/{org}/installations/29110`)
는 **id 공간 오용** — 이 경로는 installation_id를 받는데 29110은 app_id다(§1.2가
"4879411은 app_id이며 installation_id가 아니다"를 실측 확정한 것과 동일 유형).
§1.3 #9(`GET /installations/29110`)는 **존재하지 않는 경로**다. 둘 다 404를
관측값으로 기록한 것 자체는 사실이나, **부재 증거로 인용해서는 안 된다.**

**여전히 유효한 §1.3/§1.4 항목(재사용 가능).** §1.3 #3·#4·#5·#6·#7·#10
(각각 401/403 — App JWT 필요 경로에 사용자 PAT 사용), §1.3 #11
(`GET /orgs/Archright/installations/{id}/repositories` 404 — 존재하지 않는 경로),
§1.4의 "이 엔드포인트는 어떤 app_id에 대해서도 404를 반환"이라는 **관측 사실 자체**
(해석만 폐기), §1.2의 4879411 판정·권한 해석, §2 전체(관측은 29110과 무관),
§3의 설치 레코드 사실, §4의 R-1·R-3·R-4.

### A.6 재현 명령 (읽기 전용 — 그대로 실행 가능)

```bash
# (A) GraphQL App node 해석 — 29110 (결정적 채널)
ID=$(printf '03:App29110' | base64)          # → MDM6QXBwMjkxMTA=
gh api graphql -f query="query { node(id: \"$ID\") { ... on App {
  databaseId name slug clientId url createdAt updatedAt description } } }"
# 기대: databaseId=29110 name=Dependabot slug=dependabot
#       clientId=Iv1.4f9a6346434f815e url=https://dependabot-api.githubapp.com

# (B) 통제 실험 (기지의 정체 3건 — 양성 대조로 판별력 입증)
for id in 15368 4879411 5082347; do
  nid=$(printf "03:App%s" "$id" | base64)
  gh api graphql -f query="query { node(id: \"$nid\") { ... on App {
    databaseId name slug clientId } } }"
done
# 기대: 15368→GitHub Actions/github-actions, 4879411→axiom-ci-elastic,
#       5082347→axiom-release-authority (기지의 정체와 정확히 일치)

# (C) 음성 대조 — 2781 (기존 §1.4의 "2781 = Dependabot" 주장 반증)
nid=$(printf '03:App2781' | base64)
gh api graphql -f query="query { node(id: \"$nid\") { ... on App { databaseId name slug } } }"
# 기대: {"data":{"node":null},"errors":[{"type":"NOT_FOUND", ...}]}

# (D) slug 전용 REST 엔드포인트 대조
gh api /apps/dependabot     # 200 → id=29110, owner.login="github"
gh api /apps/29110          # 404 ("Not Found") — 판별력 없음

# (E) org 설치 목록 (29110 부재 = GitHub 소유 앱 특성)
gh api /orgs/Archright/installations --paginate \
  --jq '.total_count, (.installations[] | {app_id, app_slug, repository_selection, permissions})'
# 기대: total_count=2 → 4879411/axiom-ci-elastic(all), 5082347/axiom-release-authority(selected)

# (F) 규칙 + 우회 + 제한 경로
gh api /repos/Archright/Axiom/rulesets/23967915 \
  --jq '{id, name, target, enforcement, conditions, bypass_actors, rules}'
# 기대: bypass_actors = [OrgAdmin(always), 29110(always), 4879411(always)]
#       rules = file_path_restriction restricted=[".github/workflows/**/*",".github/actions/**/*"]

# (G) 우회 실사용 — Dependabot PR 8건의 수정 경로 (전부 restricted 경로)
for pr in 910 709 708 707 283 282 281 280; do
  gh api "/repos/Archright/Axiom/pulls/$pr/files" \
    --jq '[.[] | .filename] | join(", ")'
done
# 기대: 8건 전부 ".github/workflows/**" 만

# (H) Dependabot 활성 + 5082347 릴리스 산출물 0건
gh api -i "/repos/Archright/Axiom/dependabot/alerts?per_page=3" | head -1
# 기대: HTTP/2.0 200 OK
gh api /repos/Archright/Axiom/releases --jq 'length'
# 기대: 0

# (I) 규칙 생성 시각 (최초 버전) + Dependabot 설정 커밋 시각
gh api "/repos/Archright/Axiom/rulesets/23967915/history?per_page=100" --jq '.[-1].updated_at'
# 기대: 2026-09-25T07:54:16.090+09:00
git log --reverse --format='%H %cI %s' --diff-filter=A -- .github/dependabot.yml
# 기대: 6065b49b27540ae50531a37a46db1bd55ee52ecc 2026-09-25T09:40:00+09:00
```

### A.7 Amendment 1이 대체하는 §4 권한 매트릭스 행 (갱신)

| 대상 | §4 원문 | Amendment 1 이후 |
|---|---|---|
| bypass integration 29110 신원 | ❌ 미확정 (§1.3 11경로 전 실패) | ✅ **확정 — `Dependabot`** (GitHub 소유, slug `dependabot`, app_id 29110, client_id `Iv1.4f9a6346434f815e`) |
| 잔여 위험 R-2 | "29110의 정체가 미상. 미확정 App이 `.github/workflows/**` push를 우회할 수 있는 상태로 잔존" | **무효** — 29110 = Dependabot, 규칙상 의도된 허용이며 **실사용**(PR 910 병합)까지 실증. 잔여 위험이 아님 |
| §3 "complete list" 주장 | "`total_count=2`가 완전 목록이며, 둘 다 Axiom에 적용된다" | **철회** — GitHub 소유 앱은 org 설치 목록에 등재되지 않는다 (§A.1) |
| §1.4 "2781 = Dependabot" | 대조표 행 | **오기** — 2781은 GraphQL에서 `NOT_FOUND`. Dependabot은 29110 (§A.5 #3) |
| 5082347의 Axiom 적용 여부 | "선택 목록 조회 실패 — 확인 불가" | **부분만 유지** — 신원·권한·bypass 부재·릴리스 산출물 0건은 확정. `repository_selection=selected`의 구체 저장소 목록만 App JWT 필요 = **운영자 확인 항목**(§A.3) |

**_END OF AMENDMENT 1_**
