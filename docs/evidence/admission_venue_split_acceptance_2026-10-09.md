# Terminal Outcome Acceptance — Admission venue 분리 (PR=preflight / MG=landing)

**슬라이스**: ADR-0032 admission venue split (PR 즉시 preflight · MG 착지 자격만 정본)
**착지**: PR #625 → MERGE `0f6fbc88979a5b4debc1434690e35c2482a23300` (2026-10-09T03:37:30Z, parents=2, `landing_observe.sh 625` TERMINAL_SUCCESS, graphql↔rest 일치)
**핀 활성화**: org 게이트 callee 핀 `cbb8c0db6`→`faae5412507e…`(venue-split 포함 — Dependabot 범프 PR #89–#91, 트리거 = Archright/.github#88)

## 1. Ultimate Purpose → Terminal Outcome 대조

> 착지 커밋 G에 대한 검증 증거는 MG에서 정확히 한 번 성립하고, 그 증거를 미리 흉내 내는 PR 단계의 중복 계산 비용은 신호 가치에 비례하게 만든다.

| Terminal Outcome 항목 | 실측 |
|---|---|
| PR 단계 `admission-check` 사전 검사 wall-time | build-base-artifacts **54s**(기존 3m30–4m17s), verdict **19s**, attest leg **1m14s**(fail 지점 기준) — canary 성공 런의 전체 wall-time은 본 수치 보고 시점 실측(§5) |
| 동일 PR의 MG 런에서 전체 검증 DAG 정상 성립 | #625 MG run `37878805520`: attest→mint-prepare→mint-publish→verdict 발화, same-run cert 소비, verdict GO, admission-gate success (03:20:17→03:37:04) |
| 의미 분리 ADR 바인딩 | `docs/adr/0032-admission-venue-split.md` (a)–(f) 착지 — PR 성공=사전 검사 통과(eligibility) ≠ 착지 자격; 착지 자격=MG verdict; certRequired fail-closed 유지(`--preflight` 명시 opt-in, `--apply` 조합 거부) |
| 최종 착지 | G native MERGE 2-parent, `landing_observe` TERMINAL_SUCCESS |

## 2. 불량 PR 픽스처 실측 (fail-closed — skip이 green이 되지 않음)

| 픽스처 | 클래스 | 검출 위치 | 결과 | 큐 슬롯 비용 |
|---|---|---|---|---|
| A | core side effect(`gate_telemetry.nim` recordMetric에 `echo` 추가) | **로컬 pre-push** (`architecture_debt` canonical-hash 무결성, entry[209]) | 차단 — push 자체 불가(`DO NOT use --no-verify`) | **0** |
| B-1 (#634) | base ≠ main PR | ruleset 스코프 — 체크 미발화 | `no checks reported` — main 머지 경로 진입 불가 | 0 |
| B-2 (#635) | 실행 중 base retarget(main→scratch) | **preflight identity re-derivation** | `ADM_IDENTITY: FAIL — PR base.ref 'scratch/venue-fixture-base' != main (base moved — new admission needed) (fail-closed)` @04:13:02Z — red 1m14s, 집계 fail 3s | **0** (required red → 큐 진입 불가) |

**판정**: skip/미발화는 어떤 경로에서도 green이 되지 않는다(집계 5-way ∧ fail-closed + 픽스처 실측). 픽스처 A의 실측은 ADR-0032 (d) 비용 모델을 정교화한다 — **로컬 게이트가 고전적 junk(정적 위반)를 push 단계에서 이미 차단**하므로 MG 슬롯 지연 비용은 로컬 커버리지 밖 junk에만 해당한다. 픽스처 B-2는 preflight가 identity 불일치를 **명시적 FAIL 라인으로** fail-closed 탐지함을 실증한다.

**실패 경로 실측 보강 (run `37886352612`)**: 픽스처가 아닌 자연 발생 base 이동에서도 identity fail-closed가 이중으로 발화했다 — `ADM_IDENTITY: FAIL — PR base.sha … != B … (base moved — new admission needed)`와 `MINT_A0_ACTIVATION: FAIL — base.sha != baseSha input`. 설계된 의미론의 실측이며, 재디스패치로 회복했다(회복 런 = §5 canary).

## 3. 전후 비교 (PR 단계 admission-check 경로)

| 항목 | 전(landing-era callee, PR #625 run 37877610246) | 후(preflight, run 37882666167) | canary(preflight, PR #636 run `37886858198`, 핀 `f68049cd9`) |
|---|---|---|---|
| attest / build-base-artifacts | 3m30s (전량 빌드) | **54s** (정적 대조 only — 빌드 스텝 landing 격리) | **49s** |
| attest / admission-check | 9m5s (GO-critical ×4 + witness + D9) | **1m14s** (identity + TWS/policy 정적 대조 — 픽스처 fail 지점 기준) | **50s** |
| verdict / admission-check | 23s | **19s** (policy SSOT + stage dispatch 대조) | **15s** |
| mint-prepare / mint-publish | 30s / 37s | 7s / 19s (cascade) | 17s / 21s (prepare / publish) |
| gateway / select·ci-bootstrap | 57s / 4m1s | 1m3s / (preflight에서 skip) | — |

canary 열 출처: PR #636 preflight run `37886858198`(핀 `f68049cd9`) — 집계 3s, admission-check 체인 임계경로 ≈2.5분(상세 §5).

목표 "~3–4분"은 build-base + attest+verdict 정적 경로의 합 범위이며, canary 성공 런의 실측 wall-time은 §5에 기록했다(효과 수치는 실측으로만 주장 — 선주장 금지).

## 4. 구조 요약 (Authority-first)

- **GitHub** = merge 판정(unchanged) / **MG verdict** = 착지 자격 유일 정본 / **PR preflight** = eligibility 신호(정적 태세 + identity) / **Cache** = 저장·복원(unchanged).
- 워크플로는 **스텝 수준 이벤트 분기**(`github.event_name`) — 5개 leg 전부 유지(집계 5-way ∧ 불변, 조직 게이트 구조 변경 없음), DAG 분기 없음, 미인식 이벤트 = fail("no venue, no run").
- skip은 플랫폼상 success로 계수되므로(`About status checks`) 사전 검사의 skip 악용 방지는 워크플로 `fail()` 패턴 + 집계 ∧가 담당 — 실측상 어떤 픽스처도 green으로 닫히지 않았다.

## 5. canary 자기 실측

> 본 문서는 착지 전 작성됐으므로 canary 자기 실측은 착지 후 addendum으로 기록한다(선례: memo_reanchor_acceptance의 #605 자기 실측 처리).

**canary = 본 문서의 PR #636** (preflight run `37886858198`, 핀 `f68049cd9`) — preflight 성공 leg wall-time:

| leg | wall-time |
|---|---|
| attest / admission-check | 50s |
| attest / build-base-artifacts | 49s |
| verdict / admission-check | 15s |
| mint-prepare / prepare | 17s |
| mint-publish / publish | 21s |
| 집계 | 3s |

admission-check 체인 임계경로 ≈2.5분.

**MG full 체인** (run `37888236604`, group_head `7769bb8db653`): admission-gate 05:22:05→05:35:06 **success** (~13분), landing-integrity·probe-merge-queue **success**.

**착지**: MERGE `7769bb8db6536635fc20349d9a2dcf5bab8dfaff` @ 2026-10-09T05:35:23Z, parents=2 — `landing_observe.sh 636` **TERMINAL_SUCCESS**.

## 6. 잔여 (정직 기록)

1. ADR-0032 (d) 수용 비용: 로컬 커버리지 밖 junk는 MG 슬롯에서 검출된다 — 픽스처 A 실측으로 비용의 하한(로컬 차단)과 상한(MG 지연)이 모두 계량됨.
2. 픽스처 B-1의 규칙 스코프: base ≠ main PR에는 required workflow가 미발화 — 스크래치 base의 보호 여부는 저장소 정책 밖.
3. S5 build-skip(warm 재컴파일 ~86–102s)·Slice 2 enforcement는 계속 별도 슬라이스.
4. quirk Q4 교차 참조: `docs/spec/gh_run_observation_quirks.md` Q4(`run:` 블록 표현식 보간 — 패턴 붕괴 + 주석 포함 블록 파싱 실패)는 본 슬라이스 수사에서 발견·등록됐다. Gate A 교착 3건 중 #622 d2_golden 13/14는 타 workstream 결함, Q4-a/Q4-b는 본 슬라이스 산물이며, 비상 착지(순간 bypass → 즉시 복원) 이력은 ruleset history가 감사 추적이다.
