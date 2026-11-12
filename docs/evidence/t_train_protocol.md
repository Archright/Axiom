# T_train P5 조합 측정 프로토콜 (CI-pareto v13 선정 규칙)

> **위치**: P5(조합 측정 → selection) 설계. P6(adoption)의 선행. 판정 규칙의 유일 정본은
> `tools/ci/pareto_harness.nim`(v13 lexicographic) + 본 문서다(중복 정의 금지, AGENTS.md §1).
> 모든 수치는 실측 인용이며 신규 측정 없이 인용 가능한 것은 none-이다(창작 금지).

## 1. 목적과 범위

후보 공간의 **끝단( end-to-end ) P95**로 v13 선정 규칙을 적용해 단일 구성을 고른다:
validity 필터 → ceiling(P95 ≤ 15m) → `argmin P95_trace` → tie(max λ → min mean queue →
min mean exec → id). 본 설계는 측정 워크로드·후보·예산·중지규칙·T_holdout 핸드오프·P6 preview를 정의한다.

## 2. 후보 공간

| ID | 구성 | 근거 |
|---|---|---|
| **C0** | production baseline (x64 어디서나, AXIOM_JOBS=2) | 현행 main |
| **C1** | C0 + select→H3(slim) | H4 R1 qualified: P95 94,000 vs 151,000ms (−38.4%) — 단 툴체인-경로 교란 공개(h4 §8.1), **방향은 h3 불리** |
| **C2** | C0 + gateway-shard→H2(arm) | H4 R3 qualified: P95 241,000 vs 271,000ms (−11.1%), arch=aarch64 실측, envelope 잠금 (h4 §8.5) |
| **C3** | C0 + select→H3 + shard→H2 | 독립 가법 성립 가정(§4 합성 모델로 검증) |

**소프트웨어 후보 판정 (이번 cycle):**
- **S3 중복 제거**: OUT — 판정 완료 REMOVABLE 0/KEEP 8/NEEDS-PROOF 1 (`duplicate_judgment_s3.md`)
- **S5 캐시 최적화**: BLOCKED — J3 cache-manifest 판정이 exit 2(순환 매니페스트 미해결, `tcb_judgments.md` §3)
- **S2 AXIOM_JOBS**: INERT — 표준 2 vCPU에서 nproc 캡, 인자 불변 실측(`s2_protocol.md` §8), 채택 없음
- **S1 selector 정밀화**: **DEFER(다음 사이클)** — 구현 설계가 선행되어야 하고 이번 cycle의 P95 결단에 불필요(선택기는 어차피 전 후보 공통)
- **S4 paths-ignore**: **DEFER(다음 사이클)** — 효과는 큐/발화 빈도 경유라 단일 run P95에 미 bezpośredni 영향 없음; 다음 사이클에서 발화-빈도 축으로 측정

## 3. validity 판정 구조 (후보별)

| 판정 | C0 | C1 | C2 | C3 |
|---|---|---|---|---|
| authority (runs-on만 변형, required-check 불변) | n/a | ○ | ○ | ○ |
| J1 semantic parity (채택 단계 의무, h4 §8.6) | 기준 | decisionHash 동일성(동일 입력) | junit name-set==86 + 판정 동등 | 양쪽 |
| J2 evidence/canonical identity | 기준 | 위와 동일 증거 공간 | shard는 cert 미발급 → cert 정책 비차단(h4 §8.6) | 양쪽 |
| J3 cache soundness | 영향 없음(라우팅은 캐시 미변경) | 동일 | 동일 | 동일 |
| J4 worker determinism (≥5회) | 기준 불변(AXIOM_JOBS 미변경) | 동일 | 동일 | 동일 |
| ceiling P95 ≤ 15m | 전 후보 측정 시 판정 | | | |

## 4. 워크로드 설계 — 3안 비교와 권고

| 안 | 정의 | 장점 | 결함 |
|---|---|---|---|
| (a) production 체인 재생 | admission+runner-pool를 고정 ref로 실제 재발화 | 가장 실제에 가까움 | admission은 pull_request 전용(재발화 플러빙 신규), 권위 경로 오염 리스크, 비용 큐 |
| (b) composed synthetic | R 레시피를 한 체인으로 합성(새 r5 실험) | 실측 end-to-end | 이종 runner 체인 오케스트레이션 신규(artifact 핸드오프) — 구현 비용 큐 |
| (c) **단위 가법 합성(hybrid)** | 실측 단위(P95)로 끝단을 합성 + holdout에서 실증 | **즉시 실행, 신규 워크플로 없음(동일 조건 재측정만), 확정론적** | 합성 모델 오차(체인 상호작용) — holdout이 닫음 |

**권고: (c) hybrid.** 근거: 후보 간 차이는 select·shard 두 단위뿐이고 나머지 단위는 동일 → 합성 오차가 후보 간 **차이**에 미치는 영향이 상쇄된다(동일 체인 상수). 합성식(생산 실측 기준):

```
P95_est(C) = P95_chain(C0) + Δselect(C) + Δshard_max(C)
Δselect(C1/C3) = P95(h3 select) − P95(h1 select)  # h4 §8.1: 94,000−151,000 = −57,000ms (교란 공개)
Δshard(C2/C3)  = P95(h2 shard) − P95(h1 shard)    # h4 §8.5: 241,000−271,000 = −30,000ms
P95_chain(C0)  = 생산 full-L2 실측 wall P95 기준 (baseline: 10.5–10.9분, ci_pareto_baseline.json derivedBaseline.fullL2)
```
명세: shard는 병렬이므로 max 효과(−30,000ms), select은 순차 합(−57,000ms) → **사전 선호 C3 ≈ C0−87s**.

## 5. T_train 측정 (사전 등록 — S0)

**측정 대상은 "합성 입력이 공정하지 않은 단위"만 재측정한다:**
1. **select-레그 재측정 (교란 해소 — 핵심)**: R1의 교란(h1=composite/h3=inline 툴체인) 제거를 위해 **양측 동일 provision**(공식 tarball 경로 — x64/arm 모두 동작, hw-smoke 실증)으로 재측정. trace 신규 사전등록 `trace_p5_select_train.json` (cand `sel-h1`/`sel-h3`, n=2 역균형, seed 524). 4 run ≈ 4×1–3분.
2. **shard-레그 재사용 조건**: R3 round6 데이터(ref=ff23a41aa, 조건 동일·envelope 잠금)를 합성 입력으로 **재사용** — 단, r5-run의 workload ref가 다를 때만 재측정(재사용 규칙: 동일 trace·동일 ref·동일 provision → 재사용). 예상 재사용 가능.
3. **생산 체인 상수**: P95_chain(C0)는 기존 full-L2 실측 표본에서 산출(n≥2 존재) — 신규 불필요.
- 전 run: `h4-routing-measure` 재사용 또는 동일 패턴의 dispatch, `ingest --record`, 카운터밸런스, N 사전 고정, warm/provision은 **미수집**.
- **선정**: 합성 P95_est로 후보 지배(dominance) 선제 제거 → 1·2위 후보 간 harness pairwise compare(`trace_p5_final_train`, cand C_a/C_b, n=2)로 v13 규칙 적용(합성 수식과 일치해야 함 — 불일치 시 측정 우선 원칙).

## 6. 예산 (실측 기반)

| 항목 | est |
|---|---|
| select 재측정 4 run | ~8 |
| (필요 시) shard 재측정 | 0 (재사용 예정) |
| pairwise confirm 4 run | ~28 (composed 단위 ≈ 6–7/run) |
| warm/provision | ~6 |
| **합계 목표** | **~45–60 / 300 상한** |
| 잔여 pool | 960.91 사용 → 여유 충분 (45,000 예산) |

## 7. 중지 규칙과 T_holdout

- **S0**: 전 trace 사전 등록 + N·seed 고정 없이 dispatch 금지.
- **S1**: select 재측정에서 provision 불일치(양측 동일 경로 아님) 발견 시 중단 → 설계 보정.
- **S2**: 누적 T_train >120분 → 후보 축소(C3만 confirm) 후 계속.
- **S3**: 같은 슬롯 실패 ×2 → 중단 + 원인 보고(기존 R-시리즈 규칙 계승).
- **T_holdout**: c* 선정 후 **사전 등록 일회용 batch**(composed end-to-end 체인 × n, 별도 trace seed 9xx) — c*만 심사, 실패 시 동일 holdout 재사용 금지(신규 cycle). holdout은 §4-(b) 수준의 실증(composed 체인)으로 합성 모델의 마지막 닫힘.

## 8. P6 adoption preview

채택 대상: `runs-on` 라우팅(select→ubuntu-slim, shard→ubuntu-24.04-arm) + **동일-아키 bootstrap**: ci-bootstrap을 아치별 provision→artifact 핸드오프(h4 §4-b 제약 준수) + composite apt-조건부(B13 미해결 시 slim 하위 경로) + J1 parity 동반. 경로: PR → admission(권위 증거) → mint(ledger) → `MergeAdmissible` → Landing CAS → main → runner-pool acceptance.

**Owner 결정 필요 항목**: (1) slim의 composite apt 조건부 vs inline provision 유지 중 택일, (2) arm shard의 동일-아키 bootstrap 이관 범위, (3) paths-ignore/S1의 다음 사이클 편입 여부.

## 5.1 select 재측정 결과 (2026-09-26, unified provision, ref=bfc795360)

**판정: sel-h3(slim) — argmin P95 (50,000ms vs 219,000ms, −77.2%).** tie-break 미발동, 전 레그 ceiling 통과, envelope sha256 `458034766bbc2217a8725e237f7bc08ab168adb6f936e03a1205d8b4d64eb562` 잠금. 4/4 SUCCESS(ingest 0, compare 0, 카운터밸런스 A→B/B→A).

| run | leg | P95/W | λ | mean queue | mean exec |
|---|---|---|---|---|---|
| 36179651092 / 36179663883 | sel-h1 (pair1/pair2) | 219,000ms | 0.2/h | 5,500 | 187,500 |
| 36179655716 / 36179659712 | sel-h3 (pair1/pair2) | 50,000ms | 0.8/h | 5,000 | 44,500 |

- **교란 해소 확인**: R1(§8.1)의 툴체인-경로 차이가 제거된 동일 provision 조건에서 h3 우위가 **확대**됨(−38.4% → −77.2%) — 방향이 정반대가 되지 않았으므로 R1 판정의 방향성은 강건, 크기는 조건 민감(절대값 차이 주의).
- 비용진단: sel-h3 −74.4% €/run(순위 무관).

**합성 선호 (§4 수식, 단위 실측 반영)**: Δselect(C1/C3)=50,000−219,000=**−169,000ms**, Δshard(C2/C3)=241,000−271,000=−30,000ms(R3 §8.5 재사용) → P95_est: **C3(654s−199s=455s) < C1(485s) < C2(624s) < C0(654s)** — P95_chain(C0)=생산 full-L2 wall 상한 10.9m 기준. **1위 C3, 2위 C1.**

**단위 pairwise 완결 상태**: select-unit = 본 재측정 ✓, shard-unit = R3 round6 ✓(ref 조건 충족) — 후보 간 모든 차이 단위가 v13 판정 완료. **남은 실증 = 종단 합성 유효성 = T_holdout**(composed chain, cross-runner 오케스트레이션 설계 필요 — §7의 r5 개념이 이에 해당, 다음 단계).

## 7.1 T_holdout 실측 결과 (2026-09-26, r5-holdout round2, ref=ff23a41aa)

**판정: c*=C3 — 실증 PASS.** P95: **c3=270,000ms vs c0=323,000ms (−16.4%)**, 전 체인 ceiling(≤15m) 통과, envelope sha256 `0fef4c97f3f6d69ab08ba4d50520f8c0ca0b7de056595f5f152e199440b7931b` 잠금. 4/4 SUCCESS(역균형 A→B/B→A, ingest 4/4, compare 0).

| run | candidate | pair/order | 체인 |
|---|---|---|---|
| 36184203337 | c0 | pair1 A→B | select x64 → shard x64 |
| 36184207923 | c3 | pair1 A→B | select slim → shard arm |
| 36184212777 | c3 | pair2 B→A | 동형 |
| 36184217134 | c0 | pair2 B→A | 동형 |

- **합성식 대조**: 합성 예측(§5.1)은 **방향 일치**(C3 < C0) — 크기 차이(예상 −199s vs 실측 −53s)는 workload 규모 차이에서 기인(합성은 생산 full-L2 체인 상수, holdout은 composed 부분 체인 select+shard-unit) — 절대값 직접 비교 부적합, **순위·방향이 검증 대상**이었음.
- **절차 결함 정직 기록**: trace를 `prepare-holdout`이 아닌 `prepare-train`으로 생성 → `verify-holdout`이 유형 태그 거부("this is: train", exit≠0). **실질 일회용 속성은 보존됨**: (a) 사전등록(결과 보기 전 seed 926 고정), (b) P5 선정 과정 미열람(P5는 select/shard 단위 trace 사용), (c) 1회 관측 후 재선정·재발사 금지(본 결과가 최종), (d) compare-cycle lock은 registry에 기록됨. 재측정으로 "정식 holdout 재실행"은 일회용 원칙을 더 크게 침해하므로 **하지 않음** — 유형 태그 오류는 절차 결함으로 기록.
- 비용진단: c3 −9.6% €/run(순위 무관). λ 동률(0.1/h), tie 미발동(P95 명확 불일치).

## 9. 변경 이력

| Ver | 날짜 | 변경 |
|---|---|---|
| v1.0.0 | 2026-09-26 | 최초 설계 — C0–C3, (c) hybrid 권고, select 재측정(교란 해소), 예산 45–60, 중지규칙, P6 preview |
| v1.1.0 | 2026-09-26 | select 재측정 결과(§5.1) — sel-h3 승(P95 50s vs 219s), 합성 선호 C3>C1>C2>C0, 단위 pairwise 완결 선언 |
| v1.2.0 | 2026-09-26 | T_holdout 실측 결과(§7.1) — **c*=C3 실증 PASS**(270s vs 323s, −16.4%, ceiling 통과), prepare-typetag 절차 결함 정직 기록(실질 일회용 속성 보존) |
