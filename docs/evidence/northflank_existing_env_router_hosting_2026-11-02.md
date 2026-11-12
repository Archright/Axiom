# Northflank 기존 실행 환경 Router 고정 실행 가능성 조사 (2026-11-02)

> **종류**: 읽기 전용 조사 증거 기록 — 인프라 변경 0건(명령은 GET·grep·git show
> 전부). 본 문서는 결정을 대리하지 않는다 — 판정·권고를 **결정자료**로 제공하며,
> 최종 판정(제거 실행·기질 선택)은 **operator 전용**이다(AGENTS.md §0.3).
> **권한**: 조사 의뢰·권한 — operator(2026-11-02). **ledger 수정 없음** — 본 문서는
> residual ledger·전환 계약을 수정하지 않는다.
> **기준 revision**: `origin/main` @ `ed9cab36d`(2026-11-02, PR #1206 병합).
> **선행 문서**:
> `docs/spec/northflank_control_plane_transition_contract.md`(전환 계약 — §3
> 3제약·§5 실행 순서·§6 별개 판정),
> `docs/evidence/northflank_medium_selection_request_2026-11-02.md`(#1204 — D1
> 결정요청서),
> `docs/evidence/northflank_incident_response_2026-10-31.md`(사고 대응 — §5.1
> 운영자 방침),
> `docs/spec/ci_provider_failover_quirks.md`(Q1–Q18),
> `docs/spec/ci_provider_december_unattended_fallback_acceptance_contract.md`
> (12월 무인 폴백 사전계약).

## 0. operator 방향 (2026-11-02 원문 인용)

> "내 권고는 Northflank 대체 VM을 새로 만들지 않는 것입니다. 먼저 Ubicloud를
> 포함해 이미 보유한 실행 환경 중 Router를 고정 실행할 수 있는 곳이 있는지
> 확인해야 합니다. 그 경로가 성립한다면 Northflank는 제거 대상입니다."

본 문서는 이 방향의 조사 항목 — "이미 보유한 실행 환경(Ubicloud 포함) 중
Router를 고정 실행할 수 있는 곳이 있는가" — 을 전부 실측 기반(명령→관측)으로
수행한 기록이다. 조사 성격은 **읽기 전용**이며 러너·그룹·변수·시크릿·워크플로
어떤 것도 변경하지 않았다.

## 1. 배경 — #1204와의 관계

- #1204(`docs/evidence/northflank_medium_selection_request_2026-11-02.md`,
  MERGED 2026-11-02T03:52:01Z)는 전환 계약 §5 1단계의 **운영 기질(medium)
  채택(D1)**을 operator에 요청한 문서다 — 권고 없음, 후보 재열거 없음(계약
  §3–§4 참조로 갈음).
- operator 방향 전환(§0 인용)은 D1의 **전제**(신규 대체 VM 채택)를 바꾼다 —
  새 대체 VM을 만들지 않는 한 기질 선택은 발생하지 않는다. 따라서 **D1 회부는
  방향 전환으로 초점이 변경된 것이며, 요청서 자체는 대체되지 않는다** — 기존
  환경 경로가 불성립하면 D1(기질 선택)이 회귀한다.
- 본 조사는 방향 전환의 물음에 대한 결정자료를 제공한다: (a) 기존 환경 경로
  성립 → Northflank 제거 경로 또는 (b) 불성립 → 기질 선택 회귀.

## 2. Router 실행 모델 실측 — "Northflank 제어면 러너가 실제로 무엇을 실행하는가"

### 2.1 워크플로우 정의 (origin/main 기준)

`git show origin/main:.github/workflows/ci-provider-router.yml` 실측:

| 항목 | 실측값 |
|---|---|
| `runs-on` | **`[self-hosted, axiom-control]`** (`:116` 단일 지점) — `CI_RUNNER_MAP` **절대 참조 금지** 주석(`:107–115`: "제어기가 자기가 제어하는 변수를 읽어 자기 러너를 고르면 자기 참조 고리가 생긴다") |
| 트리거 4종 | `workflow_run`(5개 required check 워크플로 completed — admission-gate·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice) / `push`(main) / **`schedule: cron '7,37 * * * *'`** / `workflow_dispatch`(`force_trial`) |
| 권한 | `actions: write`(rerun/dispatch/poll) + `checks: read` — GITHUB_TOKEN에 variables 부재(quirks Q3) |
| environment | `ci-provider-router`(App 시크릿 `CI_ROUTER_APP_ID`/`CI_ROUTER_APP_PRIVATE_KEY` 스코프 — 잡 종료까지 노출 창 한정) |
| concurrency | group `ci-provider-router` + `cancel-in-progress: false` + `queue: max`(단일 writer 직렬화 — quirks Q5) |
| timeout | `timeout-minutes: 15` |

**CI_RUNNER_MAP 쓰기 메커니즘**: GITHUB_TOKEN으로는 변수 접근 불가(Q3) →
environment 시크릿의 GitHub App 자격으로 in-job 토큰 민팅(pinned
actions/create-github-app-token; 설치 권한 `actions_variables:write` +
`metadata:read`만 상속 — quirks Q9) →
`PATCH repos/Archright/Axiom/actions/variables/CI_RUNNER_MAP` 단일 write.
GET 실패·schema 위반·write 실패 시 전부 **fail-closed**(전이 없음, UNKNOWN
기록, 기존 라우팅 유지). App 자격 부재 시 registration gate가 잡을 실패시킨다
(자격 없음 = 변수 읽기·쓰기 없음).

### 2.2 러너 라벨 소비자 전수 (runs-on 전수 조사)

`git grep -n 'runs-on' origin/main -- .github/workflows/` — 46건 전수:

- **`[self-hosted, axiom-control]` 소비자는 `ci-provider-router.yml` 1건뿐**이다.
- 나머지는 `runs-on: [ "${{ fromJSON(vars.CI_RUNNER_MAP).x64|slim|arm64 }}" ]`
  템플릿(변수 기반 라우팅 — router가 제어) 또는 GitHub-hosted 고정 라벨
  (`ubuntu-24.04`·`ubuntu-slim`·`ubuntu-24.04-arm` — ghec-canary·release-ship·
  dependabot-auto-merge·diagnostic-authority·gateway-jobs-measure·
  h4-routing-measure·hardware-falsification-smoke).
- 즉 Northflank 제어면 러너가 실제로 실행하는 워크플로우는
  **`ci-provider-router.yml` 유일**이다 — 인시던트 대응 기록 §2의 "[live]"
  관측과 일치. 러너 자체 라벨에 "northflank"는 없다 — 라벨은
  `[self-hosted, axiom-control]`이고 "northflank"는 **러너 이름**
  (`axiom-control-northflank`)의 일부다.

### 2.3 런 실측 — 실행 주체 샘플

`gh api repos/Archright/Axiom/actions/runs/<id>/jobs` 6건 샘플(2026-11-02,
workflow_run·push·schedule 발화 혼합: 41389269223·41388161596·41387654980·
41386915119·41367787229·41291765000):

- **전부** `runner_name=axiom-control-northflank`,
  `runner_group_name=axiom-control`, `labels=[self-hosted, axiom-control]`,
  conclusion=success.
- 최근 7일 라우터 run 물량: `?created=>=2026-10-26` → **total_count=1501**
  (~214건/일). 잡 소요 시간 샘플 5건: 21·10·11·19·17초(평균 ~16초).
- group 7 라이브 재확인: `gh api /orgs/Archright/actions/runner-groups/7` →
  `restricted_to_workflows=true`(허용 워크플로는 전환 계약 §2.2 실측대로
  `ci-provider-router.yml@refs/heads/main` 1개 파일), 소속 러너 1대 —
  `axiom-control-northflank`(id **6185**, Linux, online, busy).

### 2.4 schedule 발화 실측 (러너 부재·시계와의 관계)

`gh api .../runs?event=schedule&per_page=8` — 최근 8건 전부 success, 생성
시각: 10-31T15:15:15Z → 19:29:51 → 22:46:13 → 11-01T02:05:55 → 09:08:04 →
16:16:23 → 20:46:13 → 11-02T00:33:32Z. **발화 간격 3h14m–7h08m** — 30분 cron
명목 주기 대비 시간 단위 지연·불규칙(quirks Q10 재확인 — "늦고 불규칙,
죽지 않음"; GitHub 공식 문서도 schedule을 best-effort로 규정).

- 이 지연은 **GitHub 스케줄러 측 속성**이지 러너 가용성의 함수가 아니다 —
  러너가 부재해도 run은 생성되고 잡이 self-hosted 큐에서 대기한다(24h 초과 시
  실패 — quirks Q12 인용 GitHub 문서). 따라서 "스케줄 발화가 러너 부재로
  놓친다"는 경로는 성립하지 않으며, 실제 리스크는 (1) GitHub 측 발화 지연·
  누락(Q10 — 구조적, 기존 정본이 push(main) 재조정 차량으로 이미 보완)과
  (2) 러너 부재 창의 잡 대기·실패다.

## 3. 제어면 요건 (문서 정독 — 계약·인시던트·quirks·12월 사전계약)

Router의 고정 실행 기질이 만족해야 하는 요건을 5개로 정리한다. R1·R4·R5는
전환 계약 §3의 3제약(C1–C3)과 동일 내용의 요건화다.

| # | 요건 | 근거 (정본) |
|---|---|---|
| **R1** | **항상 대기** — 스케줄 재조정·workflow_run 발화 시 잡을 즉시 승차할 상시 러너. 부재 시 잡은 self-hosted 큐에서 최대 24h 대기 후 실패(그 기간 라우터 자동 제어 정지 — 전환 계약 failure semantics) | 계약 §5 failure semantics; quirks Q12(GitHub 문서 인용); Q10(schedule은 늦고 불규칙 — 러너 문제 아님) |
| **R2** | **시계 정확성** — 변수 타임스탬프(`last_transition_at`)·관측 기록의 clock 기준. Northflank 기질은 **−1h 오프셋** 관측(2026-11-01, GitHub 정본 UTC 대비) | 복귀수용 문서 §2; 전환 계약 §2.4·§5 6단계(신기질 clock 재관측 계약) |
| **R3** | **시크릿·API 접근** — environment `ci-provider-router`의 App 시크릿 주입 + org runner group·App 설치(`actions_variables:write`+`metadata:read`) 관리. self-hosted 러너는 isolation이 없어 environment 시크릿이 repo-secret 등급 노출(quirks Q8) — 러너 소유 주체가 신뢰 경계다 | router 워크플로우 헤더·steps; quirks Q3·Q8·Q9; 인시던트 기록 §2(매 실행 시 개인키 러너 VM 주입 — 7일 925회 당시 실측) |
| **R4** | **공급자 독립성** — 제어기는 자기가 제어하는 변수(CI_RUNNER_MAP)를 읽지 않는다(C1) + **폴백 공급자 위에 있으면 안 된다**(C2) + Ubicloud 장애 = 제어기 정지(H9 이중 장애)는 복구 범위 밖 | 계약 §3 C1·C2·§3.2; router 워크플로우 주석 원문(`:107–115`, `:110` "2026-10-26 이전에는 ubicloud-standard-2였다"); router 헤더 신뢰 경계 절 |
| **R5** | **비용 — GHEC 과금 회피** — GHEC 포함량 소진 창(제어기가 필요한 바로 그 창)에 제어기 자신이 과금·0-step 차단돼서는 안 된다(C3). 예산 hard-stop의 강제 영역은 GitHub-hosted dispatch뿐(Q2) → GHEC 배치는 자기모순(계약 §3.1 [derived]) | 계약 §3 C3·§3.1; quirks Q1·Q2·Q11 |

**12월 계약 관점의 R4 보강**
(`ci_provider_december_unattended_fallback_acceptance_contract.md`): 무인 폴백
복귀 사슬은 ① 라우터 schedule/push 발화 → ② ghec-canary dispatch·identity
판정 → ③ 라우터 CI_RUNNER_MAP 전이 → ④ return_acceptance=confirmed 기록의
4단계이며, 성공 3요소(S1 스케줄 무인 발화·S2 canary 실제 실행·S3 라우터 승인
전이·수용 기록)는 **라우터 자신의 생존을 전제**한다. 라우터가 폴백 공급자
(Ubicloud) 위에 있으면 Ubicloud 장애 창 — 실제로 폴백이 필요한 창 — 에 사슬
전체가 관측 불능이 되고(§2.3 UNKNOWN → fail-closed), "무인 폴백·복귀 판정"이
불능이 된다. 이것이 C2가 단순 선호가 아니라 계약인 이유다.

**Northflank 고유 quirk의 위치**: quirks Q1–Q18에서 "Northflank" 언급은 0건이다
(`git grep -i northflank` 실측). Northflank 고유 관측은 −1h 시계 오프셋(복귀수용
문서 §2), 러너 그룹·App 설치 실측(전환 계약 §2), 노출면·방침(인시던트 기록)에
기록돼 있다 — 본 조사도 동일 출처를 인용한다.

## 4. 기존 실행 환경 인벤토리·대조

### 4.1 인벤토리 (라이브 실측 2026-11-02, 전부 읽기 전용)

| 환경 | 실측 상태 |
|---|---|
| **Northflank** (group 7 `axiom-control`) | org의 **유일 상시 self-hosted 러너**(`axiom-control-northflank`, id 6185, online) — `gh api /orgs/Archright/actions/runners` 전체 1대. Router 실행 중(§2.3) |
| **Ubicloud managed JIT runners** (`ubicloud-managed-runners` GitHub App, JIT → repo Default group) | org runner group 목록: id 1·5 = Default(JIT 러너 잡 실행 시 임시 등록), **id 3(axiom-ci)·4(axiom-publisher)·5 = runners total_count 0** — 빈 그룹. repo 레벨 러너 `total_count: 0`. 현재 CI_RUNNER_MAP: `mode=ghec / GHEC_ACTIVE / generation=15 / fallback_provider=ubicloud / return_acceptance=confirmed`(2026-11-02T04:37:02Z GHEC_RETURN_CONFIRMED) — Ubicloud는 **대기 폴백** |
| **GitHub-hosted** (group 0, `ubuntu-24.04` 등) | required checks·canary의 현재 실행 주체(GHEC_ACTIVE) |
| **기타 self-hosted** | 없음 — Hetzner fleet machinery는 제거됨(2026-09 CI=0 cutover, commit `077bf663c` — `docs/agents/operations.md` §Environment); 로컬·worktree 환경은 상시 online 보장이 없고 인간 의존이라 CI 제어면 실행 환경이 아니다 |

### 4.2 대조표 — 요건 R1–R5 충족 여부

| 환경 | R1 항상 대기 | R2 시계 | R3 시크릿·API | R4 공급자 독립성 | R5 GHEC 과금 회피 | 판정 |
|---|---|---|---|---|---|---|
| **Ubicloud JIT** (group 1) | ✗ — **고정 실행 제품 속성 없음**(§4.3 공식 문서 — 잡당 JIT 에페머럴, 서비스 가용성에 준속) | 미견(−1h 사례는 Northflank 기질 속성 — Ubicloud 기질의 clock은 미관측) | △ — App 설치·시크릿 주입은 가능하나 self-hosted 무 isolation(Q8), 커스텀 라벨은 테넌트가 못 만든다(Q7 실측 라벨 집합 `["ubicloud-standard-2"]` 고정 — §5 UNKNOWN) | **✗ C2 위반** — Ubicloud는 `fallback_provider` 그 자체. 해지 불가 순환 + H9 이중 장애 + 12월 무인 사슬 S1–S3 관측 불능(§3) | ✓ — self-hosted 과금 영역 밖(Q2). 단 Ubicloud 자체 과금은 hard cap 없음(Q7 — UsageAlert는 email 알림뿐) | **불성립** |
| **GitHub-hosted** (group 0) | ✓ — GitHub 관리 풀 | ✓ GitHub-clock | ✓ | ✓ — GHEC는 폴백 공급자가 아니라 primary | **✗ C3 위반** — 소진 창에 제어기 자신이 과금 대상 + hard-stop이 제어기 자신의 dispatch를 0-step 차단(계약 §3.1 자기모순). 물량 실측: 1,501런/7일 × ≥1분 → 월 ~6,400분 소비(GHEC Linux $0.008/min — [derived] ~$51/월 상당) | **불성립** |
| **Northflank** (group 7, 현행) | ✓ 상시 online | ✗ −1h 오프셋 관측(복귀수용 §2) | ✓(현행 environment) | ✓ — Ubicloud와 무관 | ✓ self-hosted | 2026-10-31 운영자 방침 "Northflank를 Axiom에 더 사용하지 않는다" — **제거 대상**(대안이 아님) |
| **operator 소유 신규 자체호스트** (#1204 D1) | ✓(구성에 따라) | ✓(신기질 clock 재관측 — 계약 §5-6) | ✓ operator 직접 구성 | ✓ Ubicloud·GHEC 양쪽과 무관 | ✓ self-hosted | 계약 §4 — 3제약 전부 충족 후보. 단 operator 방향 전환으로 **"새로 만들지 않는다"가 현재 방침** — 본 조사의 결론(§6)에 따라 회귀 여부가 정해진다 |

### 4.3 Ubicloud 공식 문서 확인 (context7 — docs.ubicloud.com 인용)

- **JIT·에페머럴**: "We use GitHub's REST API to create and receive a JIT
  config file… This ensures that we create **ephemeral, JIT runners. These
  runners perform at most one job before being automatically removed**"
  (github-actions-integration/security — Using Just-In-Time Runners).
- **잡당 클린 VM**: "For each new CI/CD job, we also provide you with a clean
  and **ephemeral VM**. Upon the job's completion, we decommission the VM"
  (동페이지 — Clean and Ephemeral VM for Each Job).
- **지역·가용성**: "Github runners are **automatically provisioned** either at
  European regions that powered by Hetzner or Leaseweb Germany based on the
  **overall availability of the regions at the time of the provisioning**"
  (about/regions). 혼잡 시 대형 러너는 AWS로 spillover(2026-09 changelog).
  "allocates virtual machines (VMs) across data centers in Germany to provide
  high availability"는 **서비스 수준의 가용성** 서술이지 고정·상시 러너
  할당이 아니다.
- **과금**: 분 단위 사용량 과금, 계정당 월 $2.5 크레딧(= standard-2 1,250분).
  Q7 실측 요율: standard-2 $0.00125/min. 라우터 물량(1,501런/7일, 잡 ~16초)을
  Ubicloud에 올리면 **잡당 1분 ceiling 과금**(Q7)으로 월 ~6,430분 →
  [derived] standard-2 기준 ~$8/월(premium-2 $0.002/min 기준 ~$12.9/월) —
  소액이지만 **hard spending cap이 없다**(Q7 — ProjectQuota는 동시성 상한일
  뿐 지출 상한이 아니다).
- 결론: Ubicloud는 **"Router를 고정(상시) 실행하는" 제품 속성을 제공하지
  않는다** — 필요 시점의 JIT 에페머럴 프로비저닝 모델이다. 역사적 사실로서
  2026-10-23~26 구간 제어기는 Ubicloud(`ubicloud-standard-2`) 위에서 실제
  실행됐으나(계약 §3.2 — 주석 원문), 그 배치는 C2 교훈으로 폐기됐다.

## 5. 판정

**기존 환경 경로는 불성립이다 — (b) 기질 선택 회귀.**

- **Ubicloud**: 불성립. R4(C2) 위반이 구조적 차단이다 — Ubicloud는 현재
  `fallback_provider`이며, 제어기를 그 위에 두면 (i) Ubicloud 해지·재판정이
  제어기 이주를 선결 조건으로 요구하는 순환, (ii) H9 이중 장애(Ubicloud 장애 =
  제어기 정지), (iii) 12월 무인 폴백·복귀 사슬 S1–S3가 Ubicloud 장애 창에
  관측 불능 — 문서화된 근거 3중(계약 §3.2 + router 워크플로우 주석 원문 +
  12월 사전계약 §2). 여기에 R1 불충족(고정 실행 제품 속성 부재 — §4.3)과
  라벨 실측(Q7 — JIT 러너 라벨 집합 고정, `axiom-control` 라벨 부재)이
  겹친다. "Ubicloud에서 실행 자체가 불가능하다"는 아니다(역사적 실행 실측) —
  **"제어면 계약을 만족하는 고정 실행으로 성립하지 않는다"**가 판정이다.
- **GitHub-hosted**: 불성립. R5(C3) 위반 — 소진 창(제어기의 존재 이유가 발동하는
  창)에 제어기 자신이 hard-stop 0-step 차단 대상이 되는 구조적 자기모순(계약
  §3.1), 물량 실측 1,501런/7일의 Actions 분 소비.
- **기타 보유 환경**: 인벤토리 부재 — org 상시 러너는 Northflank 1대뿐이고
  (§4.1), group 3·4·5는 빈 그룹, repo 러너 0, Hetzner는 제거됨. 로컬·worktree는
  상시성·신뢰 경계(R1·R3)를 만족하는 CI 실행 환경이 아니다.
- **Northflank**: "제거 대상"은 이미 2026-10-31 운영자 방침(인시던트 기록 §5.1)으로
  고정돼 있다 — 방향 전환의 물음("기존 환경으로 대체 가능한가")에 대한 답이
  아니라 대체 *전* 상태다.
- 표현 규율(계약 §4 준수): 위 판정은 **"확인·평가한 범위에서"** 기존 환경 경로가
  3제약(R1·R4·R5)을 만족하지 않는다는 기록이다. 평가하지 않은 대안(다른
  자체호스트 클라우드, 신규 GitHub App 관리 러너 등)을 배제하는 주장이 아니며,
  새 후보는 언제나 계약 §3 3제약으로 판정된다.

## 6. 권고 (operator 결정자료)

1. **(b) 기존 환경 경로 불성립 → 기질 선택 회귀를 권고한다.** #1204의 D1
   (운영 기질 채택) 전제는 방향 전환으로 무효화되지 않는다 — 오히려 본 조사가
   D1의 근거를 보강한다: 신규 operator 소유 자체호스트 기질이 계약 §4가 확인한
   3제약 충족 후보이며, 기존 환경(Ubicloud·GitHub-hosted)은 §5의 판정대로
   불성립이다.
2. 기질 선택 시 판정 기준은 계약 §3 3제약(C1 고정 라벨·C2 폴백 공급자 배치
   금지·C3 GHEC 과금 회피) + 본 문서 R1·R2(항상 대기·시계 정확성 — 계약 §5-6에서
   신기질 clock 재관측이 이미 계약)다. 절차는 계약 §5 6단계(단일 일관 세대
   전환 — 신규 러너 canary 선행, runs-on·그룹 7 세대 전환, drain, 라벨 소비자 0
   확인, 전환 후 관측)와 롤백 경로를 그대로 따른다 — 신규 절차 없음.
3. Northflank 제거의 절차·순서(기질 전환과의 관계): **App 설치 해제
   (`northflank-cloud-build-run`, installation id 175323502)과 콘솔 계좌 폐기는
   러너 전환과 순서 종속성 없는 별개 operator 판정**(계약 §6.1·§6.2 — App 설치는
   runs-on과 무관한 별개 표면, 계약 §2.3). RESID-10(청구액 확인 — ledger 원문
   `CLOSED / BLOCKED`, "API 403 관측 기록", 외부 계정 소유자 항목)도 별개다.
   러너 자체의 제거는 계약 §5 4~5단계(drain → 라벨 소비자 0 확인 후 group 7에서
   제거·offline)에만 속한다.
4. 본 권고는 조사 결과에 기반한 **결정자료**다 — 기질 선택·프로비저닝·전환
   실행·Northflank 제거 실행은 operator 전용이다(AGENTS.md §0.3, #1204 §3).

## 7. UNKNOWN (관측하지 못한 것 — UNKNOWN은 UNKNOWN으로 기록)

| # | 항목 | 상태 |
|---|---|---|
| U1 | **Ubicloud 커스텀 라벨 생성 가능성** — Q7 실측(2026-10-23, 공개 소스)은 "커스텀 라벨은 support 팀만 생성"인데, Ubicloud changelog(2025-10)는 "You can now create custom labels for your GitHub runners"를 발표했다. 두 출처가 상충하며 본 조사에서 콘솔 재검증은 수행하지 않았다(콘솔 접근 없음 — 읽기 전용 조사 범위 밖). **판정에는 불영향** — 라벨이 만들어져도 C2·H9·12월 사슬이 구조적 차단이다 | UNKNOWN |
| U2 | **Northflank 청구액** — RESID-10 CLOSED/BLOCKED(API 403, 경로 접근 불가). 기존 환경 비용 대조표의 Northflank 셀은 공백으로 남는다 | UNKNOWN (ledger 이관) |
| U3 | **Ubicloud 기질의 clock 오프셋** — −1h 관측은 Northflank 기질의 속성이다. Ubicloud 러너의 시계 기준은 본 조사에서 관측하지 않았다(판정 불영향 — R4가 먼저 차단) | UNKNOWN |
| U4 | **12월 무인 폴백 경로의 실제 발화** — 12월 사전계약의 관측 창에서만 종결 가능한 별도 작업(계약 §3 — "GHEC가 소진되지 않으면 발화할 필요 없음") | 별도 작업 (계약 소관) |
| U5 | **새(미평가) 대안의 존재 가능성** — §5 표현 규율대로, 조사하지 않은 외부 자체호스트 옵션의 전수는 본 조사 범위가 아니다 | 범위 밖 |

## 8. 실측 기록 (Completion Evidence — command → observation)

측정 일시 2026-11-02, 기준 revision `origin/main` @ `ed9cab36d`. **전부 읽기
전용** — 인프라 변경 0건(변수·시크릿·러너·그룹·워크플로·App 어떤 것도
수정하지 않았다).

| # | 명령 | 관측 |
|---|---|---|
| 1 | `git show origin/main:.github/workflows/ci-provider-router.yml` | `runs-on: [self-hosted, axiom-control]`(:116, CI_RUNNER_MAP 참조 0건), 트리거 4종(workflow_run 5 required 워크플로·push main·schedule `'7,37 * * * *'`·workflow_dispatch force_trial), `permissions: actions:write + checks:read`, `environment: ci-provider-router`, concurrency `group: ci-provider-router + cancel-in-progress: false + queue: max`, App 토큰 in-job 민팅 → `PATCH /actions/variables/CI_RUNNER_MAP`, fail-closed 분기(등록 게이트·GET 실패·schema 위반·write 실패) |
| 2 | `git grep -n 'runs-on' origin/main -- .github/workflows/` | 46건 — `[self-hosted, axiom-control]` 소비자는 `ci-provider-router.yml:116` **1건**; 나머지는 `CI_RUNNER_MAP` 템플릿 또는 GitHub-hosted 고정 라벨(ubuntu-24.04/ubuntu-slim/ubuntu-24.04-arm) |
| 3 | `gh api repos/Archright/Axiom/actions/runs/{41389269223,41388161596,41387654980,41386915119,41367787229,41291765000}/jobs` | 6건 전부 `runner_name=axiom-control-northflank`, `runner_group_name=axiom-control`, `labels=[self-hosted, axiom-control]`, conclusion=success (workflow_run·push·schedule 발화 혼합) |
| 4 | `gh api /orgs/Archright/actions/runner-groups/7` + `/7/runners` | `name=axiom-control, restricted_to_workflows=true`; 러너 1대 — `axiom-control-northflank, id=6185, Linux, online, busy, labels=[self-hosted, Linux, X64, axiom-control]` |
| 5 | `gh api /orgs/Archright/actions/runners?per_page=100` | org 등록 러너 **전체 1대**(Northflank 러너가 유일 self-hosted) |
| 6 | `gh api /orgs/Archright/actions/runner-groups?per_page=100` + 그룹 3·4·5 runners | 그룹: 1(Default)·3(axiom-ci)·4(axiom-publisher, restricted)·5(Default)·7(axiom-control, restricted); **그룹 3·4·5 runners total_count=0** — 빈 그룹 |
| 7 | `gh api repos/Archright/Axiom/actions/runners` | repo 레벨 러너 `total_count: 0` |
| 8 | `gh api '.../workflows/ci-provider-router.yml/runs?event=schedule&per_page=8'` | 최근 schedule run 8건 전부 success; 간격 3h14m–7h08m(30분 cron 명목 — Q10 재확인) |
| 9 | `gh api '.../runs?created=>=2026-10-26&per_page=1'` | `total_count=1501` — 최근 7일 라우터 run 물량 |
| 10 | 잡 소요 샘플 (run 5건 jobs API, `completed_at - started_at`) | 21·10·11·19·17초 |
| 11 | `gh api repos/Archright/Axiom/actions/variables/CI_RUNNER_MAP` | `mode=ghec, state=GHEC_ACTIVE, generation=15, x64=ubuntu-24.04, fallback_provider=ubicloud, return_acceptance=confirmed, return_acceptance_run_id=41389395375, last_transition_at=2026-11-02T04:37:02Z (GHEC_RETURN_CONFIRMED)` |
| 12 | Ubicloud 공식 문서 (context7 `/websites/ubicloud` → docs.ubicloud.com) | §4.3 인용 — JIT at-most-one-job 에페머럴, 잡당 클린 VM, 독일 지역 자동 배정(Hetzner/Leaseweb, 프로비저닝 시점 가용성), AWS spillover(2026-09), 분당 과금($2.5/월 크레딧 = standard-2 1,250분) — **고정·상시 러너 제품 속성 부재** |
| 13 | `gh pr view 1204` | `state=MERGED, mergedAt=2026-11-02T03:52:01Z` — `northflank_medium_selection_request_2026-11-02.md` 착지(D1 결정요청서) 확인 |
| 14 | 문서 정독 (origin/main) | 전환 계약(§2 실측·§3 3제약·§4·§5·§6), 인시던트 기록(§2 노출면·§5.1 방침), quirks Q1–Q18 헤더 + Q2·Q7·Q10·Q12 전문 — **quirks 내 Northflank 언급 0건**(git grep 실측), 12월 사전계약(S1–S3·§2.3 UNKNOWN·§2.4 사후 기준 변경 금지), 복귀수용 문서 §2(−1h), residual ledger RESID-10 행(146행 — CLOSED/BLOCKED) |
| 15 | `git grep -i northflank origin/main -- docs/spec/ci_provider_failover_quirks.md` | 매치 0건 — Northflank 고유 quirk는 quirks 문서에 없고 전환 계약·인시던트·복귀수용 문서에 기록 |

## 참조

- `docs/spec/northflank_control_plane_transition_contract.md` — 3제약(§3)·실행
  순서(§5)·별개 operator 판정(§6)의 정본. 본 문서는 그 어느 절도 개정하지 않는다.
- `docs/evidence/northflank_medium_selection_request_2026-11-02.md` — D1
  결정요청서(#1204). 본 문서는 그 §4 절차 위임 구조를 유지한다.
- `docs/spec/ci_provider_december_unattended_fallback_acceptance_contract.md`
  — 무인 폴백 복귀 판정 기준(S1–S3) — R4 보강 근거.
- `docs/spec/ci_provider_failover_quirks.md` — Q2(과금 hard-stop 영역)·Q3/Q9
  (변수 쓰기)·Q5(queue)·Q7(Ubicloud identity·과금)·Q8(무 isolation)·Q10
  (schedule 지연)·Q12(큐 24h·rerun).
- `docs/evidence/northflank_incident_response_2026-10-31.md` — 운영자 방침·
  노출면·별개 operator 항목.
- `docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md` — −1h 시계
  오프셋(§2)·census 계약(§5).
- `docs/agents/operations.md` — Hetzner fleet 제거(CI=0 cutover)·Environment.
