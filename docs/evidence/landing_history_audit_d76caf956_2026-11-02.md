# d76caf956 착지 이력 기계 증거 감사 — 2026-11-02

> **유형**: 실행 증거(관측·검증 기록). **정본 규범**: `docs/spec/admission-generation.md` §3.2·§4.1·§4.3·§5.4.
> **데이터·스크립트**: `data/promotions/d76caf956-landing-audit/` — 원본 규칙세트 버전 스냅샷 75개(verbatim)·sha256 digest·provenance·감사로그 이벤트 105건·21행 매핑·§5.4 상태 diff·재생산 스크립트.
> **관련**: `agents/main/plans/d76caf956-dossier.md`(d76caf956 진입 트랜잭션 검증) · `docs/evidence/resid22_org_repin_closure_2026-11-02.md`(최종 착지 재핀) · PR #1189(node24 전환 대기).

## 1. 목적·판정 상태

**목적**: 2026-11-02에 제출된 **HOLD 권고**(d76caf956 세대 승격 보류, 사유 "§4.3 이행 증거 미확보")의 사실 기반을 기계 증거로 정밀화하여 인간 아키텍트의 공식 판정 입력을 제공한다.

**판정 상태 기록(권한 정확성)**: HOLD는 **권고이지 채택된 인간 결정이 아니다**. 원문(2026-11-02 대화, `wire.jsonl` msg_01M6D24R86TJXHV82KR8C5WX4Q): "내 권고는 지금은 보류입니다… 권고하는 실행 1. 인간 결정은 보류로 기록합니다" — 공식 채택 선언은 존재하지 않는다. 현재 상태: **HOLD 권고 제출 — 인간 아키텍트 공식 판정 대기**(§9 질문 참조). 본 감사는 권고의 전제("44개 중간 착지 개별 §4.3 이행 증거 미확보")를 다음과 같이 갱신한다: **21착지로 축소 + 재핀 행위·상태의 상당 부분 기계 입증 + 2건 확인 일탈 + rollback 5건 + readback 행위는 부분 문서화.** 위반 단정은 아니며 규범 해석은 인간 판정 사항이다.

## 2. 방법·증거 분류 규칙

GET-only GitHub REST(`gh`, wintrover 인증, org admin read) — 감사 중 변경 호출 0건. **증거 4분리**(통합 서술 금지):

| 분류 | 증명하는 것 | 원천 |
|---|---|---|
| 병합 사실 | native merge 이벤트·SHA·시각 | compare API(first-parent, 2-parent 전수) |
| 재핀 행위 | 행위·주체·시각·before→after 핀 | org 감사로그 `repository_ruleset.update`(action 필드 검증 내장) |
| 상태 | 규칙세트가 특정 버전에 도달한 사실 | 규칙세트 버전 스냅샷(REST `history/{version_id}`의 `state` — bypass_actors 포함 전체 상태; UI 내보내기는 bypass 제외하므로 REST가 우월 원본) |
| readback 행위 | 당시 조회·일치 확인 행위 | `docs/evidence/*.md` 문서만(감사로그·스냅샷은 readback 행위를 입증하지 않음) |

readback 행위 등급: **explicit**(재핀 문서에 readback 결과 명시) / repin_only / prereg_only(사전등록만) / indirect(타 문서 간접) / drift-recorded(드리프트 기록) / absent.
**정정 기록**: PR #228의 등급을 repin_only→**explicit**으로 정정했다(2026-11-02). 근거: `mg_evidence_gate_canary2_2026-10-17.md:20-22`가 readback 결과("정책 필드는 sha 단 하나만 변경 — enforcement·conditions·rules·bypass_actors 바이트 동일")를 명시. mapping.json/tsv에 정정 사유 기록.

## 3. 규범 시행 시점(§4.3)

§4.3(HARD RULE)은 **2026-10-15** 커밋 `3f3d3f86`(문서 탄생)으로 도입 — 감사창 개시(10-16) 전날. repo 전역 pickaxe로 이전 문처 없음. 원문은 `24233738·23943917` 표기 → 10-17 `e2ab7846` 상수만 갱신("재핀 의무 본문은 불변" 명시). 착지 #248(10-23)·#250(10-31) 시점의 시행본 = `e321fbbd`(10-21 main 병합)으로 §4.3 본문이 현행과 byte-identical. **소급 적용 문제 없음 — 규범은 창 전체에 시행 중이었다.** 창 내 실천 기록: `1275d65c`(10-17)가 §4.3 이행을 기록.

## 4. 착지 인벤토리(21착지 + 기준)

compare API `29094836bc...d76caf956`: total_commits=44이나 **first-parent 체인(=HEAD 전진=착지)은 21개 native merge 전수**(2-parent, committer=GitHub, direct push 0건). 나머지 23개는 PR 브랜치 내부 커밋(비착지). 기준: H_new=`29094836bc`(PR #227 merge, 10-16T23:52:42Z). 전체 목록은 `landings.json`.

## 5. 21행 증거 매핑

재핀 Δ는 병합 시각 기준. 양측 재핀은 항상 쌍동(≤2초 차). 상세 열(스냅샷 version ID·before/after·근접 repo-level 이벤트)은 `mapping.json`/`mapping.tsv`.

| PR | merged_at(UTC) | repin 25218071 | repin 23943917 | Δ(252) | readback | 비고 |
|---|---|---|---|---|---|---|
| #227(기준) | 10-16T23:52 | 10-17T00:07 | 10-17T00:07 | +15m | explicit(00:35Z readback) | 창 기준 H_new 재핀 |
| #228 | 10-17T04:18 | 04:54 | 04:54 | +36m | **explicit**(정정) | — |
| #229 | 10-17T10:55 | 10:57 | 10:57 | +1m21s | repin_only | — |
| #230 | 10-18T09:02 | 09:04 | 09:04 | +1m24s | repin_only | — |
| #231 | 10-18T13:29 | 13:31 | 13:31 | +1m53s | explicit | 핀은 #242 재핀까지 지속 |
| #232 | 10-20T09:42 | 09:43 | 09:43 | +75s | prereg_only | **rollback anchor ×5** |
| #233 | 10-20T11:11 | 12:18 | 12:18 | +66m | explicit | ROLLBACK 15:43 |
| #235 | 10-20T16:51 | 16:52 | 16:52 | +97s | absent | ROLLBACK 17:22 |
| #236 | 10-20T17:52 | 17:53 | 17:53 | +65s | absent | ROLLBACK 18:21 — SHA 최종 상태 미생존 |
| #238 | 10-20T17:56 | 17:56 | 17:56 | +43s | absent | ROLLBACK 18:21 — SHA 최종 상태 미생존 |
| #239 | 10-20T18:53 | 18:54 | 18:54 | +52s | absent | ROLLBACK 19:20 |
| #240 | 10-20T19:51 | 20:07 | 20:07 | +15m | absent | ROLLBACK 20:36 |
| #241 | 10-20T21:02 | 21:03 | 21:03 | +46s | absent | rollback 후 유지된 첫 핀 |
| #242 | 10-20T21:42 | 21:46 | 21:46 | +4m | absent | — |
| #243 | 10-20T23:54 | 00:00 | 00:00 | +5m | absent | 섀도 25514358 근접(§7-4) |
| #245 | 10-21T05:47 | 05:48 | 05:48 | +60s | explicit | — |
| #246 | 10-21T12:16 | 12:16 | 12:16 | +4s | explicit | — |
| #247 | 10-21T16:21 | 16:21 | 16:21 | +5s | indirect | — |
| #248 | 10-23T06:12 | **NONE** | 06:30 | — | drift-recorded | **단측 재핀(§7-1)** |
| #249 | 10-29T09:03 | 09:04 | 09:04 | +1m28s | explicit | before-sha가 #248 미진입 입증(§7-1) |
| #250 | 10-31T02:27 | **NONE** | **NONE** | — | absent | **무재핀(§7-2)** |
| #251 | 10-31T07:14 | 07:16 | 07:16 | +2m01s | explicit | d76caf956 진입 — dossier 검증 완료 |

**집계**: 재핀 행위 20/21(감사로그 기계 입증) · 상태 매칭 양측 19/단측 1(#248)/무 1(#250) · readback 행위 explicit 7 + repin_only 2 + prereg_only 1 + indirect 1 + drift-recorded 1 + absent 9.

## 6. §5.4 상태 무변경(사후 기계 검증)

연속 버전 스냅샷 73쌍 필드 diff 결과: **창 내 이벤트는 전부 `workflows[].sha`만 변경** — enforcement(`active`)·conditions·bypass_actors(공집합)·rules 구조 불변. 감사로그도 동일 결론(101 update 전부 workflows rule 변경, 규칙 외 필드 변경 0건). 비-sha 변경 16쌍 = 15 사전기준선(10-09/10-10 enforcement toggle·10-15 ref:main 제거) + **1 창 시작 경로 변경**(10-16T07:17 `admission-gate.yml`→`admission-gate-v2.yml` — H_v2 전환 시대, H_new 이전). 스냅샷 `updated_at`은 KST(+09:00) — 파생 파일은 UTC 환산, 감사로그와 0-2초 일치 검증.

## 7. 관측된 일탈·이상(사실 기록 — 위반 단정 아님, 해석은 §9)

1. **#248 단측 재핀·6일 드리프트**: 23943917만 `bcfc1bbdea`로 재핀(10-23T06:30). 25218071은 #247 핀(`7fffee31`)에 10-29까지 잔존 — **#249 재핀의 before-sha(`7fffee31→58a2c546`)가 #248이 25218071에 진입한 적 없음을 기계 입증**. 당시 문서가 "기존 드리프트"로 기록(`epoch_record_mint_retention_2026-10-29.md:93`). #248 파일 diff: `landing-integrity.yml`+`pin-promotion-gate.yml`(admission-gate-v2.yml 불변).
2. **#250 무재핀(4h47m)**: 양 org ruleset에 이벤트·스냅샷 전무 — `3fcc2b5c80`은 **어느 핀에도 존재하지 않는다**(양측 모두 #249 핀에서 #251 핀으로 점프). 10-31T02:27 병합 → 07:14 #251 재핀까지 핀≠HEAD. #250 파일 diff: `pin-promotion-gate.yml`(+50/−32)만 — pinned 파일 불변. 관측 사실: repo-level ruleset 20303214(merge_queue rule)은 10-31T03:50 갱신.
3. **10-20 rollback 스톰 5회**: 핀이 `22a9a0ed26`(#232 SHA)로 후퇴(15:43·17:22·18:21·19:20·20:36 — 각 양측 2초 차). #233·#235·#236·#238·#239·#240 핀 폐기, **#236·#238 SHA는 최종 상태에 미생존**. `incident_emergency_disable_window_2026-10-20.md`(34회 ruleset 쓰기·enforcement 불변)와 정합 — §4.2 비상창 선례 문단은 10-21 `e321fbbd`로 사후 문서화됨.
4. **섀도 규칙세트 25514358**(`generation-shadow-evaluate`): 10-21T00:00:52 생성(#243 핀)→00:51:36 후퇴(#232 핀)→01:05:19 파괴(64분 수명). §4.3 규정 대상(25218071·23943917) 밖 — 관측 기록만.
5. **창 시작 규칙세트 재생성**: 구 24233738 파괴(10-16T04:51:13)→신규 25218071 생성(04:51:14, 1초 차) — §4.3 상수 갱신(10-17)의 배경.
6. **고아 핀 없음**: 모든 핀 SHA는 착지에 대응(사전창 핀: #224·#225·#226 검증).

## 8. 무결성 판정(분류 — 선언 아님)

| 조건(9항 체크리스트) | 상태 |
|---|---|
| 1. §4.3 적용 단위·규범 해석 | 단위: PR native merge 이벤트(기계 확정 — 21착지 2-parent·direct push 0). **범위 해석('모든 착지'): 인간 판정 대기** |
| 2. 전체 착지 이벤트 목록 | ✓ 확보(21 + 기준 #227) |
| 3. 모든 착지 native merge 증거 | ✓ (compare API 전수) |
| 4. 각 착지 양 Ruleset 재핀 증거 | 20/21 기계 입증 · #248 단측 · #250 부재(관측 사실) |
| 5. 각 착지 양 Ruleset Readback 증거 | 행위: explicit 7(+기준 1)·미기록 13 · **상태(§5.4): 창 내 전수 사후 기계 검증 ✓** — 행위 전수는 미확보 |
| 6. d76caf956 3-way SHA 일치 | ✓ (dossier §4 — blob b9792fc6==TWS==epoch manifest N+7) |
| 7. 최종 양 Ruleset 실제 상태 | ✓ (양측 sha==d76caf956·현 org HEAD==d76caf956, 2026-11-02 관측) |
| 8. 미해결 UNKNOWN·증거 공백 없음 | **✗** — 확인 일탈 2건(#248·#250)·rollback 5건·readback 행위 미기록 다수(UNKNOWN 아닌 확인 사실이나 공백 존재) |
| 9. 인간 아키텍트 명시적 승격 판단 기록 | 대기(§9) |

## 9. 인간 판정 질문(Stage 2 — node24 org 착지 전 창구)

1. **d76caf956 공식 판정**: HOLD 권고를 채택(보류 유지)할 것인가, 승격을 선언할 것인가.
2. **§4.3 '모든 착지' 범위 해석**: 무조건(→ #248·#250은 시행 중인 규범 하의 일탈) vs 세대 전환·pinned-file 변경 착지 한정(→ #248은 landing-integrity 재핀으로 정합하나 25218071 6일 드리프트는 여전 관측 사실, #250은 내용 무해). 소급 적용 문제는 소멸(§3).

## 10. 재현성·보존

- **재생산 스크립트**: `audit_landing_history.sh`(GET-only·창 파라미터화·action 필드 검증 내장·phrase fallback 함정 및 감사로그 1750 req/hr 한계 문서화). 동일 입력 → 동일 21행.
- **원본 보존**: `ruleset_*/versions/*.json`(75개 verbatim)·`digests.sha256`(sha256sum -c 전건 통과)·`provenance.json`(endpoint·질의 시각 2026-11-02T03:14-03:23Z·건수)·`audit_log_ruleset_events.json`(105)·`landings.json`·`compare_raw.json`·`mapping.json/tsv`·`state_diff_report.json`·`filediff_{248,250}.json`.
- 플랫폼 보존(규칙세트 이력 180일·감사로그 180일)과 무관하게 본 PR 보존분이 영구 감사 원본이다.

## 11. 근거·인용

- 정본: `docs/spec/admission-generation.md`(§3.2:77-79·§4.1:95-97·§4.3:114·§5.4:130) · `docs/agents/ci_epoch_cutover.md` §2.5.
- 착지별 readback 문서(11종 grep 검증): `generation_promotion_hnew_2026-10-17.md`·`mg_evidence_gate_canary2_2026-10-17.md`·`lane_fix_operational_verdict_2026-10-18.md`·`mg_reuse_cutover_e2e_2026-10-18.md`·`rotation_allowlist_vs1_preflight_prereg_2026-10-20.md`·`lane_activation_observation_2026-10-20.md`·`ci_generation_repair_2026-10-21.md`·`v5_generation_acceptance_a_2026-10-21.md`·`epoch_record_mint_retention_2026-10-29.md`·`resid22_org_repin_closure_2026-11-02.md`·`incident_emergency_disable_window_2026-10-20.md`.
- 외부(Context7 검증, 2026-11-02): docs.github.com REST — org rulesets(단일-ruleset 연산·PUT 전체 치환·batch/transaction 부재)·ruleset history 180일·`history/{version_id}` state 전체 스냅샷·감사로그 180일·phrase qualifier(`action:`·`created:`)·미지 action fallback은 미문서화.
- 감사 수행: agent-52(데이터 수집·검증), agent-53(§4.3 시행 시점), agent-51(외부 문서), main agent(판정 분류·#228 정정·문서화). 2026-11-02.
