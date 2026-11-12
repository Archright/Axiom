# node24 세대 merge-queue 배치 임계경로 Census (critical-path census) — 2026-11-03

> **문서 종류**: docs/evidence — 읽기 전용 관측·분석 보고서. 코드·워크플로·게이트·판정 의미론 변경 0.
> **규율 원천**: 실행 계획 "Node24 Merge-Group Critical-Path Census"(READ-ONLY Vertical Slice — 모집단·판정 기준·금지 사항 사전 고정 + 개선 3건 반영: 그래프 A/B 분리, 8 관측/6 required 판정/2 보조 구분, 소표본 비확대·#1166 선점 금지) · 표본 규칙 `docs/evidence/slo_official_measurement_prereg_2026-11-01.md` §5·§7(진단 모집단 허용·창 고정·전수·제외 사유 공개 — 본 표본은 공식 SLO 모집단을 대체하지 않는 진단 표본) · 직계 형식 `docs/evidence/node24_merge_group_job_decomposition_2026-11-02.md`(잡 내부 비용 분해, n=2 — 본 문서는 그 상위 시야: 배치 전체 임계경로) · 선행 종결 `docs/evidence/node24_mint_tail_decomposition_2026-11-02.md`(mint tail n=5, BLOCKED)·`docs/evidence/arestore_optimization_blocked_2026-11-02.md`(PR #1192, A-restore BLOCKED)·`docs/evidence/cross_venue_b_reuse_closure_2026-11-02.md`(교차-venue B 재사용 종결) · 관측 quirk `docs/spec/gh_run_observation_quirks.md` Q16(merge_group 목록 누락)·`docs/spec/jq_17_in_membership_quirk.md`(신규 — 본 스윕 중 발견) · 경합 분류 기준: 동시 실행 구조 증명 + 자원 공유 신호(동일 runner_id·캐시 키·lock 오류) 또는 복원 시간 인과 곡선 없으면 경합 아님(UNKNOWN 유지).
> **권위**: 배치·런·잡·스텝 존재·타임스탬프·결론 = GitHub Actions REST API(gh, GET-only; jobs `filter=latest` 명시, 표본 전부 `run_attempt=1`) · 배치 경계 = PR timeline 이벤트(`added_to_merge_queue`/`merged`/`removed_from_merge_queue`) · B-key 동일성 = 실행 로그 원문(`AXIOM_CACHE_KEYGEN`/`AXIOM_CACHE_B_RESTORE`/`AXIOM_CACHE_B_VERIFY` 행 — §5) · required 집합 = repo ruleset 20303214(컨텍스트 체크) + org rulesets 25218071·23943917(required workflows, 핀 `Archright/.github` repo_id 1182157951 @ `7eaa9624d128b9f10e9e40d140d5c23367dabdad`) readback. 본 문서는 Reporter다 — 병합 판정 권위(GitHub ruleset·merge queue)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).
> **측정 기준**: api-second-granularity(±1 s) · wall = `merged − added_to_merge_queue` epoch 차 · 스텝/잡 wall = `completed_at − started_at` epoch 차 · skipped 판별자 = `conclusion == "skipped"`(시작=종료 동일 시각 마킹 — '실행 안 됨', 0초 실행 아님) · 중앙값·범위는 n=15 코호트 전수 계산(`data/ci_provider/census_20261103T025821Z/analysis.json` — `analyze.py` 재실행 결정론 확인).

## §1 배경과 질의

선행 조사들(mint tail n=5·교차-venue B 재사용·잡 내부 분해 n=2)은 "개별 잡에서 무엇을 줄일 수 있는가"를 물었다. 이들은 각자의 범위에서 안전한 절감 후보 0개(BLOCKED)로 종결됐다. 남은 조사 공백은 상위 구조다:

**질의**: 자연 발생한 merge_group 배치에서 GitHub가 최종 병합을 허용하기까지 실제로 무엇이 마지막 필수 경로를 구성하며, 그 경로에서 Axiom이 안전하게 통제할 수 있는 비용은 무엇인가?

분리하는 두 그래프(개선 ① 반영):

- **그래프 A — Admission DAG**: required check의 실제 의존관계. 병합 판정 가능 시점(`t_req` = 마지막 required 런 성공 완료)을 결정한다.
- **그래프 B — Resource Contention**: required가 아닌 보조 실행·교차 배치 중첩이 러너 자원을 소비하는 관측. 병합을 직접 막는 의존관계가 아니다(인과 미입증 시 관측 가설로만 기록).

## §2 표본 — 모집단·열거·경계·완결성

**모집단 규칙(사전 고정)**: node24 coherent generation에서 자연 발생한 merge_group 배치 중, 관측창 종료 시각 이전에 MERGE가 완결된 배치 전수. 창 `[2026-11-02T08:08:28Z, 2026-11-03T02:58:21Z)` — 시작 = 세대 개시(양 org ruleset 재핀 readback `7eaa9624…`, updated 08:11:42.586Z/08:12:08.926Z, 하한 = 늦은 쪽 이후 첫 배치 진입 08:39:02Z), 종료 = 스윕 직전 마지막 until 관측 기록.

**열거**: 15배치 = PR #1214–#1228. 배치당 8 워크플로 런 관측(개선 ② 반영):

| 구분 | 집합 | 근거 |
|---|---|---|
| 관측(8 런/배치) | admission-gate, landing-integrity, axiom-operational-slice, bsec-integrity, debt-registry-gate, generation-acceptance, observer-manifest-consistency, probe-merge-queue | merge_group 런 전수 열거(Q16: 창 내 총 120런, 단일 질의 `total_count<1000`) |
| required 런(6/배치) | 위 6종(보조 2종 제외) | repo ruleset 20303214 컨텍스트 체크 5(admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice — admission-check는 admission-gate 런이 산출) + org required workflows 2(admission-gate-v2.yml·landing-integrity.yml) — **distinct 게이트 기준 6** |
| 보조(2/배치) | observer-manifest-consistency(`observe`), probe-merge-queue | 셀프 선언 + ruleset 부재 확인 — 은폐 게이트 없음 |

**완결성 교차검증**: 15/15배치·120/120런 일치(배치 파일 vs 창 열거). `mismatched_heads` 유일값 `71f237e62` = PR #1229 — 런은 창 내 생성(02:47:35Z)했으나 MERGE 02:59:57Z = 컷오프 96초 후 → 규칙상 배제, **경계로 기록**(침묵 탈락 아님). 창 외 추가 관측 8런(스윕 후 창 연장분). `run_number`는 PR 번호가 아니라 큐 진입 순서를 따른다(#1216이 #1217/#1218보다 늦게 진입 → 824): 1214→816, 1215→818, 1216→824, 1217→821, 1218→823, 1219→826, 1220→828, 1221→830, 1222→832, 1223→835, 1224→836, 1225→838, 1226→840, 1227→843, 1228→844.

**GO 실행 코호트(레인 판정 재사용)**: REUSED 4배치(#1214·#1218·#1221·#1226 — GO-critical admission tests 스텝 완료 0초 = 판정 CAS 재사용 경로) / EXECUTED 11배치(신실행 — 표 참조).

## §3 배치별 임계경로 — 그래프 A (전수 15배치)

`critical_wf`(t_req를 늦추는 런) = **admission-gate 15/15**. wall = 진입→MERGE.

| PR | wall | disp | base | lane0 | lane1 | rollup | adm-chk | mint-prep | mint-pub | final | t_req | mrgap | headroom | GO |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| #1214 | 549 | 18 | 90 | 188 | 207 | 3 | 91 | 50 | 48 | 3 | 08:47:51Z | 20 | 115 | REUSED |
| #1215 | 685 | 19 | 79 | 299 | 337 | 2 | 98 | 45 | 43 | 4 | 09:05:05Z | 20 | 139 | EXEC |
| #1216 | 770 | 20 | 77 | 386 | 321 | 3 | 136 | 46 | 53 | 2 | 09:51:40Z | 19 | 252 | EXEC |
| #1217 | 744 | 19 | 66 | 380 | 336 | 3 | 119 | 53 | 48 | 13 | 09:36:17Z | 18 | 240 | EXEC |
| #1218 | 552 | 20 | 119 | 156 | 189 | 3 | 105 | 35 | 35 | 3 | 09:42:07Z | 5 | 75 | REUSED |
| #1219 | 727 | 19 | 73 | 377 | 335 | 3 | 130 | 25 | 51 | 4 | 12:49:00Z | 25 | 212 | EXEC |
| #1220 | 778 | 19 | 87 | 430 | 239 | 13 | 118 | 35 | 58 | 4 | 13:49:43Z | 6 | 270 | EXEC |
| #1221 | 526 | 18 | 72 | 194 | 171 | 3 | 127 | 26 | 37 | 3 | 14:00:53Z | 6 | 17 | REUSED |
| #1222 | 793 | 20 | 95 | 437 | 336 | 14 | 105 | 35 | 51 | 14 | 14:42:07Z | 14 | 406 | EXEC |
| #1223 | 846 | 20 | 68 | 484 | 333 | 5 | 136 | 34 | 46 | 4 | 15:10:09Z | 18 | 343 | EXEC |
| #1224 | 771 | 19 | 78 | 436 | 340 | 4 | 109 | 27 | 58 | 4 | 15:11:02Z | 20 | 318 | EXEC |
| #1225 | 678 | 19 | 100 | 302 | 260 | 6 | 110 | 34 | 53 | 5 | 15:35:04Z | 21 | 282 | EXEC |
| #1226 | 566 | 19 | 98 | 190 | 202 | 10 | 113 | 34 | 36 | 7 | 15:57:11Z | 15 | 40 | REUSED |
| #1227 | 749 | 18 | 100 | 429 | 314 | 4 | 93 | 31 | 44 | 3 | 02:29:37Z | 10 | 355 | EXEC |
| #1228 | 651 | 18 | 94 | 280 | 330 | 2 | 91 | 32 | 37 | 2 | 02:35:08Z | 24 | 133 | EXEC |

단위: 초. disp = 진입→런 생성 · lane0/1 = 병렬 레인 각 wall · t_req = 마지막 required 런 성공 완료 · mrgap = t_req→MERGE · headroom = admission 종료 − operational-slice 종료(그래프 A 경주에서 admission 체인의 우위 폭).

**집계**: wall median **727s** [526, 846], p25 566, p75 771 · headroom median **240s** [17, 406] — admission 체인이 operational-slice 대비 15/15 배치에서 늦게 끝남(최소 우위 17s = #1221).

**구조 관측(진단 추정)**: `wall ≈ max(admission 체인, axiom-operational-slice) + dispatch + merge gap`. admission 체인이 소멸하는 극단 가정에서도 operational-slice(median 458s [349,504]) + dispatch(19s) + merge gap(18s) ≈ 495s > 480s — **단일 안전 절감으로 P95 480s 도달은 구조적으로 불가능**하다는 진단 결론(§8 한정 참조). 이중 체인의 두 축이 모두 480s를 넘는 영역에 있으므로, SLO 달성은 개별 최적화가 아니라 세대 설계(체인 축소·opslice 이관)의 사전등록 주제다.

**정밀화(2026-11-03, dual_lane_assurance_audit §0)**: 495s는 본 진단 코호트(15배치) 중앙값 기반의 반사실 추정이며, #1166 공식 모집단의 P95가 수학적으로 480s를 초과함을 증명하지 않는다 — 공식 SLO 판정은 #1166 동결 계약의 모집단·판정창에서만 수행된다.

## §4 admission 체인 분해 — 그래프 A 내부

### §4.1 스테이지 중앙값 (n=15 전수)

| 스테이지 | median | min | max |
|---|---|---|---|
| attest / build-base-artifacts | 87 | 66 | 119 |
| **attest / go-critical-lane (0∥1 병렬, 지배)** | **377** | **189** | **484** |
| attest / go-critical-rollup | 3 | 2 | 14 |
| attest / admission-check | 110 | 91 | 136 |
| mint-prepare / prepare | 34 | 25 | 53 |
| mint-publish / publish | 48 | 35 | 58 |
| admission-check (7-fold 최종 롤업) | 4 | 2 | 14 |

체인 전 잡(walk 합, 병렬 포함 — wall 아님): admission-gate 런당 실행 잡 13/24(11 skipped), 잡 wall 합 median 663s [462, 777](7스테이지 최종잡 기준).

### §4.2 레인 내부 — GO 코호트 분기가 비용을 설명한다

**EXECUTED 11배치**: `[lane] GO-critical admission tests` lane0 median 190s [max 252] / lane1 median 149s [152]. **REUSED 4배치**: 동 스텝 0초(판정 CAS 재사용 — 운영 중인 판정 재사용 시스템). GO 스텝은 레인 wall의 지배 스텝이다.

**전 15배치 실행 스텝**(재사용 코호트도): `[lane] evidenceId contract check` lane0 med 90s / lane1 med 110s — B-owned self-check 배터리(§7-④).

### §4.3 setup-axiom-toolchain 누적

체인 경로상 잡별 `setup-axiom-toolchain` 스텝 median: build-base 56 · lane0 70 · lane1 48 · attest admission-check 49 · mint-prepare 13 · mint-publish 9 — **직렬 경로 누적 ≈ 197s**(lane0/lane1 병렬이므로 느린 레인 70만 경로에 놓임). 병렬 포함 전 잡 합은 배치당 med 357s [281, 422](집계 컴퓨트량 — wall 아님). 경로 밖: closure-deriver 69 · gateway ci-bootstrap 60(n=10, 조건부 실행).

### §4.4 플랫폼 구간 (GitHub/러너 측)

dispatch(진입→런 생성) med **19s** [18, 20] · 첫 잡 시작 gap(런 시작→첫 잡 started) med 4s [3, 9] · 체인 스테이지 간 핸드오프(직전 종료→다음 시작) med 3s [−15, 26](음수 = 서브초 타임스탬프 역전 quirk §10, clamp 관측 28건 원문 보존) · merge gap(t_req→MERGE) med **18s** [5, 25]. 합계 ≈ 60s — wall 727s의 약 8%가 플랫폼 구간이고, 나머지는 실행 그 자체다. 러너 배정만을 분리 입증할 수 없는 구간은 UNKNOWN으로 남긴다(API가 직접 증거를 제공하지 않음).

## §5 verifier "중복 빌드" 가설 종결 — #1221 B-key 3-way 증거

가설: admission 레인과 axiom-operational-slice가 같은 verifier를 각자 컴파일한다(배치 내 중복 빌드). **기각 — 로그 원문 3-way 증거**:

#1221(런 41461770302 계열)에서 두 잡의 setup-axiom-toolchain 로그:

- admission 레인(go-critical-lane 0): `cache-build-source: aaba7fb36ad0cb01763ec4782bfceba0494cb8d1` (base.sha) → `AXIOM_CACHE_KEYGEN: b-identity=06b9e0c6566df50ea799d42673e7abdb689a0468 b-key=axiom-b-06b9e0c6566df50ea799d42673e7abdb689a0468-41ae9d00a404ca743cd4050a788817ecfec503b1cd6570e7737ce3968b7e9d62 probe-tree=e95be09cee85` → `AXIOM_CACHE_B_RESTORE: exact-hit=true` → `AXIOM_CACHE_B_VERIFY: RESULT OK — 5/5 entries digest-verified, identity=06b9e0c6566d re-derived from trusted inputs (closure+recipe+a_fp), key exact-hit`
- axiom-operational-slice: `cache-build-source: a5cfd5bb2abb4c7aa011914d970e3176962967ba` (merge head) → 동일 `b-identity=06b9e0c6566df50ea799d42673e7abdb689a0468` 동일 b-key(probe-tree=b919d08cc31a — 소스 SHA가 달라도 의미론적 클로저·레시피·a_fp 다이제스트가 동일) → `exact-hit=true` 5/5 digest-verified.

**해석**: b-identity는 소스 SHA가 아니라 검증된 입력 클로저(closure+recipe+a_fp)의 다이제스트에서 재도출되므로, base와 merge head가 다른 SHA여도 **동일 B-key exact-hit**로 nimcache를 공유한다. 중복 컴파일 0. 각 잡의 이후 바이너리 재생산(nimcache 복원 후 C-컴파일+LTO)은 **설계된 동작**이다 — `.github/actions/setup-axiom-toolchain/action.yml:22-24`: "verdicts are always recomputed (the 4 ci-compile binaries are recompiled even on a HIT today; census 2026-09-30) — cache is acceleration, never evidence". opslice의 `Build the release verifier (ci-compile authority)` med 191s(n=15, max 202)는 이 재생산 비용이며, J3 계약상 판정 신선성(캐시≠증거)을 위해 유지된다. `docs/evidence/cross_venue_b_reuse_closure_2026-11-02.md`의 종결과 일치한다.

## §6 그래프 B — Resource Contention (관측 가설)

교차 배치 실행 중첩(배치 A의 실행 구간 ∩ 배치 B): 4쌍 — #1217/#1218 215s · #1218/#1216 183s · **#1223/#1224 716s** · #1227/#1228 306s. #1223/#1224는 코호트 최저 wall 2배치(846/771s — 최고·4위)와 동시에 최장 중첩을 보인다.

**판정: UNKNOWN(관측 가설 — 인과 미입증)**. 근거: (a) required workflow의 동시 실행은 GitHub 문서상 병합을 막는 의존관계가 아니다(required checks 통과가 admission 조건 — 긍정형 문서; 부정형 보증은 미문서화, 모순 아님); (b) 동일 runner_id·캐시 키 경합·lock 오류 등 자원 공유 신호 또는 복원 시간 인과 곡선이 관측되지 않았다(경합 분류 기준 미충족). Build concurrency 스로틀 존재 시에도 그래프 B 소속이다. 러너가 GitHub-hosted 풀에서 교차 배치 잡을 흡수했는지는 본 관측으로 분리 불가 — 제거 후보가 아니다.

## §7 6기준 판정 — GO 0 / BLOCKED 7 / UNKNOWN 3

기준: 실제 비용 재현 · 임계경로 위치 · 제어 가능성 · 검증 의미론 보존 · 노이즈 대비 효과(관측 provider 변동 ~23s는 참고, 고정 임계값 아님) · 부정 시험 가능성.

**GO 0건.**

### BLOCKED 7건 (제거하면 안 되거나, 안전 제거 증명 불가 — 변경하지 않고 종결)

| # | 비용 | 근거 |
|---|---|---|
| ① | A-restore/setup 반복(경로 누적 ≈197s, §4.3) | PR #1192 심판(`docs/evidence/arestore_optimization_blocked_2026-11-02.md`): mechanism 2(제거·대체)는 의미론 파괴 — A-restore가 검증 stage-b/c 실행 재료 공급, ircheck fail-closed·`lake env lean`+z3 무조건. mechanism 1(경합 완화 스태거링)은 lane 창으로 경합 재배치 + 효과가 provider 노이즈(23s)에서 식별 불가 |
| ② | verifier 배치 내 재빌드(opslice 191s 등) | J3 설계 — §5 3-way 증거: 동일 B-key exact-hit·중복 컴파일 0, 재생산은 "cache is acceleration, never evidence" 계약 |
| ③ | GO tests 실행(EXECUTED 코호트 lane0 med 190s) | 검증 의미론 그 자체 + **판정 재사용 시스템이 이미 운영 중**(REUSED 4/15 — 클로저 일치 시 0초 재사용, 미일치 시 필수 신실행). 추가 재사용 확장은 입력 동일성 증명 의무(J1–J4) 선행 필요 |
| ④ | evidenceId contract check(전 배치 실행, 레인별 med 90/110s) | B-owned self-check — 증거 무결성 배터리, 재사용 대상 아님 |
| ⑤ | mint-prepare 34s + mint-publish 48s | 선행 n=5 mint tail 분해가 안전 절감 후보 0개로 BLOCKED 종결(`docs/evidence/node24_mint_tail_decomposition_2026-11-02.md`) — CAS ledger append 보존 |
| ⑥ | dispatch 19s + 핸드오프 + merge gap 18s | GitHub 플랫폼측(merge queue 스케줄·러너 배정·MERGE 커밋 처리) — Axiom 제어 영역 밖. 실행 어댑터측 원인을 워크플로 검사 제거로 해결하지 않는다 |
| ⑦ | required 체크 수·구조(6 게이트) | 신뢰 경계 — AGENTS.md §2.3(merge admission authority = GitHub ruleset)·검증 의미론. 축소는 제품 계약 개정 사안이지 최적화 사안이 아님 |

### UNKNOWN 3건 (관측됐으나 원인 미입증 — 추가 증거 없이 최적화하지 않는다)

| # | 관측 | 미입증 이유 |
|---|---|---|
| ① | 교차 배치 중첩 4쌍(§6) — 716s 최장 | 인과 미입증(그래프 B — 관측 가설). **정밀화(2026-11-03, unknown_closure §1)**: 재검증 완료 — 중첩 창 내 갭 상승 없음(med 3s 양측)·러너 재사용 0/340(잡당 신규 VM, 공식 문서상 구조적으로 불가)·오류 시그니처 0·인과 곡선 부재. **입증 실패로 UNKNOWN 유지**(경합 부정이 아님) |
| ② | 사전 큐 갭(PR green → 큐 진입) | 관측창 밖(본 Census는 진입 이후만 관측) — 별도 관측 설계 필요. **정밀화(2026-11-03, unknown_closure §3)**: **해소(진단 측정)** — 갭 med 60s [5,197] n=15, 트리거 분해 증명(auto-merge 3건 7/15/24s·수동 12건 med 60.5s), 큐 메커니즘 소비 0(그룹 커밋 생성 ±1s), GitHub admission 처리 ≤7s |
| ③ | #1192 잔여 후송: attest A-restore의 Lean+`~/.local/bin` 스코프 축소(~12–15s) | 사전 분석 존재(`docs/evidence/lean_toolchain_scope_analysis_2026-11-02.md`) — GO/NO-GO는 미판정, WP-B2 사전등록 검토 대기 |

### 잔여 후송 참고 2건 (본 Census 범위 밖 기록)

- SLO P95 480s 도달은 이중 체인 구조상 단일 안전 절감으로 불가(§3 구조 관측) — 세대 설계 주제로 별도 사전등록 필요.
- `verdict / admission-check`(med 43s [38,59])가 attest admission-check와 병렬 스테이지 분리로 실행 중(스테이지 분리가 판정 경로 중복을 제거하는 설계 — 잡 분해 보고서 §4.3과 일치).

## §8 셀프 한정 — #1166 공식 판정과의 관계 (개선 ③)

**본 Census는 진단 코호트 요약이며, #1166의 공식 SLO 판정(공식 모집단·P50/p95·판정창 until 타임스탬프)을 산출하지도 선점하지도 않는다.** n=15는 이동 모집단의 전수 스냅샷이다 — 코호트 규칙·컷오프 시각(2026-11-03T02:58:21Z)이 본문에 고정되어 있으므로 재현 가능하지만, 공식 판정창의 표본 규칙(`slo_official_measurement_prereg_2026-11-01.md`)과는 별개다. 개별 배치의 병목(예: #1223 lane0 484s)이 전체 운영에서 반복된다는 일반화는 하지 않는다 — 반복 관측·임계경로 기여도·코호트 변동성 확인 전에는 UNKNOWN 유지 원칙(§7).

## §9 검증 가능성 (GET-only 재현)

정본 데이터: `data/ci_provider/census_20261103T025821Z/`(배치 15파일·completeness·analysis·analyze.py·workflow_defs·manifest — `python3 analyze.py` 재실행으로 동일 analysis.json 재생산 확인). 원문 API 재조회:

```bash
# 0) required 집합 readback (repo 컨텍스트 체크 + org required workflows 핀)
gh api repos/Archright/Axiom/rulesets/20303214 --jq '.rules[] | select(.type=="required_status_checks")'
gh api orgs/Archright/rulesets/25218071 --jq '.rules[].parameters.workflows[] | {path, repository_id, sha}'
gh api orgs/Archright/rulesets/23943917 --jq '.rules[].parameters.workflows[] | {path, repository_id, sha}'
# → sha 7eaa9624…, path .github/workflows/{admission-gate-v2,landing-integrity}.yml, repo_id 1182157951
#    (2026-11-03 교정: org ruleset REST API의 rule type은 "workflows"·매개변수
#     .parameters.workflows[] — 기존 "required_workflow" 경로는 현행 응답에서 빈 출력.
#     SHA·repo_id 판독 결과는 불변, dual_lane_assurance_audit §9와 동일 교정)

# 1) 관측창 열거 (Q16 — 단일 질의 total_count 확인 + run-id dedupe)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-02T08:08:28Z..2026-11-03T02:58:21Z&per_page=100" --paginate

# 2) 배치 경계·배치별 런 (PR timeline = 배치 경계 권위; merge_group SHA로 런 매핑)
gh api repos/Archright/Axiom/pulls/1221 --jq '{merge_commit_sha, merged_at}'
gh api repos/Archright/Axiom/pulls/1221/timeline --paginate   # added_to_merge_queue / merged
gh api "repos/Archright/Axiom/actions/runs?head_sha=<merge_group_sha>&event=merge_group"

# 3) 잡·스텝 원문 (filter=latest 명시 — 재실행 이전 시도 조용히 제외 방지; 전부 run_attempt=1)
gh api "repos/Archright/Axiom/actions/runs/<run_id>/jobs?filter=latest" --paginate

# 4) §5 B-key 증거 재조회 (잡 로그 — 90일 보존)
gh api repos/Archright/Axiom/actions/jobs/<lane_job_id>/logs | grep -a "AXIOM_CACHE_KEYGEN\|AXIOM_CACHE_B_RESTORE\|AXIOM_CACHE_B_VERIFY"

# 5) 집계 재실행 (결정론 — 동일 analysis.json)
cd data/ci_provider/census_20261103T025821Z && python3 analyze.py
```

## §10 관측 quirk (§0.5 — 문서화)

- **jq 1.7 `IN($arr)` 멤버십 오답**: 존재하는 원소에 false 반환 — `index()`로 회피. 신규 문서화: `docs/spec/jq_17_in_membership_quirk.md`.
- `gh api` 잡 로그 취득 시 `--allow-escape-sequences` 필요(누락 시 0바이트+오류) — `docs/spec/gh_run_observation_quirks.md` 계보.
- 잡 레벨 서브초 타임스탬프 역전 28건(`completed_at < started_at`) — 원문 보존, 집계에서 clamp 처리(analysis.json `reversal_clamps` = 0은 체인 스테이지 기준치; 잡 레벨 원값은 배치 파일에 보존).
- skipped 잡은 `steps: []`·`runner_name: null` 반환.
- 큐 퇴장 이벤트 실명 = `removed_from_merge_queue`(timeline).
- `run_number`는 PR 번호가 아닌 큐 진입 순서(§2).
