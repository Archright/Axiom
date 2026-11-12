# SLO 상태 스냅샷(진단) — 세대 정렬 관측 상태: Merge Queue wall P95 (2026-11-02) — 최종 판정 아님 · #1166 동결 계약 불변

> **문서 성격(최우선 규정)**: 본 문서는 **상태 스냅샷(진단) — 최종 판정 아님; #1166 동결 계약 불변**이다.
> 세대 정렬(Node 24 신세대) 진행 상황의 관측 기록이지 공식 SLO 판정 보고서가 아니다. SLO 달성·미달성 주장
> 어느 쪽도 아니다. 모든 수치는 "status snapshot @ 2026-11-02 (T_snap = 2026-11-02T10:34:37Z)" 한정이다.
> **공식 판정의 위치**: 최종 판정은 별도로 사전등록된 판정창 문서
> `docs/evidence/slo_judgment_window_prereg_2026-11-02.md`(본 문서와 같은 docs-only PR에 동반 착지)가
> 등록한 관측 창이 **창 종료 후** 산출한다. 본 문서의 스냅샷 값은 그 판정의 근거로 소비되지 않는다(§1·§9).
> **Date**: 2026-11-02 · **Branch**: docs-only PR(`docs/evidence/` 착지 — 관측 종결 문서 5건 동반: 본 문서·mint tail 분해(`node24_mint_tail_decomposition_2026-11-02.md`)·캐시 회전 관찰(`actions_cache_rotation_observation_2026-11-02.md`)·교차-venue 종결(`cross_venue_b_reuse_closure_2026-11-02.md`)·판정창 사전등록(`slo_judgment_window_prereg_2026-11-02.md`))
> **Scope**: 본 문서 1건(`docs/evidence/slo_status_snapshot_2026-11-02.md`) — 코드·워크플로우·게이트·핀·도구
> 변경 0건. docs-only 비행 → trust surface 아님(정상 merge queue 경로).
> **측정 시각**: T_snap = 2026-11-02T10:34:37Z — 재현 명령 실행 2026-11-02T10:34–10:45Z(§8).
> **권위**: 본 문서는 **Reporter**다 — GitHub merge authority(required checks·merge queue·MERGE commit)를
> 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 어떤 게이트도 본 문서의 값을 소비하지 않는다.
> 모든 관측은 GET-only·`gh` 네이티브 인증(AGENTS.md §2.4). 저장소 변경 0건.

---

## 1. 문서의 위치 — 진단 스냅샷과 공식 판정의 관계

- 본 문서는 세대 정렬 진단 스냅샷이다. 공식 SLO 판정 보고서가 아니며, 판정을 대신하거나 앞당기지 않는다.
- **#1166 동결 계약(`docs/evidence/slo_official_measurement_prereg_2026-11-01.md`, 이하 "prereg")은 본
  문서가 변경·재해석·재분모화하지 않는다** — 본 문서는 prereg의 지표 정의(§2)·모집단 규칙(§4)·백분위
  계산식(§6)·관측 프로토콜(§9)을 그대로 소비해 한 시점의 상태를 기록한 2차 문서다(측정·기록 계층).
- **공식 판정 = `slo_judgment_window_prereg_2026-11-02.md`가 사전등록한 판정 관측 창 [since, until]에서
  창 종료 후에만 산출된다.** 상호 참조: 본 문서 → 판정창 문서(판정 위치 선언, §9). 본 문서의 스냅샷 값이
  판정에 사용되는 일은 없다 — 판정창 문서가 등록하는 창만이 판정 근거다.
- 극장 방지 선언: 본 문서의 값은 어떤 판정·게이트·자동화·merge-admission에도 소비되지 않는다.

## 2. #1166 동결 계약 요약 (본 문서가 변경하지 않음)

**차량**: PR #1166 "docs(evidence): 공식 SLO 측정 계약 사전등록 (2026-11-01)" — state MERGED,
merged_at **2026-11-01T13:35:28Z**, merge_commit `a8f7464c54bb`, docs-only 1건
(`docs/evidence/slo_official_measurement_prereg_2026-11-01.md` = prereg). 댓글 0건
(GET `repos/Archright/Axiom/issues/1166/comments` → 빈 배열). 동결 원문은 로컬 clone 상기 문서와 일치.

| 계약 항목 | 동결 내용 (prereg 위치) |
|---|---|
| **공식 지표** | `official_wall = run.updated_at − run.created_at [초]` — **큐 대기 포함**(`created_at`은 merge-queue 표본(그룹) 생성 시점 — 의도된 정의). API second granularity ±1초 — 소수 보고 금지, 초 단위 정수 차로 산출 (prereg §2) |
| **공식 모집단** | 관측 창 내 `admission-gate` merge_group 런 중 **완료(conclusion ∈ {success, failure}) 런 전수**, run 객체 단위(1 run = 1 표본 — 배치 병합으로 복수 PR이 하나의 런을 공유하므로 PR 단위 정의 금지) (prereg §4) |
| **취소 런** | 모집단 제외 + **별도 등록 의무**(ID·생성·종료·사유 — 불명은 `unknown`). Censoring 감시: `cancel_ratio > 15%` 또는 취소 중앙 큐 대기 > 완료 런 중앙값 ×2 → P95 보고에 **편향 경고 병기**(역치 동결) (prereg §4) |
| **백분위** | **Hyndman & Fan (1996) type 7(R 기본값, 선형 보간)으로만** 산출 — 결정론. nearest-rank(`tools/ci/pareto_harness.nim:236`)와 병행 보고 시 방법명 명시 의무 (prereg §6) |
| **판정 조건** | **n ≥ 30**(공식 모집단 완료 런 기준; 미달 시 P95 미산출 — p50만 "잠정") + **관측 시간창 [since, until] 명시 의무**(UTC, 런 `created_at` 기준 GitHub-clock; 창 외 관측의 사후 편입 금지) + 보고 필수 동반값(n·측정 구간·p50·p95·최소·최대) (prereg §7) |
| **진단 2값 병행** | `latest_attempt_wall` = `updated_at − run_started_at`, `attempt_wall` = attempt-scoped job interval union(`/attempts/{n}/jobs`, `filter=all`) + **`run_attempt` 병기** — 모든 보고 동반 (prereg §3) |
| **큐 wall 단독값** | **계약 미정의** — "큐 wall" 독립 산출식은 계약에 없다. `run_started_at − created_at`은 **취소 런 censoring 진단 전용**으로만 등록됐다(prereg §4). 본 스냅샷도 queue-only wall을 별도 산출하지 않는다 |
| **소급 수정** | **금지**(prereg §10) — 과거 prereg·판정 데이터 재분류·재계산·재분모화 금지; 계약 변경은 새 날짜의 사전등록 문서로만 |
| **epoch** | 공식 모집단은 전체 전수(epoch를 가르지 않음) — epoch 혼합 명시 의무, epoch 진단층은 2차 보고 전용. GHEC 복귀 경계 = 2026-11-01T10:53:18Z `GHEC_RETURN_CONFIRMED` (prereg §5) |

## 3. 공식 모집단 스냅샷 @2026-11-02T10:34:37Z — **최종 판정 아님·480s 초과 관측 상태**

**관측 창(본 스냅샷 등록값)**: `[2026-11-01T13:35:28Z, 2026-11-02T10:34:37Z]`
— 창 시작 = 계약 착지(merged_at), 근거: prereg §4 "본 문서 착지 이후의 측정부터 취소를 분리 등록" +
자연 누적 원칙(임의 표본 생성 금지). 창 끝 = 스냅순간 T_snap. 6h 서브윈도 4개로 열거(prereg §9 프로토콜).

### 3.1 열거 결과 (창별)

| 창 (UTC, created 기준) | 쿼리 total_count | ≪1000 유효 | admission-gate 런 | 비고 |
|---|---|---|---|---|
| W1 11-01T13:35:30..19:35:30 | 80 | ✓ | 10 | 시작 2초 오프셋(13:35:28→:30) — 갭 GET 확인 **0건** |
| W2 11-01T19:35:30..11-02T01:35:30 | 120 | ✓ | **15** | 1페이지(100건) 한도로 13건 — `--paginate`로 +2 복원 |
| W3 11-02T01:35:30..07:35:30 | 208 | ✓ | **26** | 1페이지로 12건 — `--paginate`로 **+14 복원** |
| W4 11-02T07:35:30..10:34:37 | 48 | ✓ | 6 | |

- **페이지네이션 효과 실증**: 페이지 1만 썼다면 57건 중 16건 누락(27%). prereg §9 프로토콜이 실제로 작동했다.
- run ID dedupe: 4창 교집합 0. 동일 head_branch 중간 완료 런: 0건.
- **경계 관측(모집단 유지, 규칙 그대로 적용)**: pr-1211 이중 도크 — 그룹 `pr-1211-5af660d3f…`
  런 41398223460 **failure**(06:10:06) → 재도크 그룹 `pr-1211-b15e2a10…` 런 41398406308 success(06:11:53).
  서로 **다른 head_branch = 다른 그룹**이므로 prereg §4 문자대로 둘 다 모집단(failure는 정의상 모집단 구성원).
- **Q16 단일 GET 교차검증 6건 전부 초 단위 일치**: 41312498886(#695, 창 최초), 41414648142(#816),
  41416443711(#818), 41420386024(#821), 41421620938(#823), 41422458822(#824, 창 최말).

### 3.2 공식 값 (prereg §6 R-7 · §7 동반값 동반) — **라벨: "최종 판정 아님·480s 초과 관측 상태"**

| 항목 | 값 |
|---|---|
| **라벨** | **최종 판정 아님·480s 초과 관측 상태** — 스냅샷 시점(T_snap)의 관측일 뿐, 판정 아님 |
| **n (완료 = success+failure)** | **57** (success 56 · failure 1 · cancelled 0, run_attempt 전부 1) |
| **측정 구간** | [2026-11-01T13:35:28Z, 2026-11-02T10:34:37Z] |
| **p50 (R-7)** | **584초** |
| **p95 (R-7, 공식 방법)** | **738초** (= 737 + 0.2×(742−737); h=53.2 → sorted[53..54]) |
| 최소 / 최대 | 429초 / 835초 |
| 참고: nearest-rank p95 (공식 아님, 방법명 명시 의무) | 742초 (`pareto_harness.nim:236` 방식) |
| 참고: success 한정 (n=56, 비공식 참고) | p50 587.5 · p95 738.25 |
| 정렬 표본 (57개 전부) | 429,430,445,445,450,451,456,461,462,464,466,470,471,472,479,484,485,487,488,495,509,512,515,527,528,559,560,578,584,591,595,610,618,626,627,635,637,647,659,659,663,671,677,679,693,698,699,700,708,708,711,730,731,737,742,752,835 |

### 3.3 Censoring 감시·진단값·epoch

- **Censoring 감시(prereg §4 병행 의무)**: `cancel_ratio = 0/(57+0) = 0%` — 역치 15% 미만,
  **편향 경고 없음**. 취소 중앙 큐 대기: 취소 0건 → 산출 불가(n/a). 취소 런 별도 등록: 해당 없음(0건).
- **진단값(prereg §3)**: 57/57 런에서 `run_started_at == created_at` → `latest_attempt_wall =
  official_wall`(전 런), 런 객체 내 큐 대기(run_started−created) = 0초. `attempt_wall`(job interval
  union)은 **미산출** — 런별 `/attempts/{n}/jobs` 순회 생략(진단값이며 공식 지표 아님; 스냅샷 한계로
  명시 — §7 UNKNOWN 목록 참조).
- **Epoch 분리(prereg §5)**: 본 창은 GHEC 복귀 경계(2026-11-01T10:53:18Z) 및 전환 창(~10:53:18Z)
  **이후 전체** — 단일 epoch(ghec 복귀 후), 혼합 없음. 공식 모집단은 원래 epoch를 가르지 않으나,
  이 창은 우연히 단일 epoch다. (대비: 공식 baseline P95 1,988초·n=133, gen12 진단 P95 1,133.4초·n=44,
  GHEC-return 진단 P50 641초·n=18은 **각각 다른 모집단** — 본 스냅샷에서 재계산·병합하지 않았다. prereg §10.)

### 3.4 해석 금지 문구(필수)

**p95 738초는 SLO of record 480초(P95)를 넘는 "최종 판정 아님·480s 초과 관측 상태"다** — 스냅샷 시점의
관측일 뿐이며, 등록 판정이 아니고 n=57·단일 창·단일 epoch 스냅샷이다. 장기 성능 보증으로 해석하지 않는다
(prereg §7 해석 한계). 초과의 원인 판정도 본 문서가 수행하지 않는다(§7).

## 4. Node 24 신세대 census — 동결창 [2026-11-02T08:12:08.926Z, 09:13:00Z] + 창 이후 누적

동결창 명시 쿼리(GET `event=merge_group&created=2026-11-02T08:12:08.926Z..09:13:00Z`) → total_count 16
(= 2 그룹 × 8 워크플로), 그중 admission-gate **정확히 2건** — **창 내 전수 n=2 확정**.
스냅순간 T_snap까지 census 창 [08:12:08.926Z, 10:34:37Z] 전체는 merge_group 런 40건(5 그룹 × 8 워크플로),
그중 admission-gate 5건(창 내 2 + 창 이후 3). 나머지 7개 병행 워크플로(axiom-operational-slice,
bsec-integrity, probe-merge-queue, generation-acceptance, landing-integrity, debt-registry-gate,
observer-manifest-consistency)는 **모집단 외**다(prereg §4 admission-gate 한정).

### 4.1 창 내 (동결창 n=2 — 최종 판정 대상 아님, 코호트 스냅샷)

| run id | run_number | PR | head_sha | 판정 basis (4/4 subject) | 상태·결론 | created → updated | official_wall | latest_attempt_wall | attempt |
|---|---|---|---|---|---|---|---|---|---|
| 41414648142 | 816 | #1214 | 9381cb3a5 | **REUSED** | completed·success | 08:39:20Z → 08:47:52Z | **512초** | 512초 | 1 |
| 41416443711 | 818 | #1215 | 4c19fa9b6 | **EXECUTED** | completed·success | 08:54:19Z → 09:05:06Z | **647초** | 647초 | 1 |

### 4.2 창 이후 누적 (created > 09:13:00Z, ~T_snap) — **사후 창 편입 아닌 별도 표기**

| run id | run_number | PR | head_sha | 판정 basis (4/4 subject) | 상태·결론 | created → updated | official_wall | latest_attempt_wall | attempt |
|---|---|---|---|---|---|---|---|---|---|
| 41420386024 | 821 | #1217 | 0ebe84493 | **EXECUTED** | completed·success | 09:24:30Z → 09:36:18Z | 708초 | 708초 | 1 |
| 41421620938 | 823 | #1218 (배치, batch head 8d6dbf6b8) | 8d6dbf6b8 | **REUSED** | completed·success | 09:33:20Z → 09:42:08Z | 528초 | 528초 | 1 |
| 41422458822 | 824 | #1216 (배치, head a241012ed) | a241012ed | **EXECUTED** | completed·success | 09:39:30Z → 09:51:41Z | 731초 | 731초 | 1 |

**편입 금지 명시**: 창 후 3런(#821·#823·#824)은 동결창 [08:12:08.926Z, 09:13:00Z]의 코호트·모집단
어디에도 **편입하지 않는다** — prereg §7 "창 외 관측의 사후 편입 금지" 준수. 별도 표기일 뿐이다.

### 4.3 basis 판정 아티팩트 (GET /runs/{id}/artifacts → 소형 zip GET 다운로드, /tmp만 사용)

- 아티팩트 구성(런당): `admission-verdict-<sha>-1`(~1.1–1.2KB), `judgment-record-<sha>-1`(~9.2–11.6KB),
  `go-judgment-lane-{0,1}`, `admission-check-<sha>-1`, `evidence-record-<sha>-1` + 대형 캐시류(다운로드 생략).
- basis 필드는 **`judgment-record-<sha>-1`** 안 per-subject 레코드에 존재. 관측 결과(전부 4 subject 일괄):
  #816 REUSED / #818 EXECUTED / #821 EXECUTED / #823 REUSED / #824 EXECUTED.
- 의미 대응(계약 외 참고 정의): closure re-derivation + executionEpoch + per-read re-hash all passed →
  REUSED / no record for the current closure (fresh judgment) → EXECUTED.
- `admission-verdict-*`는 전부 `mergeGo/GO`·`qualification NORMAL`(착지 허용 판정) — basis 필드는 미포함.

### 4.4 큐 wall — **계약 미정의**

- prereg에는 queue-only wall 독립 산출식이 없다(§2 official_wall이 큐 대기 포함이 전부;
  §4의 `run_started_at − created_at`은 취소 런 censoring 진단 전용). → **별도 큐 wall 수치를 산출하지 않는다.**
- 관측 사실: census 5런 전부 `run_started_at == created_at`(런 객체 내 큐 대기 0초).

## 5. 불일치 기록 (사실 기록만 — 판정에 반영하지 않음)

- **정합 확인**: 배경 문서의 "런 wall 512s(#1214)/647s(#1215)"는 #1166 계약의 official_wall과 일치 ✓.
- **불일치(기록 대상)**: 배경 문서의 "큐 wall 530s(#1214)/565s(#1215)"는 **계약 산출식으로 재현 불가**다.
  created→merged 실측은 **531초(#1214, merged 08:48:11Z)·666초(#1215, merged 09:05:25Z)**이며 —
  #1214는 API second granularity ±1초 내 근사, **#1215는 565초와 불일치** — run 객체 필드의 어떤 조합으로도
  565초는 도출되지 않는다(§8 merged_at 관측 명령).
- **처리**: 본 항은 **사실 기록만** 한다 — 판정·모집단·기준·해석에 반영하지 않는다(prereg §10 소급 수정 금지).
  565초의 산출 근거는 **UNKNOWN**이며 추측하지 않는다(prereg §8 규율).

## 6. 모집단 분리 선언 (혼입 없음)

| 모집단 | 본 스냅샷에서의 지위 |
|---|---|
| ① 공식 SLO 모집단 (§3, n=57, 창 [착지, T_snap]) | **유일하게 계산한 판정 대상 모집단** — R-7 p50/p95 산출. 단, "판정 대상 모집단"의 계산이지 **판정 선언이 아니다**(§9) |
| ② Node 24 신세대 코호트 (§4, 창 내 n=2 + 창 이후 n=3) | census 전용 뷰. ①과 동일 run 5건이 포함되지만 **관점 구분 표기**이지 별도 모집단 병합 아님. 코호트 단독 백분위는 산출하지 않음(n 미달·표본 생성 금지) |
| ③ 역사 모집단 (baseline P95 1,988초·n=133 / gen12 P95 1,133.4초·n=44 / GHEC-return 진단 P50 641초·n=18) | **관측·재계산·병합 0건** — prereg §10 소급 금지 준수, 원 수치 인용만 |
| ④ provider·epoch 진단층 (prereg §5) | 본 창은 단일 epoch(ghec 복귀 후)라 층 분리 불요. 병행 계산 안 함 |

## 7. 측정 사실 vs 원인 판정 분리 — UNKNOWN 명시

- 본 문서가 등록하는 것은 전부 **측정 사실**이다: 런 객체 타임스탬프(created/started/updated)·conclusion·
  run_attempt·head_branch·merged_at의 GET 관측값과 그 정수 초 차이.
- **원인 판정은 수행하지 않는다.** "왜 이 wall인가"(러너 배정·동시성 제한·의존성 대기·문서 자체 성격 등의
  귀속)는 prereg §8이 정한 규율을 따른다 — 잡 `started_at − created_at`은 혼합값이고 API로 구분 불가하므로
  **UNKNOWN으로 기록하는 것이 정답**이며, 근거 없는 추측은 금지다. 본 스냅샷은 원인 귀속 시도 자체를 하지
  않음으로써 이 규율을 준수한다. p95 738초 > 480s 초과의 원인 판정도 하지 않는다 — "초과 관측 상태"까지만
  등록한다.
- **UNKNOWN 목록**:

| 항목 | 상태 | 사유 |
|---|---|---|
| `attempt_wall`(57런 job interval union) | **UNKNOWN(미산출)** | `/attempts/{n}/jobs` 순회 생략 — 진단값이며 공식 지표 아님; 스냅샷 한계로 명시 |
| queue-only wall | **계약 미정의** | prereg에 독립 산출식 없음(§2·§4) — 본 스냅샷은 산출하지 않음(§4.4) |
| 런 객체 내 큐 대기(run_started−created) | 관측값 **0초**(57/57) — 귀속 대상 없음 | 대기 자체가 관측되지 않아 원인 귀속 문제가 발생하지 않음 |
| 배경 "큐 wall 530s/565s"의 산출 근거 | **UNKNOWN(재현 불가)** | §5 — 계약 필드 조합으로 도출 불가, 추측 금지 |
| 480s 초과의 원인 | **UNKNOWN** | 원인 판정 미수행(본 절) — 관측 상태만 등록 |

## 8. 재현 명령 전부 (GET-only, 2026-11-02T10:34–10:45Z 실행)

```bash
# 계약 원문/차량
gh issue view 1166 --repo Archright/Axiom
gh api repos/Archright/Axiom/issues/1166 --jq '{title,state,created_at,updated_at,comments_count:.comments}'
gh api repos/Archright/Axiom/issues/1166/comments            # → [] (0건)
gh api repos/Archright/Axiom/pulls/1166 --jq '{merged_at,merge_commit_sha}'
# 동결 원문: docs/evidence/slo_official_measurement_prereg_2026-11-01.md (로컬 clone read-only)

# 공식 모집단 열거 (§9: 6h 창 분할, 창당 total_count ≪ 1000)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-01T13:35:30Z..2026-11-01T19:35:30Z&per_page=100" --jq '{total_count, admission_gate: [.workflow_runs[] | select(.name=="admission-gate") | {id,status,conclusion,created_at,updated_at,run_started_at,run_attempt,head_branch}]}'
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-01T19:35:30Z..2026-11-02T01:35:30Z&per_page=100" --paginate --jq '[.workflow_runs[] | select(.name=="admission-gate")] | length'   # → 15
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-01T19:35:30Z..2026-11-02T01:35:30Z&per_page=100" --paginate --jq '[.workflow_runs[] | select(.name=="admission-gate") | {id,conclusion,created_at,updated_at,run_started_at,run_attempt,head_branch}]'
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-02T01:35:30Z..2026-11-02T07:35:30Z&per_page=100" --paginate --jq '[.workflow_runs[] | select(.name=="admission-gate") | {id,conclusion,created_at,updated_at,run_started_at,run_attempt,head_branch}]'  # → 26
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-02T07:35:30Z..2026-11-02T10:34:37Z&per_page=100" --jq '{total_count, admission_gate: [.workflow_runs[] | select(.name=="admission-gate") | {id,conclusion,created_at,updated_at,run_started_at,run_attempt,head_branch}]}'
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-01T13:35:28Z..2026-11-01T13:35:30Z&per_page=100" --jq '.total_count'   # → 0 (창 시작 갭 확인)

# Q16 경계·전수 대상 단일 GET 교차검증 (6건)
for id in 41312498886 41414648142 41416443711 41420386024 41421620938 41422458822; do \
  gh api repos/Archright/Axiom/actions/runs/$id --jq '{id,run_number,name,status,conclusion,created_at,run_started_at,updated_at,run_attempt}'; done

# census (동결창 명시 쿼리 + 창 내 전체 워크플로)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-02T08:12:08.926Z..2026-11-02T09:13:00Z&per_page=100" --paginate --jq '{total_count, admission_gate: [.workflow_runs[] | select(.name=="admission-gate") | {id,run_number,conclusion,created_at,updated_at,run_started_at,head_branch}]}'
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-02T08:12:08.926Z..2026-11-02T10:34:37Z&per_page=100" --paginate --jq '[.workflow_runs[] | {id,name,conclusion,created_at,updated_at}]'

# 판정 basis 아티팩트 (목록 GET → 소형 zip GET, /tmp 외 쓰기 없음)
gh api "repos/Archright/Axiom/actions/runs/<run_id>/artifacts?per_page=100" --jq '[.artifacts[] | {id,name,size_in_bytes,expired}]'
gh api repos/Archright/Axiom/actions/artifacts/<artifact_id>/zip > /tmp/slo_snap_art/<alias>.zip
unzip -p /tmp/slo_snap_art/jr_<runnum>.zip | grep -o '"basis":"[A-Z]*"' | sort | uniq -c
# artifact id: #816 judgment-record=13127705895, #818=13127224700, #821=13130511091, #823=13130626280, #824=13131785028

# 큐 wall 정합성 확인용 (계약 산출식 아님 — merged_at 사실 관측)
for pr in 1214 1215 1216 1217 1218; do gh api repos/Archright/Axiom/pulls/$pr --jq '{pr:.number,merged_at}'; done

# R-7 백분위 (§6 동결 코드 그대로) + dedupe/censoring 검사
python3 /tmp/slo_snap_calc.py   # percentile_r7(sorted_walls, 50)=584.0, (…,95)=738.0
```

원시 증거 파일(/tmp): `slo_snap_calc.py`(57런 전수 데이터·R-7 계산), `slo_snap_art/`(아티팩트 zip 10개).
(/tmp 파일은 세션 로컬 원시 증거다 — §3.2에 57개 정렬 표본 전체가 수록돼 있어 prereg §6 동결 코드로의
R-7 재산출은 본 문서 자체만으로 가능하다: p50 = sorted[28] = 584, p95 = 737 + 0.2×(742−737) = 738.)

## 9. 공식 판정과의 관계 (본 문서가 아닌 것)

1. **표본 기준 n≥30**: 이미 자연 누적으로 충족 — 창 [착지, T_snap] 내 완료 런 n=57 (약 21시간, ~57건/day).
   그러나 n≥30은 등록 절차상 계산 가능 최소 표본 수이지 **안정적 장기 추정이 아니다**(prereg §7 해석 한계 동결)
   — 더 긴 자연 누적이 안정성을 높인다.
2. **본 스냅샷 = 최종 판정이 아니다.** 최종 판정은 별도 등록 행위다: `slo_judgment_window_prereg_2026-11-02.md`
   (같은 PR 동반 착지)가 **사전등록한 판정 관측 창 [since, until]**에서 **창 종료 후** 산출된다. 본 문서의 창
   [2026-11-01T13:35:28Z, T_snap]은 판정창이 아니며, 스냅샷 값(§3)은 그 판정의 근거로 소비되지 않는다.
3. 판정 시 동반 의무(prereg §3·§7): 보고 필수 동반값 세트(n·측정 구간·p50·p95·최소·최대) + 진단 2값·
   `run_attempt` 병기 — 단, `attempt_wall`은 본 스냅샷에서 job union 미순회로 미산출이므로 판정 보고에서는
   산출 필요(스냅샷 한계 해소). censoring 병행 보고(스냅샷 시점 cancel_ratio 0% — 경고 없음).
4. 스냅샷 값 p95 738초는 SLO of record 480초 대비 초과 **관측 상태**이나, 판정 선언·달성 주장 어느 쪽도 아니다.

---

*본 문서는 상태 스냅샷(진단)이다 — 최종 판정이 아니며 #1166 동결 계약을 변경하지 않는다. 공식 판정은
`slo_judgment_window_prereg_2026-11-02.md`가 사전등록한 창의 종료 후에만 산출된다. 본 문서의 수치는
모두 §8 명령(GET-only)으로 재현 가능하다.*
