# AXIOM_DUAL_TRACK 점진적 승격 정책 (Progressive Promotion)

> **⚠️ 완전 삭제됨 (2026-08-08)** — 이 문서에 기술된 dual-track 파이프라인은
> **제거되었습니다.** `auto_heal` 엔진(`tools/auto_heal.nim`), 게이트 래퍼
> (`src/gate/runners/auto_heal.nim`), `bin/auto_heal` 배포, 그리고
> `src/gate/gateway.nim`의 `runDualTrack` 및 `AXIOM_DUAL_TRACK` 실행 경로가 전부
> **2026-08-08에 완전 삭제**되었습니다. 근거는
> `docs/history/debt/auto-heal-removed-2026-08-08.md`를 참조하십시오.
>
> 아래 내용은 삭제 이전의 상태를 보존하는 역사적 기록이며, 현재 실행 경로가
> **없음(비활성 + 엔진 제거됨)**을 알립니다. 아래 Phase 1/2/3 승격 래더는 현재
> 적용 대상이 없습니다.

## 배경

> **REMOVED 2026-08-08**: `AXIOM_DUAL_TRACK`는 `src/gate/gateway.nim`의 `runDualTrack`을 활성화하여
> `auto_heal converge src` (Track 1, 15s 타임아웃)와 `auto_heal prove src` (Track 2, 180s 타임아웃)를
> 동시에 실행하는 병렬 검증 파이프라인이었다. 해당 경로는 2026-08-08에 완전 삭제되어
> 더 이상 코드에 존재하지 않는다.

현재 `cmdProve`는 NO-OP 보고서 작성기("ax prove integration pending")이며,
`cmdConverge`는 회로 차단기(circuit breaker)가 적용되어 비수렴 시 경고 + exit 0, 결코 블로킹하지 않는다.

이 문서는 해당 기능이 실험 단계에서 프로덕션 CI로 승격되는 3단계 래더를 정의한다.

> **결정 ② (2026-08-08)**: ~~`auto_heal` 기본값을 OFF로 전환. `src/gate/gateway.nim`의
> `runDualTrack`은 `AXIOM_DUAL_TRACK="on"`일 때만 활성화된다 (미설정/빈값 = 비활성).
> `bin/auto_heal` 바이너리가 배포되지 않으므로 기존 기본값(ON 취급)은 항상
> "auto_heal binary not found — skipping" 스킵 로그 소음을 발생시켰다. 이를 제거하기 위해
> 기본값을 OFF로 변경했으며, Healing Orchestrator 모듈 자체는 변경하지 않는다.
> 참조: `src/gate/gateway.nim:runDualTrack`.~~
>
> **결정 ③ (2026-08-08, 완전 삭제)**: 결정 ②의 default-off dead 상태와 `runDualTrack`의
> 잠재 false-return 버그로 인해 `auto_heal` 엔진/게이트 래퍼/`runDualTrack`을 **완전 삭제**.
> Healing Orchestrator 모듈(`healing_orchestrator`)은 별개 모듈로 유지된다.

---

## Phase 1 — Local Manual (현재 상태)

| 속성 | 값 |
|---|---|
| 기본값 | `AXIOM_DUAL_TRACK` 미설정/빈값 → 비활성 (default OFF, 2026-08-08 결정 ②) |
| 활성화 조건 | `AXIOM_DUAL_TRACK=on`일 때만 `runDualTrack` 실행 |
| 범위 | 수동 로컬 실험 전용 |
| CI 영향 | 없음. 커밋 속도 보장. |
| `cmdConverge` | 회로 차단기 활성 — 비수렴 시 경고 후 exit 0 |
| `cmdProve` | NO-OP 보고서 작성기 (실제 증명 미실행) |

**목적**: 개발자가 로컬에서 dual track 동작을 수동 검증할 수 있는 진입점 제공.
PR/CI 파이프라인에 영향을 주지 않으므로 언제든 활성화 가능.

---

## Phase 2 — Nightly Cron (비차단 메트릭 수집)

| 속성 | 값 |
|---|---|
| 기본값 | `AXIOM_DUAL_TRACK` 미설정/빈값 → 비활성 (default OFF, 2026-08-08 결정 ②) |
| 트리거 | nightly cron / 외부 스크립트로 실행 (`AXIOM_DUAL_TRACK=on` 명시 필요) |
| PR 차단 | ❌ 차단하지 않음 |
| 수집 메트릭 | ① `cmdConverge` 고정점 도달률 (converge fixed-point hit ratio) ② Track 1/2 각각의 타임아웃 발생률 ③ 감쇄 곡선 (timeout decay over commits) |
| 출력 | 메트릭 로그 파일 또는 별도 저장소 (예: `docs/metrics/dual_track/`) |
| `cmdProve` | 여전히 NO-OP — Prove 백엔드 미연동 |

**목적**: 실패/성능 데이터를 사람이 분석하여 Phase 3 진입 판단 근거로 활용.
개발 워크플로에 영향을 주지 않으면서 장기 추세 관찰.

**제약 (CI=0)**: `.github/workflows/`는 CI=0 cutover(2026-09-20)로 삭제되었으며, 과거엔 immutable 영역(AGENTS.md §-1)이었다. Phase 2 관측(장기 추세)은 외부 인프라(서버 cron, 별도 스크립트 디스패처) 또는 로컬 실행으로 수행해야 한다.

---

## Phase 3 — PR Blocking CI

| 속성 | 값 |
|---|---|
| 기본값 | `AXIOM_DUAL_TRACK=on` → PR CI에서 `runDualTrack` 강제 실행 |
| PR 차단 | ⛔ Track 1/2 중 하나라도 실패 시 PR 커밋 차단 |
| `cmdConverge` | 회로 차단기 해제 — 실제 수렴 실패 시 CI 실패 |
| `cmdProve` | 실제 Z3/SMT-LIB2 백엔드 증명 연동 — 증명 실패 시 CI 실패 |

### 🔴 Hard Exit Criteria

Phase 2의 메트릭 분석 결과 **모두** 충족되어야 Phase 3 진입 가능:

1. **`cmdConverge` 고정점 도달 실패율 0%**
   - 전체 테스트 셋에서 타임아웃 감쇄(timeout decay) 완료.
   - 회로 차단기가 단 한 번도 트리거되지 않는 상태가 최소 7일 연속 관찰.
2. **`cmdProve` 실제 증명 백엔드 연동 완료**
   - `cmdProve`가 NO-OP 보고서 작성기("ax prove integration pending")를 벗어나
     실제 Z3/SMT-LIB2 백엔드를 통한 증명을 수행해야 함.
   - NO-OP 상태에서는 Phase 3 진입 절대 불가.

### ⚠️ Immutable 영역 제약 (CI=0 이후 해소)

Phase 3를 `.github/workflows/`에 직접 편입하려면 해당 디렉터리 수정이 필요했다.
그러나 `.github/workflows/`는 `AGENTS.md` §-1에 의해 **immutable 영역**으로 지정되어 있었다.
(CI=0 cutover, 2026-09-20로 워크플로 디렉터리 자체가 제거 — 해당 제약은 소멸)

따라서 다음 중 하나의 우회 경로가 필요했다:

1. **Architect 명시 승인**: 사람 architect가 `AGENTS.md` 예외 승인.
2. **외부 cron/스크립트 우회**: GitHub Actions workflow와 독립적인 외부 CI 인프라에서
   `AXIOM_DUAL_TRACK=on` 상태의 Axiom CLI를 실행하고 결과를 PR 상태에 반영.
   (예: 별도 CI 서버의 webhook → GitHub Commit Status API)
3. **Gate 레이어 확장**: `src/gate/` 레이어에 새로운 gate 추가로 동일한 차단 효과를
   `.github/workflows/` 수정 없이 구현. (권장)

어떤 우회 경로를 선택하든 **Phase 3 활성화는 architect의 명시적 결정**이어야 하며,
본 문서의 Hard Exit Criteria 검증 결과와 함께 기록되어야 한다.

---

## 부록: 상태 요약

| Phase | 기본값 | 활성화 | CI 차단 | cmdConverge | cmdProve |
|---|---|---|---|---|---|---|
| 1 (Local Manual) | off | `AXIOM_DUAL_TRACK=on`으로 활성화 | ❌ (아직 Phase 3 아님) | 회로 차단기 | NO-OP |
| 2 (Nightly Cron) | off | 동일 (`AXIOM_DUAL_TRACK=on` 명시 필요) | ❌ | 회로 차단기 (메트릭 수집) | NO-OP (메트릭 수집) |
| 3 (PR Blocking CI) | on | 강제 | ⛔ | 회로 차단기 해제 | 실제 증명 연동 |
