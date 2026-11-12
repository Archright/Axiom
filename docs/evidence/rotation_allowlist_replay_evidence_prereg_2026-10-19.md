# ADR-0025 Amendment 사전등록 — replay-evidence 회전 동반 경로 열거 (2026-10-19, 두 번째)

> **종류**: 사전등록 문서 (decision pre-registration) — Replay Evidence Admission 슬라이스(G1/G2 등급 계약·귀속 제약 쿼리·BuildInvocation 단일 객체·G2 문구)의 candidate delta가 클로저 멤버 `src/verification/rust_rust_pipeline.nim`·`src/verification/rust_replay_adapter.nim`·`src/cli/rust_lane_cli.nim`을 변경해 ROTATION 클래스로 분류됨에 대응하는 ④ 핀 재앵커 + ① 동반 경로 열거형 확장의 사전등록이다(62dbeab8b PR #895·10-18·10-19 guard_confirmation 선례와 동일 fix-class).
> **등록일**: 2026-10-19 (착지 이전 고정 — no-peeking; 본 문서는 같은 날짜의 첫 사전등록 `rotation_allowlist_guard_confirmation_prereg_2026-10-19.md`와 별개 슬라이스의 등록이다).
> **소유자**: 2026-10-19 사용자 전면 허가("권한이 필요한 부분은 전면 허가한다") 하에 기계적 부분을 착지 워크트리에서 등록한다.
> **고정성**: 본 문서가 착지하는 순간 §1의 열거는 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 수록 범위 — 열거형 2경로 (glob 없음, A4 규율 준수)

`src/cli/merge_cli.nim` `RotationAllowlistExtra`에 아래 2경로를 추가한다. A5·mg_evidence·guard_obligation·guard_confirmation이 이미 수록한 경로(변경 테스트 2종 포함)는 재열거하지 않는다.

1. `docs/spec/replay_evidence_policy.md`(신규 등급 계약 문서 — G1/G2 admission·귀속 규칙·pinnedChannel 결정)
2. `docs/evidence/rotation_allowlist_replay_evidence_prereg_2026-10-19.md`(본 문서 — 착지와 동반)

## 2. 판정 변화의 결정론성

- 본 회전은 **멤버십 불변** 조건의 내용 재앵커다: ④ `line-set(pin@H) == set(derived H)`는 유도값(`tools/ci/derive_checker_closure --ref H`) 기준으로만 갱신한다 — 추측 해시 금지.
- 재앵커 대상 4경로: `src/verification/rust_rust_pipeline.nim`(귀속 제약 쿼리·`guardModelAttributionSafe`·마커 강화), `src/verification/rust_replay_adapter.nim`(`RustBuildInvocation`·`rustReplayCommandMismatch`), `src/cli/rust_lane_cli.nim`(admissionNote 로그), `src/cli/merge_cli.nim`(열거형 확장의 단일 최종 앵커 패스 — 본 커밋 blob).
- `data/architecture_debt.json`: `debt_engine --regen-arch`; `data/nimtry_baseline.json`: `nimtry --update-baseline`(rustGuardObligationAttempt SLOC 확장 등 공식 래칭) + `--sync-budget`.
- 동반 등록의 효력은 다음 세대부터이며, 본 PR의 착지 경로는 trust-surface 수동 병합 경로다(④ 통과 시 TRUST_SURFACE_MODIFIED dryRunExit 0 — 전례 PR #856·62dbeab8b).

## 3. 검증 계획 (착지 전 기계 검증)

1. `agent_preflight` PASS
2. `bin/nimtry src/` exit 0(래칭 후)
3. 커밋 후 `derive_checker_closure --ref HEAD` == pin(멤버십 불변·blob 등식)
4. `tools/ci/verify_trusted_writer_set.sh` PASS, `debt_engine --validate` PASS
