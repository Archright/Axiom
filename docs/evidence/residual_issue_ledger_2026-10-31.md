# 잔여 이슈 장부 (Residual Issue Ledger) — 2026-10-31

> **종류**: 잔여 이슈 종결 장부 — Round-4 반박 검증(6개 수정)과 5개 조사 workstream(agent-80/81/82/83/84)의 수렴 결과를 항목별 상태 모델로 귀속한다. 본 문서는 관측·판정 기록이며 코드·워크플로·게이트·판정 의미론을 변경하지 않는다(§0.12).
> **권위**: 각 행의 `evidence_ref`가 가리키는 실측 문서·런·커밋·API 관측이 그 행의 근거다. 본 문서는 Reporter다 — 문서의 병합 성공(L4)과 문서 안 주장의 진실성은 별개이며, 후자는 `evidence_ref`가 입증한다(Authority ≠ Adapter, AGENTS.md §2.3).
> **상태 모델 (2-필드)**: `work_state` = INVESTIGATING / READY / EXECUTING / OBSERVING / CLOSED (작업 진행), `disposition` = RESOLVED / ACCEPTED / DEFERRED / BLOCKED (최종 종결).
> **귀속 규칙**: (a) CLOSED 행은 정확히 하나의 disposition을 갖는다. (b) 진행 중인 행은 "진행 계정(in-flight)" 섹션에 두며, 완료 후 갱신 커밋으로 종결 부여 — 이때만 "미분류 0"이 성립한다. NOT_ADOPTED/DORMANT/DECISION_REQUIRED 등은 disposition이 아니라 `detail` 세부 상태다(NOT_ADOPTED·DORMANT는 유지·수용된 상태이므로 ACCEPTED, DECISION_REQUIRED는 결정권자 대기이므로 BLOCKED).
> **판정 시점**: 갱신 1차 — 2026-10-31T03:45Z (KST 12:45) + 보강 03:58Z. v91 착지·C5-B 검증·VS-B epoch 재개·LCOM 구조 수리·#1143 L4 확정·#1125/#1128 소유자 병합 및 L4 확정 반영 — 진행 계정 0, 4상태 귀속 확정. 갱신 2차 — 2026-11-01 (PR-2): RESID-13 선언 기대 반증 + GHEC 복귀 수리·전이로 종결(DEFERRED→RESOLVED 이동). 남은 소유자 종속 항목은 #1128 org re-pin(인간 조치) — RESID-22 참조. 갱신 3차 — 2026-11-02: RESID-22 re-pin readback 확인(①② 완료) + ③ 사전등록 관측 **기준 미충족**(mean +64.5s<120s·p95 악화)으로 OBSERVING 유지 + side-pin 최신성 신규 항목 RESID-23 추가(진행 계정 — operator 소유). 갱신 4차 — 2026-11-02: RESID-23 조사 완결(INVESTIGATING→READY — 결정 요청서 정본화, 권고 ① 재핀 — operator 판정 대기, 값 갱신 미수행).

---

## 1. 집계 (갱신 7차 — 2026-11-02, RESID-23 operator 판정 수령·재핀 착지 종결)

| disposition | 항목 | 수 |
|---|---|---|
| RESOLVED | RESID-01, 03, 04, 06, 07a, 07b, 08a, 13, 14, 18, 19, 20, 21, 23 | 14 |
| ACCEPTED | RESID-15, 16, 17 | 3 |
| DEFERRED | RESID-05, 09, 22 | 3 |
| BLOCKED | RESID-02, 08b, 10, 11, 12 | 5 |

총 25행(갱신 3차에서 RESID-23 신규 1행 추가 — Round-4 분모 밖 신규 발견) — 25행 disposition 귀속 완료(미분류 0)·진행 계정 0(갱신 7차 — RESID-23 CLOSED/RESOLVED 전환). 갱신 1차(03:45Z) + 보강(03:58Z — #1125 종결·#1128 병합·L4 확정 반영) + 갱신 2차(2026-11-01 PR-2 — RESID-13 반증·종결) + 갱신 3차(2026-11-02) + 갱신 4차(2026-11-02 — RESID-23 조사 완결) + 갱신 5차(2026-11-02 — RESID-22 ADR-0040 정본화) + 갱신 6차(2026-11-02 — RESID-22 옵션 A 수령·재평가 종결) + 갱신 7차(2026-11-02 — RESID-23 재핀 착지·종결)의 재집계. (DEFERRED 행의 work_state는 READY/OBSERVING일 수 있음 — 종결 판정은 disposition 기준, RESID-05 채택 대기·RESID-09 표본은 next_trigger에 명시 — RESID-22 ③ 재평가는 갱신 6차 옵션 A 수령으로 종결됐다.)

## 2. 항목 원장

### RESID-01 — merge queue 1차 시도 실패 (MG 런 41070945674)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1133 (merge `297e854ac`) · `docs/evidence/merge_queue_first_attempt_failure_2026-10-31.md` (186행, main 실재 확인) · 2차 MG 런 41074587078 success |
| verified_at | 2026-10-31T01:30Z |
| next_trigger | 재발 시(무음 다운로드 종료 패턴) 본 문서 §5 가설 체크리스트 재적용 |
| status_owner | Axiom (관측 기록) |
| 핵심 | 근본 원인 = 소비 잡(`attest/admission-check`)의 41.4 MB 아티팩트 다운로드가 완료 시퀀스(digest·4줄) 없이 소멸 → `manifest.txt` 부재 → `admission-check.yml:927` fail-closed exit 1. 온전성 역증명 3건(verdict 잡 동일 ID·digest 완전 다운로드, v4 불변성, 같은 sa13 엔드포인트 소형 2건 성공). 2차 시도가 동일 입력으로 성공(15:01:02Z 병합) → 일시성 결함 확정. **UNKNOWN**: 다운로드 프로세스 소멸의 직접 사인(OOM·크래시·러너 개입)은 러너 내부 진단 접근 불가 — 확정하지 않는다. |

### RESID-02 — rearm 자동화가 수동 재등록을 감지 못함 (class=UNKNOWN→no-arm)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / BLOCKED** (detail: DECISION_REQUIRED) |
| evidence_ref | PR #1133 §rearm — 14:46:02Z 재등록 actor `wintrover`(수동), rearm 자동화 런 41173248120 `class=UNKNOWN, action=no-arm` · rearm 앵커 전환 권고 |
| verified_at | 2026-10-31T01:30Z |
| next_trigger | 사용자의 rearm 앵커 전환 승인 (권고: 수동 재등록을 rearm 앵커 신호로 승격) 또는 현행 유지 결정 |
| status_owner | 사용자 (정책 결정) |
| 핵심 | 14:46:02Z 재등록은 인간 수동이며 rearm 자동화는 이를 class=UNKNOWN으로 판정해 no-arm. 앵커 전환은 신뢰 계약 변경(자동 판정 확장)이므로 에이전트가 자율 채택하지 않는다. |

### RESID-03 — ci-cache-publisher cancelled 24건의 취소 주체

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1135 (merge `6da875ac0`, 2026-10-31T01:43:20Z 병합 확정) · `docs/evidence/cache_publisher_cancellation_forensics_2026-10-31.md` (314행) |
| verified_at | 2026-10-31T01:43Z (병합 확정) |
| next_trigger | 없음 (원인 확정) |
| status_owner | Axiom (관측 기록) |
| 핵심 | 취소 주체 = **GitHub 플랫폼의 concurrency 그룹 pending 축출 기본 동작**. 2026-10-30 창(11:11:39Z–12:15:21Z) census 159런 = cancelled 43 · skipped 105 · success 11. 4-SHA 24/24 cancelled 전건 "다음 런 도착 ≤3초 내 취소" 상관 — 잡 0건, 로그 22바이트 빈 zip. 근거: `ci-cache-publisher.yml:185-187` (single-flight group + `cancel-in-progress: false` + queue 미선언) → GitHub 공식 문서 "By default, any existing pending job or workflow in the same concurrency group will be canceled". **"dedupe" 가설 기각, 미해명 0건.** UNKNOWN: canceller 필드 부재 → 수동 개입 배제는 시간 인과 추론만. VS-A 문서 정정 2건(잡 총량 skipped 98+success 8; `head_sha`는 기본 브랜치 HEAD 배정이지 원런 상속 아님) 포함 반영. |

### RESID-04 — C_out SAT→cvConfirmed 미발화 (VS-2 PR-4 parity)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1134 (merge `297e854ac`) · `docs/evidence/cout_lane_parity_investigation_2026-10-31.md` (164행, main 실재 확인) |
| verified_at | 2026-10-31T01:30Z |
| next_trigger | 없음 (경로 의미 축 판정 완료) |
| status_owner | Axiom (관측 기록) |
| 핵심 | SAT→cvConfirmed 5단계 사슬(`counterexample_validator.nim:144-193`가 makeDisproved 유일 호출부). PR #1130 parity 미발화 = **설계된 dispatch 셰도잉** (sidecar precedence 10 > C_out 20, `axiom_engine.nim:2308-2313`/`:5412-5424`) + subject-identity fail-closed. **경로 의미 축 갭 없음** — 양 분기 실측(클린 트리 14-record BUG_FOUND 골든 재현, 더티 트리 강등 분기 26/26). 잔여는 관측성 갭만(RESID-05). |

### RESID-05 — C_out 관측성 갭 (실행 중 parity 상태 관측)

| 필드 | 값 |
|---|---|
| work_state / disposition | **READY / DEFERRED** |
| evidence_ref | PR #1134 관측성 갭 섹션 (구현 없음 권고) |
| verified_at | 2026-10-31T01:30Z |
| next_trigger | 관측성 개선 채택 결정 시 별도 PR (제품 계약 정당화 필요, §0.12) |
| status_owner | 사용자 (채택 결정) |
| 핵심 | 런타임에 sidecar/C_out dispatch 선택을 관측할 표면 부재 — 권고만 존재, 채택 전 구현하지 않는다. |

### RESID-06 — repository_surface 정책 PR 착지 경로 (v90 이전 전체)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1137 (merge `e2666e10c`, 2026-10-31T01:54:42Z 병합 확정) · 정책 포렌식 문서 · 텔레메트리 `~/.cache/axiom/push-admissibility/log.jsonl` · org audit-log(admin:org 스코프) |
| verified_at | 2026-10-31T01:55Z (병합 확정) |
| next_trigger | 없음 (경로 실증 완료) |
| status_owner | Axiom (관측 기록) |
| 핵심 | 99개 정책 커밋 전수 매핑. **세 정책 PR(v90=#1116, v89=#1064, v86=#1045) 전부 merge queue 경유 GitHub 네이티브 MERGE로 착지** — v91 서버 측 커밋 경로에 대한 Round-4 우려를 반박하지 않고 **실증**한다. v86/v89 push FAIL은 push-admissibility 텔레메트리 실측(1473e7449/bec8270ea). **`BYPASS-PUSH-PRE-RECORD`는 저장소에 존재하지 않는 문자열**(`git log -S --all` 0건) — 외부 실행기 세션이 Owner Decision #18(c) 근거로 직접 기록한 것. 5건 "DIRECT" 분류는 분류 버그로 재매핑 완료. `protected_branch.policy_override` 2건 관측. repository-surface check가 failure여도 병합됨(advisory 확인 — 병합 권위는 ruleset required 5종 + merge queue). |

### RESID-07a — LCOM 0.6017 (check-arch) 원인 규명

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1136 (merge `f188e2f9b`, 2026-10-31T01:40:49Z 병합 확정) · 사전 존재 메트릭 드리프트 포렌식 문서 |
| verified_at | 2026-10-31T01:43Z (병합 확정) |
| next_trigger | 없음 (원인 확정) — 수리는 RESID-07b |
| status_owner | Axiom (관측 기록) |
| 핵심 | LCOM 0.6→0.6017316 = 커밋 `52feb9354`(2026-10-25, perf)가 `lean_kernel_boundary.nim`에 `measuredBinaryDigest` proc를 추가해 대상 21→22함수, 앵커 시점 정확히 경계(84/210=0.6)→92/231. 측정 도구·정책(policy 10-20 이후) 무변경 → **순수 코드 구조 문제(실제 퇴행), baseline 낡음 아님** — baseline 재앵커 경로 기각. 임계값 0.6은 정책값으로 불변. |

### RESID-07b — LCOM 구조 수리 (lean_kernel_boundary.nim)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1143 MERGED `3ae3736a` (03:29:41Z, 2커밋: `33d5e9e05` 구조 수리 본체 + `e845a48ac` TWS rotation 881→882멤버, 핀 회전 도구 `reanchor_pin --ref HEAD --write` + dry-run no-drift OK) · LCOM 실측: **0.6017316 → 0.578947** (139/231, 22함수 → 110/190, 20함수, TCC 0.421 > 0.3) · 측정 프로브가 게이트 경로(extractModuleFactsV4 + computeCohesion)와 일치 교차검증 · L4 OBSERVED_SUCCESS (main push run 41164600467, attempt 1, verdict=PASS, tier=dual-verified, artifact 13029096388, binary.sha256 `613a2e50`) |
| verified_at | 2026-10-31T03:45Z (PR 병합·L4는 갱신 이력에 기록) |
| next_trigger | 없음 (임계 복귀 완료) — nimtry 기존 경고 22건 잔류는 RESID-08a 후속 실측 참조 |
| status_owner | Axiom (실행 완료) — baseline 변경과 별도 PR 분리 원칙 준수 |
| 핵심 | 포렌식 §5.2의 "IO 헬퍼 모듈 분리" 경로 채택 — `measuredFileDigest` + `measuredBinaryDigest` + `BinaryDigestMemo`/threadvar를 신규 모듈 `src/verification/obligation/measured_digests.nim`로 **순수 이동** (본문·시그니처 무변경, 내부 전용 proc — 외부 호출부 0건). 행위 보존 입증: bundle_digest_test 5/5, test_capture_toolchain_fingerprint 5/5, test_evidence_truth_boundary OK, `bin/ax` 전체 빌드 성공. 임계값 0.6·측정기·게이트 로직·baseline 전부 무변경, `[lcom_overrides]` 미사용(FROZEN 면제 경로 회피). 경로 class: `src/verification/**` = PRODUCT (surface 사전 확인 통과 — FROZEN 아님). 부수 효과: nimtry 게이트 LCOM error 1건 → 0건 (RESID-08a 참조). |

### RESID-08a — nimtry DRIFT (projection 2 vs 15) 원인 규명

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1136 · `tools/nimtry/nimtry_cli.nim:473-480` · `data/nimtry_baseline.json` BUDGET#004 이력 |
| verified_at | 2026-10-31T01:43Z (병합 대기 중, 조사는 완결) |
| next_trigger | 없음 (원인 확정) — 수리는 RESID-08b |
| status_owner | Axiom (관측 기록) |
| 핵심 | DRIFT 표시 불일치(projection 2 vs ledger 15) 메커니즘 = `nimtry_cli.nim:473-482`에서 신규 **ERROR가 있으면 경고 출력을 무시하고 return** — 실제 신규 위반 **23건(1 ERROR + 22 warning, `--diff-baseline` 실측)** 중 ERROR 1건만 보여 projection=2. ledger 15는 `data/debt_ledger.json` BUDGET#004의 10-24 `1f82b8d68` sync-budget 값(registry 46→47 동시 갱신 = 표준 안무, `lastVerifiedAt` 동결은 `tools/debt_engine.nim:1579` 도구 사양). DRIFT의 직접 원인은 baseline 낡음 단독이 아니다 — 표시 마스킹·budget 이력·실제 신규 23건의 조합. **UNKNOWN 3건**(agent-83 문서 §6.3): 15 기록 경로의 간접 확증, 경고 22건 개별 유입 커밋 범위 밖, 마스킹 사양 문서 미발견. **후속 실측 (03:45Z)**: RESID-07b LCOM 구조 수리(PR #1143) 후 nimtry 게이트 **ERROR 0건** 실측 — LCOM ERROR 1건 소멸 확인. 경고 22건 잔류 = 10-21 앵커 이후 기존 부채(신규 아님) — 표시 수리(RESID-08b) 후 정확 카운트 노출 예정. |

### RESID-08b — nimtry 표시 계층 수리 (ERROR-가림 + projection 카운트)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / BLOCKED** (detail: POLICY_DECISION_REQUIRED v92) |
| evidence_ref | agent-92 실행 실측: 수리 대상 `src/gate/nimtry/nimtry_cli.nim`이 `src/gate/**` FROZEN glob에 흡수 — surface_guard 기계 판정 **FAIL / SURFACE_FORBIDDEN** (푸시 게이트 차단). 수리 내용 확정: 경고를 ERROR와 함께 보고 + projection 카운트 정정 (판정·baseline 무변경 — 표시 계층만) |
| verified_at | 2026-10-31T03:45Z |
| next_trigger | v92 정책 PR(TCB `src/gate/**` FROZEN→CONTROLLED 재등록) 인간 아키텍트 승인 시 즉시 진행 — 기존 계획에 없던 신규 경로로 본 갱신에서 BLOCKED 귀속 |
| status_owner | 사용자 / 인간 아키텍트 (v92 TCB 신뢰 표면 결정) — §-1 에이전트 수정 제한 준수 |
| 핵심 | v90/v91 어느 정책으로도 허용 경로 없음(기계 판정 실측) — 우회 금지, v92 정책 개정이 유일한 정식 경로. LCOM ERROR는 RESID-07b 수리로 소멸(RESID-08a 후속 실측)하여 재앵커 상호의존성 해소 — 남은 작업은 표시 계층만. RESID-08a 경고 22건·projection 정확 카운트는 v92 승인 후 노출. |

### RESID-09 — CI p50/p95 측정 일반화

| 필드 | 값 |
|---|---|
| work_state / disposition | **OBSERVING / DEFERRED** |
| evidence_ref | PR #1131 (merge `efa771da`) · `docs/evidence/ci_three_venue_decomposition_2026-10-30.md` (VS-A) — 3-venue 분해, 잡별 wait/exec |
| verified_at | 2026-10-31T01:43Z |
| next_trigger | 표본 충분 시점(집단별 N≥30 목표)에 집단별 p50/p95 보고 — 그 전은 잠정·미산출 |
| status_owner | Axiom (관측 — 기존 도구만, 신규 측정 인프라 없음) |
| 핵심 | 현재 표본 **N=2 (PR 2건, 하루 74분) — 사례 관측치**로 p50/p95를 주장하지 않는다. 측정 계약: wait = `started_at - created_at` (**GitHub pre-start wait**로 명명 — Ubicloud 프로비저닝 단독이 아님, GitHub 스케줄링·러너 할당 포함), exec = `completed_at - started_at`. 집단 분리: PR/MG/push × provider × 잡 종류 × `run_attempt`. 표본 2의 p95는 최대 관측값에 수렴 — 안정적 백분위 주장 금지. Ubicloud 내부 프로비저닝 단계는 GitHub REST로 분해 불가 — 별도 텔레메트리 없는 한 미관측으로 둔다. |

### RESID-10 — Northflank 청구액 확인

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / BLOCKED** |
| evidence_ref | API 403 관측 기록 (경로 접근 불가) |
| verified_at | 2026-10-31T01:43Z |
| next_trigger | 계정 소유자 콘솔 확인 — 실제 청구액·기간 기록 |
| status_owner | 외부 계정 소유자 (사용자) |
| 핵심 | API 403은 경로 접근 거부이지 청구액 0이 아니다. 실제 상태는 콘솔 소유자만 확인 가능 — 코드로 해결 불가. |

### RESID-11 — OVH 공인 IP 4개

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / BLOCKED** |
| evidence_ref | PROVIDER_POLICY ovh 행 제거(PR #1127, merge `a9b4dca68` — 입력 스키마 거절 fail-closed) |
| verified_at | 2026-10-31T01:43Z |
| next_trigger | 계정 권한자 콘솔 확인 — IP 4개 존재·연결 리소스·과금 확인, 미사용 시 해제 승인 |
| status_owner | 외부 계정 소유자 (사용자) |
| 핵심 | IP 존재·연결·과금은 콘솔에서만 확인 가능. 미사용 확인 전 해제 금지. |

### RESID-12 — GitHub App 4879411 권한 분리

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / BLOCKED** |
| evidence_ref | org installations 6종 관측 기록 |
| verified_at | 2026-10-31T01:43Z |
| next_trigger | 조직 관리자 결정 — Action→Required Permission→Owner 정리 후 최소권한 분리 승인 |
| status_owner | GitHub 조직 관리자 |
| 핵심 | 권한 분리 결정은 조직 관리자 권한. 운영 기능이 깨지지 않는 범위에서 미사용 권한 제거. |

### RESID-13 — GHEC 시험창 (2026-11-01~03 UTC)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** (갱신 2차 — 2026-11-01, PR-2) |
| evidence_ref | 최초 등록: cron(id 01M67R3FKT7A7B7DTHN2BANQZ4 `17 9,21 1-3 11 *` + one-shot 01M67R3FKWQAZZZDYYXJG8VC22) · 관측 출력 `tmp/ghec_window_observation_2026-11.md` · CI_RUNNER_MAP gen-12 → 종결: `docs/evidence/ci_provider_canary_fix_epoch_2026-11-01.md`(반증 기록 — §"결함"·§"RESID-13 충돌 해소") · `docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md`(수리 후 force_trial 전이·수용 증거 세트) |
| verified_at | 2026-10-31T01:43Z (관측 등록) · 2026-11-01T09:36Z (반증·전이 관측, GitHub-clock) |
| next_trigger | 없음 (관측 종결 — 12월 자동 폴백 경로의 무인 확인은 별개 운영 항목이며 이 행의 종결 조건이 아님) |
| status_owner | Axiom (관측 기록) |
| 핵심 | 선언된 기대("GHEC 차단 유지 → canary 0-step 실패 → Ubicloud 유지")는 11-01 01:36:46Z 첫 시험에서 **반증**: GHEC는 가용이었고(잡이 실제 GitHub-hosted 러너에 배정·실행 — runner_id=1000035432, runner_group_id=0, steps=3, 01:36:58→01:37:02Z) 실패 원인은 쿼터가 아니라 검증 술어 결함(jq labels 인덱싱, Q16). 창 내 대기 시 잔여 자동 재시도(11/2·11/3)가 같은 결정론적 결함으로 시도 2/3·3/3을 소진해 복귀를 12월로 밀어내므로 잔여 관측 가치 0 — 반증된 전제 기록 + 수리(PR #1160, native MERGE `0ba17ad36`) + force_trial 전이(generation 15, `GHEC_TRIAL_SUCCESS`, canary run 41289547761 success)로 종결. 관측 계약("관측만 수행") 위반이 아니라, 관측 결과가 전제를 반증해 계약의 목적(창 소진 전 판정)을 달성한 것이다. |

### RESID-14 — CI_RUNNER_MAP `last_trial_result=failed` 해석

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | 직접 재검증: `last_trial_run_id=40072684018` (gh API 확인) · last_trial_at=2026-10-24T07:04:09Z · gen-12 BOOTSTRAP 2026-10-30T07:46:09Z · 5종 required 잡 Ubicloud JIT 러너(`gr*`) success 관측 |
| verified_at | 2026-10-31 (R4-5 완료) |
| next_trigger | 없음 (해석 확정) |
| status_owner | Axiom (관측 기록) |
| 핵심 | failed는 **10-24 시험 잔류값**(GHEC 예산 0-step) — gen-12 BOOTSTRAP가 last_trial_* 필드를 보존(에포크 문서 §2.3 계약). Ubicloud 실사용은 5종 required 전부 성공으로 입증. Ubicloud 전환 실패가 아님 — 과장 해석 방지. **UNKNOWN**: BOOTSTRAP 쓰기 주체. |

### RESID-15 — closure-watcher GARM 참조

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / ACCEPTED** (detail: DORMANT) |
| evidence_ref | GARM 제거 기록 + 참조 도달 불가 분석 |
| verified_at | 2026-10-31T01:43Z |
| next_trigger | 향후 .github 표면 개정 기회에 정리 (FROZEN 해제 시) |
| status_owner | Axiom (상태 유지) |
| 핵심 | 제거된 인프라에 대한 잔존 참조 — 도달 불가. FROZEN 상태에서 코드 정리만을 위해 신뢰 표면을 열 이유 없음. |

### RESID-16 — Ubicloud 지출 상한 미설정

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / ACCEPTED** |
| evidence_ref | 사용자 방향 결정 (상한 두지 않음) — 명시적 위험 수용 |
| verified_at | 2026-10-31T01:43Z |
| next_trigger | 청구 기준 도달 또는 월간 운영비 검토 시 재판단 |
| status_owner | 사용자 (수용) |
| 핵심 | 미완성 구현이 아니라 명시적 위험 수용. 재검토 트리거만 유지. |

### RESID-17 — C5 (a)/(c) 명제 (정준성·uint64 상위 결함 영역)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / ACCEPTED** (detail: NOT_ADOPTED) |
| evidence_ref | PR #1129 (merge `9b87ce7ca`) · `docs/spec/` C5 3명제 제안 문서 |
| verified_at | 2026-10-31T01:43Z |
| next_trigger | 사용자가 명제 의미 채택 + SpecID 표현 계약 확장(각각 별도 승인) 시에만 진행 |
| status_owner | 사용자 (채택 권한 — 2중: 명제 의미 + 문법 확장) |
| 핵심 | 명제 의미 결정(채택 권한)과 canonicalSpecIR·오버레이 문법의 uint64 표현 능력 확장(설계 권한)은 별개 승인. 채택 전까지 Axiom 구현에 영향 0. 제안서 해시만 존재 — SpecID로 호칭하지 않는다. |

### RESID-18 — C5-B 명제 채택 + ax prove (종결)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1138 MERGED `8e79d8d58` — L3 TERMINAL_SUCCESS + L4 OBSERVED_SUCCESS (run 41158879080, dual-verified). 채택 hash-bound: SpecID `ddf7eca1151d672f963b04716c4772940e5e59b69045428b5385151d764f0607` 재계산 일치 · subject pin=verified · adoption registry entries=7 · d1/d2 콜드런 byte-identical |
| verified_at | 2026-10-31T03:45Z |
| next_trigger | 없음 (종결) — 단 **ax prove 판정은 UNKNOWN**(WP4-e canonical refusal, exit 2, 인증서 0건)로 정직 기록: 증명 성공이 아니라 판정 불능. 어댑터 후속은 별도 계정 |
| status_owner | Axiom (실행) / 사용자 (채택 승인 근거: 계획 승인 Option A + "전면 허가" — RESID-20 v91 승인과 **별도 기록**) |
| 핵심 | C5-B-BASELINE 63비트 값 왕복 보증 채택·실행·증거 종결. **판정 UNKNOWN = 파이프라인이 명제를 판정하지 못했다는 정직한 결과** — 성공으로 주장하지 않는다(§0.9 극장 금지 준수). 이 검증이 원래 C5 결함(2^63 ≤ v < 2^64) 해결이 아님 명시 유지 — C5-HIGH-UINT64/C5-CANONICALITY는 RESID-17 NOT_ADOPTED. |

### RESID-19 — VS-B PR 이벤트 진단 테스트 실행 (종결)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1142 MERGED `ece9a599b` (03:02:24Z). §2.5 ⑦ **PR 이벤트 진단 실행 success**: `tests-ci-unit-diagnostic` 42s — run 41161039287, event=pull_request, head `3ac4bddf4`, runner `grh64ytv5t…`, job 124418429800 · ⑧ ruleset 20303214 required 5종 불변 실측 (admission-check, bsec-integrity, debt-registry-gate, generation-acceptance, axiom-operational-slice) · ⑨ L4 OBSERVED_SUCCESS (run 41162604443, verdict=PASS, tier=dual-verified). 복원: frozen ref `work/vs-b-pending-epoch`(96ce298bc) blob `1c79e811` 일치 검증 후 1파일 배치 — v91 base+ADD 게이트 PASS 실측(pre-push 통과) |
| verified_at | 2026-10-31T03:45Z |
| next_trigger | 없음 (epoch 재개 완결 — §2.5 ⑦⑧⑨ 전부 실측) |
| status_owner | Axiom (실행) — §2.5 세대 전환 절차 준수 |
| 핵심 | v91 착지 후 frozen ref 복원 경로로 워크플로 1파일 배치(naive rebase 회피 — add/add 충돌). PR 이벤트에서 실제 실행·결과 관측으로 종결. 진단 워크플로는 required 아님(병합 차단 없음) — required 5종 불변은 ⑧으로 실증. 러너 격리 agent-88 6/6 충족 유지(ephemeral JIT 잡당 VM, `persist-credentials: false`, PR 트리거 명시적 permissions, secrets 0, 캐시 restore-only). |

### RESID-20 — v91 정책 개정 (종결)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1140 MERGED `8415a9b0f` (02:27:45Z) — L4 OBSERVED_SUCCESS (run 41160114938). 서버 측 시퀀스 실측: refs API로 `policy/v91` 브랜치(`e2666e10c` 기반) → Contents API PUT (커밋 `568112aa`, parent 검증 통과, blob sha `a662319c` 명시) → PR → merge queue 착지. v91 내용: policyVersion 91 + CONTROLLED 268 항목(진단 워크플로 경로 포함) + description 변경기록 1행. 사전 양방향 게이트 실측: v90 base+ADD=FAIL / v91 base+ADD=PASS (동일 바이너리) |
| verified_at | 2026-10-31T03:45Z |
| next_trigger | 없음 (착지 완결 — RESID-19 epoch 재개로 이어짐) |
| status_owner | Axiom (실행) / 사용자 (승인 A — v91: 계획 승인 Option A + "전면 허가". RESID-18 C5-B 승인과 **별개**) |
| 핵심 | 서버 측 Contents API는 커밋 생성 도구일 뿐 병합 권위가 아니다 — 병합은 merge queue가 판정했다(RESID-06 실증 재확인). 정책 PR(v91)과 워크플로 PR(RESID-19) 분리 착지 실증. branch·blob sha 명시로 main 직접 커밋 방지(Round-4 수정 3 반영). |

### RESID-21 — PR #1125 (rearm App in-job mint) 처리

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** |
| evidence_ref | PR #1125 MERGED `496c54e5e` (02:41:51Z, 병합 수행자 `wintrover` — 인간 병합) · **L4 OBSERVED_SUCCESS** (main push run 41161156845, attempt 1, verdict=PASS, tier=dual-verified, artifact 13027670660, binary.sha256 `ddc70f4e`) — 본 세션 사후 최초 관측 실측 |
| verified_at | 2026-10-31T03:55Z (병합·L4 관측 확정) |
| next_trigger | 없음 (착지 + 수용 관측 완료) |
| status_owner | 사용자 (병합 수행) / Axiom (L4 관측 기록) |
| 핵심 | 01:43Z 시점 소유자 대기(BLOCKED)였으나 소유자가 직접 병합해 종결. 초판 기록의 stale-base FAIL(계약 동작, 결함 아님)·rearm 전제조건 미완(§2.4 인간 영역 — 발견 시크릿 대체 수단 시도 금지)은 당시 사실로 유지 — 병합 후 main push 런 PASS로 착지 수용 확인. |

### RESID-22 — PR #1128 (mg nimcache 분리) 병합

| 필드 | 값 |
|---|---|
| work_state / disposition | **OBSERVING / DEFERRED** (유지 — ③ 사전등록 관측 기준 미충족) |
| evidence_ref | PR #1128 MERGED `f18713934` (03:41:41Z, 병합 수행자 `wintrover` — MUST-T2 인간 수동 병합 계약 이행, head `cda164af` 일치) · **L4 OBSERVED_SUCCESS** (main push run 41165467895, attempt 1, verdict=PASS, tier=dual-verified, artifact 13029411695, binary.sha256 `613a2e50`) · **re-pin readback 확인**(2026-11-02, `docs/evidence/resid22_org_repin_closure_2026-11-02.md` §1): org ruleset 25218071/23943917 workflows sha `d76caf956…` = Archright/.github main HEAD(ls-remote 실측 — 10-31 이후 이동 없음) · admission-check.yml @`f18713934` blob = `b9792fc61825f05f81b43e9dd4db4d36bede0630` = 현행 main blob · **③ 사전등록 관측**(동 문서 §5-6): 창A(T 직전 최근 5런, Ubicloud 실측) mean 255.8s/p95 726.6s vs 창B([T,T2) Ubicloud 실측 158런) mean 191.3s/p95 803.9s → mean +64.5s(<120 미달)·p95 악화 — **기준 미충족 FAIL** |
| verified_at | 2026-11-02T00:25Z (re-pin readback + ③ 관측 판정 — OBSERVING 유지 확정) |
| next_trigger | ① org re-pin: **완료·readback 확인**(2026-11-02 — evidence 문서 §1) ② ruleset: 현행 sha 일치 — 조치 불요 ③ 사전등록 관측: **기준 미충족(UNKNOWN 유지)** — mean ≥120s 미달(+64.5s)·p95 악화(803.9>726.6). 재평가 트리거: 공급자 단일화된 창(전환 안정화 후)의 재관측 또는 워크플로별 정규화를 포함한 창 재설계 계약 개정 — **재평가 결정요청서 ADR-0040 정본화**(2026-11-02, `docs/adr/0040-resid22-observation-window-reevaluation-decision-request.md`): 옵션 A(기존 FAIL 유지 — 디폴트)/B(신규 사전등록 계약 — 별도 워크스트림) 인간(계약 소유자) 결정 대기, 권고 없음 — **인간 결정 수령(2026-11-02): 옵션 A 채택 — 기존 FAIL 판정 유지, 재평가 종결**(`docs/adr/0040-resid22-observation-window-reevaluation-decision-request.md` Status Accepted 갱신 — 수용은 FAIL 판정·본 행 상태를 바꾸지 않음) ④ side-pin 최신성 → RESID-23(operator 소유) |
| status_owner | 사용자 (org re-pin — 신뢰 표면, 완료·readback 확인) / Axiom (L4·관측 기록) |
| 핵심 | T2 인간 수동 병합 완료 — 에이전트는 병합을 대리하지 않았다(계약 준수). re-pin은 PR 본문이 명시한 착지 후 인간 조치: re-pin 전까지 이 PR의 행위 변경은 production에서 지연 상태(behavior-neutral). repo 내부 핀 재앵커(trusted_writer_set.json·epoch_manifest.json → `b9792fc6`)는 커밋 `cda164af`에 이미 포함. 갱신 3차(2026-11-02): re-pin 착지·readback 확인 — 그러나 ③ 관측 기준은 미충족: 8종 혼합 모집단의 창 평균은 엔트리 구성비에 지배되며 개선은 admission-gate 단일 워크플로(959.4→780.0, −179.4s)에 집중(계약 모집단 기준 미달 — 해석 보조로만 기록). 재고정 착지(사실 1)와 성능 개선(사실 2)은 분리 — CLOSED 전환은 계약 충족 관측으로만. |

### RESID-23 — Archright/.github admission-gate-v2.yml side-pin 최신성 (18b180094 고정 2핀)

| 필드 | 값 |
|---|---|
| work_state / disposition | **CLOSED / RESOLVED** (갱신 7차 — 2026-11-02: operator 판정 ① 수령 → Archright/.github 재핀 착지·readback 확인 — 진행 계정 정리) |
| evidence_ref | `docs/evidence/resid22_org_repin_closure_2026-11-02.md` §8 + **`docs/evidence/resid23_pin_freshness_decision_request_2026-11-02.md`**(조사 완결 2026-11-02T02:33Z): drift 2핀 재확인(:266 action.yml blob `262d42b74…`≠@main `b65bf7b70…`·:584 rpa blob `de255e798…`≠@main `8a530f746…`) — 핀 커밋 `18b180094…`은 Archright/**Axiom** 커밋(2026-10-17T10:36:09Z, PR #906 머지; .github 측 조회 404/422 → 저장소 정정 기록). 핀 이후 대상 경로 커밋 **4건 전부 fix 계열**(버그 수정 3·공급망 하드닝 1): `0ecd532e1c` SL-09 scope 수리·`1837fa64c4` reusable-workflow outputs object 형식 수리(bare mapping → HTTP 422 파싱 실패)·`03e3731a79` LFS-safe archive(핀 버전 keygen 실패 실측 run 39463081984)·`6a2a547569` dpkg 락 타임아웃+choosenim init.sh sha256 핀 fail-closed+arm64 sha256. **호출자 소비 계약 불변**: :266 inputs(`cache-save-enabled`·`cache-build-source`) pin=main, :584 inputs(`target_sha`·`force_full`) 동일 + 호출자는 `needs.gateway.result` 롤업만 소비 — main 신설 workflow_call outputs 4종은 additive. 후보 `6a2a5475697083e9d1c751293b0ea769d8ded603`(양 경로 최종 변경 커밋 — blob@후보=blob@main 실측 일치·compare behind_by 0) + **§8 operator 결정 기록(2026-11-02)**: 판정 ① 채택 — 착지 Archright/.github **PR #252 MERGE** `0684026f1b929ed9b9c3884be4da3dc89aa2bdc6`(2026-11-02T04:47:57Z native merge, diff :266·:584 정확히 2행 = 조사 §4 회전 파급 범위 예측과 일치). 핀 편차는 **pin-promotion-gate(DEBT#473) epoch-승격 강제**(제안 SHA 비승격 → fail-closed·waiver 불가) — 제안의 직계 조상이며 3경로 blob이 제안·현행 main과 동일한(action `b65bf7b70`·rpa `8a530f746`·admission-check `b9792fc618`=승격값) 승격 SHA `f18713934dad…`로 착지(컨텐츠 동일). org ruleset 2종(axiom-admission-gate 25218071·landing-integrity 23943917) workflows rule sha `0684026f…` 갱신·readback 일치(핀 4곳 `f18713934`·ruleset·원격 HEAD). 재핀 후 admission-gate v2 첫 실동: PR #1210(`b15e2a10b`)·#1211(`36576a956`) merge_group 8/8 success |
| verified_at | 2026-11-02T02:33Z (핀 최신성 조사 완결 — 권고 부여) → 2026-11-02 (§8 operator 판정 기입 + 재핀 착지 readback 재실측: admission-gate-v2.yml@HEAD 핀 4곳 `f18713934…`·ruleset 2종 sha `0684026f…`·원격 HEAD 일치) |
| next_trigger | **완료 — 잔여 조치 없음**: operator 판정 ① 수령·재핀 착지·readback 확인(§8). ③ 보류 조건(후보 blob 현행성 파괴)은 판정 완료로 소멸 — 향후 drift 재발은 통상 핀 최신성 검토 절차(본 항목 재개 아님). Northflank 기질 선택(#1204 D1)·제거 절차(전환 계약 §5·§6)·RESID-10 청구액은 별도 항목 — 본 항목과 무관 |
| status_owner | operator (핀 최신성 판정·재핀 착지 완료) / Axiom (조사·§8 판정 기록·갱신 7차 완료) |
| 항목 범위 | "핀 최신성 검토" — certificate-mint(@`d117ae8e`, blob `479f9b5b…` = 현행)·admission-check(@`f18713934`, blob `b9792fc6…` = 현행)는 내용 현행이므로 제외 — **2026-11-02T02:33Z 재확인: 현행 유지·drift 재발 없음(핀 커밋 존재 포함)**. `18b180094…` 사용처는 admission-gate-v2.yml :266/:584 2행이 유일(code search 양쪽 저장소 실측 — 회전 파급 범위 확정). 본 항목은 갱신 3차의 신규 발견(Round-4 분모 밖)으로 진행 계정 1행이었다 — 갱신 7차로 CLOSED/RESOLVED 종결(진행 계정 0). |

## 3. 분모 대응 검증

- Round-4 보고의 "잔여 11개 = 5 조사 + 1 관측 + 5 계획 필요"와 본 장부 24행의 대응: 5 조사 → RESID-01/03/04/06/(07a+08a) 각각 귀속. 관측 1 → RESID-09(+13 GHEC 추가 관측). 계획 필요 5 → v91(RESID-20)+진단 실행(RESID-19)+C5-B(RESID-18)+LCOM/nimtry 수리(07b/08b)로 분해, 나머지는 외부 소유자 항목(RESID-10/11/12/21/22)으로 재분류. 기존 표의 6행(외부 전용)은 GARM=ACCEPTED·지출=ACCEPTED 포함 6행 전부 유지 — 개수 정합 확인.
- 인간 전용 표 6행 ↔ RESID-10/11/12/21/22 + GHEC(RESID-13, 관측 DEFERRED) — GARM(DORMANT→RESID-15)·지출(ACCEPTED→RESID-16)은 조치 항목이 아니므로 제외.

## 4. 갱신 이력

| 시각(UTC) | 내용 |
|---|---|
| 2026-10-31T01:43Z | 초판 — 24행, 종결 22(RESOLVED 7·ACCEPTED 3·DEFERRED 6·BLOCKED 6) + 진행 2(RESID-18/20). PR #1135/#1136/#1137 병합 SHA 미기입(큐 대기 중) — 갱신 커밋로 기입 예정 |
| 2026-10-31T03:45Z | 갱신 1차 — 진행 계정 2건(RESID-18/20) + READY 2건(RESID-19/08b) 전부 종결 처리: 18 CLOSED/RESOLVED(PR #1138 `8e79d8d58`, L3+L4, 판정 UNKNOWN 정직 기록) · 19 CLOSED/RESOLVED(PR #1142 `ece9a599b`, §2.5 ⑦⑧⑨ 실측) · 20 CLOSED/RESOLVED(PR #1140 `8415a9b0f`, L4 run 41160114938) · 07b CLOSED/RESOLVED(PR #1143 MERGED `3ae3736a` 03:29:41Z, LCOM 0.6017316→0.578947, **L4 OBSERVED_SUCCESS** — main push run 41164600467, verdict=PASS, tier=dual-verified, binary.sha256 `613a2e50`) · 08b DEFERRED→**BLOCKED**(v92 TCB 정책 결정 필요 — agent-92 surface_guard FAIL/SURFACE_FORBIDDEN 기계 판정 실측, 기존 계획 외 신규 경로) · 08a 후속 실측 추가(LCOM ERROR 소멸 — nimtry 게이트 error 0건, 경고 22건 잔류는 기존 부채). 집계: RESOLVED 11 · ACCEPTED 3 · DEFERRED 3 · BLOCKED 7 · 진행 0. #1135/#1136/#1137 merge SHA는 각 행 evidence_ref에 기입 완료. |
| 2026-10-31T03:58Z | 갱신 1차 보강 — #1143 L4 판정 확정(OBSERVED_SUCCESS, run 41164600467, dual-verified) + **#1125 종결**(MERGED `496c54e5e` 02:41:51Z, 병합자 `wintrover`, L4 OBSERVED_SUCCESS run 41161156845 — 03:45Z 판정 시점에 이미 병합돼 있었던 사실을 정정 반영) + **#1128 병합·L4 확정**(MERGED `f18713934` 03:41:41Z, MUST-T2 인간 수동 병합 계약 이행, **L4 OBSERVED_SUCCESS** run 41165467895, dual-verified — org re-pin 인간 조치 잔여). 집계 재조정: RESOLVED 12 · ACCEPTED 3 · DEFERRED 4 · BLOCKED 5 · 진행 0. |
| 2026-11-02T00:25Z | 갱신 3차 — **RESID-22**: org re-pin readback 확인(org ruleset 25218071/23943917 workflows sha `d76caf956…` = Archright/.github main HEAD — 10-31 이후 이동 없음 · admission-check 핀 blob `b9792fc61825…` = 목표값 = 현행 main blob) + ③ 사전등록 관측 실측(창A T 직전 최근 5런 Ubicloud mean 255.8s/p95 726.6s vs 창B [T,T2) Ubicloud 158런 mean 191.3s/p95 803.9s — 런별 jobs API 공급자 실측으로 GHEC 32런 혼입 제거) → mean +64.5s 미달·p95 악화로 **기준 미충족** → **OBSERVING/DEFERRED 유지**(미충족 기준 명시 — 재고정 착지와 성능 개선은 분리 사실, CLOSED 금지 규칙 준수). **RESID-23 신규**(side-pin `18b180094` 고정 2핀 blob 불일치 — 진행 계정 1행, operator 소유). 증거: `docs/evidence/resid22_org_repin_closure_2026-11-02.md`. 집계: RESOLVED 13 · ACCEPTED 3 · DEFERRED 3 · BLOCKED 5 · 진행 1 — 총 25행(RESID-23 신규 포함, 미분류 0). |
| 2026-11-02T02:33Z | 갱신 4차 — **RESID-23 조사 완결**(INVESTIGATING→READY — disposition 미부여·진행 계정 유지): drift 2핀의 핀→main 변화 전수 실측 — 대상 경로 커밋 **4건 전부 fix 계열**(버그 수정 3·공급망 하드닝 1: `03e3731a79` LFS-safe archive 수리 — 핀 버전 keygen 실패 실측 run 39463081984 · `1837fa64c4` reusable-workflow outputs object 형식 수리 — bare mapping은 HTTP 422로 워크플로 자체 미디스패치 · `0ecd532e1c` SL-09 실행 범위 수리 · `6a2a547569` dpkg 락 타임아웃 300s + choosenim init.sh sha256 핀 fail-closed + arm64 tarball sha256 + curl 유한 재시도). **호출자 소비 계약 불변** — :266 action inputs 동일, :584 inputs 동일 + 호출자는 `needs.gateway.result` 롤업만 소비(:687), main 신설 outputs 4종(executed_jobs·scope_sl09·scope_sl09_reason·epoch_id)은 additive. 핀 버전 결함 4종 확정 — 그중 scope_sl09 무조건 false 침묵 게이트는 현재 epoch N+7(SL-09 미승격)에서 행위 차이 0, 미해시 `curl|sh` 부트스트랩만 지속 노출. 나머지 4핀(admission-check@`f18713934`·certificate-mint@`d117ae8e`) 현행 유지 재확인 — drift 재발 없음. 핀 커밋 `18b180094…`은 Archright/**Axiom** 커밋(10-17, PR #906)으로 실측 정정(.github 측 조회 404/422 기록). 권고 **① 재핀** — 후보 `6a2a5475697083e9d1c751293b0ea769d8ded603`(양 경로 최종 변경 커밋 — blob@후보=blob@main 실측 일치, compare behind_by 0). 판정·값 갱신(Archright/.github :266/:584)은 operator 권한 — 본 갱신은 docs-only, 값 갱신 미수행. 근거: `docs/evidence/resid23_pin_freshness_decision_request_2026-11-02.md`(Context7 GitHub Actions 공식 문서 3건 인용 — SHA 핀 안전성·"bug fixes and security updates 미수취" 비용 포함). 집계 불변: RESOLVED 13 · ACCEPTED 3 · DEFERRED 3 · BLOCKED 5 · 진행 1 — 총 25행. |
| 2026-11-02T03:06Z | 갱신 5차 — **RESID-22**: ③ 관측 기준 재평가 인간 결정요청서 **ADR-0040** 정본화(`docs/adr/0040-resid22-observation-window-reevaluation-decision-request.md` 신규) — 창 구성비 지배 관측(closure 문서 §6 인용)의 사전등록 평가 계약 설계 결함 여부와 옵션 A(기존 FAIL 판정 유지 — 변경 없음, 디폴트)/B(워크플로 정규화 포함 창 재설계 신규 사전등록 계약 — 결정 후 별도 워크스트림) 선택을 인간(계약 소유자) 결정으로 회부. 권고 없음. 창A 신규 API 수집은 계약 개정 승인 후에만, 신계약 판정식의 기존 FAIL 소급 적용 금지(12월 계약 §2.4 원리 — PR #1182 착지). 상태·disposition·집계 불변 — OBSERVING/DEFERRED 유지(RESOLVED 13 · ACCEPTED 3 · DEFERRED 3 · BLOCKED 5 · 진행 1, 총 25행). RESID-22 행 next_trigger에 ADR-0040 포인터 등록(유일한 행 변경). |
| 2026-11-02T04:39Z | 갱신 6차 — **RESID-22**: ③ 재평가 **인간 결정 수령**(2026-11-02, 계약 소유자 — 원문 지시 "A를 기본값으로 유지"): **옵션 A 채택** — 기존 FAIL 판정 유지(mean +64.5s<120s 미달·p95 803.9>726.6 악화 → 기준 미충족), 평가 계약 구조적 개정 없음(구성비 지배 관측을 계약 설계 결함으로 취급하지 않음), 창A 신규 API 수집 재분석·창 재설계 신계약·워크플로 정규화 미수행 — 재평가 질의 종결(결정 대기 해소). **ADR-0040 Status 갱신**: Proposed(결정 대기) → Accepted — 옵션 A 채택(2026-11-02, 결정 수령). 행 변경은 next_trigger ③ 결정 수령 문구 추가가 유일 — 상태·disposition·work_state·집계 불변: OBSERVING/DEFERRED 유지(RESOLVED 13 · ACCEPTED 3 · DEFERRED 3 · BLOCKED 5 · 진행 1, 총 25행). |
| 2026-11-02T06:40Z | 갱신 7차 — **RESID-23 종결**(READY→CLOSED/RESOLVED, 진행 계정 1→0): operator 판정 **① 재핀 채택** 수령(제안 `6a2a5475697083e9d1c751293b0ea769d8ded603`) → 착지 Archright/.github **PR #252 MERGE** `0684026f1b929ed9b9c3884be4da3dc89aa2bdc6`(2026-11-02T04:47:57Z native merge — diff :266·:584 정확히 2행, 조사 §4 회전 파급 범위 예측과 일치). **핀 편차(게이트 강제)**: 제안 SHA가 pin-promotion-gate(DEBT#473) "epoch-승격 아님" 판정으로 FAIL(fail-closed·waiver 불가 — 경로 2026-10-21 제거) → 제안의 직계 조상 + 3경로 blob이 제안·현행 main과 동일(action `b65bf7b70`·rpa `8a530f746`·admission-check `b9792fc618`=승격값)인 epoch-승격 SHA `f18713934dad…`로 착지 — **컨텐츠 동일, 편차 사유는 게이트 강제뿐**(§8 투명 기록). org ruleset 2종(axiom-admission-gate `25218071`·landing-integrity `23943917`) workflows rule sha `0684026f…` 갱신(enforcement=active 유지·landing-integrity.yml blob 불변), readback 재실측 일치(핀 4곳 `f18713934`·ruleset 2종·원격 HEAD). **재핀 후 admission-gate v2 첫 실동**: PR #1210(`b15e2a10b`)·#1211(`36576a956`) merge_group 8/8 전부 success — 신규 핀으로 착지 검증. 집계: RESOLVED 14 · ACCEPTED 3 · DEFERRED 3 · BLOCKED 5 · 진행 0 — 총 25행. 근거: `docs/evidence/resid23_pin_freshness_decision_request_2026-11-02.md` §8(본 갱신과 동일 PR로 기입·판정 수령·편차·readback 전문). |
