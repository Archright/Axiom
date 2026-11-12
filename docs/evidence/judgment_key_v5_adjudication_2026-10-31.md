# v5 판정 CAS 재사용 — 측정 판정 기록 (2026-10-31)

> **Status**: MEASURED-ADJUDICATED — 사전등록된 절차(prereg)에 따라 측정을 완결하고 판정을 기록한다.
> 본 기록은 **Reporter**다(재결 2026-10-18 §8-3) — 판정 권위가 아니며 어떤 게이트·required check·병합 권한에도 영향을 주지 않는다.
> **데이터 원장**: `data/ci_optimization/judgment_key_v5_adjudication_2026-10-31.json` (본 문서와 동일 착지).
> **Date**: 2026-10-31T11:45:00Z · **Branch**: `work/v5-adjudication` · **Scope**: 기록 3건 — data JSON 1·evidence 본 문서 1·`docs/spec/gh_run_observation_quirks.md` Q16 1(Q16은 §0.5 Quirk Mandate에 의한 문서화).
> **사후 정정**: 2026-11-01 — 증명된 증거 오독 정정·사후 관측 보정·Q16 상한 문서화·인과 어휘의 상관 재규정(§12). prereg 절차·1차 통계·모집단 수치는 불변이다.

## §0. 권위·상속 (본 판정이 따른 등록 규칙 — 재해석 없음)

| 권위 | 내용 | 위치 |
|---|---|---|
| 1차 판정 규칙(동결) | docs-only REUSED 표본 MG wall **중앙값** vs before-baseline **#925 717s**, n≥5, "감소 없으면 효과 없음 보고(정책 유지는 별도 재결)" | `docs/evidence/mg_reuse_policy_redecision_2026-10-18.md` §4 |
| 실행 절차(사전등록) | 표본 단위·epoch 층화·P95 절차·증거 위생·경계 귀속 — 착지 후 비편집 준수 | `docs/evidence/judgment_key_v5_measurement_prereg_2026-10-31.md` (PR #1145, 9c007db40) |
| SLO of record | Merge Queue wall P95 ≤ 8분(policy) | `docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md`:133-135 |
| 판정 CAS 계약 | 5조건·fail-closed("조회 실패도 MISS다") | `docs/spec/test_judgment_cas_contract.md` §5-§6 |
| 관측 창 | 2026-10-21T16:40:44Z(B2 #1020 병합) ~ 2026-10-31T11:27:31Z(#1146 착지) | prereg §2 |

**관측 모집단(전수)**: 창 내 admission-gate merge_group 런 **130 완료**(성공 117·실패 6·취소 7)·착지 PR 112.
목록 스윕 중 `GET /actions/runs?event=merge_group` 이 실존 런 4건(#1021~#1024)을 누락한 quirk를 발견했고,
단일 런 GET으로 교차확정해 모집단에 포함했다 — **Q16** 참조(`docs/spec/gh_run_observation_quirks.md`).

## §1. 운영 판정 요약 (3분리 — "기능이 존재한다는 이유로 완료 선언하지 않는다")

| 구분 | 판정 | 근거 |
|---|---|---|
| **① 정상 작동** | **오작동 0건** | 21/21 효과 표본 all-REUSED·`no record for the current closure` **0건**·mint 멱등(`MINT_JUDGAPPEND: OK — idempotent no-op, append exactly-once: 0`)·fail-closed 경로(전이 EXECUTED 4건 + C #1021 + #1146) 실증 — 재사용·거부·멱등 전부 계약 부합 |
| **② 실제 성능** | **1차: 감소 없음(+139s) · 2차: epoch 내 −162~−276s** | 1차(동결 규칙): 표본 중앙값 856.0s vs 717s → 절대 wall은 provider epoch 교란이 지배. 2차(prereg §3.c): 동일 epoch 내 REUSED vs EXECUTED **비교치가 전 층 같은 방향**(상관 비교 — 사후 정정 §3·§12.3, "재사용 효과 실증" 인과 어휘 철회) |
| **③ SLO** | **미달** | P95(전수 130) **2315.8s**·P95(성공 117) 2012.8s vs SLO 480s(≈4.8×/4.2×). 지배 인자는 semantic EXECUTED tail·provider epoch — 별개 프로그램(§10) |

정책(판정 CAS 재사용)의 유지·확장 여부는 별도 재결 사항이다 — 본 기록은 관측만 보고한다.

## §2. 1차 판정 (동결 규칙 그대로 — 권위: 10-18 재결 §4)

- **표본**: docs-only·N-제외·PR-최종 착지 런·4주체 REUSED·success — **n=21**(사전등록 기대 n≥5 충족; §4 표).
- **중앙값(wall₁)**: **856.0s** vs before-baseline **717s** → **+139s — 감소 없음**.
- **판독 기준(prereg §4 고정)**: 감소분이 관측 표본 분산(±100-200s)을 초과해야 감소 — 감소가 아니므로 **효과 없음 보고**.
- **교란 공개(정직 의무)**: before-baseline #925는 **GHEC 시대** 값이고, 표본 창은 ghec→failover(공급자 장애 조치 혼잡, 1798-2241s 밴드 3표본)→gen12(Ubicloud)를 가로지른다. 사전등록 §3이 **등록·예견한 교란**이며, 1차 지표가 이를 반영하지 못하는 것이 규칙상 결과다. ghec 시대 REUSED 참조값(#1025 518s·#1046 529s·#1047 506s·#1032 458s)은 v4 밴드(401-550s)에 부합한다.

## §3. 2차 — epoch 내 대조 (prereg §3.c — 사후 정정 2026-11-01: "confound-controlled" 철회, 상관 비교로 재규정)

| epoch | REUSED 중앙값(n) | EXECUTED 중앙값(n) | **Δ(재사용 절감 추정)** |
|---|---|---|---|
| ghec | 821.0 (4) | 1097.0 (29) | **−276.0s** |
| failover | 962.0 (7) | 1231.0 (29) | **−269.0s** |
| gen12 | 840.5 (10) | 1002.5 (16) | **−162.0s** |
| pre-gen12 합산 | 902.0 (11) | 1158.5 (58) | **−256.5s** |

- **사후 정정(2026-11-01)**: epoch 층별 REUSED vs EXECUTED **비교치는 전 층에서 같은 방향**이다(−162~−276s). Δ는 상관 비교값이지 인과 효과의 입증이 아니며(공급자 혼합·클로저 규모 교란 — §12.3; 기존 "재사용 효과가 존재한다" 인과 어휘 철회), 1차 판정 규칙을 대체하지 않는다.
- **동일 클래스 비교**: docs-only EXECUTED(전이 4건, §8) 중앙값 1045.0s — 동일 클래스 비교에서도 REUSED(856.0s)가 낮다(비교치; "교란 배제" 주장은 사후 정정으로 철회 — n=4 비교는 통제된 추정이 아니다).
- **post-fold 관측**: #1128 fold 분리(10-31 03:41 착지) 이후 gen12 REUSED 699→612s(#1144→#1145) — 추가 ~150-200s 개선은 fold 분리 슬라이스 기여로 맥락 기록한다(본 측정과 별개 슬라이스).
- **EXECUTED 대조군 확정치**: n=74·중앙값 1115.5s(선행 손계산 71/1113과의 차이 원인은 §9 — 기계값 권위).
- **사후 정정(2026-11-01)**: epoch 버킷은 prereg §3.b의 **created_at 시간 분류이지 공급자 실측이 아니다** — 'ghec' 버킷 표본 #1059·#1065·#1067(런 39946342302·39985134369·39989958441)은 jobs API 잡 메타데이터 직접 확인 결과 전 잡 `ubicloud-standard-2` 라벨·`gr*` 러너·group `Default`로 **실측 Ubicloud**였다. prereg 분류·층화 수치는 변경하지 않으며, 이에 따라 본 층화 지표는 **공급자 혼합값**으로 동일 공급자 내 효과·인과 효과의 입증이 아니다(§12.3).

## §4. 효과 표본 21 (전수 — 기계 재유도·독립 재계산과 21/21 일치)

| # | PR | MG 런 | 착지 창(created→updated) | wall₁(=wall₂) | epoch | D3(s) | merge commit | s1a 레코드 | 절감 vs 717 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1025 | 39675531001 | 10-21 21:02:51→21:11:29 | 518 | ghec | 844 | b65b28b32 | c2b11f2f7369 | **+199** |
| 2 | 1059 | 39946342302 | 10-23 11:28:41→11:43:43 | 902 | ghec | 1998 | 749e4cbd6 | 2f8cabf15b8f | −185 |
| 3 | 1065 | 39985134369 | 10-23 16:14:34→16:29:41 | 907 | ghec | 1459 | 89cf99d31 | 96793f8f3ab0 | −190 |
| 4 | 1067 | 39989958441 | 10-23 16:49:25→17:01:45 | 740 | ghec | 1257 | 7ebf8aa54 | 96793f8f3ab0 | −23 |
| 5 | 1081 | 40079379320 | 10-24 08:46:57→08:58:48 | 711 | failover | 1208 | 7505facb4 | a5eede731ed2 | **+6** |
| 6 | 1087 | 40097072886 | 10-24 13:11:33→13:25:17 | 824 | failover | 1124 | cf630fa7e | aea14320792a | −107 |
| 7 | 1091 | 40100253953 | 10-24 13:55:55→14:07:56 | 721 | failover | 2387 | 5ca1f6c89 | 10989b623319 | −4 |
| 8 | 1092 | 40101054190 | 10-24 14:06:54→14:22:56 | 962 | failover | 3010 | 72454c853 | 10989b623319 | −245 |
| 9 | 1110 | 40471512329 | 10-27 08:09:03→08:41:55 | 1972 | failover | 8445 | 8f445d25d | 4063d1ae9beb | −1255 |
| 10 | 1118 | 40853901193 | 10-29 09:59:08→10:29:06 | 1798 | failover | 4591 | 644fb9a22 | e4b6f595b9c1 | −1081 |
| 11 | 1119 | 40869901205 | 10-29 12:01:27→12:38:48 | 2241 | failover | 6639 | de9c9e2de | e4b6f595b9c1 | −1524 |
| 12 | 1122 | 41036811489 | 10-30 09:54:21→10:10:29 | 968 | gen12 | 1413 | 8ac1cd114 | 6a7a051537fd | −251 |
| 13 | 1131 | 41070398329 | 10-30 14:16:21→14:32:04 | 943 | gen12 | 2242 | efa771dab | aa53e3c87abd | −226 |
| 14 | 1132 | 41074587078 | 10-30 14:46:20→15:00:36 | 856 | gen12 | 3335 | 53e49e113 | aa53e3c87abd | −139 |
| 15 | 1133 | 41154020696 | 10-31 01:10:28→01:27:23 | 1015 | gen12 | 1418 | 297e854ac¹ | aa53e3c87abd | −298 |
| 16 | 1134 | 41154291783 | 10-31 01:13:36→01:27:00 | 804 | gen12 | 1196 | 297e854ac¹ | aa53e3c87abd | −87 |
| 17 | 1135 | 41155460769 | 10-31 01:27:47→01:43:03 | 916 | gen12 | 2034 | 6da875ac0 | aa53e3c87abd | −199 |
| 18 | 1136 | 41155410447 | 10-31 01:27:07→01:40:17 | 790 | gen12 | 1714 | f188e2f9b | aa53e3c87abd | −73 |
| 19 | 1137 | 41156509649 | 10-31 01:40:52→01:54:37 | 825 | gen12 | 1523 | e2666e10c | aa53e3c87abd | −108 |
| 20 | 1144 | 41184705309 | 10-31 08:27:49→08:39:28 | 699 | gen12 | 18305² | 1d94d5040 | 7fe9623ad931 | **+18** |
| 21 | 1145 | 41193592538 | 10-31 10:38:42→10:48:54 | 612 | gen12 | 998 | 9c007db40 | 7fe9623ad931 | **+105** |

¹ 동일 merge commit(2-부모 배치 병합). ² 핀 회전 재도크 대기 포함. #1145는 사전선언 차량(prereg §8).
절감 양수 4/21(#1025·#1145·#1144·#1081) — 전체 원값은 JSON `savings` 참조.
4주체 basis는 lane0+lane1 잡 로그 마커 원문으로만 확정했다(prereg §2 — 역추적 보간 금지). lane1 3주체의 개별 레코드 ID는 미관측(재현 명령으로 확보 가능).

## §5. B/C 수용 귀속 (prereg §1 — 요약)

- **B(동일 closure REUSED)**: PR #1020 "B2"(런 39635671834, wall 485s) — 4주체 `REUSED — record … re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)`.
- **C(변경 closure 거부)**: PR #1021(런 39639158902, wall 1131s) — `EXECUTED — no record for the current closure (fresh judgment)` + `exec-record[s1a] verdict=PASS basis=EXECUTED`.
- **정직 부정**: 최초 B 차량 #1016은 중간 semantic #1015로 EXECUTED 착지(정상 fail-closed) — #1019(v5.1)가 신기록 발화 후 B2가 형식 완결. 전문은 prereg §1.

## §6. P95·SLO 위치 (해석 한계 고정 — prereg §6)

| 집단 | n | P50 | P90 | P95 |
|---|---|---|---|---|
| 창 내 완료 런 **전수** | 130 | 1086.0 | 2012.4 | **2315.8** |
| 성공 런 한정 | 117 | 1058.0 | 1729.6 | **2012.8** |
| REUSED 표본 | 21 | 856.0 | — | **미산출(N<30)** — RESID-09 어휘 |

- **SLO of record(480s) 미달** — 전수 P95 ≈ 4.8×, 성공 한정 ≈ 4.2×. REUSED 표본만 보면 중앙값 856s·최대 2241s로 여전히 원거리다.
- **지배 인자**: semantic EXECUTED tail(성공 최대 2951s·실패 2862s) + failover epoch 밴드 + 취소 런 큐 대기(#1113 3886s). provider epoch 안정화·serial-tail은 **별개 프로그램**(mg folding prereg :11-12 분리 원칙)이다.
- **해석 한계(고정)**: n=130은 등록 절차상 계산 가능 최소(N≥30) 충족이지 안정적 장기 추정이 아니다 — 본 P95를 장기 성능 보증으로 해석하지 않는다. 측정 구간 10일(2026-10-21~31)이 provider 세대 전환을 가로질러 P95는 세대 혼합값이다.

## §7. 세대 타임라인 (s1a 주체 기준 — 창 내 21종 관측 + #1146 신규 발행)

관측된 s1a 레코드 세대(reusedBy — 전체 원값은 JSON `recordGenerations`):

```
c2b11f2f7369[1025] → 101058650ba1[1032] → e537af3f60e3[1046,1047] → 397658cf26c8[1055]
→ 2f8cabf15b8f[1059,1060] → 9a97f36ba37f[1063] → 96793f8f3ab0[1065,1066,1067,1068]
→ d9f17b77a2b3[1070] → 8355deedfa8f[1076] → a5eede731ed2[1077,1081] → aea14320792a[1087]
→ 10989b623319[1091,1092] → 4af0ed46d2b7[1094×2] → 8501ad4dd39d[1106] → 4063d1ae9beb[1110]
→ c2a6a7608748[1113×3,1114×5] → e4b6f595b9c1[1117×2,1118,1119] → 6a7a051537fd[1122]
→ aa53e3c87abd[1131,1132×2,1133~1137] → 0baec2116a41[1142] → 7fe9623ad931[1144×3,1145]
→ 7f58908b6d59[1146]
```

- 세대 귀속은 재사용 **마커 원문(관측)** + 타임라인 추론의 조합이다(v4 interim generation2 정직 표기 계승). 직접 관측된 mint 근거: `7fe9623ad931` ← #1128 착지 런·원장 커밋 e54016ab3(prereg §3.d), #1145 mint no-op 원문, #1146 mint-publish success.
- **사후 정정(2026-11-01)**: #1146의 key(12자리 표기)는 착지 당시 미관측이었으나 사후 관측으로 `7f58908b6d59`(mint job 124524533029, 11:26:40.051Z append exactly-once: 1)로 확정해 위 타임라인에 반영했다(§12.4). `0baec2116a41`(12자리 표기)의 최초 관측 append도 #1138~#1141 시퀀스가 아닌 **병렬 #1125 재도크 런 41159685724의 mint(02:40:35.463Z, append exactly-once: 1)**에서다 — 세대 귀속으로서는 유력 설명이며 12자리 접두사 기준이다(§12.2).
- 최장 재사용 스트릭: c2a6a7608748 8런(10-27~10-28), aa53e3c87abd 9런(10-30~31).
- **REUSED 빈도**: 최종 착지 112 중 all-REUSED 38(21 docs-only + 17 code-or-mixed — 클로저 외부 파일 변경에서도 재사용, v4 #933 선례 동일 구조) = 33.9%. docs-incl-spec(클로저 멤버 docs) 착지는 관측 범위 내 전부 EXECUTED(#1088·#1146).

## §8. 경계 관측 (증거 격리 — PR+런 ID 귀속, JSON `boundaryCandidates` 전문)

1. **전이 docs-only EXECUTED 4건**: #1080(1236s)·#1089(1075s)·#1139(976s)·#1141(1015s) — 전부 `EXECUTED — no record for the current closure (fresh judgment)` ×4주체. #1080/#1089/#1139는 직전 semantic 착지(#1079·#1088·#1138)의 **런 진행 중** 착지로 CAS 조회~mint 발행 경합 타임라인과 정합. **[2026-11-01 사후 정정 — §12.1·§12.2]** #1141의 원인에 대한 유력 설명이 확보됐다: 동일 12자리 key `0baec2116a41`의 최초 관측 append는 병렬 #1125 재도크 런 41159685724의 mint(job 124418276357, 02:40:35.463Z append exactly-once: 1)였고 #1141의 lane0 조회(job 124417566244, 02:38:02.747Z no-record)는 그 **154초 선행** — 원장 부재가 실재했다는 순서 경합 설명이 원문 증거와 정합한다(자체 mint job 124420553967은 02:51:03.099Z idempotent no-op). 12자리 접두사 충돌 배제·원장 전수 검증은 수행하지 않아 원인 확정은 아니며, 기존 "원인 미완결" 표기는 유력 설명 확보로 갱신되고 잔여 후보(mint 원장 가시성 지연·speculative stacking Q2)는 기각이 아니라 우선순위가 낮아진 것이다. 또한 기존에 인용된 `MINT_PUB: OK — append raced/failed but reconciliation (A) holds`(job 124524533029)는 **스크립트 원문이지 실행 출력이 아니다**(실제 출력 11:26:28.104Z `first issuance, append 1` — #1146은 신규 클로저의 정상 첫 발행) — "경합이 실재하는 운영 모드임을 직접 입증" 문장을 철회한다. 어느 경로든 **계약상 fail-closed·sound — false REUSED 0**는 변함없다.
2. **#1132**: 1차 실패(1040s — attest manifest 무음 소멸 fail-closed) 후 재도크 착지(856s, 표본 #14).
3. **#1144**: 핀 회전 재도크 2건(825s·579s — org ruleset SHA-exact) 후 최종 착지(699s, 표본 #20). D3 18305s에 대기 포함.
4. **#1113**: 취소 런 wall₁ 3886s vs wall₂ 1185s(큐 대기 ~45분) — **창 내 wall₁≠wall₂ 유일례**(prereg §4 공개 의무: 두 정의 차이는 유의하지 않음).
5. **실패 6·취소 7**: JSON `boundaryCandidates`에 런 ID·wall 전부 기록. #1107·#1109는 exec-record 마커 미발화(no-exec-record)로 조기 실패.
6. **#1146**: 사용자(Owner) 직접 생성 "B셀" 세대 전진 차량(docs/agents/logging.md — 클로저 멤버) — EXECUTED 772s 착지·mint-publish success. 창 종료 마지막 착지. **효과 표본 아님.**
7. **관측 quirk(Q16)**: runs 목록 event 필터가 실존 런 4건 누락 — `docs/spec/gh_run_observation_quirks.md` Q16으로 문서화(헌법 §0.5 Quirk Mandate).

## §9. 통계 방법·독립 검증 (2차 비판 ①②③ 수용의 실행 증거)

- **방법**: 백분위 Hyndman–Fan R-7(idx=1+(n−1)p·선형 보간). 중앙값·P50/P90/P95·D3 전부 기계 계산(손계산 아님). wall₁(1차 정의)과 wall₂(병행 정의)를 함께 산출 — 차이 >60s는 1/130(취소 #1113)뿐.
- **독립 검증(백그라운드 병렬 서브에이전트)**: 사전등록 규칙을 독립 재판독해 전 수치 재계산 — 표본 21/21·중앙값 5종·P95(129런 스냅샷) 2322.60·절감 4건·API 대조 5런(불일치 0)·**D3 21건 전부 +0s** 수렴. #1146 완료(11:27:15Z) 전 스냅샷에서 수렴했고, #1146 추가분(772s EXECUTED)은 본 세션 기계 재계산으로 반영했다.
- **차이 해소**: 선행 손계산 EXECUTED 71건/1113s → 기계 74건/1115.5s(최종). 원인 2건 — #1021(손계산 모집단 누락)과 #1109 재도크(손계산 불일치 제외 — 유사 사례 #1107은 포함돼 있었음). 규칙 문자대로 전부 포함한 기계값을 권위로 채택했다.

## §10. 후속 레버 (별도 재결 권고 — 본 기록은 Reporter, 임계 조정·실행 없음)

P95 미달의 지배 인자는 재사용이 아니다 — 재사용 표본은 epoch 내 −162~−276s의 비교 우위와 공존한다(상관 비교 — §3 사후 정정). 남은 병목(별개 프로그램):

1. **provider epoch 안정화** — gen12(Ubicloud) P50 ~1058-1086s로 수렴 중; failover 밴드 제거가 P95 최대 감쇄원.
2. **serial-tail** — mg folding prereg :11-12 분리 원칙에 따라 별개 슬라이스.
3. **mint 가시성 창** — 전이 EXECUTED 4건(연속 착지 시 조회~mint 경합)의 완화(예: 조회 재시도 창)는 별도 재결 후보.
4. **지속 관측** — gen12 REUSED 612-699s(post-fold)의 안정성 추적과 REUSED 부분집합 N≥30 도달 시 P95 산출(RESID-09 어휘).

## §11. 재현 (GET-only — 원장 JSON `reproduction` 전문)

```bash
# 모집단 스윕 — [2026-11-01 사후 정정, Q16] 목록 엔드포인트는 필터 검색당 최대 1,000 결과이고
# 상한 초과 시 초과 page가 {'total_count':0,'workflow_runs':[]} 빈 응답으로 끝나 --paginate가 완결로 오판한다.
# 재현 절차: (1) created 타임스탬프 창으로 분할해 각 질의 total_count < 1000이 되도록 한다(=1000이면 상한 포화 가능 — 더 세분화)
#   (실측 예: 2026-10-21T00:00:00Z..2026-10-25T00:00:00Z → total_count 704, 전 건 회수)
# (2) 창 간 결과를 run id로 중복 제거해 합산한다
# (3) 경계 4런(39639158902·39657167861·39661104154·39672117787) 등 누락이 의심되는 런은
#   gh api repos/Archright/Axiom/actions/runs/{id} 단일 GET으로 개별 검증한다.
# --paginate 정상 종료를 전수 완결의 근거로 쓰지 않는다.
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-10-21T00:00:00Z..2026-10-25T00:00:00Z&per_page=100" --paginate \
  --jq '.workflow_runs[] | select(.name=="admission-gate") | [.id,.created_at,.run_started_at,.updated_at,.conclusion] | @tsv'
# 잡·마커(Q3 — ANSI 이스케이프 취급)
gh api "repos/Archright/Axiom/actions/runs/{run_id}/jobs" --jq '.jobs[] | [.id,.name,.conclusion] | @tsv'
gh api --allow-escape-sequences "repos/Archright/Axiom/actions/jobs/{job_id}/logs" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -E "AXIOM_JUDGMENT_CAS|basis=|no record|go-exec|MINT_JUDGAPPEND|MINT_PUB"
# PR 메타(D3·merge commit)
gh api repos/Archright/Axiom/pulls/{N} --jq '[.created_at,.merged_at,.merge_commit_sha]'
```

## §12. 사후 정정 기록 (2026-11-01 — GET-only 직접 검증)

> 본 섹션은 2026-10-31 판정 기록의 **증명된 증거 오독**만 정정하고 사후 관측을 관측 시점을 명기해 공개한다. prereg 절차·1차 판정(856.0s vs 717s)·모집단(완료 130·성공 117·착지 112)·P95(2315.8/2012.8s)·표본 21·epoch 층화 수치는 **변경 없다**. JSON 대응 필드는 `postHocCorrections.corrections[0..4]`다.

1. **#1146 mint 로그 오독 정정(서술 철회)** — 기존 §8·JSON `boundaryCandidates[pr=1141].corroboratingEvidence`·`observations.mintIdempotency`·`recordGenerations`가 인용한 `MINT_PUB: OK — append raced/failed but reconciliation (A) holds`는 mint-publish **job 124524533029 로그에서 2026-10-31T11:26:23.837Z의 스텝 스크립트 원문**(echo, 인수 `$commit_meta` 미전개)이며 실행 출력이 아니다. 실제 출력은 **11:26:28.1045741Z `MINT_PUB: OK — ledger append (first issuance, append 1) with provenance: …`** — #1146은 클로저 신규(docs/agents/logging.md)로 정상 첫 발행이며 경합 조정 분기는 미발화했다. 분기 자체는 `.github/workflows/certificate-mint.yml`의 실재 코드 경로다(ledger-append 실패→재조회 성립 시, certificate-mint.yml:2177-2183). #1146은 애초 신규 closure·비효과 표본으로 기록돼 있으므로 이 정정은 판정 수치에 영향이 없다. "경합이 실재하는 운영 모드임을 직접 입증" 문장을 철회한다 — 경합 조정 경로의 **운영 발화 관측은 본 기록 범위에 없다**.
2. **#1141 원인에 대한 유력 설명(미완결 갱신)** — 기존 §8·JSON `boundaryCandidates[pr=1141].context`의 "단순 동시진행 설명 부족(잔여 후보: mint 원장 가시성 지연·speculative stacking Q2) — 원인 미완결"을 다음의 유력 설명으로 갱신한다(확정 아님): #1141 lane0 조회(job 124417566244)는 2026-10-31T02:38:02.7475082Z `EXECUTED — no record for the current closure`였고, 동일 12자리 key `0baec2116a41`의 최초 관측 append는 **같은 main 트리(gateway_headSha 496c54e5ea9f)에서 병렬 실행 중이던 #1125 재도크 착지 런 41159685724의 mint-publish job 124418276357의 02:40:35.4632535Z `MINT_JUDGAPPEND: OK — judgment record appended (key 0baec2116a41, append exactly-once: 1)`**다. 조회가 그 154초 선행 — 원장 부재가 실재했다는 순서 경합 설명이 원문 증거와 정합한다. 단, 12자리 접두사 충돌 배제와 원장 전수 검증은 수행하지 않아 원인 확정은 아니며, 잔여 후보(mint 원장 가시성 지연·speculative stacking Q2)도 기각이 아니라 우선순위가 낮아진 것이다. #1141 자체 mint(job 124420553967)는 02:51:03.0996622Z `idempotent no-op (judgment key 0baec2116a41 already stored, append exactly-once: 0)`. `recordGenerations`의 0baec2116a41 귀속 표기도 이에 맞춰 정정했다(§7). fail-closed·sound 결론은 변함없다.
3. **epoch 'ghec' 버킷의 공급자 실측 불일치(사후 correction — 분류·통계 불변)** — prereg §3.b의 epoch는 created_at **시간 버킷**이다. jobs API 잡 메타데이터 직접 확인 결과 런 39946342302(#1059)·39985134369(#1065)·39989958441(#1067)의 전 잡은 **labels `ubicloud-standard-2`(일부 `-arm`)·runner_name `gr*`·runner_group_name `Default`** — 실측 공급자는 Ubicloud로 'ghec' 버킷명과 불일치한다. 과거 prereg 분류·epoch 귀속·통계는 **변경하지 않으며**(기록 시점 표기 유지), 이 3건의 실측 공급자를 별도 사후 correction으로 기재한다. 따라서 기존 epoch 층화 지표(§3 표)는 **공급자 혼합값**이며 동일 공급자 내 효과·인과 효과의 입증이 아니다 — Δ(−162~−276s) 해석 시 이 한계가 적용된다(JSON `epochStratification.providerMixPostHocNote` 동일).
4. **#1146 judgment key 사후 관측** — 기존 "#1146 신규 발행 — key 미관측" 표기(§7 타임라인·JSON `recordGenerations`·`boundaryCandidates[pr=1146].note`)를 사후 관측으로 보정한다: **key(12자리 표기) `7f58908b6d59`**, mint-publish job 124524533029 로그 2026-10-31T11:26:40.0512305Z `MINT_JUDGAPPEND: OK — judgment record appended (key 7f58908b6d59, append exactly-once: 1)`. 기록 시점(2026-10-31T11:45:00Z)에는 미관측이었음이 역사 시점으로 명확히 유지된다.
5. **Q16 목록 상한 문서화·reproducer 개정** — GitHub REST 공식 문서("List workflow runs for a repository")는 해당 엔드포인트가 **필터 검색당 최대 1,000 결과**를 반환한다고 명시한다("up to 1,000 results for each search when using the following parameters: actor, branch, check_suite_id, created, event, head_sha, status"). 2026-11-01 직접 재현: `event=merge_group` `--paginate`는 정확히 1,000건 수집 후 `{"total_count":0,"workflow_runs":[]}` 빈 page로 종료(완결 오판); `created=>2026-10-21` 필터에서 total_count 1280 vs 실수집 1000 — **상한은 필터 뒤에 적용**된다. 10-31의 경계 4런 누락(Q16 원 기록)은 이 상한(필터 후 적용)으로 설명 가능한 정합 서명이다 — 다만 당시 목록 응답이 보존되지 않아 과거 누락의 실제 원인은 미확정으로 유지한다. 재현 절차를 **타임스탬프 창 분할(각 질의 total_count < 1000 — =1000은 상한 포화 가능, 더 세분화) → 창 간 run id 중복 제거 → 누락 의심 런 단일 GET 개별 검증**으로 개정했고 `--paginate` 정상 종료를 전수 완결의 근거로 쓰지 않는다(§11·JSON `reproduction.populationSweep` 동일 반영). 실측: 창 `created=2026-10-21T00:00:00Z..2026-10-25T00:00:00Z`(total_count 704)에서 경계 4런 전부 재관측.

검증 원천(전부 GET): `gh api repos/Archright/Axiom/actions/jobs/{124524533029,124418276357,124420553967,124417566244}/logs` · `gh api repos/Archright/Axiom/actions/runs/{39946342302,39985134369,39989958441}/jobs` · docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-repository.
