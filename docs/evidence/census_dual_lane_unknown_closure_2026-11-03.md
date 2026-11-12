# Census·Dual-Lane 잔여 UNKNOWN 종결 — 동시성·b-identity·사전 큐 갭 (2026-11-03)

- **문서 종류**: docs/evidence — 읽기 전용 **후속 증거 보고**. 코드·워크플로우·게이트·판정 의미론 변경 0. 본 보고서는 판정을 만들지 않는다(Reporter — merge admission authority = GitHub).
- **방식**: census §7 UNKNOWN①②·dual-lane §7 UNKNOWN②·l3_followup §1 측정 4항을 **백그라운드 병렬 서브에이전트 3건**(F-1~F-3)으로 조사하고, 각 산출을 본 Reporter가 원본(잡 로그 원문·check-runs·API 재조회·스윕 독립 재실행)에서 재검증해 재인용했다(dual-lane:3 스타일 계승 — AGENTS.md §2.3 Authority ≠ Adapter).
- **코호트**: census 진단 코호트 15배치(#1214–#1228) **재사용(읽기 전용 재계산·API GET 재조회)** — 새 CI 실행을 만들지 않았다. 본 수치는 진단 계층이며 #1166 공식 SLO 모집단과 무관하다.
- **데이터**: `data/ci_provider/unknown_closure_20261103T111036Z/` — `concurrency_queue.json`(F-1)·`bidentity_summary.json`+`bidentity_verbatim.json`(F-2 원문 225행)·`prequeue_gap.json`(F-3)·`manifest.json`.

## §0 판정 요약

| 항목 (정본 위치) | 결과 | 핵심 |
|---|---|---|
| census §7 UNKNOWN① — 교차 배치 중첩 인과 | **UNKNOWN 유지(부정적 재검증 완료)** | 경합 분류 기준 재적용: 러너 재사용 0/340·중첩 창 내 갭 상승 없음(med 3s 양측)·오류 시그니처 0·인과 곡선 부재 — **"경합 아님"이 아니라 입증 실패**. 호스팅 러너는 잡당 신규 VM·종료 시 폐기(공식 문서) → 흡수 가설도 구조적 반증 |
| census §7 UNKNOWN② — 사전 큐 갭 | **해소(진단 측정)** | 갭 = PR green → 큐 진입, med **60s** [5,197] n=15. 트리거 분해 증명: auto-merge 3건(7/15/24s)·수동 12건(med 60.5s). 큐 메커니즘은 갭을 소비하지 않음(그룹 커밋 생성 ±1s) — GitHub admission 처리 ≤7s |
| dual-lane §7 UNKNOWN② — 14배치 b-identity 로그 원문 | **해소** | 75잡 로그 원문 전량 추출: **12/15 cross-lane SAME + 3/15(src 변경) 예고된 2-key 분기**, 75/75 exact-hit=true. 일반화 n=1 → n=12(+분기 3) |
| l3_followup §1 — S-1 측정 4항 중 (1)(2)(4) | **측정 완료** | 관측 최대 동시 잡 **15**(< 최소 티어 20, 여유 5)·created→started 갭 med 3s [2,39](큐 병목 징후 없음)·attest 창 headroom 5–10(Free 기준) |

유지되는 UNKNOWN(정직 기록): org 플랜 티어(어느 한도 열과 비교해야 하는지)·갭 내부 분해(동시성 큐 vs VM 프로비저닝)·수동 갭의 인간 반응 시간 분리·중첩 쌍의 물리적 인과 — 전부 API 미노출 변수다.

## §1 F-1 — 동시성·큐 갭 실측 (UNKNOWN① 부정적 재검증 + S-1 측정항)

**측정 기반**: 실행 잡 340(510 레코드 − 스킵 170), jobs API 재조회 무결성(120런 — census 대비 missing 0·extra 0·started_at 불일치 0). 3가지 동시각 규약(시작우선·종료우선·반개구간 브루트포스) 모두 동일 결과.

**(a) 관측 최대 동시 잡 = 15** (14:58:57Z, #1223 5잡 + #1224 10잡 — 최장 중첩 창 내). side_job 281건은 self-hosted(`axiom-control-northflank`)로 플랜 한도 회계와 별개 풀이며 포함 시 16. 배치별 창 내 최대는 대부분 10–11, 중첩 배치 #1223/#1224에서 15. 공식 문서 대조: 최대 15 < **최소 티어(Free) 20** — 코호트 최고 순간에도 5 슬롯 여유. org 티어는 미관측 → 어느 열과 비교할지는 UNKNOWN.

**(b) created→started 갭**: med **3s** [2,39] p90 13, n=340. gap=0은 0건(전 잡 ≥2s — 플랫폼 고정 비용). 8 워크플로 전부 med 3s. 전체 최대 39s는 **비중첩** 배치 #1215 — 중첩과 무관. 분해: run created→첫 잡 created 0–1s, 잡 created→started 2–14s. 내부 분해(동시성 큐 vs 러너 배정)는 API 미노출 → census §4.4 UNKNOWN 계승.

**(c) 중첩 4쌍 재검증 — UNKNOWN 유지**: 실행창 중첩 #1216×#1218 154s·#1217×#1218 174s·#1223×#1224 676s·#1227×#1228 275s. 경합 분류 기준(동시 구조 + 자원 공유 신호 또는 인과 곡선) 적용 결과:
- 갭 비교: 창 내 시작 잡 n=90 med 3 [2,23] vs 창 밖 n=250 med 3 [2,39] — **상승 없음**
- 러너 재사용: **340잡 = 340개 상이 runner_id** (교차 배치·배치 내 모두 0건)
- 로그 원문(창 내 90잡 전수): `##[error]` 0건 — lock/QUEUED/Cache-not-found 매칭은 전부 설계된 방어 주석·표준 콜드 경로
- 복원 시간 인과 곡선: toolchain 스텝 창 내 med 45.5(n=48) vs 밖 47.0(n=127) — **상승 없음**, 12잡 유형 중 8유형이 창 내 ≤ 밖 (lane0 +14s·opslice +30s는 n=4씩, 노이즈 ~23s 이내·방향 혼재)
- 결론: **입증 실패로 UNKNOWN 유지**. 단, 호스팅 러너의 잡당 신규 VM 프로비저닝·종료 시 폐기(공식 문서)가 재사용을 구조적으로 불가하게 하며 관측(340=340)과 정합 — 러너 풀 흡수 가설은 구조적 반증.

## §2 F-2 — 15배치 cross-lane b-identity 원문 추출 (dual-lane UNKNOWN② 해소)

**방법**: dual-lane §6이 #1221에 쓴 증거 방법(잡 로그의 `AXIOM_CACHE_KEYGEN: b-identity=…`·`AXIOM_CACHE_B_RESTORE: exact-hit=…` 행)을 15배치 × 5잡(lane0·lane1·bbase·job2·opslice)에 전수 적용. 75잡 로그 수신 실패 0.

**결과**:
- **12/15 배치(docs/data 변경)**: admission 측 4잡과 opslice가 **동일 b-identity + 양측 exact-hit=true** — cross-lane 일반화가 n=1 → n=12로 입증.
- **3/15 배치(#1220·#1222·#1223, 전부 src/ 변경)**: 예고된 **2-key 분기** 그대로 — admission 측 = 변경 전 identity, opslice = 변경 후 identity(서로 다른 b-key), **양측 모두 exact-hit=true**(각자 기존 엔트리).
- 집계: 75/75 exact-hit=true·`requested-key==primary-key==matched-key`(fallback 0)·`B_VERIFY: RESULT OK — 5/5`·FAIL/DISCARDED 0·로그당 KEYGEN/RESTORE 정확히 1행(재시도 흔적 없음).
- 세대 창: b-identity `73dfd535…`(1214–1220) → `06b9e0c6…`(1221–1222) → `c60d5ae3…`(1223) → `56d95ab6…`(1224–1228); b-key recipe 성분 `41ae9d00…` → `74294042…` 1회 교체(#1222 분기 시점).

**정직한 정정(dual-lane §6 (3) 대비)**: §6 (3)은 "src/ 변경 배치는 양 레인 각자 콜드"로 예측했으나, 실측은 **양 레인 모두 exact-hit**였다(신규 키의 엔트리가 이미 존재). 게시자 체인(누가 언제 엔트리를 게시했는지)은 본 조사 범위 밖 — 재사용 범위 확대의 근거로 쓰지 않는다(가혹 조건 명시).

**부수 정합성**: admission 잡 `cache-build-source` == run queue-branch sha **15/15**·opslice `cache-build-source` == 배치 merge_commit_sha **15/15**·병합 순서 기준 직전 배치 merge head == 다음 배치 admission base **14/14** (번호 순서 3건 break는 큐 재정렬로 해소).

**이것으로 확립되지 않는 것**: dual-lane §7 UNKNOWN①(S5 opslice 확장의 중복성)은 **유지** — §6 승격 증거 4항 중 (1)만 완료됐고, (2) 산출물 동등성·(4) 미배선 반사실은 미확보, 레인 간 소비 계약 부재도 그대로다.

## §3 F-3 — 사전 큐 갭 측정 (census UNKNOWN② 해소)

**규칙(관측 전 고정)**: 갭 = `added_to_merge_queue` − (PR head에 대해 큐 진입 이전 마지막 성공 완료된 required check의 완료 시각). required 집합 = repo 5컨텍스트 + landing-integrity(org required workflow — 런 단위 `updated_at` 판정, check-run이 아님). 모집단 15배치 전수.

**결과 (n=15)**: 중앙값 **60s**, 최소 5s, Q1 24s, Q3 98s, P90 129s, 최대 197s, 평균 63.5s. 최종 게이트는 12/15에서 `axiom-operational-slice`(진입−완료 med 61s), 3/15에서 `admission-check`(med 192s).

**타임스탬프로 증명된 것**:
1. **green 연속성 15/15** — 진입 전 required 재실행·실패 0건 → 갭은 flake 복구 노이즈를 포함하지 않는 순수 구간.
2. **큐 메커니즘은 갭을 소비하지 않음** — merge-group 커밋 생성(committer_date)이 `added_to_merge_queue`와 15/15 ±1s → 측정 갭 전체는 큐 이전 구간.
3. **트리거 분해** — `auto_merge_enabled` 선행 3건(#1216·#1222·#1226)은 GitHub 자동화 트리거로 증명(갭 7/15/24s), 12건은 수동(actor 일치, 이벤트 전무)으로 증명(med 60.5s).
4. **admission 처리 상한 ≤7s** — 관측 전 케이스에서 자동 최소 7s·수동 최소 5s.

**UNKNOWN 유지**: 12개 수동 갭의 내부 분해(인간 반응 시간 vs admission 처리) — `added_to_merge_queue`가 첫 이벤트라 선행 타임스탬프 없음. 공식 문서도 green→진입 지연의 상한·SLA를 보증하지 않는다(Context7: merge_group 트리거 = 큐 추가 시점·두 진입 경로(즉시/auto-merge)만 문서화) — 본 갭은 진단 측정값이지 공식 보증이 아니다.

**게이트별 오프셋(med)**: opslice 61s·admission-check 192s·bsec 429s·debt 465s·generation 468s·landing-integrity(wf) 524s — **PR-side admission DAG의 꼬리는 opslice** (admission-check 다음).

## §4 구현 사전등록 함의

- **L3-GO 이동 슬랩 사전등록의 S-1 측정 4항 완결**: (1) 관측 최대 동시 잡 15·(2) created→started 갭 med 3s [2,39] 큐 병목 징후 없음·(4) attest 창 headroom(Free 기준 5–10) — 전부 동결 코호트 진단값으로 확정. (3) Ubicloud 러너 수는 현행 GHEC 에포크에서 0(호스팅 러너만 관측). 사전등록은 이 값을 **진단 추정**으로 인용하고 확증은 착지 후 신규 관측으로만.
- **사전 큐 갭은 병합 wall의 일부가 아니다**: census의 배치 wall(진입→MERGE)에 이 갭은 포함되지 않는다(진입 이전 구간). 병합 지연 분해는 이제 전 구간 폐쇄: 사전 큐 갭 med 60s(트리거 지연이 지배) + 배치 내 플랫폼 구간 ~60s + 실행 자체.
- **중첩 인과는 입증 실패 유지** — 어떤 최적화 후보도 여기서 나오지 않는다(조용한 추정 금지 원칙의 실천).
- **b-identity 일반화**는 dual-lane §7 UNKNOWN①(S5 중복성)의 **증거 (1)만** 채운다 — 소비 계약 설계(L1)·산출물 동등성·반사실은 그대로 별도 사전등록 소관.

## §5 재현 명령 (GET 전용·읽기 전용)

```bash
# F-1 (a)(c): 동시성 스윕 + 중첩 창 — sweep.py는 /tmp 휘발 산출이므로 census jsonl에서 재구성
cat data/ci_provider/census_20261103T025821Z/batch_*.jsonl | jq -s 'group_by(.type)|map({type:.[0].type,n:length})'
# 실행 잡 [started_at, completed_at] 이벤트 스윕(시작/종료 정렬, 동시각 3규약) → 최대 동시 15
# F-1 (b): gh api "repos/Archright/Axiom/actions/runs/<run_id>/jobs?filter=latest&per_page=100" --paginate → gap = started_at − created_at
# F-1 (c): 창 내 잡 로그 → gh api --allow-escape-sequences "repos/Archright/Axiom/actions/jobs/<id>/logs" (Q3 quirk)
# F-2: job_id는 배치 jsonl type==job 레코드에 있음;
gh api repos/Archright/Axiom/actions/jobs/<job_id>/logs --allow-escape-sequences > /tmp/logs/<pr>_<kind>.log
grep -aE 'AXIOM_CACHE_KEYGEN: b-identity=[0-9a-f]{40}' /tmp/logs/<pr>_<kind>.log
grep -aE 'AXIOM_CACHE_B_RESTORE: exact-hit=(true|false) requested-key=[0-9a-f]' /tmp/logs/<pr>_<kind>.log
grep -aE 'AXIOM_CACHE_B_VERIFY: RESULT (OK|FAIL|DISCARDED)' /tmp/logs/<pr>_<kind>.log | grep -av '\[36;1m'
# 판정: 배치 내 5잡 b-identity 집합 크기 1 → SAME(12), 2 → 2-key 분기(3)
# F-3: t_green = 6게이트 최대 완료시각(≤큐진입), 갭 = 큐진입 − t_green
gh api "repos/Archright/Axiom/issues/<n>/timeline?per_page=100" --paginate        # added_to_merge_queue + auto_merge_enabled
gh api "repos/Archright/Axiom/actions/runs?event=pull_request&head_sha=<sha>&per_page=100"  # landing-integrity(wf)
gh api "repos/Archright/Axiom/commits/<sha>/check-runs?per_page=100"             # 5 컨텍스트
```

## §6 셀프 한정 (규율 선언)

- 전 수치는 **진단 코호트 15배치의 탐색적 추정**이다 — 확증 주장이 아니며(관측 후 고정 규율, `e3_measurement_contract:13`), #1166 공식 SLO 모집단·판정창과 무관하다.
- 유지된 UNKNOWN(org 티어·갭 내부 분해·수동 갭 인간 반응·중첩 물리 인과·b-identity 게시자 체인)을 조용한 추정으로 채우지 않는다.
- 3건 전부 원인 귀속·측정·기록이며 **구현을 포함하지 않는다** — L3-GO·L1·캐시 재사용 확대는 각각 별도 사전등록(계약 + 부정 시험 + coherent generation + 신뢰 표면 인간 승인)의 소관이다.
- 서브에이전트 산출의 핵심 수치(F-1 스윕·F-2 #1221/#1220/#1223 원문·F-3 #1221/#1214 갭)는 Reporter가 원본에서 재검증한 뒤 재인용했다.
