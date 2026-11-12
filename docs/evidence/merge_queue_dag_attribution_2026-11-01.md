# merge_group DAG 귀속 보고서 — 슬라이스 1-b 종결 + 공식 baseline P95 (2026-11-01)

> **종류**: 조사 보고 + baseline 측정 기록. CI 시간 최적화 슬라이스 1의 마지막 단계 —
> (1) merge_group admission-gate DAG의 귀속 조사 결과 보고, (2) 동결 계약
> `slo_official_measurement_prereg_2026-11-01.md`(PR #1166, merge a8f7464c5)의 모집단·dedupe·R-7 식을
> 적용한 **baseline P95 직접 계산**.
> **권위**: 본 문서는 **Reporter**다 — GitHub merge authority(required checks·merge queue·MERGE commit)를
> 대체하지 않으며(Authority ≠ Adapter, AGENTS.md §2.3), 어떤 게이트도 본 문서의 값을 소비하지 않는다.
> 모든 관측은 GET-only·`gh` 네이티브 인증(AGENTS.md §2.4).
> **Date**: 2026-11-01 · **Branch**: `work/dag-attribution-report` · **Scope**: 본 문서 1건(`docs/evidence/*.md`)
> — 코드·워크플로·게이트·핀·도구 변경 0건. docs-only → trust surface 아님(정상 merge queue 경로).
> **§8 계산 준거**: 동결 계약은 관측 프로토콜(§9)까지 규율하므로 baseline 계산은 그 규칙을 그대로 적용했다 —
> 창 분할 스윕·run ID dedupe·merge-queue 그룹 최종 착지 런 모집단·취소 분리·전수 단일 GET 교차검증.
> 사용한 정확한 명령·python 코드 전문을 §8.8에 수록한다(같은 입력 → 같은 값).

---

## 1. 요약 판정

**BLOCKED — 3속성 모두 부정이 입증되는 순수 스케줄링 edge는 존재하지 않는다.** 전 edge가 데이터 의존
또는 증거 순서/판정 의미에 근거가 있으며, 실측상 needs 간선 자체의 시간 비용은 0초였다. 병목은 간선이
아니라 (1) 잡 실행시간 상위 2종(lane 292s·attest/admission-check 222s), (2) ubicloud 러너 배정 지연
(잡당 p50 22s × 직렬 5~6홉), (3) failover 시대 혼잡(p50 1,928s)이다.

- **슬라이스 2(단일 edge 착지)는 발동하지 않는다** — 후보 요건(안전한 순수 스케줄링 edge·절감 발생)이
  불성립하기 때문이다(§7).
- **공식 baseline P95(§8)**: **1,988.0초** (n=133, R-7, 창 2026-10-21T16:40:44Z~2026-11-01T13:00:00Z) —
  SLO of record 480s 대비 **≈4.1×**. 진단 최적 gen12-ubicloud 층 P95 1,133.4s(n=44)가 현재 구조의
  달성 가능 대역을 가늠게 한다.

## 2. 관측 개요

| 항목 | 값 |
|---|---|
| 창 정의 | 2026-10-21T16:40:44Z(B2 병합, v5 세대 시작) ~ 2026-11-01T13:00:00Z — `docs/evidence/judgment_key_v5_measurement_prereg_2026-10-31.md` §2 "역사 창" 계승 |
| 모집단 | merge_group 런 **1,184건**(8개 워크플로) |
| 분할 | REST 1,000 상한 회피 3분할(10-21T16:40Z~10-25 / 10-26~10-29 / 10-30~11-01), 창별 total 600+184+400=1,184 일치 |
| dedupe | run ID `sort -n -u` — 중복 0건, 분할 경계 시각(10-26T00:00Z·10-30T00:00Z) 생성 런 0건 → 경계 이중계산 없음 |
| admission-gate 모집단 | **150런 = 성공 135 · 실패 8 · 취소 7** (path `.github/workflows/admission-gate-v2.yml`, head_repository Archright/Axiom 전수) |
| 나머지 7개 워크플로 | landing-integrity 150 성공 · bsec-integrity 150 성공 · generation-acceptance 147 성공 · debt-registry-gate 147/1/2 · observer-manifest-consistency 137/11/2 · probe-merge-queue 135/15/0 · axiom-operational-slice 135/1/1 — 전부 **단일 잡 워크플로(내부 needs 0)** |
| 표본 | **89런 · 1,944잡**: 최근 7일(≥10-25T12:57Z) admission-gate 전수 74 + 층화 15(ghec 7 — NR%3 계통추출, failover 8 — NR%7) + #1150 실패 런 41202574932 포함(최근 7일에 속함). 표본 결론 분포: 성공 75 · 실패 7 · 취소 7 |
| provider 귀속 | 잡 `runner_group_id`: 0=GHEC(1,072잡), 1=ubicloud(872잡) — 창 내 실측 |

## 3. 표본 잡 타이밍 (p50, 단위 초, n=87~89)

| 잡 | wait started−created | 대기 귀속 | duration |
|---|---|---|---|
| attest / build-base-artifacts | 22 | 러너 배정(루트, 의존 없음) | 77 |
| attest / go-critical-lane (0/1) | 21 | 러너 배정(부모 완료 후 p50 21) | **292** (max 817) |
| attest / go-critical-rollup | 21 | 러너 배정 | 6 |
| attest / admission-check | 21 | 러너 배정 | **222** |
| closure-deriver | (루트) | — | 83 |
| gateway / select | 19→부모 후 20 | 러너 배정 | 43 |
| mint-prepare / prepare | 21 | 러너 배정 | 51 |
| mint-publish / publish | 19→부모 후 20 | 러너 배정 | 53 |
| verdict / admission-check | 21 | 러너 배정 | 74 |
| admission-check(최종 집계) | 20 | 러너 배정 | 6 |

**귀속 방법**: `started − max(needs 완료)`가 전 잡 유형에서 p50 19~22초로 균일 → 의존성 완료 후 지연 =
**러너 배정/프로비저닝**(원인 분해 API 필드 부재는 UNKNOWN이지만, rgid별 분해로 원인 특정):
**rgid=0(GHEC) n=1,072 p50 0.0초 vs rgid=1(ubicloud) n=872 p50 22.0초**. 의존성 실행 중 구간의 원인
분해는 불가 → 해당 구간은 UNKNOWN 유지(표기대로). 런 수준 시작 지연(created→run_started)은 전 epoch
p50 0초(failover 최대 2,701초 이상치 1건).

## 4. 정적 DAG 맵 (실행 주체 = org `Archright/.github`의 `admission-gate-v2.yml`; callee 3종은 SHA pin)

```
[admission-gate-v2 (merge_group, concurrency 블록 없음)]
anchor-resolve (PR 전용, :191-192 — MG에선 skip)
  ├→ closure-deriver (:221 needs, if:!cancelled) ──→ gateway (:574-586, V-H 레이스) ─→ mint-publish ┐
  ├→ attest (:430-443, admission-check.yml@f1871393 stage=attest)                                  │
  │     내부: build-base-artifacts(:200, stage=attest만) ┬→ go-critical-lane×2 (:2890)             │
  │                                                    └→ admission-check callee (:669-676)        │
  └→ mint-prepare (:464-496, certificate-mint.yml@d117ae8 stage=prepare)                           │
        ├→ mint-publish (:539-563, stage=publish) ←────────────────────────────────────────────────┤
        └→ verdict (:658-670, admission-check.yml stage=verdict)                                   │
              [verdict 내부: build/lane skip, admission-check callee만 실행]                        │
최종 admission-check (:671-713, needs 7개 + always(), 각 result==success 강제 — anchor skip만 off-PR 허용)
```

- pin 검증: admission-check·certificate-mint는 **pin==origin/main 동일**; runner-pool-acceptance는
  **pin(@18b1800)≠main**(pin 버전에 sl09-scope·executed-jobs 없음) — 잡 목록 실측(22잡 구성)과 pin
  버전이 정확히 일치.
- epoch manifest(`config/policy/epoch_manifest.json` @origin/main): implementedSlices에 **SL-0713
  포함**(P5/P6 발화), **SL-09 부재**(gateway 실행 leg 전부 skip — 관측과 일치).
- 병렬 필수 체크 4종(bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice)은
  모두 단일 잡 → DAG 후보 없음.

## 5. edge 속성 매트릭스

a=데이터 의존, b=증거 순서, c=실패 전파 — **3속성은 상호배타가 아니며 개별 판정이다**(한 edge가 복수
속성을 동시에 긍정할 수 있다; 아래 표가 그 실제다).

| edge | (a) | (b) | (c) | 근거 (file:line) |
|---|---|---|---|---|
| attest→mint-prepare | **TRUE** | TRUE | — | witness+base-artifact 2종 소비 명시(`admission-gate-v2.yml:468-476`), witness 생성·업로드(`admission-check.yml:1686-1784`·`:1056`), run-scoped 소비(`certificate-mint@pin:645-705·906-983`) |
| mint-prepare→mint-publish | **TRUE** | TRUE | — | subject-certificate-\<attempt\> 업로드(`certificate-mint@pin:1215`)→publish 소비(`:1794` 구간), 선언(`admission-gate-v2.yml:540-546`) |
| mint-prepare→verdict | **TRUE** | TRUE | TRUE | verdict의 cert fetch(`admission-check.yml:1972-1980`, 근거 `:1957-1971`), certRequired=true. 제거 시 첫 착지 런에서 ledger 부재 → NO_CERT red(집계 의미 변화) |
| closure-deriver→verdict | **TRUE** | TRUE | TRUE | derived-closure 다운로드(`admission-check.yml:1948-1953`, if stage=verdict∧scope_sl02∧landing — SL-02 manifest 등재), derived-M overlay M은 MG 전용(`admission-gate-v2.yml:114-127`). 부재 = fail-closed 판정(soft 다운로드는 수송 복원력일 뿐) |
| closure-deriver→gateway | 간접 TRUE | **TRUE** | — | V-H 아티팩트 레이스 차단 계약(`admission-gate-v2.yml:574-583` — H 코드 게시자의 선점 차단), proof-reconcile의 derived-closure 소비(`runner-pool-acceptance@pin:1076-1083`, 현재 SL-09 notYet skip이나 계약 유효) |
| gateway→mint-publish | **TRUE**(현재 발화) | TRUE | TRUE | P5 tested-tree-digest 3중 등가(`certificate-mint@pin:1900-1955`, 업로더 `runner-pool-acceptance@pin:221-230`) + P6 lane 결론 jobs API 평가(`:2013-2014`) — **scope_sl0713 && landing, 현 manifest 발화**. 간선 부재 레이스 실측 런 37569755722(`admission-gate-v2.yml:552-556`) |
| 7×→최종 admission-check | — | — | **TRUE**(전 edge) | 각 result success 강제, skip→FAILURE(`admission-gate-v2.yml:671-713`) — 임의 edge 제거 = ∧ 항 소멸 = 판정 의미 변화 |
| anchor-resolve→5종 | PR: TRUE / MG: 부정 | MG 부정 | MG 부정 | B_STAR 출력 소비(`:216-219·:441·:494·:561·:669`). **PR venue에서 데이터 간선이므로 공유 파일에서 제거 불가** + MG에서 부모가 생성 즉시 terminal(관측 슬랙 0) → 절감 0 |
| build→go-critical-lane / build+lane→attest-admission-check / lane→rollup (callee 내부) | **TRUE** | — | TRUE(rollup) | 소비 간선 명시(`admission-check.yml:670-675`), base-artifact 다운로드(`:905`), rollup의 LANE_RESULT 집계(`:3684-3700`). 실측: lane이 구속 부모인 런 **89/89** |
| runner-pool@pin 내부 8 edge | **TRUE**(전부) | — | — | select 출력 소비(`:475-476·:723-724·:836`), candidate-arm64 소비(`:823`+B3 주석 `:815-821`), junit 소비(`:991`), decisionHash B4(`:996-997`), executed-\* 소비(`:1097-1102`, ci-bootstrap 실행 40/89런 실측) |
| certificate-mint 내부 | — | — | — | 내부 needs 없음(단일 잡 stage 2종 `:183-189·:1240-1246`) |

## 6. edge별 대기 원인 귀속

- **간선 슬랙(V.created − max(부모 완료)) = 전 유형 p50 0.0초**(n=87~89/유형) — GitHub가 부모 완료
  즉시 자식을 생성. needs 간선 자체는 벽시계 시간을 소비하지 않는다.
- **간선 제거 잠재 절감도 0**: verdict·mint-publish의 구속 부모는 각각 **mint-prepare 87/87**,
  mint-publish의 구속 부모는 mint-prepare 87/87 — 즉 데이터 대기가 곧 임계경로.
  closure-deriver→verdict(0/87), gateway→mint-publish(0/87)는 임계경로 외(부모가 수 분 먼저 완료) —
  제거해도 절감 0이고 데이터 의존 때문에 제거 자체가 불가.
- 잡당 ~20초 시작 지연은 간선 수가 아니라 **직렬 잡 수 × provider**의 함수(GHEC 0초) → gen12 성공 런
  직렬 5~6홉 ≈ 90~130초가 러너 배정 비용.
- UNKNOWN 명시: 개별 잡 실행 구간 내 러너·큐 혼합 원인 분해는 API 필드 부재로 불가(상기 rgid 분해가
  유일한 귀속). 이는 동결 계약 §8("혼합값을 단일 원인으로 보고하는 것을 금지", 귀속 불가 → UNKNOWN)과
  동일한 규율이다.

## 7. BLOCKED 판정 근거

- 창 내 전 edge(오케스트레이터 17 + callee 4 + gateway lane 8)가 3속성 중 최소 1개를 file:line으로
  긍정한다. 두 개의 과거 순수 간선은 이미 제거됐다: **P1**(mint-publish→verdict,
  `docs/evidence/generation_promotion_hnew_2026-10-17.md` — "publish→verdict는 스케줄링 산물",
  `admission-gate-v2.yml:653-656`)과 **B3**(gateway-shard←ci-bootstrap,
  `runner-pool-acceptance@pin:815-821`). 남은 간선 중 MG에서 공허해 보이는 것(anchor-resolve→X)은
  (i) 공유 파일의 PR venue 데이터 간선이고 (ii) MG 벽시계 기여 0이라 후보 요건(절감 발생) 자체가
  불성립.
- P1 실패 전파 재확인: #1150 런 41202574932 — verdict 잡 124543038403 실패(13:01:48Z) → 최종
  admission-check 124544412963 실패(13:02:15Z).
- 문서 추정치 290~430초(조사 착수 시점 배경 수치 참조)는 DAG 간선 제거에는 귀속 불가 — 관측된 벽시계
  구조(lane 292s·attest/adm 222s·ubicloud 배정 22s×홉·failover 혼잡)로 설명되며, 이는 전체 P95
  2,315.8초(v5 등록값) 대비 SLO 480초를 단독 달성시키는 근거가 아니다(참고치).
- **다음 조사 레버(DAG 복잡화 아님)**: 러너 용량·큐 대기(ubicloud 잡당 22초, failover p50 1,928s vs
  gen12 875.5s), provider별 차이(GHEC 0초 vs ubicloud 22초 — rgid 귀속 이미 확보). 상위 2잡 실행시간
  (lane 292s·attest/admission-check 222s)도 별개 축의 레버다.

## 8. 공식 baseline P95 — 동결 계약 적용 직접 계산

> **성격**: §1~§7은 조사 에이전트의 관측 보고다. §8은 본 보고서의 **신규 기여**로, 동결 계약
> `docs/evidence/slo_official_measurement_prereg_2026-11-01.md`의 규칙(모집단 §4 · dedupe §4 ·
> official_wall §2 · R-7 §6 · 표본 기준 §7 · epoch 분리 §5 · 관측 프로토콜 §9)을 **그대로** 적용해
> 계산했다. 계산 수행 시각: 2026-11-01T13:5xZ(창 종료 13:00:00Z 이후 — 창은 폐쇄 구간).

### 8.1 스윕·모집단

- **스윕**: `gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=<창>&per_page=100"
  --paginate` — 조사와 **동일 3분할 창**(10-21T16:40:44Z~10-26T00:00:00Z / 10-26T00:00:00Z~10-30T00:00:00Z
  / 10-30T00:00:00Z~11-01T13:00:00Z). 창별 `total_count` = **600·184·400**(합 1,184 — §2 표와 일치)이고
  수집 행 수가 각 창에서 total_count와 **정확히 일치** → 1,000 상한 포화·절단 서명 없음(§9 판정 기준
  충족).
- **run ID dedupe**(rule i): 창 간 중복 0건 → 1,184 unique.
- **admission-gate 필터**: path `.github/workflows/admission-gate-v2.yml` → **150런**(name 전부
  `admission-gate`) = 성공 135 · 실패 8 · 취소 7 — §2 표와 일치. head_repository 귀속: 필터 없이
  수집한 150런의 분할이 head_repository=Archright/Axiom 필터를 적용한 조사값과 동일하고, 각 창 page 1
  표본 300건 전부 `head_repository.full_name == "Archright/Axiom"` → 포크 런 부재 확인.
- **모집단 정의(§4)**: 완료(conclusion ∈ {success, failure}) 런, run 객체 단위, **merge-queue 그룹
  dedupe(rule ii)** 적용 — 동일 `head_branch`(`gh-readonly-queue/main/pr-N-*`) 그룹에서 **그룹의 마지막
  종결 런만 모집단**에 넣고, 그 외 중간 완료 런(재도크·dequeue 산물)은 모집단에서 제외해 경계 관측으로
  기록했다(v5 prereg §2의 #1144 선례 적용).

### 8.2 모집단·제외·취소 등록

| 구분 | n |
|---|---|
| **공식 모집단(최종 착지 완료 런)** | **133** (성공 130 · 실패 3) |
| 중간 완료 런(rule ii 제외 — 경계 관측) | 10 (성공 5 · 실패 5) |
| 취소 런(별도 등록 — §4 의무) | 7 |
| 미종결 런(관측 시점) | 0 |
| run_attempt 분포(공식 모집단) | 전부 1 (재시도 0) |

- **모집단 실패 3건**: 40427371548(#1107, 2,862s)·41202574932(#1150, 960s)·41203221931(769s).
- **중간 완료 런 10건(전부 경계 관측으로 기록)**: 40049469259(pr-1069, failure, 1,395s)·
  40102247094(pr-1094, success, 1,265s)·40103490389(pr-1094, success, 816s)·40433355093(pr-1109,
  failure, 2,481s)·40538606211(pr-1113, success, 2,016s)·40648270387(pr-1114, failure, 2,485s)·
  40736781613(pr-1116, failure, 2,377s)·41070945674(pr-1132, failure, 1,040s)·41165405857(pr-1144,
  success, 825s)·41180261390(pr-1144, success, 579s). — pr-1132의 1,040s·pr-1144의 825s·579s는 v5
  adjudication §8.2~8.3에 경계 관측으로 등록된 동일 런이다(독립 재관측 일치).
- **취소 런 별도 등록(§4 — ID·created·updated(=취소 시각)·사유는 판별 가능 관측 사실만)**:

| run | created_at | updated_at(취소 시각) | 큐 대기(started−created) | 사유(관측 사실) |
|---|---|---|---|---|
| 40530789599 | 10-27T15:25:15Z | 10-27T16:30:01Z | **2,701s** | 동일 그룹 후속 런 존재(재도크) — pr-1113 |
| 40612810198 | 10-28T01:04:38Z | 10-28T01:40:24Z | 0s | 동일 그룹 후속 런 존재(재도크) — pr-1114 |
| 40617132973 | 10-28T01:47:31Z | 10-28T02:19:02Z | 0s | 동일 그룹 후속 런 존재(재도크) — pr-1114 |
| 40643668714 | 10-28T06:24:34Z | 10-28T07:00:31Z | 0s | 동일 그룹 후속 런 존재(재도크) — pr-1114 |
| 40656549144 | 10-28T08:24:25Z | 10-28T08:57:11Z | 0s | 동일 그룹 후속 런 존재(재도크) — pr-1114 |
| 40743822335 | 10-28T18:18:08Z | 10-28T18:37:00Z | 0s | 동일 그룹 후속 런 존재(재도크) — pr-1116 |
| 40835650586 | 10-29T07:28:27Z | 10-29T07:53:27Z | 0s | 동일 그룹 후속 런 존재(재도크) — pr-1117 |

  (run 40530789599 = v5 adjudication §8.4의 취소 런 — wall 3,886s·큐 대기 ~45분으로 독립 재관측 일치.
  dequeue 사유 자체는 API 판별 불가 → 위 "사유"는 동일 그룹 후속 런 존재라는 관측 사실만 기록했다.)

- **Censoring 감시(§4 병행 의무)**: `cancel_ratio` = 7/140 = **5.0%**(역치 15% 미만), 취소 런 중앙 큐
  대기 **0s** vs 공식 모집단 중앙 큐 대기 **0s**(역치 2배 미만) → **편향 경고 없음**. 취소 분리로 인한
  장기 표본 소실 편향의 징후는 관측되지 않았다.

### 8.3 공식 값 (official_wall = updated_at − created_at, 초 단위 정수 차)

| 값 | 결과 |
|---|---|
| **공식 baseline P95 (R-7)** | **1,988.0초** |
| 표본 수 n | **133** (n≥30 — P95 등록 판정 요건 충족) |
| 측정 구간 [since, until] | **2026-10-21T16:40:44Z ~ 2026-11-01T13:00:00Z**(런 created_at 기준, GitHub-clock; 모집단 실관측 범위 10-21T16:55:38Z~11-01T10:42:37Z) |
| p50 | 980초 |
| 최소 / 최대 | 458초 / 2,951초 |
| SLO of record 480s 대비 | **≈4.1×** |
| 진단값 `latest_attempt_wall` | **1,988.0초** — 공식값과 동일(모집단 전체 run_attempt=1·런 수준 시작 지연 0초 → run_started_at ≡ created_at) |
| 진단값 `attempt_wall` | **생략** — 계산 비용(런당 attempts/{n}/jobs interval union, 133런 × 페이지네이션). 모집단이 attempt 1 뿐이고 공식값과 latest_attempt_wall이 전 표본에서 일치하므로 진단적 한계가치가 비용에 미달 |

### 8.4 epoch 진단 분리 (§5 — created_at 시간 버킷, 공급자 실측 아님)

경계값: failover 시작 = CI_RUNNER_MAP `last_transition_at` **2026-10-23T09:48:03Z**
(`ci_provider_failover_2026-10-23.md` :185·:215 등록값 — 계약 §5의 일 단위 표기 "2026-10-23"을 그날의
등록 전환 시각으로 정밀화; gen12 경계 10-30T07:46:09Z와 GHEC 복귀 경계 10-53:18Z는 계약 등록 원시값
그대로), 전환 혼합 창 [11-01T09:35:43Z, 11-01T10:53:18Z]은 계약 §5의 옵션대로 **`ghec-transition`
층으로 분리** 보고했다(잡 단위 rgid 분류는 수행하지 않음 — 등록 경계 원시값은 임의 변경 없음).

| epoch 층 | n | min | p50 | P95 (R-7) | max |
|---|---|---|---|---|---|
| ghec(pre-failover, <10-23T09:48Z) | 28 | 458 | 1,027.5 | **미산출 — 최소 표본 미달(n<30, §7·RESID-09)** | 1,753 |
| failover (10-23T09:48Z~10-30T07:46Z) | 58 | 711 | 1,196.5 | **2,310.7** | 2,951 |
| gen12-ubicloud (10-30T07:46Z~11-01T09:35Z) | 44 | 612 | 907 | **1,133.4** | 1,287 |
| ghec-transition ([09:35:43Z, 10:53:18Z]) | 3 | 623 | 645 | **미산출 — 최소 표본 미달(n<30)** | 691 |
| ghec-return (>11-01T10:53:18Z) | 0 | — | — | 표본 없음 | — |

- **과제 지정 경계(2026-11-01T10:53:18Z) 전/후**: 이전 n=133·P95 1,988.0초 / 이후 **n=0** — 창 종료
  시점까지 복귀 확정 경계 이후 생성 착지 런이 없었다(모집단 마지막 런 = 41298669695, 10:42:37Z 생성,
  #1166 착지 런·GHEC 복귀 수용 확인 런).
- **해석(진단 전용)**: provider 세대 전환은 P95의 지배 인자로 계속 관측된다 — failover 2,310.7s vs
  gen12-ubicloud 1,133.4s(≈ −51%). 이는 v5 adjudication §6·§10의 "provider epoch 안정화가 P95 최대
  감쇠원" 판정과 정합하며, §7의 레버 목록(러너 용량·큐 대기·provider 차이)과 같은 방향을 가리킨다.
- **버킷의 정직 한계**: epoch 층은 `created_at` 시간 버킷이지 **공급자 실측이 아니다** — v5
  adjudication §12.3이 사후 확인한 불일치(시간 버킷 표기와 잡 실측 공급자의 어긋남)가 본 층화에도
  이론상 적용된다. 정밀화된 경계(09:48:03Z)는 v5의 일 단위 버킷보다 오분류 후보를 줄이지만, 층별 공급자
  실측 검증(잡 rgid 전수 확인)은 수행하지 않았다.

### 8.5 구정의·신정의 나란히 (§10 — baseline 재계산 시 병행 보고 의무)

| 정의 | 모집단 | n | p50 | P95 (R-7) | 최대 |
|---|---|---|---|---|---|
| **신정의(본 계약 — 취소 제외·rule ii 적용)** | 최종 착지 완료 런 | **133** | 980 | **1,988.0** | 2,951 |
| 신정의, 성공 한정(진단) | success 런 | 130 | 985.0 | 1,966.1 | 2,951 |
| 구정의 참고(진단 전용 — 취소 포함·rule ii 미적용) | 전 종결 런 | 150 | 1,029 | 2,218.5 | 3,886 |
| (역사 등록값 — 본 계산 아님) | v5 전수, 창 ~10-31T11:27:31Z | 130 | 1,086.0 | **2,315.8** | 3,886 |

- 본 창(11-01T13:00Z까지)은 v5 창보다 길고 provider 세대 구성이 다르므로, 위 구정의 참고값은 v5 등록값
  2,315.8s의 재계산이 **아니다** — §10의 소급 수정 금지에 따라 v5 등록값은 원값 그대로 보존되며, 본
  계산은 "동일 규칙을 새 창에 적용한 나란히 값"으로만 제시한다. 두 정의 모두 SLO 480s 대비 ~4배 이상
  격차(4.1×/4.6×) — 정의 선택이 판정을 뒤집지 않는다는 §10의 예견과 부합.

### 8.6 관측 프로토콜 준수 검증 (§9)

- **창 분할·상한**: 창당 total_count 600·184·400 — 전부 1,000 미만(§9 유효 표본 창 요건; v5 §11의
  total_count 704 창 선례와 동등). 수집 행 수 == total_count(각 창) → --paginate 완결 오판(Q16 상한
  서명) 부재.
- **전수 단일 GET 교차검증(경계 런 + 전수 판정 대상 런)**: admission-gate **150런 전수**(모집단 133 +
  중간 10 + 취소 7)를 `GET /actions/runs/{id}`로 개별 확정 — status·conclusion·run_attempt·
  created_at·run_started_at·updated_at 6 필드가 목록값과 **불일치 0건**. Q16으로 문서화된 v5의 누락
  4런(39639158902·39657167861·39661104154·39672117787)도 본 스윕 3분할 창에서 전부 재관측됐고 모집단에
  포함됐다(창 분할 절차의 유효성 재확인).
- **모든 관측 GET-only·`gh` 네이티브 인증** 준수. raw 응답은 계산 중 임시 버퍼(/tmp)로만 사용 — 캐시는
  증거가 아님(§9).

### 8.7 재현 (같은 입력 → 같은 값)

```bash
# (1) 창별 total_count — 1,000 상한 회피 검증 (§9: ≪1000만 유효 표본 창)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-10-21T16:40:44Z..2026-10-26T00:00:00Z&per_page=100" --jq '.total_count'   # 600
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-10-26T00:00:00Z..2026-10-30T00:00:00Z&per_page=100" --jq '.total_count'   # 184
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-10-30T00:00:00Z..2026-11-01T13:00:00Z&per_page=100" --jq '.total_count'   # 400

# (2) 3창 전수 수집 (TSV: id,name,path,event,status,conclusion,run_attempt,created_at,run_started_at,updated_at,head_branch,head_sha)
#     → cat w1 w2 w3 | sort -t$'\t' -k1,1 -n -u (run ID dedupe) → adm.tsv
for W in "2026-10-21T16:40:44Z..2026-10-26T00:00:00Z" "2026-10-26T00:00:00Z..2026-10-30T00:00:00Z" "2026-10-30T00:00:00Z..2026-11-01T13:00:00Z"; do
  gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=$W&per_page=100" --paginate \
    --jq '.workflow_runs[] | [.id,.name,.path,.event,.status,.conclusion,.run_attempt,.created_at,.run_started_at,.updated_at,.head_branch,.head_sha] | @tsv'
done

# (3) 전수 단일 GET 교차검증 (§9 — 150런, 6필드 대조, 기대 불일치 0)
gh api repos/Archright/Axiom/actions/runs/<id> --jq '[.id,.status,.conclusion,.run_attempt,.created_at,.run_started_at,.updated_at]|@tsv'
```

계산 스크립트 전문(위 (2)의 adm.tsv를 입력으로 소비 — 본 보고서 수치의 유일한 산출 경로):

```python
#!/usr/bin/env python3
# baseline P95 계산 — 동결 계약 docs/evidence/slo_official_measurement_prereg_2026-11-01.md 규칙 적용
# 모집단=§4, dedupe=§4(v5 계승), official_wall=§2, R-7=§6, 표본 기준=§7, epoch=§5
from datetime import datetime, timezone

def parse_ts(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)

rows = []
with open("/tmp/dag_baseline/adm.tsv") as f:
    for line in f:
        p = line.rstrip("\n").split("\t")
        rows.append({
            "id": int(p[0]), "name": p[1], "path": p[2], "event": p[3],
            "status": p[4], "conclusion": p[5], "run_attempt": int(p[6]),
            "created_at": p[7], "run_started_at": p[8], "updated_at": p[9],
            "head_branch": p[10], "head_sha": p[11],
        })

# (i) run ID dedupe — 창 분할 스윕 중복 제거
seen = {}
for r in rows:
    seen[r["id"]] = r
rows = sorted(seen.values(), key=lambda r: (r["created_at"], r["id"]))

# (ii) 동일 merge-queue 그룹(동일 head_branch)에서 최종 완료 런만 모집단,
#      중간 완료 런은 경계 관측, 취소는 별도 등록, 미종결은 관측 기록
groups = {}
for r in rows:
    groups.setdefault(r["head_branch"], []).append(r)
for g in groups.values():
    g.sort(key=lambda r: (r["created_at"], r["id"]))

population, intermediates, cancelled, pending = [], [], [], []
for hb, g in groups.items():
    last = g[-1]
    for r in g:
        if r["conclusion"] == "cancelled":
            r["_later"] = (r is not last)
            cancelled.append(r)
        elif r["status"] != "completed":
            pending.append(r)
        elif r["conclusion"] in ("success", "failure"):
            (population if r is last else intermediates).append(r)
        else:
            pending.append(r)

wall = lambda r: int((parse_ts(r["updated_at"]) - parse_ts(r["created_at"])).total_seconds())
lwall = lambda r: int((parse_ts(r["updated_at"]) - parse_ts(r["run_started_at"])).total_seconds())
qwait = lambda r: int((parse_ts(r["run_started_at"]) - parse_ts(r["created_at"])).total_seconds())

# §6 R-7 핀 함수 — 동결 문서 원문 그대로
def percentile_r7(sorted_values, p):
    """Hyndman & Fan (1996) type 7 (R default) — 결정론 백분위.
    sorted_values: 오름차순 정렬된 표본(list[float]), p: 0 이상 100 이하."""
    n = len(sorted_values)
    if n == 0:
        raise ValueError("empty sample")
    h = (n - 1) * (p / 100.0)
    lo = int(h)              # floor(h)
    hi = min(lo + 1, n - 1)  # ceil(h), 경계 클램프
    gamma = h - lo
    return sorted_values[lo] + gamma * (sorted_values[hi] - sorted_values[lo])

def fmt(v):
    return str(int(v)) if float(v) == int(v) else f"{v:.1f}"

def stats(label, vals):
    s = sorted(vals)
    n = len(s)
    if n == 0:
        print(f"{label}: n=0 (표본 없음)")
        return
    p50 = percentile_r7(s, 50)
    line = f"{label}: n={n} · min={fmt(s[0])} · p50={fmt(p50)} · max={fmt(s[-1])}"
    if n >= 30:
        line += f" · P95={fmt(percentile_r7(s, 95))}"
    else:
        line += " · P95=미산출(n<30 최소 표본 미달 — RESID-09/§7)"
    print(line)

print("=== 공식 모집단 (§4: 완료 success|failure 최종 착지 런, rule (ii) 적용) ===")
print(f"모집단 n={len(population)} · 중간 완료 런(제외)={len(intermediates)} · 취소={len(cancelled)} · 미종결={len(pending)}")
ows = [wall(r) for r in population]
lws = [lwall(r) for r in population]
qws = [qwait(r) for r in population]
stats("[공식] official_wall (updated-created)", ows)
stats("[진단] latest_attempt_wall (updated-run_started)", lws)
stats("[감시] queue wait (run_started-created, 공식 모집단)", qws)
print(f"run_attempt 분포(공식 모집단): {sorted(set(r['run_attempt'] for r in population))}")

print()
print("=== Censoring 감시 (§4) ===")
cr = len(cancelled) / (len(population) + len(cancelled)) * 100
print(f"cancel_ratio = {len(cancelled)}/{len(population)+len(cancelled)} = {cr:.1f}% (경고 역치 15%)")
if cancelled:
    cq = sorted(qwait(r) for r in cancelled)
    p50c = percentile_r7(cq, 50)
    p50p = percentile_r7(sorted(qws), 50)
    print(f"취소 런 중앙 큐 대기 = {fmt(p50c)}s vs 공식 모집단 중앙 큐 대기 = {fmt(p50p)}s (경고 역치 2배 초과)")
    warn = []
    if cr > 15: warn.append("cancel_ratio>15%")
    if p50c > 2 * p50p: warn.append("취소 중앙 큐 대기 > 2x 완료 중앙값")
    print("편향 경고: " + ("; ".join(warn) if warn else "없음 — P95 보고에 경고 불요"))

print()
print("=== §10 구정의(전수, 취소 포함·rule(ii) 미적용) 나란히 — 진단 전용 ===")
term = [r for r in rows if r["conclusion"] in ("success", "failure", "cancelled")]
stats("[구정의 참고] 전 종결 런 official_wall (취소 포함 150)", [wall(r) for r in term])

print()
print("=== epoch 진단 층 (§5 — created_at 시간 버킷, 공급자 실측 아님) ===")
FAILOVER_START = parse_ts("2026-10-23T09:48:03Z")   # CI_RUNNER_MAP last_transition_at UBICLOUD_ACTIVE
GEN12_START    = parse_ts("2026-10-30T07:46:09Z")   # gen-12 Ubicloud PATCH
TRANS_START    = parse_ts("2026-11-01T09:35:43Z")   # force_trial GHEC_ACTIVE
GHEC_RETURN    = parse_ts("2026-11-01T10:53:18Z")   # GHEC_RETURN_CONFIRMED
def epoch(r):
    c = parse_ts(r["created_at"])
    if c >= TRANS_START and c <= GHEC_RETURN: return "ghec-transition"
    if c < FAILOVER_START: return "ghec(pre-failover)"
    if c < GEN12_START:    return "failover"
    if c < TRANS_START:    return "gen12-ubicloud"
    return "ghec-return"
from collections import defaultdict
byep = defaultdict(list)
for r in population:
    byep[epoch(r)].append(wall(r))
for k in ["ghec(pre-failover)", "failover", "gen12-ubicloud", "ghec-transition", "ghec-return"]:
    if k in byep: stats(f"[{k}] official_wall", byep[k])
print()
print("=== 과제 지정 경계: 2026-11-01T10:53:18Z 전/후 (진단) ===")
stats("[10:53:18Z 이전] official_wall", [wall(r) for r in population if parse_ts(r["created_at"]) <= GHEC_RETURN])
stats("[10:53:18Z 이후] official_wall", [wall(r) for r in population if parse_ts(r["created_at"]) > GHEC_RETURN])
print()
print(f"창: [{rows[0]['created_at']} .. {rows[-1]['created_at']}] (모집단 created_at 최소·최대, GitHub-clock)")
```

### 8.8 계약 충돌·판단 기록

- **충돌 없음** — 계산이 모집단 규칙과 충돌한 지점은 발견되지 않았다. 판단을 요한 2지점: (a) rule (ii)의
  "최종 착지 런" 판별을 "동일 head_branch 그룹에서 마지막 종결(success|failure) 런"으로 조작화 — 그룹의
  마지막 런이 취소면 그 그룹의 완료 런은 전부 중간으로 보아 제외했다(후속 런 존재가 중간성의 관측 증거);
  (b) failover epoch 경계를 계약의 일 단위 표기에서 등록 전환 시각 09:48:03Z로 정밀화(§8.4) — 둘 다 본
  절에 기록했으며 등록 경계 원시값의 변경은 아니다.

## 9. 제한·불확실성

- 타임스탬프 1초 단위 → 0.0초 슬랙은 측정 해상도상 0(±1초).
- 표본 89/150런(59%) — 단, 12종 비스킵 잡 구성이 표본 전 런에서 동일하고 pin 버전과 관측이 일치해 구조
  대표성은 확보. 실행 시간 분포는 gen12(n=50)가 가장 두텁고 ghec는 n=7로 얇음.
- run_attempt>1 표본 1건(40530789599) — `attempts/{n}/jobs`가 `/jobs`와 22행 동일함을 확인(이중계산
  없음).
- 취소 7런은 시작된 잡만 통계에 포함.
- 오케스트레이터 원문은 `Archright/.github@main` 판독(관측 잡 그래프와 정확히 일치해 검증됨) — org
  ruleset의 required-workflow 핀 blob 별도 readback은 미수행(관측 일치로 상쇄).
- SL-0713·SL-09 승격 상태는 origin/main manifest 기준이며, 런별 B의 manifest와 다를 수 있음(failover
  초기 런).
- **baseline 계산의 한계(§8)**: (i) official_wall은 큐 대기를 포함하는 정의다(계약 §2 — 의도된 것);
  (ii) n≥30은 등록 절차상 계산 가능 최소 표본이지 안정적 장기 추정이 아니다(계약 §7 해석 한계 고정 계승)
  — 본 baseline을 장기 성능 보증으로 해석하지 않는다; (iii) 측정 구간이 3개 provider 세대를 가로지르므로
  공식 P95 1,988.0s는 **세대 혼합값**이다(계약 §5 — epoch 진단 층이 보정 정보); (iv) ghec-transition 층
  n=3·ghec-return 층 n=0 — 복귀 후 세대의 baseline은 미래 창에서 별도 측정이 필요하다; (v) epoch 층은
  created_at 버킷이지 공급자 실측이 아니다(§8.4); (vi) attempt_wall 생략으로 잡 구간 겹칩합 진단은
  본 보고에 없다(§8.3 — 비용 사유).

## 10. 참조

- `docs/evidence/slo_official_measurement_prereg_2026-11-01.md` — 동결 계약(§2 official_wall 식별 관계·§4
  모집단·dedupe·§5 epoch 경계·§6 R-7 핀·§7 표본 기준·§8 귀속 규율·§9 관측 프로토콜·§10 소급 금지·§12
  재현 명령)
- `docs/evidence/judgment_key_v5_adjudication_2026-10-31.md` — v5 판정 기록(§6 P95 2315.8/2012.8·§8
  경계 관측 선례·§12.3 epoch 버킷 한계), v5 dedupe 규칙 원문 계승 관계
- `docs/evidence/judgment_key_v5_measurement_prereg_2026-10-31.md` — v5 측정 절차(§2 표본 단위·역사 창)
- `docs/evidence/pr_to_main_attribution_prereg_2026-10-19.md` — 진단 3값 어휘(latest_attempt_wall·
  attempt_wall·total_elapsed_with_retries)·REST 상한 실측(§4.1)
- `docs/spec/gh_run_observation_quirks.md` — Q16(merge_group 목록 누락·1,000 상한·창 분할+단일 GET
  교차검증 절차)
- `docs/spec/ci_provider_failover_quirks.md` — failover quirk 본문
- `docs/evidence/ci_provider_epoch_2026-10-30.md` — gen-12 Ubicloud 전환(PATCH 2026-10-30T07:46:09Z)
- `docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md` — GHEC 복귀 수용(경계
  2026-11-01T10:53:18Z `GHEC_RETURN_CONFIRMED`·전환 창 [09:35:43Z, 10:53:18Z])
- `docs/evidence/ci_provider_failover_2026-10-23.md` — failover 시작 등록값(CI_RUNNER_MAP
  `last_transition_at` 2026-10-23T09:48:03Z)
- `docs/evidence/generation_promotion_hnew_2026-10-17.md` — P1(mint-publish→verdict) 순수 간선 제거
  선례
- `docs/evidence/residual_issue_ledger_2026-10-31.md` — RESID-09(N≥30 미달 백분위 "잠정·미산출" 어휘)
- `config/policy/epoch_manifest.json` — SL-0713 포함·SL-09 부재(pin 검증 근거, §4)
