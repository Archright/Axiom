# Slice B / S3 — rearm 결정적 분류·유한 재시도 dry-run 검증 및 무인 착지 기록 (2026-10-15)

## 1. 검증 대상·채널

PR #843(`fix/rearm-deterministic-recovery`, 착지 커밋 `1fb0748af…` → main MERGE `84346c91a`)의 `merge-queue-rearm.yml`을 `workflow_dispatch` dry-run 모드(arm·라벨 쓰기 없음, ADR-0027 Amendment E)로 검증. 정책: 총 검증 시도 ≤ 2/PR head(사용자 확정 2026-10-15), TRANSIENT 폐쇄 열거 (a)ETXTBSY/콜드 relink(+S2 입증 형제 서명: `undefined reference to`·`final link failed`·`collect2: error`) (b)artifact 5xx/429/transport (c)조회 infra — **근거 우선, 미확정 = no-arm 기본**.

> **[2026-10-15 후기 부기]**: 본 문서 작성 시점의 "(b) 5xx/429" 서술 중 429는
> 구현 브리프 오류로 판명되어 PR #849(머지 `1393366db`)로 구현에서
> 제거되었다(사용자 고정 계약 = 5xx·503·transport). 429는 이제
> UNKNOWN→DEFAULT-NO-ARM — 본 문서의 시점 기록은 원문 그대로 보존한다.

## 2. dry-run 5경로 입증 (런 ID 전수)

| # | run | 시나리오 | 관측 | 판정 |
|---|---|---|---|---|
| 1 | 38714922136 | 변형 head SHA(40-hex 아님) | `head SHA not a 40-hex OID` UNKNOWN no-arm | 가드 ✓ |
| 2 | 38714173697 | fixture 38676808805를 pr=838(MERGED)로 | `PR state is MERGED` UNKNOWN no-arm | 가드 ✓ |
| 3 | 38714205379 | 실험 런을 타 PR head로 | `head-mismatch (fail closed)` | 가드 ✓ |
| 4 | 38716119268 | **긍정 대조**: 실험 런 38710338905(Job A FAILED, 링크 손상 로그) + `rearmed@caab865d8a76` 라벨 사전 부착(PR #844 차량) | `CLASSIFIED: (a) via job 'cold-repro-guarded' log line 903` → `budget:spent, action:exhausted` — "would add rearm-exhausted and FAIL; nothing written" | **TRANSIENT (a) + 예산 소진 종결 ✓** |
| 5 | 38716442267 | 동일 + 라벨 제거 | TRANSIENT (a) → `budget:available` → "would ARM pr#844 … never arms or labels" | **would-arm ✓** |

- 가드 체인 통과 로그(4·5): PR OPEN → no-auto-rearm 없음 → 큐 부재 → trust-surface 비교집(2 changed vs 14 patterns) → (verdict check-run 부재 → 잡/로그 증거 폴백) → 앵커 매칭 → 예산.
- historical 런(38676808805 ROT_NEW_PIN·38680184078 no-verdict·38578920996 등 10/14 5건)의 전체 파이프라인 dry-run은 **구조적 제약**: 라이브 PR 맥락(OPEN·큐 부재)이 선행 게이트라 병합된 PR의 과거 런은 진입 불가 — 라벨·가드 동작은 위 5경로로 입증, ROT_* 타이틀 영구 분류는 allowlist/PERM_RE 로직(amendment E 코드 경로)로 보장. 제약은 이 기록으로 명시.

## 3. dry-run 채널이 잡은 결함 2건 (채널 존재 정당성)

1. verdict check-run 부재 시 jobs/로그 폴백 누락(하드 UNKNOWN 종결) → 폴백 통과로 수정(커밋 `53fe4c2b7`).
2. `gh api …/jobs/<id>/logs`가 gh 클라이언트 이스케이프 가드로 거부 → `--allow-escape-sequences` 추가(커밋 `1fb0748af`).

## 4. 무인 착지 증거 #1 — PR #843 (rearm 본체)

- 큐 진입: auto-merge 09:58Z, position 1 AWAITING_CHECKS → MG 런 **38716885469** (merge_group, admission-gate) **success** (~9.5분).
- MERGE: `84346c91a91bb45ff0f144f8ae846bad7aa4786c` (2026-10-15T10:17:55Z, GitHub 네이티브 MERGE, `commits/<sha>/pulls` → PR #843).
- 필수 체크: `admission-check` success · `bsec-integrity` success (merge commit check-runs).
- 실행 세대: MG `referenced_workflows` = {`ba773d0631`, `aa0511343`, `dc527994c`} — 신뢰 핀-트리플 불변.
- **세대 H₁ readback(착지 직후)**: ruleset 24233738·23943917 = sha `e968b5c0c20b7c63adaad74a235c31392b6ac497` — **신뢰경계 회전 0, ref 소멸 유지**.
- 비상 창 기록 부재·수동 rearm 미사용(착지 경로 CLEAN→green→MERGED 단일 시도 — 예산 미소진).

## 5. S2 연계

콜드 경합 통제 재현·가드 억제·부분 캐시 원자성은 `docs/evidence/slice_b_s2_cold_repro_2026-10-15.md`(런 38710338905·38711735376, 판정 reproduced-guarded-suppressed + 형제 모드 발견). 본 문서의 긍정 대조군 분류가 그 증거를 소비.

## 6. 잔여·후속 (Slice B 범위 밖, 명시적 분리)

1. **ci-cache-publisher 사망**(2026-10-12 10:05Z 이후 workflow_run 0회 — 미등록 org-required 워크플로 이름 매칭 불해석 → B/베이스 캐시 재시딩 0, red-loop 전제 (c) 미완화) — 별도 수리 슬라이스 필요(측정: B2 task 6).
2. **STALE_HEAD_RACE 열거 확장 제안**: 38680184078(cert headSha≠live PR head, 자연 재큐로 자가 회복 실측)는 고정 열거 밖 → 기본 no-arm. 열거 확장 여부는 사용자 결정 사항.
3. **레인 stderr 방출**: 10/14류 분류 강화에 필요하나 `admission-check.yml`(신뢰경계) 변경 수반 — 별도 제안(승격 절차 경유).
4. historical-run dry-run 제약(§2) — 필요 시 `run_id` 단독 게이트 통로 논의.

## 7. 증거 보존

GitHub 실행 기록의 90일 보존 한계(2026-10-01 정책)에 따라 본 문서가 핵심 증거의 정본 보존소다(런 ID·로그 발췌·판정 전수). 아티팩트는 각 런에 30일 보존.
