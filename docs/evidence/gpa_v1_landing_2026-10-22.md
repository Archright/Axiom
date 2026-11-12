# GPA v1 착지 기록 — Generation Promotion Acceptance Phase 1 (부트스트랩)

> 관측: 2026-10-21 20:52 UTC. 이 문서는 docs-only probe PR의 본문이면서
> Phase 1 착지의 감사 기록이다 (fast-path 관측이 이 PR의 목적).

## 착지 체인

| 단계 | 증거 |
|---|---|
| v83 선등록 | PR #1023 MERGED `6aec2550` (2026-10-21 19:41 UTC) — repository_surface.json v82→v83, generation-acceptance.yml CONTROLLED (2단계 choreography, #1011 선례) |
| GPA v1 본체 | PR #1024 MERGED `f490c66a` (2026-10-21 20:52 UTC) — 7 commit: ADR-0036·workflow·정책 v1.16.0/v1.16.1·merge_cli 4-check·TWS/debt 재앵커·quirk 문서 |
| 자기 실행 (pull_request) | run 39671384245 — verdict **ACCEPTED**, L2 = **PROMOTION_PENDING** (정책 4-check vs live 3-check — 자기 context 추가만 허용, ruleset PUT 대기) |
| 자기 실행 (merge_group) | run 39672117311 — completed/success (PR·merge_group 양측 판정 — ADR-0036 필수 조건) |
| workflow id | 392117427 (readback, 2026-10-22T04:53:43+09:00 할당 — 등록 자체가 uniqueness 증거) |

## 착지 전 발견·수정된 결함 (첫 실측이 잡은 것)

1. **workflow 등록 실패**: job-level env `${{ runner.temp }}` — runner context는
   `jobs.<job_id>.env`에 허용되지 않음. 증상: push 스텁 실행(무로그
   "workflow file issue") + 선언 트리거 무발화. —
   docs/spec/gh_workflow_env_context_quirks.md (§0.5 Quirk Mandate)
2. **toolchain cache-build-source**: `github.sha`(=PR merge commit)가 driver
   워크스페이스에 없어 exit 128 → base sha(DRIVER_REF)로 수정.
3. **TWS closure 핀 누락**: workflowId 기입 커밋이 merge_cli를 재변경 —
   trustedCheckerTreeClosure blob 핀 재앵커 누락 → VS-1 rotation-pin H2
   fail-closed (ROT_NEW_PIN). 재앵커로 해소.

이 세 결함은 모두 게이트의 fail-closed 설계가 실제로 발화한 사례다:
INCOMPLETE 판정(생략≠성공)도 관측됨 — "skipped가 success로 읽히지 않는다"
설계의 실증.

## 다음 단계 (이 PR이 fast-path 관측 자체)

이 PR은 실행 표면을 건드리지 않는다(docs/evidence/** 신규 1문서) —
generation-acceptance는 **NO_SURFACE_DELTA fast-path**로 판정해야 한다
(전체 검증이 아니라). 이 관측이 ruleset PUT(required 등록)의 마지막
사전 조건이다.
