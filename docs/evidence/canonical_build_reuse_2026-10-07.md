# Canonical Build Reuse — Phase 3 acceptance (2026-10-07)

트랙 0/1/2 착지 상태에서의 Phase 3 수용 기록: settlement 리드타임 재측정(T1 방법론) +
Completion Evidence 1–10 통합. 측정 시각 2026-10-07T11:35Z–14:35Z, 전건 GitHub API
관측값(`gh api`, 인증 wintrover) — 로컬 재현 아님을 명시한다.

착지 근거:

| 트랙 | PR | merge commit | 시각(Z) |
|---|---|---|---|
| 0 정책 v65 | #564 | `c35d3519c` | 12:50:48 |
| 1 publisher single-flight | #565 | `250892a6b` | 13:14:44 |
| 2 J3 manifest 앵커링 | #566 | `8d4e6d6dc` | 14:12:59 |

## 1. Settlement 리드타임 재측정 (T1 방법론)

### 방법

- 모집단: 2026-10-07 트랙 착지 전후 병합 PR 전건 = **#561–#567, n=7** (관측 종료
  14:35Z 기준 #568 이후 병합 없음. 타인 소관 포함 전건).
- 분해: `pulls/{n}` created/merged, `issues/{n}/timeline`의
  `added_to_merge_queue`, head sha `commits/{sha}/check-runs`에서 required check
  `admission-check`(aggregate job) 성공 완료 시각, `actions/runs?event=merge_group`
  head_branch `gh-readonly-queue/main/pr-{n}-*` 매칭.
- 정의: **TOT** = open→merged, **S1** = open→checks green(admission-check 성공),
  **S2** = 큐 진입→merged. 단위 분(分).
- 기준선: 동일 방법론 60건 표본 — TOT p50 20.9m, S1 36%, S2 44.5%, 큐 라운드
  7.4m (운영자 제공 T1 값; T1 원문 문서는 저장소·GitHub 검색에서 미확인 —
  §4 잔여 참조).

### 표본 (n=7)

| PR | open | green(S1 끝) | 큐 진입 | merged | TOT | S1 | S1% | S2 | S2% | 푸시→merged | MG 런 | 라운드 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 561 | 11:35:16 | 12:32:33 | 12:34:30 | 12:45:09 | 69.9m | 57.3m | 82.0% | 10.7m | 15.2% | 22.0m | 9.9m | 1 |
| 562 | 11:49:36 | 11:57:02 | 11:57:53 | 12:06:15 | 16.6m | 7.4m | 44.6% | 8.4m | 50.3% | 18.0m | 7.6m | 1 |
| 563 | 12:26:33 | 12:34:36 | 12:36:28 | 12:45:10 | 18.6m | 8.1m | 43.2% | 8.7m | 46.7% | 22.8m | 7.3m | 1 |
| 564 | 12:35:36 | 12:42:28 | 12:43:39 | 12:50:48 | 15.2m | 6.9m | 45.2% | 7.2m | 47.0% | 23.2m | 6.1m | 1 |
| 565 | 12:57:35 | 13:05:38 | 13:06:25 | 13:14:44 | 17.1m | 8.1m | 46.9% | 8.3m | 48.5% | 22.5m | 7.6m | 1 |
| 566 | 13:50:51 | 13:58:20 | 14:04:38 | 14:12:59 | 22.1m | 7.5m | 33.8% | 8.3m | 37.7% | 26.3m | 7.6m | 1 |
| 567 | 14:05:07 | 14:12:58 | 14:13:54 | 14:21:52 | 16.8m | 7.8m | 46.9% | 8.0m | 47.6% | 18.3m | 7.2m | 1 |

merge_group 런은 PR당 정확히 1세트(3 workflow, 전부 attempt 1, 전부 success) —
**재무장(dequeue→re-queue) 0건, 큐 라운드 1.0회/PR, MG 런 실패 0**.

### 통계 vs 기준선

| 지표 | 오늘 (n=7) | 기준선 (60건) | 비고 |
|---|---|---|---|
| TOT p50 (open→merged) | **17.1m** | 20.9m | −3.8m (−18%) |
| TOT p50 (#561 이상치 제외) | 16.9m | 20.9m | −19% |
| S1 절대 p50 | 7.8m | ≈7.5m (36%×20.9) | 평년 수준 |
| S2 절대 p50 | 8.3m | ≈9.3m (44.5%×20.9) | −1.0m |
| 큐 라운드 | **1.0회/PR, 재무장 0** | 7.4m 표기 | 단위 불명(분/회) — 아래 참조 |
| MG 런 길이 p50 | 7.6m | — | 6.1–9.9m 범위 |

정직한 대조:

- **표본 7건 < 10 — 지속 관측 중.** 단일 일·단일 시간대 표본이므로 TOT 개선을
  정책·슬라이스 효과로 귀속하지 않는다.
- #561은 이상치다: open 11:35 후 푸시 12:23(48분 공백, 작성자 지연)로 S1이
  57.3m로 부풀었다. 마지막 푸시→green은 9.4m로 정상 밴드. TOT(push) p50
  22.5m가 이를 교차 확인한다.
- S1·큐 절대 시간은 평년과 동일; 오늘의 TOT 개선분은 재무장 0회와 S2 −1m에서
  나왔다. publisher single-flight은 J3상 **가속 전용**이며 required-check 경로에
  없으므로 본 TOT 변화의 원인으로 주장하지 않는다.
- "큐 라운드 7.4m"의 단위가 분인지 회수인지 기준선 원문 미확인으로 판별 불가 —
  오늘 값(분 독립 시 8.3m, 회수 독립 시 1.0회) 둘 다 기록해 둔다.

## 2. publisher / B-빌드 운영 집계 (Phase 1 정의 발화)

Phase 1 착지(13:14:44Z) 이후 신규 정의로 발화한 `ci-cache-publisher` 런 4건 —
job step 결론 + verdict 로그 마커 원문으로 집계:

| 발화 | run | 트리거 | lane lookup | lane save | base lookup | base save |
|---|---|---|---|---|---|---|
| 13:58:23 | 37632810483 | #566 PR 게이트 | MISS | **저장** `axiom-b-0137e86b…` | MISS | 저장 `axiom-b-b812fa7f…` |
| 14:12:35 | 37634780905 | #566 MG 게이트 | HIT | 보류 `[publish-skip] lane key exists` | HIT | 보류 |
| 14:13:01 | 37634839812 | #567 PR 게이트 | guard-skip¹ | skip | HIT | 보류 `[publish-skip] base key exists` |
| 14:21:29 | 37636009894 | #567 MG 게이트 | MISS | **저장** `axiom-b-5441db28…` | HIT | 보류 (14:23:04Z 마커) |

¹ `tree(build_sha)=2cdc7ab8… ≠ tree(head_sha)=f928c038… — content identity not
landable as tested (R6)` — 트리 불일치 가드가 레인 저장을 거절(base 도메인은
단일화 유지).

- **"Unable to reserve cache" 0/4** (신규 정의 4발화 전체; 로그 grep 카운트 0).
  대조군: 구 정의 마지막 발화 run 37626934032(13:14:23Z)에서 1건 재현 — 원문:
  `Failed to save: Unable to reserve cache with key axiom-b-82853a6d…, another
  job may be creating this cache.` → 결함 소멸 + 대조 확정.
- **동일 트리 중복 cold 0**: 트리 `0137e86b`(=#566) cold 1회(#566 PR 게이트) →
  MG는 HIT 회수, 트리 `5441db28`(=#567 MG 큐 트리) cold 1회(#567 MG 게이트) —
  각 트리 cold 최대 1회.
- **MG 게이트 base-B 복원 2/2 웜**: #566 MG가 `axiom-b-b812fa7f…` 복원,
  #567 MG가 `axiom-b-0137e86b…` 복원(각 `attest/build-base-artifacts` 로그).
  이전 사이클 lane 저장이 다음 사이클 base로 흐르는 크로스 사이클 씨딩 관측.
- **웜 밴드**: #566 MG `attest/admission-check` 14:09:17→14:10:54 = 97s
  (기록 밴드 86–102s 상단), #567 MG 14:18:37→14:19:41 = 64s.
- MISS fallback: #566 PR 게이트 B MISS → cold 빌드 후 전 체크 green(#566 기록),
  #567 MG lane MISS → cold 빌드 → green + 발화가 저장(자기 보정).
- 관측된 한계(정직 기록): #567처럼 PR 실행과 큐 진입 사이에 base가 이동하면 lane
  트리가 달라져 PR 게이트의 lane 씨딩이 MG에 상속되지 않는다(가드가 정확히
  거절) — 단일화·무중복은 유지되지만 PR→MG 웜 핸드오프는 base 미이동일 때만
  성립한다.

## 3. Completion Evidence 1–10 통합

| # | 항목 | 명령/관측 경로 | 실측 | 기대 일치 |
|---|---|---|---|---|
| 1 | 발화 2회 → 저장 시도 1회 | publisher runs 37632810483→37634780905 | cycle B: 저장 1회(lane, 13:58:59Z) + 후속 HIT 보류(14:14:44Z 마커) | ✅ |
| 2 | reserve 실패 0건 | 신규 정의 4발화 로그 grep | 0건; 대조군(구 정의 37626934032) 1건 | ✅ |
| 3 | 후속 런 B HIT 웜 | #566 MG `attest/admission-check` 14:09:17→14:10:54 | 97s (밴드 86–102s) | ✅ |
| 4 | 동일 트리 중복 cold 0 | MG/PR 게이트 B 키 로그 | 트리당 cold ≤1회 (`0137e86b` 1회, `5441db28` 1회) | ✅ |
| 5 | MISS→저장/cold fallback | #566 PR 게이트 MISS→cold→green, #567 MG MISS→cold→green+저장 | fallback 정상, red 0 | ✅ |
| 6 | 파손 3종+동시 오염 13/13 감지 | `tests/ci/test_b_cache_anchor` (PR #566 기록, head `f7bc4410f`) | 13/13 `[OK]`, cold fallback 폐기 | ✅ (착지 PR 실측 기록 인용) |
| 7 | S5 exit 2→0 | `bin/tcb_judgments --judgment cache-manifest` (PR #566 기록) | `J3_EXIT=0` PASS | ✅ (〃) |
| 8 | HIT=공급 재사용, 판정 재계산 | `ci-compile` ×2 반복 (PR #566 기록) | 4종 매 실행 재컴파일, "up to date" 스킵 0 (96s/91s) | ✅ (〃) |
| 9 | G7 PASS + digest ×2 동일 | `verify-contract-release-e2e-full`, `ax report --canonical-digest` ×2 (PR #566 기록) | G7 pass, `80e5ad25…c3196` ×2 일치 | ✅ (〃) |
| 10 | settlement p50 대비 | 본 문서 §1 (n=7 전건 재측정) | TOT p50 **17.1m** vs 기준선 20.9m (−18%), 재무장 0 | ✅ (표본 미달 — 지속 관측 중) |

#6–9는 본 세션에서 재실행하지 않았다 — merge된 PR #566 본문의 실측 기록(측정
트리 = merge head `f7bc4410f` = 착지물)을 출처로 인용하며, 본 세션의 신규
기여는 #1–5·10의 착지 후 재관측이다.

## 4. 잔여 (blind spot / follow-up)

1. **표본 n=7 < 10**: TOT 개선(−18%)은 단일 일 표본 — 10건 누적 시 재판정
   (지속 관측 중).
2. **T1 기준선 원문 미확인**: 60건 표본 문서가 저장소·GitHub 검색에서 미발견 —
   기준선 수치는 운영자 제공값으로 인용. 원문 확정 시 "큐 라운드 7.4m" 단위
   판별 필요.
3. **PR→MG 웜 핸드오프의 base 이동 한계** (§2 관측된 한계): lane identity가
   트리 exact라 base 이동 시 MG lane이 cold — 개선 여지는 별도 슬라이스 소관.
4. **S1의 작성자 지연 민감도**: #561처럼 open 후 지연 푸시는 S1을 부풀림 —
   TOT(push) 병기가 방법론상 필요.
5. **#6–9 미재실행**: 착지 PR 기록 인용 — 본 세션 범위 밖(로컬 main clone
   mutation 금지). 필요 시 worktree 재현으로 별도 관측.
6. **Evidence 10의 인과 금지**: publisher는 required-check 경로 밖(J3 가속
   전용) — TOT 변화 원인 주장 불가.
