---
name: ci-watch
description: Use when checking CI status, PR checks, or waiting for GitHub check completion (gh pr checks, verify-static, CI poll, PR merge readiness). Replace fixed wall-clock sleeps with one observation round that judges and returns control.
---

> **정본 관계**: 절차의 정본은 [merge_admission_observation.md](../../../docs/agents/merge_admission_observation.md)다 — 관측 3층(L1/L2/L3), Liveness state machine, evidence-kind 속성, 관측 명령 인벤토리가 모두 그 문서에 있다. **이 파일은 호출 규약만 담는다.** 절차·명령·사고 이력을 여기에 재기술하면 정본이 둘이 된다(단방향 참조).

# CI / PR 체크 대기 — 호출 규약

- **루프가 아니라 관측 라운드다.** 고정 벽시계 `sleep`도, "MERGED 될 때까지" 도는 무조건 `until` 루프도 금지다 — 후자는 차단된 PR 앞에서 영원히 돌며 제어권을 반환하지 않는다(2026-10-05 사고).
- **관측 1라운드 → 판정 → 재관측은 사유가 있을 때 최대 1회** → 판정 불가면 즉시 FAIL CLOSED: 정지 + 마지막 raw facts 출력 + 제어권 반환.
- **관측은 GET / GraphQL query만.** monitor write calls = 0. auto-merge arm은 operator 행위이며 이 스킬에서 수행하지 않는다(명령의 정본은 operator 절차: `docs/agents/rules_workflow.md`, `docs/agents/operations.md`).
- **재관측 interval ≥ 30초** — `--interval 30`을 항상 명시한다.
- **wall-clock timeout은 상한 안전망이지 판정 의미론이 아니다.** bash 도구 `timeout`은 "관측 라운드가 스스로 끝나지 못하면 무언가 잘못됨"의 경계로 잡는다 — "예상 시간 + 여유"로 잡지 않는다.

## 판정 어휘 (닫힌 집합)

`SUCCESS` · `FAIL` · `RECOMPUTING` · `LANDING_PENDING_ENQUEUE` · `WAIT` · `UNKNOWN` + evidence-kind.

각 판정의 진입 조건, required 여부의 해석자(GraphQL `CheckRun.isRequired`), "UNSTABLE·DRAFT·skipped는 FAIL이 아니다" 같은 경계는 정본 문서의 **Liveness state machine** 절이 정의한다. 레거시 어휘 `READY`/`NOT_READY`는 쓰지 않는다.

## 관측 명령

정본 문서 §2.3의 관측 명령 인벤토리를 그대로 쓴다. 이 파일에 명령을 복제하지 않는다.

## 무결성

이 파일은 `tools/ci/monitor_purity_scan.sh`의 스캔 표면 중 하나다(`make check-monitor-purity`) — 여기에 GitHub mutation 동사를 추가하면 게이트가 FAIL한다.