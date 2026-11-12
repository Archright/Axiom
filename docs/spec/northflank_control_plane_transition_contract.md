# Northflank 제어면 세대 전환 계약 (실행 대기 — operator 결정)

> **종류**: 실행 경계 전환 사전계약 — CI 제어기(`ci-provider-router`)의 실행
> 기질을 Northflank에서 operator 소유 신규 자체호스트 기질로 전환하는 절차를
> **사전에** 계약으로 고정한다. 본 문서는 전환의 **순서·불변식·판정 항목**만
> 규정하며, 전환 실행 자체는 **operator의 기질 결정을 대기하는 별도 작업**이다
> (AGENTS.md §2.5/§2.6 — authority·state transition·failure semantics가
> 정의된 절차 없이 실행 경계를 변경하지 않는다).
> **상태**: 계약 확정(2026-11-02) — 실행 대기(소유자: operator, 기질 결정).
> **착지 범위**: 이 착지는 계약 정본화이며 실제 운영 검증(Northflank 전환
> 실행·전환 후 관측)은 별도이다. 본 문서는 전환이 수행됐다는 주장을 포함하지
> 않는다.
> **선행 문서**: `docs/evidence/northflank_incident_response_2026-10-31.md`
> (보안 사고 대응 완료 기록 — §5 잔여에 운영자 방침·별도 절차 요구가 기록돼
> 있다), `docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md`
> (시계 오프셋 관측 §2 — −1h), `docs/agents/ci_epoch_cutover.md`(AGENTS.md
> §2.5 절차 정본), `docs/agents/authority_invariant_protocol.md`(§2.6),
> `docs/spec/ci_provider_failover_quirks.md`.

## 1. 배경

운영자 방침(2026-10-31): **"Northflank를 Axiom에 더 사용하지 않는다"**
(`northflank_incident_response_2026-10-31.md` §5.1). 같은 항목은 runs-on
평면의 Northflank 제거가 **실행 경계 변경**이므로 별도 절차(§2.5/§2.6 규율)로만
처리되어야 한다고 명시하며, 본 문서가 그 별도 절차의 사전계약이다. 방침은
의도이지 실행이 아니므로, 전환은 operator의 기질 결정이 선행될 때까지
시작되지 않는다.

## 2. 실측 확정 사실 (그대로 인용 — 재확인 2026-11-02)

1. **runs-on 단일 지점**: `runs-on: [self-hosted, axiom-control]` 참조는
   `ci-provider-router.yml:116` **단일 지점**이다(저장소 전역 Northflank
   참조 1건 — 사고 대응 기록 §2의 "[live]" 관측과 일치).
2. **러너 그룹 계약**: org runner group **7(axiom-control)**은 해당 워크플로
   **1개 파일**로 restricted다. 라이브 재확인(2026-11-02, `gh api`):
   `runner-groups/7` → `name=axiom-control, restricted_to_workflows=true,
   selected_workflows=["Archright/Axiom/.github/workflows/ci-provider-router.yml@refs/heads/main"]`,
   허용 저장소는 Axiom 1개. 소속 러너는 **1대** —
   `axiom-control-northflank`(id **6185**, Linux, online).
3. **App 설치는 별개 표면**: Northflank GitHub App 설치
   (`northflank-cloud-build-run`, installation id 175323502,
   `repository_selection: all` — 라이브 재확인 2026-11-02)는 **runs-on과
   무관한 별개 표면**이다. GitHub App 설치는 워크플로 잡의 러너 배정에
   영향을 주지 않는다 — 러너 배정의 계약은 라벨(`[self-hosted,
   axiom-control]`)과 그룹 접근 정책(그룹 7)이며, App 설치는 그 어느 쪽도
   아니다. 따라서 App 설치 해제는 러너 전환과 **순서 종속성이 없다**(§6).
4. **시계 오프셋 관측**: Northflank 제어면 러너의 라우터 clock은 GitHub 정본
   UTC 대비 **−1h** 관측이다(복귀수용 문서 §2 — 전수조사 모집단 기준 T
   결속에 사용된 실측). 이 오프셋은 Northflank 기질의 속성이며, 전환 후에는
   새 기질의 clock 기준을 다시 관측해 기록해야 한다(§5 6단계).
5. **운영자 방침**: §1의 2026-10-31 방침. runs-on 평면 제거는 §2.5/§2.6
   규율의 별도 절차로만 처리한다(사고 대응 기록 §5.1).

## 3. 제어기 배치 3제약 (원문 인용)

`ci-provider-router.yml:107–115` 주석(원문 — 현재 구현의 배치 근거; runs-on
단일 지점은 :116):

> 고정 라벨 — CI_RUNNER_MAP 절대 참조 금지. 제어기가 자기가 제어하는
> 변수를 읽어 자기 러너를 고르면 자기 참조 고리가 생긴다(전환 도중 제어기가
> 스스로의 러너를 잃는다).
> 2026-10-26 이전에는 ubicloud-standard-2였다. 제어기를 폴백 공급자 중
> 하나(Ubicloud) 위에 두면 그 공급자를 해지할 수 없고, GHEC 포함량이 소진된
> 구간에서는 제어기 자신이 과금 대상이 된다. 그래서 제어기는 Northflank의
> axiom-control 러너 그룹(org group id 7 — 저장소 Axiom 1개, 이 워크플로
> 1개 파일로 접근 제한)에서 돈다. 선택은 라벨로 한다 — 라벨이 계약이고
> 접근 정책은 그룹이 강제한다.

정리하면 3제약이다. **어떤 대체 기질도 3개를 모두 만족해야 한다.**

| # | 제약 | 내용 |
|---|---|---|
| C1 | **CI_RUNNER_MAP 자기참조 금지** | 제어기는 고정 라벨로 자기 러너를 선택해야 한다. `runs-on`이 CI_RUNNER_MAP을 읽으면 전환 도중 제어기가 스스로의 러너를 잃는다(자기 참조 고리). |
| C2 | **폴백 공급자(Ubicloud) 위 배치 금지** | 제어기를 폴백 공급자 위에 두면 그 공급자를 해지할 수 없게 된다(제어기 이주가 해지의 선결 조건이 되는 순환). |
| C3 | **GHEC 과금 회피** | GHEC 포함량이 소진된 구간에서 제어기 자신이 과금 대상이 되어서는 안 된다. |

### 3.1 GHEC 배치의 위반 근거

- **C3 위반(주석 원문)**: "GHEC 포함량이 소진된 구간에서는 제어기 자신이
  과금 대상이 된다". GHEC 소진 구간이야말로 제어기의 존재 이유(0-step 차단
  관측 → Ubicloud 전이, quirks Q1/Q2)가 발동하는 창이므로, GHEC 배치는
  제어기를 **필요한 바로 그 창에** 비용·차단 위험에 놓이게 한다.
- **[derived] 차단 자기모순**: 예산 hard-stop의 강제 영역은 GitHub-hosted
  dispatch뿐이다(quirks Q2/rule 2). 제어기가 GHEC 위에 있으면, 제어기가
  차단을 관측해야 하는 동일한 hard-stop이 제어기 자신의 dispatch를 0-step
  차단한다 — failover 제어기가 failover가 필요한 상태에서 동작 불능이 되는
  구조적 자기모순이다.

### 3.2 Ubicloud 배치의 위반 근거

- **C2 위반(주석 원문)**: "제어기를 폴백 공급자 중 하나(Ubicloud) 위에 두면
  그 공급자를 해지할 수 없고". Ubicloud 해지(또는 요금·가용 재판단)가
  언제든 제어기 이주를 선결 조건으로 요구하는 순환이며, 폴백 공급자 장애가
  곧 제어기 정지다(H9 이중 장애 — `ci-provider-router.yml` 신뢰 경계 절:
  제어기가 Ubicloud 라벨에서 돈다는 것은 Ubicloud가 살아 있다는 관측을
  전제한다). 실제로 2026-10-26 이전 제어기는 Ubicloud 위에서
  `ubicloud-standard-2`로 실행됐고(주석 원문), C2는 그 배치의 교훈이다.

### 3.3 C1은 배치 선택과 무관한 구조 제약

C1은 어느 공급자 위에 두든 동일하게 적용되는 **라벨 계약**이다 — 전환 후에도
`runs-on: [self-hosted, axiom-control]` 고정 라벨(또는 동등한 고정 식별)과
그룹 접근 정책이 유지되어야 한다. 라벨이 계약이고 접근 정책은 그룹이 강제한다
(주석 원문). CI_RUNNER_MAP을 `runs-on`에서 참조하는 설계는 어떤 기질에서도
금지된다.

## 4. 대체 기질 판정 (표현 규율)

**"현재 확인·평가된 대안 중 operator 소유 신규 자체호스트 기질만이 3제약을
모두 만족하는 후보로 확인됐다."**

- operator 소유 신규 자체호스트 기질은: C1 — 고정 라벨·그룹 접근 정책을
  operator가 직접 구성하므로 만족, C2 — Ubicloud와 무관하므로 만족, C3 —
  GitHub-hosted 과금 영역 밖이므로(quirks Q2 — self-hosted는 Actions 분을
  소비하지 않는다) 만족한다.
- **'유일한 선택' 같은 절대 표현을 쓰지 않는다.** 평가하지 않은 대안(다른
  자체호스트 클라우드, 추가 GitHub App 관리 러너 등)을 사실처럼 배제하지
  않는다. 위 문장은 "확인·평가된 범위에서"라는 한정을 유지하며, 새 대안의
  평가가 이 계약을 변경하지 않는다 — 어떤 후보든 §3의 3제약을 판정 기준으로
  통과해야 한다.
- 기질의 최종 선정·프로비저닝·비용 판단은 **operator 결정 항목**이다. 본
  계약은 선정 자체를 수행하지 않는다.

## 5. 실행 순서 계약 (단일 일관 세대 전환)

전환은 **단일 일관 세대(coherent generation) 전환**이다(AGENTS.md §2.5 —
활성 실행 경계의 in-place 부분 수정으로 상태를 혼합하지 않는다). 순서는
아래에 고정되며, 각 단계의 판정은 기계 관측 증거를 남긴다(§2.6).

| # | 단계 | 계약 |
|---|---|---|
| 1 | **operator 기질 결정** | §4 후보 조건을 만족하는 기질을 operator가 선정·프로비저닝한다. 선정 근거(3제약 대조)를 기록한다. |
| 2 | **신규 제어면 러너 canary** | 신규 러너를 그룹 7(axiom-control)에 등록하고, 동일 라벨 `[self-hosted, axiom-control]`로 `ci-provider-router` 실제 성공 실행을 관측한다(router run success + job의 runner_name/runner_id가 신규 러너로 귀속 — canary는 전용 프로브를 새로 만들지 않고 제어기 자체의 성공 실행을 증거로 쓴다). 신규 러너 위 수동 trial(force_trial) 실행이 이 단계의 검증 경로다. |
| 3 | **runs-on + 그룹 7 재구성의 단일 일관 세대 전환 (§2.5/§2.6)** | 워크플로 파일(runs-on) 변경·그룹 7 멤버십·(필요 시) 라벨 정책을 **하나의 세대 전환 단위**(단일 PR + epoch record)로 착지한다. ci_epoch_cutover.md 10단계(Freeze → Record → … → Rollback)를 적용한다 — dispatch-only 비-required 프로브도 명시 포함된다(:113 anti-rationalization). 워크플로 파일 변경은 push rule 통제 표면이므로 운영자 rotation 경로가 필요하다. |
| 4 | **기존 잡 drain** | Northflank 러너(6185) 위의 **진행 중 잡 완료를 대기**한다. 진행 잡이 없는 것(전 잡 terminal)을 관측한 뒤에만 다음 단계로 간다 — 실행 중 제어 잡을 죽이는 전환이 아니다. |
| 5 | **라벨 소비자 0 확인** | 저장소 전역에서 `axiom-control` 라벨·Northflank 참조의 소비자가 0건임을 확인한다(grep 전수 + 러너 그룹 멤버십 재조회). Northflank 러너를 그룹에서 제거·offline 처리한다. |
| 6 | **전환 후 관측 + 시계 오프셋 정리** | 전환 후 router run의 전 잡 identity가 신규 기질임을 census 관례(모집단 정의 + id 기반 분류 — 복귀수용 문서 §5)로 관측한다. Northflank의 −1h 시계 오프셋(§2.4)이 소멸하므로, 이후 변수 타임스탬프·관측 기록의 clock 기준을 **새 기질 기준으로 재정의**하고, 기존 기록(2026-11-01 census 등)의 오프셋 표기는 역사 기록으로 유지한다 — 과거 기록을 소급 수정하지 않는다. |

**롤백 경로**: 단계 2(canary)에서 신규 러너가 검증에 실패하면 그룹 7에서
신규 러너만 제거하고 Northflank 기질은 그대로 유지된다 — Northflank 제거가
아니라 신규 후보 기각이므로 현행 실행 경계는 무손상이다. 단계 3 이후의
문제는 ci_epoch_cutover.md 10단계(Rollback — revert PR)가 다룬다.

**failure semantics**: 단계 3의 워크플로 변경이 착지했으나 신규 러너가
offline이면 제어기 잡은 self-hosted 큐 계약(24h 대기 후 실패 — quirks Q12
문서 근거)에 들어가고, 그 기간의 라우터 자동 제어는 정지된다. 이 때문에
단계 순서(러너 canary 선행 — 2단계가 3단계의 전제)가 계약이다. 전환 창에서의
제어기 정지 시간은 관측 항목으로 기록한다.

## 6. 별개 operator 판정 항목 (본 전환과 분리)

다음 항목은 러너 전환과 **순서 종속성 없는 별개 판정**이며, 본 계약의 실행
순서에 포함되지 않는다:

1. **Northflank GitHub App 설치 해제** (`northflank-cloud-build-run`,
   `repository_selection: all`) — §2.3의 별개 표면 근거로, 러너 전환 전에
   해제해도 제어기 실행에 영향이 없다. 시점은 operator 판정 항목이다.
2. **Northflank 콘솔 계좌 폐기·시크릿 점검** — 사고 대응 기록 §5.2/§5.3의
   잔여(AI 키 평면 부재·폐기 시 소멸 예정, 폐기 전 콘솔 잔존 확인은 운영자
   항목). 계좌 폐기 시점은 operator 결정 항목이다.

이 둘은 §5의 전환이 종결되기 전에 수행될 수도 있고 후에 수행될 수도 있다 —
어느 쪽이든 본 전환 계약의 전제조건이 아니다.

## 7. 본 계약의 위치 (범위 명시)

이 착지는 **계약 정본화**이며, 실제 운영 검증 — Northflank 전환 실행·전환 후
관측·Northflank 해지 — 는 operator의 기질 결정 이후의 별도 작업이다. 본 문서는
"Northflank가 제거됐다", "전환이 안전하다"는 주장을 포함하지 않으며, §5의
순서가 지켜지지 않은 전환은 본 계약 위반이다(AGENTS.md §2.5 — 절차 축약
anti-rationalization 포함).

## 참조

- `docs/evidence/northflank_incident_response_2026-10-31.md` — 운영자 방침
  (§5.1), 노출면 실측(§2), 별개 operator 항목(§5.2/§5.3)
- `docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md` — 시계
  오프셋 −1h 관측(§2), census 모집단 계약(§5), axiom-control 자체호스트
  잡 관측(§6 재관측 census)
- `.github/workflows/ci-provider-router.yml` — runs-on 단일 지점(:116),
  배치 3제약 원문(:107–115), 신뢰 경계(H9)
- `docs/agents/ci_epoch_cutover.md` — §2.5 세대 전환 10단계 절차 정본
- `docs/agents/authority_invariant_protocol.md` — §2.6 변경 불변조건 프로토콜
- `docs/spec/ci_provider_failover_quirks.md` — Q2(과금·hard-stop 영역),
  Q3/Q9(변수 쓰기 경로), Q12(self-hosted 큐 24h), Deterministic rule 2
- 2026-11-02 라이브 재확인: `gh api /orgs/Archright/actions/runner-groups/7`
  및 `.../runners`, `gh api /orgs/Archright/installations` (본 문서 §2에
  실측값 기록)
